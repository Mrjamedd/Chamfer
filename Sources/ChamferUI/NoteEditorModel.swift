import ChamferCore
import Foundation
import Observation

@MainActor
@Observable
final class NoteEditorModel {
    var text: String
    private(set) var saveErrorMessage: String?

    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private let save: (String, String) throws -> Void
    @ObservationIgnored private var lastSavedText: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    convenience init(
        document: NoteDocument,
        autosaveDelay: Duration = .milliseconds(450),
        save: @escaping (String) throws -> Void
    ) {
        self.init(
            document: document,
            autosaveDelay: autosaveDelay,
            saveReplacing: { text, _ in try save(text) }
        )
    }

    init(
        document: NoteDocument,
        autosaveDelay: Duration = .milliseconds(450),
        saveReplacing: @escaping (String, String) throws -> Void
    ) {
        text = document.text
        lastSavedText = document.text
        self.autosaveDelay = autosaveDelay
        self.save = saveReplacing
    }

    var hasUnsavedChanges: Bool { text != lastSavedText }

    func textDidChange() {
        pendingSave?.cancel()
        pendingSave = nil
        guard text != lastSavedText else {
            saveErrorMessage = nil
            return
        }

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
                saveErrorMessage = "Couldn’t autosave. \(error.localizedDescription)"
            }
        }
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard text != lastSavedText else {
            saveErrorMessage = nil
            return
        }
        persist(text)
    }

    private func persist(_ text: String) {
        do {
            try save(text, lastSavedText)
            lastSavedText = text
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Couldn’t autosave. \(error.localizedDescription)"
        }
    }
}
