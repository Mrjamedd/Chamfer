import Foundation

/// A folder Chamfer has been pointed at.
public struct WatchedFolder: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let url: URL
    public let noteCount: Int
    /// False when the security-scoped bookmark no longer resolves, e.g. an
    /// external disk was unplugged.
    public let isReachable: Bool
    public var lastSweep: Date?
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
    /// The connected vaults, each with its own overrides.
    public var vaults: [Vault]
    /// Every rewrite or restore that reached a conclusion, newest first once sorted.
    /// Stored in full; the interface decides how much of it to show.
    public var history: [HistoryEntry]
    /// Supported note paths known to exist, including notes current rules keep
    /// out of the processing index. History needs that distinction: excluded
    /// work stays undoable, while a deleted file must not offer a dead action.
    public var existingNoteURLs: Set<URL>

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
        existingNoteURLs: Set<URL>? = nil,
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
        self.existingNoteURLs = existingNoteURLs ?? Set(
            searchableNotes.map { $0.url.standardizedFileURL }
                + recentNotes.map { $0.url.standardizedFileURL }
        )
    }

    public var pendingProposals: [Proposal] {
        proposals.filter { $0.state == .pending }
    }

    /// Connected vaults nobody has told Chamfer how to treat.
    ///
    /// Drives the amber dot. Unreachable vaults are excluded — a folder on an
    /// unplugged disk already says what is wrong with it, and two warnings
    /// about the same vault would be one too many.
    public var unconfiguredVaults: [Vault] {
        vaults.filter { !$0.isConfigured && $0.availability.isAvailable }
    }

    public var needsConfiguration: Bool { !unconfiguredVaults.isEmpty }

    public var actionableProposals: [Proposal] {
        proposals.filter { $0.state.isActionable }
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
        let key = url.standardizedFileURL
        return recentNotes.first { $0.url.standardizedFileURL == key }?.modifiedAt
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

    public mutating func disconnectVault(_ id: UUID) {
        guard let vault = vaults.first(where: { $0.id == id }) else { return }
        let root = vault.url

        vaults.removeAll { $0.id == id }
        folders.removeAll { Self.isInside($0.url, root: root) }
        searchableNotes.removeAll { Self.isInside($0.url, root: root) }
        recentNotes.removeAll { Self.isInside($0.url, root: root) }
        recentlyCleaned.removeAll { Self.isInside($0.note.url, root: root) }
        existingNoteURLs = Set(existingNoteURLs.filter { !Self.isInside($0, root: root) })
        proposals.removeAll {
            $0.vaultID == id || Self.isInside($0.note.url, root: root)
        }
        if let openNote, Self.isInside(openNote.url, root: root) {
            self.openNote = nil
        }
    }

    public mutating func removeNote(at url: URL) {
        removeIndexedNote(at: url, fileStillExists: false)
    }

    public mutating func removeIndexedNote(at url: URL, fileStillExists: Bool) {
        let key = url.standardizedFileURL
        searchableNotes.removeAll { $0.url.standardizedFileURL == key }
        recentNotes.removeAll { $0.url.standardizedFileURL == key }
        recentlyCleaned.removeAll { $0.note.url.standardizedFileURL == key }
        proposals.removeAll { $0.note.url.standardizedFileURL == key }
        if fileStillExists {
            existingNoteURLs.insert(key)
        } else {
            existingNoteURLs.remove(key)
        }
        if openNote?.url.standardizedFileURL == key {
            openNote = nil
        }
    }

    public mutating func reconcileVaultScan(
        vaultID: UUID,
        documents: [NoteDocument],
        summaries: [NoteSummary],
        existingNoteURLs foundURLs: Set<URL>
    ) {
        guard let vault = vaults.first(where: { $0.id == vaultID }) else { return }
        let root = vault.url
        let eligible = Set(summaries.map { $0.url.standardizedFileURL })
        searchableNotes.removeAll { Self.isInside($0.url, root: root) }
        searchableNotes.append(contentsOf: documents)

        recentNotes.removeAll { Self.isInside($0.url, root: root) }
        recentNotes.append(contentsOf: summaries)

        existingNoteURLs = Set(existingNoteURLs.filter { !Self.isInside($0, root: root) })
        existingNoteURLs.formUnion(foundURLs.map { $0.standardizedFileURL })

        proposals.removeAll {
            ($0.vaultID == vaultID || Self.isInside($0.note.url, root: root))
                && !eligible.contains($0.note.url.standardizedFileURL)
        }
        recentlyCleaned.removeAll {
            Self.isInside($0.note.url, root: root)
                && !eligible.contains($0.note.url.standardizedFileURL)
        }
        if let openNote, Self.isInside(openNote.url, root: root) {
            self.openNote = documents.first {
                $0.url.standardizedFileURL == openNote.url.standardizedFileURL
            }
        }
    }

    public mutating func limitRecentNotes(to limit: Int = 40) {
        recentNotes = Self.mostRecent(recentNotes, limit: limit)
    }

    public mutating func rebaseVault(_ id: UUID, to newRoot: URL) {
        guard let index = vaults.firstIndex(where: { $0.id == id }) else { return }
        let oldRoot = vaults[index].url.standardizedFileURL
        let newRoot = newRoot.standardizedFileURL
        guard oldRoot != newRoot else { return }

        vaults[index].url = newRoot
        vaults[index].folders = vaults[index].folders.map {
            Self.rebased($0, from: oldRoot, to: newRoot)
        }
        folders = folders.map { Self.rebased($0, from: oldRoot, to: newRoot) }
        searchableNotes = searchableNotes.map {
            guard let url = Self.rebased($0.url, from: oldRoot, to: newRoot) else { return $0 }
            return NoteDocument(url: url, text: $0.text)
        }
        recentNotes = recentNotes.map { Self.rebased($0, from: oldRoot, to: newRoot) }
        recentlyCleaned = recentlyCleaned.map {
            guard Self.isInside($0.note.url, root: oldRoot) else { return $0 }
            return CleanupRecord(
                id: $0.id,
                note: Self.rebased($0.note, from: oldRoot, to: newRoot),
                rules: $0.rules,
                appliedAt: $0.appliedAt
            )
        }
        proposals = proposals.map { Self.rebased($0, from: oldRoot, to: newRoot) }
        history = history.map { Self.rebased($0, from: oldRoot, to: newRoot) }
        existingNoteURLs = Set(existingNoteURLs.map {
            Self.rebased($0, from: oldRoot, to: newRoot) ?? $0
        })
        if let openNote,
           let url = Self.rebased(openNote.url, from: oldRoot, to: newRoot) {
            self.openNote = NoteDocument(url: url, text: openNote.text)
        }
    }

    public func isHistoryActionable(_ entry: HistoryEntry) -> Bool {
        guard let current = history.first(where: { $0.id == entry.id }) else {
            return false
        }
        // Restore entries stay restorable, which makes Undo on a restore a
        // natural redo. Once a later event names this one as its source it has
        // already been undone, so leaving its control visible would offer an
        // action whose only result is another copy of the same restore.
        let hasBeenRestored = history.contains {
            $0.action.restoredEntryID == current.id
        }
        return current.canRestore
            && !hasBeenRestored
            && isHistoryNoteAvailable(current)
    }

    public func isHistoryNoteAvailable(_ entry: HistoryEntry) -> Bool {
        guard let current = history.first(where: { $0.id == entry.id }) else {
            return false
        }
        let key = current.path.standardizedFileURL
        guard existingNoteURLs.contains(key)
                || searchableNotes.contains(where: { $0.url.standardizedFileURL == key })
                || recentNotes.contains(where: { $0.url.standardizedFileURL == key })
        else { return false }

        if let vaultID = current.vaultID {
            return vaults.first(where: { $0.id == vaultID })?.availability.isAvailable == true
        }
        return vaults.contains {
            $0.availability.isAvailable && Self.isInside(current.path, root: $0.url)
        }
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        NoteEligibility.relativePath(of: url, under: root) != nil
    }

    private static func rebased(_ url: URL, from oldRoot: URL, to newRoot: URL) -> URL? {
        guard let relative = NoteEligibility.relativePath(of: url, under: oldRoot) else {
            return nil
        }
        return newRoot.appending(path: relative).standardizedFileURL
    }

    private static func rebased(
        _ summary: NoteSummary,
        from oldRoot: URL,
        to newRoot: URL
    ) -> NoteSummary {
        guard let url = rebased(summary.url, from: oldRoot, to: newRoot) else {
            return summary
        }
        return NoteSummary(
            id: summary.id,
            url: url,
            title: summary.title,
            wordCount: summary.wordCount,
            modifiedAt: summary.modifiedAt
        )
    }

    private static func rebased(
        _ folder: WatchedFolder,
        from oldRoot: URL,
        to newRoot: URL
    ) -> WatchedFolder {
        guard let url = rebased(folder.url, from: oldRoot, to: newRoot) else {
            return folder
        }
        return WatchedFolder(
            id: folder.id,
            url: url,
            noteCount: folder.noteCount,
            isReachable: folder.isReachable,
            lastSweep: folder.lastSweep
        )
    }

    private static func rebased(
        _ proposal: Proposal,
        from oldRoot: URL,
        to newRoot: URL
    ) -> Proposal {
        guard isInside(proposal.note.url, root: oldRoot) else { return proposal }
        return Proposal(
            id: proposal.id,
            note: rebased(proposal.note, from: oldRoot, to: newRoot),
            hunks: proposal.hunks,
            baseText: proposal.baseText,
            proposedText: proposal.proposedText,
            createdAt: proposal.createdAt,
            sourceModifiedAt: proposal.sourceModifiedAt,
            mode: proposal.mode,
            modelID: proposal.modelID,
            vaultID: proposal.vaultID,
            retryCount: proposal.retryCount,
            automaticReviewReason: proposal.automaticReviewReason,
            excludedHunkIDs: proposal.excludedHunkIDs,
            state: proposal.state
        )
    }

    private static func rebased(
        _ entry: HistoryEntry,
        from oldRoot: URL,
        to newRoot: URL
    ) -> HistoryEntry {
        guard let path = rebased(entry.path, from: oldRoot, to: newRoot) else {
            return entry
        }
        return HistoryEntry(
            id: entry.id,
            note: rebased(entry.note, from: oldRoot, to: newRoot),
            path: path,
            vaultID: entry.vaultID,
            occurredAt: entry.occurredAt,
            mode: entry.mode,
            modelID: entry.modelID,
            previousText: entry.previousText,
            appliedText: entry.appliedText,
            application: entry.application,
            sourceWasOutdated: entry.sourceWasOutdated,
            retryCount: entry.retryCount,
            ruleIDs: entry.ruleIDs,
            action: entry.action,
            outcome: entry.outcome
        )
    }

    private static func mostRecent(
        _ summaries: [NoteSummary],
        limit: Int = 40
    ) -> [NoteSummary] {
        summaries.sorted { left, right in
            if left.modifiedAt != right.modifiedAt {
                return left.modifiedAt > right.modifiedAt
            }
            return left.url.path < right.url.path
        }
        .prefix(limit)
        .map { $0 }
    }
}
