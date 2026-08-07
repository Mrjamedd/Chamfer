import ChamferCore
import Foundation
import Observation

@MainActor
@Observable
final class NoteEditorModel {
    var text: String
    private(set) var saveErrorMessage: String?

    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private let save: (String) throws -> Void
    @ObservationIgnored private var lastSavedText: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(
        document: NoteDocument,
        autosaveDelay: Duration = .milliseconds(450),
        save: @escaping (String) throws -> Void
    ) {
        text = document.text
        lastSavedText = document.text
        self.autosaveDelay = autosaveDelay
        self.save = save
    }

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
            try save(text)
            lastSavedText = text
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Couldn’t autosave. \(error.localizedDescription)"
        }
    }
}
