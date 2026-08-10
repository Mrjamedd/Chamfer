import Foundation

/// Everything awaiting a decision or already recorded for one note.
///
/// The dashboard-wide Review page and this note-scoped view are two windows
/// onto the same values. Keeping the filtering here prevents either surface
/// from quietly disagreeing about what still needs the user's attention.
public struct NoteChangeHistory: Sendable, Equatable {
    public let noteURL: URL
    public let queued: [Proposal]
    public let history: [HistoryEntry]

    public init(
        noteURL: URL,
        proposals: [Proposal],
        history: [HistoryEntry]
    ) {
        let key = noteURL.standardizedFileURL
        self.noteURL = key
        queued = proposals
            .filter {
                $0.state.isActionable
                    && $0.note.url.standardizedFileURL == key
            }
            .sorted { $0.createdAt > $1.createdAt }
        self.history = HistoryWindow.sorted(
            history.filter { $0.path.standardizedFileURL == key }
        )
    }

    public var count: Int { queued.count + history.count }
    public var isEmpty: Bool { queued.isEmpty && history.isEmpty }
}

public extension DashboardState {
    func changes(forNoteAt url: URL) -> NoteChangeHistory {
        NoteChangeHistory(
            noteURL: url,
            proposals: proposals,
            history: history
        )
    }
}
