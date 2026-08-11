import ChamferCore
import Foundation

public enum NoteEditingError: LocalizedError {
    case unsupportedDocument
    case documentChangedExternally

    public var errorDescription: String? {
        switch self {
        case .unsupportedDocument:
            "This note is not an editable document in an available connected vault."
        case .documentChangedExternally:
            "This note changed outside Chamfer. Reopen it before saving your draft."
        }
    }
}

/// Declares which real documents the dashboard may edit.
///
/// The backing store owns the decision. The gallery approves one example;
/// the shipping app approves every supported note in an available connected
/// vault. Documents without a writable backing store remain readable but can
/// never pretend to save.
public struct NoteEditingConfiguration {
    private let canEditAction: @MainActor (URL) -> Bool
    private let saveAction: @MainActor (NoteDocument, String?) throws -> Void

    public init(
        canEdit: @escaping @MainActor (URL) -> Bool,
        save: @escaping @MainActor (NoteDocument) throws -> Void
    ) {
        canEditAction = canEdit
        saveAction = { document, _ in try save(document) }
    }

    public init(
        canEdit: @escaping @MainActor (URL) -> Bool,
        saveReplacing: @escaping @MainActor (NoteDocument, String) throws -> Void
    ) {
        canEditAction = canEdit
        saveAction = { document, expectedText in
            guard let expectedText else {
                throw NoteEditingError.documentChangedExternally
            }
            try saveReplacing(document, expectedText)
        }
    }

    /// Convenience for the gallery's single file-backed example.
    public init(
        documentURL: URL,
        save: @escaping @MainActor (NoteDocument) throws -> Void
    ) {
        let key = documentURL.standardizedFileURL
        self.init(
            canEdit: { $0.standardizedFileURL == key },
            save: save
        )
    }

    @MainActor
    public func canEdit(_ url: URL) -> Bool {
        canEditAction(url.standardizedFileURL)
    }

    @MainActor
    public func save(_ document: NoteDocument) throws {
        guard canEdit(document.url) else {
            throw NoteEditingError.unsupportedDocument
        }
        try saveAction(document, nil)
    }

    @MainActor
    public func save(_ document: NoteDocument, replacing expectedText: String) throws {
        guard canEdit(document.url) else {
            throw NoteEditingError.unsupportedDocument
        }
        try saveAction(document, expectedText)
    }
}

enum DashboardNoteDrafts {
    static func retain(_ document: NoteDocument, in state: inout DashboardState) {
        if state.openNote?.url == document.url {
            state.openNote = document
        }

        for index in state.searchableNotes.indices
        where state.searchableNotes[index].url == document.url {
            state.searchableNotes[index] = document
        }
    }
}
