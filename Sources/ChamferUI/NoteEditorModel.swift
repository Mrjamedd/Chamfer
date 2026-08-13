import ChamferCore
import Foundation
import Observation

enum NoteSaveStatus: Hashable {
    case saved
    case saving
    case failed(String)
}

/// Keeps each live draft with the saved baseline it was opened against.
///
/// Dashboard state is the saved, searchable truth. Editor models are session
/// state instead: retaining the model lets a failed save survive a trip to
/// another note without publishing every typed character to the whole window.
@MainActor
final class DashboardNoteEditorSessions {
    private var editors: [URL: NoteEditorModel] = [:]

    func editor(for url: URL) -> NoteEditorModel? {
        editors[url.standardizedFileURL]
    }

    func retain(_ editor: NoteEditorModel, for url: URL) {
        editors[url.standardizedFileURL] = editor
    }
}

@MainActor
@Observable
final class NoteEditorModel {
    var text: String
    private(set) var saveErrorMessage: String?
    private(set) var saveStatus: NoteSaveStatus = .saved

    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private let save: (String, String) throws -> Void
    @ObservationIgnored private let didSave: (String) -> Void
    @ObservationIgnored private var lastSavedText: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    convenience init(
        document: NoteDocument,
        autosaveDelay: Duration = .milliseconds(450),
        didSave: @escaping (String) -> Void = { _ in },
        save: @escaping (String) throws -> Void
    ) {
        self.init(
            document: document,
            autosaveDelay: autosaveDelay,
            didSave: didSave,
            saveReplacing: { text, _ in try save(text) }
        )
    }

    init(
        document: NoteDocument,
        autosaveDelay: Duration = .milliseconds(450),
        didSave: @escaping (String) -> Void = { _ in },
        saveReplacing: @escaping (String, String) throws -> Void
    ) {
        text = document.text
        lastSavedText = document.text
        self.autosaveDelay = autosaveDelay
        self.didSave = didSave
        self.save = saveReplacing
    }

    var hasUnsavedChanges: Bool { text != lastSavedText }

    func textDidChange() {
        pendingSave?.cancel()
        pendingSave = nil
        guard text != lastSavedText else {
            saveErrorMessage = nil
            setSaveStatus(.saved)
            return
        }

        saveErrorMessage = nil
        setSaveStatus(.saving)
        let nextText = text
        pendingSave = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: autosaveDelay)
                try Task.checkCancellation()
                persist(nextText)
            } catch is CancellationError {
                return
            } catch {
                reportSaveFailure(error)
            }
        }
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard text != lastSavedText else {
            saveErrorMessage = nil
            setSaveStatus(.saved)
            return
        }
        setSaveStatus(.saving)
        persist(text)
    }

    private func persist(_ text: String) {
        do {
            try save(text, lastSavedText)
            lastSavedText = text
            saveErrorMessage = nil
            setSaveStatus(.saved)
            didSave(text)
        } catch {
            reportSaveFailure(error)
        }
    }

    private func reportSaveFailure(_ error: Error) {
        let message = "Couldn’t autosave. \(error.localizedDescription)"
        saveErrorMessage = message
        setSaveStatus(.failed(message))
    }

    /// A draft can change many times while its footer remains in the same
    /// state. Avoiding a write for those repeats keeps observers of the quiet
    /// page chrome off the editor's per-keystroke path.
    private func setSaveStatus(_ status: NoteSaveStatus) {
        guard saveStatus != status else { return }
        saveStatus = status
    }
}
