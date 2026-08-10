import ChamferCore
import ChamferUI
import ChamferWatch
import Foundation

/// The real backing store for note editing in the shipping app.
///
/// Authorization is evaluated for every save rather than captured when the
/// page opens. If a vault is disconnected or becomes unavailable while a note
/// is open, the editor stops writing instead of retaining stale authority.
@MainActor
struct ConnectedVaultNoteEditor {
    let model: AppModel
    let notes: NoteService

    var configuration: NoteEditingConfiguration {
        NoteEditingConfiguration(
            canEdit: canEdit,
            saveReplacing: save
        )
    }

    func canEdit(_ url: URL) -> Bool {
        editableVault(containing: url) != nil
    }

    func save(_ document: NoteDocument) throws {
        try save(document, replacing: nil)
    }

    func save(_ document: NoteDocument, replacing expectedText: String) throws {
        try save(document, replacing: Optional(expectedText))
    }

    private func save(_ document: NoteDocument, replacing expectedText: String?) throws {
        guard let vault = editableVault(containing: document.url) else {
            throw NoteEditingError.unsupportedDocument
        }

        try VaultBookmark.withAccess(to: vault.url) {
            if let expectedText {
                let current = try String(contentsOf: document.url, encoding: .utf8)
                guard current == expectedText else {
                    throw NoteEditingError.documentChangedExternally
                }
            }
            try Data(document.text.utf8).write(
                to: document.url,
                options: .atomic
            )
        }
        notes.refreshAfterUserEdit(document.url)
    }

    private func editableVault(containing url: URL) -> Vault? {
        guard NoteEligibility.isSupportedFile(url.lastPathComponent) else {
            return nil
        }

        return model.dashboard.vaults
            .filter { vault in
                vault.availability.isAvailable
                    && NoteEligibility.relativePath(of: url, under: vault.url) != nil
            }
            .max {
                $0.url.pathComponents.count < $1.url.pathComponents.count
            }
    }
}
