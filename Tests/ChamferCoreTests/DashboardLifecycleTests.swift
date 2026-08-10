import Foundation
import Testing

@testable import ChamferCore

private let lifecycleClock = Date(timeIntervalSince1970: 1_800_000_000)

private func lifecycleSummary(_ url: URL, title: String? = nil) -> NoteSummary {
    NoteSummary(
        url: url,
        title: title ?? url.deletingPathExtension().lastPathComponent,
        wordCount: 12,
        modifiedAt: lifecycleClock
    )
}

private func lifecycleProposal(
    _ url: URL,
    vaultID: UUID,
    state: ProposalState = .pending
) -> Proposal {
    Proposal(
        note: lifecycleSummary(url),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: lifecycleClock,
        vaultID: vaultID,
        state: state
    )
}

private func lifecycleHistory(_ url: URL, vaultID: UUID) -> HistoryEntry {
    HistoryEntry(
        note: lifecycleSummary(url),
        path: url,
        vaultID: vaultID,
        occurredAt: lifecycleClock,
        mode: .fullCleanup,
        modelID: "local.ollama",
        previousText: "teh",
        appliedText: "the",
        application: .review
    )
}

private func lifecycleState(vault: Vault, noteURL: URL) -> DashboardState {
    let summary = lifecycleSummary(noteURL)
    return DashboardState(
        runState: .idle,
        folders: [
            WatchedFolder(
                url: noteURL.deletingLastPathComponent(),
                noteCount: 1,
                lastSweep: lifecycleClock
            )
        ],
        proposals: [lifecycleProposal(noteURL, vaultID: vault.id)],
        recentlyCleaned: [
            CleanupRecord(note: summary, rules: ["whitespace"], appliedAt: lifecycleClock)
        ],
        recentNotes: [summary],
        searchableNotes: [NoteDocument(url: noteURL, text: "teh")],
        openNote: NoteDocument(url: noteURL, text: "teh"),
        vaults: [vault],
        history: [lifecycleHistory(noteURL, vaultID: vault.id)],
        existingNoteURLs: [noteURL]
    )
}

@Test func disconnectingAVaultRemovesEveryEphemeralReferenceButKeepsHistory() {
    let root = URL(filePath: "/Vault")
    let noteURL = root.appending(path: "Projects/Kickoff.md")
    let vault = Vault(url: root, noteCount: 1)
    var state = lifecycleState(vault: vault, noteURL: noteURL)

    state.disconnectVault(vault.id)

    #expect(state.vaults.isEmpty)
    #expect(state.folders.isEmpty)
    #expect(state.searchableNotes.isEmpty)
    #expect(state.recentNotes.isEmpty)
    #expect(state.recentlyCleaned.isEmpty)
    #expect(state.openNote == nil)
    #expect(state.proposals.isEmpty)
    #expect(state.existingNoteURLs.isEmpty)
    #expect(state.history.count == 1)
    #expect(!state.isHistoryActionable(state.history[0]))
}

@Test func deletingANoteRemovesEveryActionableReferenceButKeepsHistory() {
    let root = URL(filePath: "/Vault")
    let noteURL = root.appending(path: "Kickoff.md")
    let vault = Vault(url: root, noteCount: 1)
    var state = lifecycleState(vault: vault, noteURL: noteURL)

    state.removeNote(at: noteURL)

    #expect(state.searchableNotes.isEmpty)
    #expect(state.recentNotes.isEmpty)
    #expect(state.recentlyCleaned.isEmpty)
    #expect(state.openNote == nil)
    #expect(state.proposals.isEmpty)
    #expect(state.history.count == 1)
    #expect(!state.isHistoryActionable(state.history[0]))
}

@Test func aSuccessfulRescanDropsNotesAndProposalsThatRulesNoLongerPermit() {
    let root = URL(filePath: "/Vault")
    let includedURL = root.appending(path: "Projects/Kickoff.md")
    let excludedURL = root.appending(path: "Archive/Old.md")
    let vault = Vault(url: root, noteCount: 2)
    var state = lifecycleState(vault: vault, noteURL: excludedURL)
    state.searchableNotes.append(NoteDocument(url: includedURL, text: "keep"))
    state.recentNotes.append(lifecycleSummary(includedURL))
    state.existingNoteURLs.insert(includedURL)

    state.reconcileVaultScan(
        vaultID: vault.id,
        documents: [NoteDocument(url: includedURL, text: "keep")],
        summaries: [lifecycleSummary(includedURL)],
        existingNoteURLs: [includedURL, excludedURL]
    )

    #expect(state.searchableNotes.map(\.url) == [includedURL])
    #expect(state.recentNotes.map(\.url) == [includedURL])
    #expect(state.openNote == nil)
    #expect(state.proposals.isEmpty)
    #expect(state.history.count == 1)
    #expect(state.isHistoryActionable(state.history[0]))
}

@Test func aSuccessfulRescanRefreshesTheOpenNoteFromTheSameSnapshotAsSearch() {
    let root = URL(filePath: "/Vault")
    let noteURL = root.appending(path: "Kickoff.md")
    let vault = Vault(url: root, noteCount: 1)
    var state = lifecycleState(vault: vault, noteURL: noteURL)
    let refreshed = NoteDocument(url: noteURL, text: "current text")

    state.reconcileVaultScan(
        vaultID: vault.id,
        documents: [refreshed],
        summaries: [lifecycleSummary(noteURL)],
        existingNoteURLs: [noteURL]
    )

    #expect(state.searchableNotes == [refreshed])
    #expect(state.openNote == refreshed)
}

@Test func reconnectingAVaultRebasesEveryVaultRelativeURL() {
    let oldRoot = URL(filePath: "/Volumes/Old/Vault")
    let newRoot = URL(filePath: "/Volumes/New/Vault Renamed")
    let oldNote = oldRoot.appending(path: "Projects/Kickoff.md")
    let newNote = newRoot.appending(path: "Projects/Kickoff.md")
    let vault = Vault(
        url: oldRoot,
        noteCount: 1,
        folders: [
            WatchedFolder(
                url: oldRoot.appending(path: "Projects"),
                noteCount: 1,
                lastSweep: lifecycleClock
            )
        ]
    )
    var state = lifecycleState(vault: vault, noteURL: oldNote)

    state.rebaseVault(vault.id, to: newRoot)

    #expect(state.vaults[0].url == newRoot)
    #expect(state.vaults[0].folders[0].url == newRoot.appending(path: "Projects"))
    #expect(state.folders[0].url == newRoot.appending(path: "Projects"))
    #expect(state.searchableNotes[0].url == newNote)
    #expect(state.recentNotes[0].url == newNote)
    #expect(state.recentlyCleaned[0].note.url == newNote)
    #expect(state.openNote?.url == newNote)
    #expect(state.proposals[0].note.url == newNote)
    #expect(state.history[0].path == newNote)
    #expect(state.history[0].note.url == newNote)
    #expect(state.existingNoteURLs == [newNote])
}

@Test func historyCannotBeActedOnWhileItsVaultIsUnavailable() {
    let root = URL(filePath: "/Volumes/Notes")
    let noteURL = root.appending(path: "Kickoff.md")
    var vault = Vault(url: root, noteCount: 1)
    var state = lifecycleState(vault: vault, noteURL: noteURL)

    #expect(state.isHistoryActionable(state.history[0]))

    vault.availability = .offline
    state.vaults[0] = vault
    #expect(!state.isHistoryActionable(state.history[0]))
}

@Test func everyQueueStateWithAnAvailableActionIsCounted() {
    let vaultID = UUID()
    let root = URL(filePath: "/Vault")
    let proposals = [
        lifecycleProposal(root.appending(path: "Pending.md"), vaultID: vaultID),
        lifecycleProposal(
            root.appending(path: "Working.md"),
            vaultID: vaultID,
            state: .regenerating
        ),
        lifecycleProposal(
            root.appending(path: "Failed.md"),
            vaultID: vaultID,
            state: .failed(.vaultUnavailable)
        ),
        lifecycleProposal(
            root.appending(path: "Accepted.md"),
            vaultID: vaultID,
            state: .accepted
        ),
        lifecycleProposal(
            root.appending(path: "Rejected.md"),
            vaultID: vaultID,
            state: .rejected
        )
    ]
    let state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: proposals,
        recentlyCleaned: []
    )

    #expect(state.actionableProposals.map(\.note.title) == ["Pending", "Working", "Failed"])
    #expect(state.timeline().pendingCount == state.actionableProposals.count)
}
