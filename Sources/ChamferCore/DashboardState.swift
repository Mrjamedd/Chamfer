import Foundation

/// A folder Chamfer has been pointed at.
public struct WatchedFolder: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let noteCount: Int
    /// False when the security-scoped bookmark no longer resolves, e.g. an
    /// external disk was unplugged.
    public let isReachable: Bool
    public let lastSweep: Date?

    public init(
        id: UUID = UUID(),
        url: URL,
        noteCount: Int,
        isReachable: Bool = true,
        lastSweep: Date?
    ) {
        self.id = id
        self.url = url
        self.noteCount = noteCount
        self.isReachable = isReachable
        self.lastSweep = lastSweep
    }
}

/// What Chamfer is doing right now.
public enum RunState: Sendable, Equatable {
    case idle
    case sweeping(completed: Int, total: Int)
    case rewriting(noteTitle: String)
    case paused
    /// Rules still run; the rewrite pass is switched off with a reason.
    case rewritingUnavailable(reason: String)
    case failed(message: String)
}

/// Everything the dashboard renders, in one value.
///
/// The UI knows only this type. Fixtures produce it today and the real watcher
/// produces it later, and no view has to change in between.
public struct DashboardState: Sendable, Equatable {
    public var runState: RunState
    public var folders: [WatchedFolder]
    public var proposals: [Proposal]
    public var recentlyCleaned: [CleanupRecord]
    /// Lightweight metadata for the notes most recently touched by the user.
    ///
    /// This is intentionally separate from `recentlyCleaned`: opening or
    /// editing a note should make it recent even when Chamfer changed nothing.
    public var recentNotes: [NoteSummary]
    /// Full note values available to title-and-content search.
    ///
    /// The watcher owns populating this collection. Keeping it in dashboard
    /// state lets the UI remain a pure renderer with no filesystem access.
    public var searchableNotes: [NoteDocument]
    /// The note currently on the page, if one is open.
    public var openNote: NoteDocument?

    public init(
        runState: RunState,
        folders: [WatchedFolder],
        proposals: [Proposal],
        recentlyCleaned: [CleanupRecord],
        recentNotes: [NoteSummary] = [],
        searchableNotes: [NoteDocument] = [],
        openNote: NoteDocument? = nil
    ) {
        self.runState = runState
        self.folders = folders
        self.proposals = proposals
        self.recentlyCleaned = recentlyCleaned
        self.recentNotes = recentNotes
        self.searchableNotes = searchableNotes
        self.openNote = openNote
    }

    public var pendingProposals: [Proposal] {
        proposals.filter { $0.state == .pending }
    }
}
