import ChamferCore
import Foundation

public enum NoteEditingError: LocalizedError {
    case unsupportedDocument

    public var errorDescription: String? {
        "This example note is not backed by an editable file."
    }
}

/// Declares exactly which real document the dashboard may edit. Documents
/// without a backing store remain readable but can never pretend to save.
public struct NoteEditingConfiguration {
    public let documentURL: URL
    private let saveAction: (NoteDocument) throws -> Void

    public init(
        documentURL: URL,
        save: @escaping (NoteDocument) throws -> Void
    ) {
        self.documentURL = documentURL
        saveAction = save
    }

    public func canEdit(_ url: URL) -> Bool {
        url.standardizedFileURL == documentURL.standardizedFileURL
    }

    func save(_ document: NoteDocument) throws {
        guard canEdit(document.url) else {
            throw NoteEditingError.unsupportedDocument
        }
        try saveAction(document)
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
