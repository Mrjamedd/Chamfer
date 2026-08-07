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
    /// This folder's departures from its vault's settings — the third and
    /// most specific level of the configuration hierarchy. A folder with
    /// nothing to say leaves this inherited and never appears in the
    /// interface as a thing to configure.
    public var policy: PolicyOverride

    public init(
        id: UUID = UUID(),
        url: URL,
        noteCount: Int,
        isReachable: Bool = true,
        lastSweep: Date?,
        policy: PolicyOverride = .inherited
    ) {
        self.id = id
        self.url = url
        self.noteCount = noteCount
        self.isReachable = isReachable
        self.lastSweep = lastSweep
        self.policy = policy
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
    /// The connected vaults, each with its own overrides.
    public var vaults: [Vault]
    /// Every rewrite that reached a conclusion, newest first once sorted.
    /// Stored in full; the interface decides how much of it to show.
    public var history: [HistoryEntry]
    /// The settings everything inherits from.
    public var globalPolicy: RewritePolicy

    public init(
        runState: RunState,
        folders: [WatchedFolder],
        proposals: [Proposal],
        recentlyCleaned: [CleanupRecord],
        recentNotes: [NoteSummary] = [],
        searchableNotes: [NoteDocument] = [],
        openNote: NoteDocument? = nil,
        vaults: [Vault] = [],
        history: [HistoryEntry] = [],
        globalPolicy: RewritePolicy = .standard
    ) {
        self.runState = runState
        self.folders = folders
        self.proposals = proposals
        self.recentlyCleaned = recentlyCleaned
        self.recentNotes = recentNotes
        self.searchableNotes = searchableNotes
        self.openNote = openNote
        self.vaults = vaults
        self.history = history
        self.globalPolicy = globalPolicy
    }

    public var pendingProposals: [Proposal] {
        proposals.filter { $0.state == .pending }
    }

    public var vaultNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0.name) })
    }

    /// The most recent modification date we know of for a note.
    ///
    /// Used to decide whether a pending rewrite has been overtaken by the
    /// user's own editing. Looks at the notes the watcher has seen rather than
    /// the disk, so the answer is a pure function of state.
    public func currentModification(of url: URL) -> Date? {
        recentNotes.first { $0.url == url }?.modifiedAt
    }

    /// Whether this rewrite was written against text that has since changed.
    public func isOutdated(_ proposal: Proposal) -> Bool {
        proposal.isOutdated(currentModification: currentModification(of: proposal.note.url))
    }

    public func timeline(limit: Int = HistoryWindow.standardLimit) -> ReviewTimeline {
        ReviewTimelineBuilder.build(
            proposals: proposals,
            history: history,
            vaultNames: vaultNames,
            limit: limit
        )
    }
}
