import Foundation

/// Review and History as one page.
///
/// They are the same sequence of events in two tenses — rewrites that have not
/// been judged, and rewrites that have. Keeping them apart would put the same
/// note in two places and make "what happened to this note" a question you
/// answer by remembering which tab you were in. So: pending at the top,
/// grouped by vault as the scope requires, then everything that has already
/// happened, newest first, running off the bottom of the scroll.
public struct ReviewTimeline: Sendable, Equatable {
    /// Pending rewrites for one connected vault.
    public struct PendingGroup: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let vaultName: String
        public let proposals: [Proposal]

        public init(id: UUID, vaultName: String, proposals: [Proposal]) {
            self.id = id
            self.vaultName = vaultName
            self.proposals = proposals
        }
    }

    public let pending: [PendingGroup]
    /// The past, already trimmed to the requested depth.
    public let past: [HistoryEntry]
    /// How many entries exist in total, however many are being shown.
    public let storedCount: Int
    public let limit: Int

    public init(
        pending: [PendingGroup],
        past: [HistoryEntry],
        storedCount: Int,
        limit: Int
    ) {
        self.pending = pending
        self.past = past
        self.storedCount = storedCount
        self.limit = limit
    }

    public var pendingCount: Int {
        pending.reduce(0) { $0 + $1.proposals.count }
    }

    public var isEmpty: Bool { pending.isEmpty && past.isEmpty }

    /// Whether the "show everything" control at the foot has anything to
    /// reveal. The one condition under which it appears at all.
    public var hasMoreStored: Bool { storedCount > past.count }

    public var hiddenCount: Int { max(0, storedCount - past.count) }
}

public enum ReviewTimelineBuilder {
    /// Builds the page's contents.
    ///
    /// `vaultNames` is passed in rather than looked up so this stays a pure
    /// function over values; anything a proposal cannot be attributed to falls
    /// into one unnamed group rather than being dropped, because a rewrite the
    /// user cannot see is worse than one filed untidily.
    public static func build(
        proposals: [Proposal],
        history: [HistoryEntry],
        vaultNames: [UUID: String],
        limit: Int = HistoryWindow.standardLimit
    ) -> ReviewTimeline {
        let waiting = proposals.filter { $0.state.isActionable }

        let grouped = Dictionary(grouping: waiting) { $0.vaultID ?? Self.looseGroupID }
        let groups = grouped
            .map { vaultID, proposals in
                ReviewTimeline.PendingGroup(
                    id: vaultID,
                    vaultName: vaultNames[vaultID] ?? "Unfiled",
                    proposals: proposals.sorted { $0.createdAt > $1.createdAt }
                )
            }
            // Vaults in a stable order, with the loose group last so it never
            // pushes a real vault down the page.
            .sorted { left, right in
                if left.id == Self.looseGroupID { return false }
                if right.id == Self.looseGroupID { return true }
                return left.vaultName.localizedCaseInsensitiveCompare(right.vaultName) == .orderedAscending
            }

        return ReviewTimeline(
            pending: groups,
            past: HistoryWindow.recent(history, limit: limit),
            storedCount: history.count,
            limit: limit
        )
    }

    /// The bucket for proposals with no vault. A fixed identifier rather than
    /// a fresh one so the group keeps its identity across rebuilds and does
    /// not animate as if it were new every time the state changes.
    public static let looseGroupID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!
}

// MARK: - Selection

/// What the user has ticked for a bulk action.
///
/// The scope is explicit that bulk accept and reject apply only to rewrites
/// the user selected — never to everything on screen — so the selection is a
/// value the actions read from rather than an implicit "all visible".
public struct ReviewSelection: Sendable, Equatable {
    private(set) var ids: Set<UUID>

    public init(ids: Set<UUID> = []) {
        self.ids = ids
    }

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    public mutating func toggle(_ id: UUID) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
    }

    public mutating func clear() {
        ids.removeAll()
    }

    /// The proposals a bulk action would actually touch: the selected ones,
    /// and only those still awaiting judgement.
    public func resolve(in proposals: [Proposal]) -> [Proposal] {
        proposals.filter { ids.contains($0.id) && $0.state.isPending }
    }

    /// Drops selections whose proposal has gone, so a stale tick can never
    /// silently widen the next bulk action.
    public mutating func prune(against proposals: [Proposal]) {
        let live = Set(proposals.filter { $0.state.isPending }.map(\.id))
        ids.formIntersection(live)
    }
}
