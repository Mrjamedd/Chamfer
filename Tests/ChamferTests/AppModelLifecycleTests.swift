import ChamferCore
import ChamferWatch
import Foundation
import Testing

@testable import Chamfer

private let appClock = Date(timeIntervalSince1970: 1_800_000_000)

private func appSummary(_ url: URL) -> NoteSummary {
    NoteSummary(
        url: url,
        title: url.deletingPathExtension().lastPathComponent,
        wordCount: 4,
        modifiedAt: appClock
    )
}

private func appProposal(_ url: URL, vaultID: UUID) -> Proposal {
    Proposal(
        note: appSummary(url),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: appClock,
        vaultID: vaultID
    )
}

private func appDashboard(vault: Vault, noteURL: URL) -> DashboardState {
    DashboardState(
        runState: .idle,
        folders: [],
        proposals: [appProposal(noteURL, vaultID: vault.id)],
        recentlyCleaned: [],
        recentNotes: [appSummary(noteURL)],
        searchableNotes: [NoteDocument(url: noteURL, text: "teh")],
        openNote: NoteDocument(url: noteURL, text: "teh"),
        vaults: [vault],
        existingNoteURLs: [noteURL]
    )
}

private func appTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Test @MainActor
func removingAVaultAlsoRemovesItsBookmarkAndEveryDependentStateValue() {
    let root = URL(filePath: "/Vault")
    let noteURL = root.appending(path: "Kickoff.md")
    let vault = Vault(url: root, noteCount: 1)
    let model = AppModel()
    model.addVault(vault, bookmark: Data([0x01]))
    model.dashboard = appDashboard(vault: vault, noteURL: noteURL)

    model.removeVault(vault.id)

    #expect(model.bookmark(for: vault.id) == nil)
    #expect(model.dashboard.vaults.isEmpty)
    #expect(model.dashboard.searchableNotes.isEmpty)
    #expect(model.dashboard.recentNotes.isEmpty)
    #expect(model.dashboard.openNote == nil)
    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func reconnectingAVaultKeepsItsIdentityAndRebasesItsState() {
    let oldRoot = URL(filePath: "/Volumes/Old/Vault")
    let newRoot = URL(filePath: "/Volumes/New/Vault")
    let oldNote = oldRoot.appending(path: "Kickoff.md")
    let vault = Vault(url: oldRoot, availability: .missing, noteCount: 1)
    let model = AppModel(dashboard: appDashboard(vault: vault, noteURL: oldNote))

    model.reconnectVault(vault.id, to: newRoot, bookmark: Data([0x02]))

    #expect(model.dashboard.vaults.map(\.id) == [vault.id])
    #expect(model.dashboard.vaults[0].url == newRoot)
    #expect(model.dashboard.vaults[0].availability == .available)
    #expect(model.dashboard.searchableNotes[0].url == newRoot.appending(path: "Kickoff.md"))
    #expect(model.bookmark(for: vault.id) == Data([0x02]))
}

@Test @MainActor
func restoringStartsFromSavedTruthInsteadOfLeavingSessionStateBehind() throws {
    let directory = appTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    try store.save(.empty)

    let root = URL(filePath: "/Vault")
    let noteURL = root.appending(path: "Kickoff.md")
    let vault = Vault(url: root, noteCount: 1)
    let model = AppModel(store: store)
    model.addVault(vault, bookmark: Data([0x01]))
    model.dashboard = appDashboard(vault: vault, noteURL: noteURL)

    model.restore()

    #expect(model.dashboard == .empty)
    #expect(model.bookmark(for: vault.id) == nil)
}

@Test @MainActor
func aVaultWithoutABookmarkCannotBeSilentlyDroppedFromTheSavedState() throws {
    let directory = appTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    let saved = StoredState()
    try store.save(saved)

    let vault = Vault(url: URL(filePath: "/Vault"), noteCount: 0)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [vault]
        ),
        store: store
    )

    model.flush()

    #expect(store.load().state == saved)
    #expect(model.storeFailure != nil)
}

@Test @MainActor
func persistenceKeepsOnlyProposalStatesThatCanStillBeActedOn() throws {
    let directory = appTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    let root = URL(filePath: "/Vault")
    let vaultID = UUID()
    let pending = appProposal(root.appending(path: "Pending.md"), vaultID: vaultID)
    var failed = appProposal(root.appending(path: "Failed.md"), vaultID: vaultID)
    failed.state = .failed(.vaultUnavailable)
    var regenerating = appProposal(root.appending(path: "Working.md"), vaultID: vaultID)
    regenerating.state = .regenerating
    var accepted = appProposal(root.appending(path: "Accepted.md"), vaultID: vaultID)
    accepted.state = .accepted
    var rejected = appProposal(root.appending(path: "Rejected.md"), vaultID: vaultID)
    rejected.state = .rejected
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [pending, failed, regenerating, accepted, rejected],
            recentlyCleaned: []
        ),
        store: store
    )

    model.flush()
    let persisted = store.load().state.proposals
    #expect(persisted.map(\.id) == [pending.id, failed.id, regenerating.id])
    #expect(persisted[2].state == .pending)

    try store.save(
        StoredState(proposals: [pending, failed, regenerating, accepted, rejected])
    )
    model.restore()
    #expect(model.dashboard.proposals.map(\.id) == [pending.id, failed.id, regenerating.id])
    #expect(model.dashboard.proposals[2].state == .pending)
}

@Test @MainActor
func overlappingVaultsCannotBeConnectedAndScheduleTheSameNoteTwice() {
    let outer = Vault(url: URL(filePath: "/Notes"), noteCount: 0)
    let inner = Vault(url: URL(filePath: "/Notes/Projects"), noteCount: 0)
    let model = AppModel()

    #expect(model.addVault(outer, bookmark: Data([0x01])))
    #expect(!model.addVault(inner, bookmark: Data([0x02])))
    #expect(model.dashboard.vaults.map(\.id) == [outer.id])
    #expect(model.bookmark(for: inner.id) == nil)

    let inverse = AppModel()
    #expect(inverse.addVault(inner, bookmark: Data([0x03])))
    #expect(!inverse.addVault(outer, bookmark: Data([0x04])))
    #expect(inverse.dashboard.vaults.map(\.id) == [inner.id])
    #expect(inverse.bookmark(for: outer.id) == nil)

    let other = Vault(url: URL(filePath: "/Other"), noteCount: 0)
    #expect(model.addVault(other, bookmark: Data([0x05])))
    #expect(!model.reconnectVault(
        other.id,
        to: URL(filePath: "/Notes/Archive"),
        bookmark: Data([0x06])
    ))
    #expect(model.dashboard.vaults.first(where: { $0.id == other.id })?.url == other.url)
}

@Test @MainActor
func historyIsSavedEvenWhenTheStateFileCannotBeReplaced() throws {
    let directory = appTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    try FileManager.default.createDirectory(
        at: store.stateURL,
        withIntermediateDirectories: true
    )
    let noteURL = URL(filePath: "/Vault/Kickoff.md")
    let entry = HistoryEntry(
        note: appSummary(noteURL),
        path: noteURL,
        occurredAt: appClock,
        mode: .spelling,
        modelID: "test",
        previousText: "teh",
        appliedText: "the",
        application: .review
    )
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            history: [entry]
        ),
        store: store
    )

    model.flush()

    #expect(store.load().history == [entry])
    #expect(model.storeFailure != nil)
}

@Test @MainActor
func restoringFutureSettingsNeverOverwritesThemOnFlush() throws {
    let directory = appTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    var future = StoredState()
    future.version = StoredState.currentVersion + 1
    try store.save(future)
    let original = try Data(contentsOf: store.stateURL)
    let model = AppModel(store: store)

    model.restore()
    model.flush()

    #expect(model.storeFailure == .fromTheFuture(version: future.version))
    #expect(try Data(contentsOf: store.stateURL) == original)
}

@Test @MainActor
func clearingVaultSettingsPreservesConnectionsAIIndependentDataAndFiles() throws {
    let directory = appTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    let firstRoot = directory.appending(path: "First")
    let secondRoot = directory.appending(path: "Second")
    try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
    let noteURL = firstRoot.appending(path: "Keep.md")
    try Data("Keep this note exactly.".utf8).write(to: noteURL)
    let configured = VaultConfiguration(
        mode: .grammar,
        application: .automatic,
        runTrigger: .schedule,
        sweep: .everyHours(6),
        preserved: .all
    )
    let first = Vault(
        url: firstRoot,
        noteCount: 1,
        lastSweep: appClock,
        configuration: configured,
        folders: [
            WatchedFolder(
                url: firstRoot,
                noteCount: 1,
                lastSweep: appClock
            )
        ],
        rules: [VaultRule(kind: .exclude, path: "Archive")]
    )
    let second = Vault(
        url: secondRoot,
        noteCount: 0,
        configuration: configured,
        rules: [VaultRule(kind: .includeOnly, path: "Current")]
    )
    let history = HistoryEntry(
        note: appSummary(noteURL),
        path: noteURL,
        vaultID: first.id,
        occurredAt: appClock,
        mode: .grammar,
        modelID: "cloud.anthropic",
        previousText: "Before",
        appliedText: "After",
        application: .review
    )
    let preferences = AppPreferences(
        notifications: [.rewriteFailed, .modelUnavailable],
        launchAtLogin: true,
        localProcessingOnly: true
    )
    let model = AppModel(preferences: preferences, store: store)
    #expect(model.addVault(first, bookmark: Data([0x11])))
    #expect(model.addVault(second, bookmark: Data([0x22])))
    model.dashboard.proposals = [appProposal(noteURL, vaultID: first.id)]
    model.dashboard.searchableNotes = [
        NoteDocument(url: noteURL, text: "Keep this note exactly.")
    ]
    model.dashboard.history = [history]
    model.dashboard.existingNoteURLs = [noteURL]
    let generation = model.configurationGeneration

    let failure = model.clearAllVaultSettings()

    #expect(failure == nil)
    #expect(model.configurationGeneration == generation + 1)
    #expect(model.dashboard.vaults.map(\.id) == [first.id, second.id])
    #expect(model.bookmark(for: first.id) == Data([0x11]))
    #expect(model.bookmark(for: second.id) == Data([0x22]))
    #expect(model.dashboard.vaults.allSatisfy {
        $0.configuration == nil && $0.rules.isEmpty && $0.lastSweep == nil
    })
    #expect(model.dashboard.vaults[0].folders.allSatisfy { $0.lastSweep == nil })
    #expect(model.dashboard.proposals.isEmpty)
    #expect(model.dashboard.history == [history])
    #expect(model.dashboard.searchableNotes.count == 1)
    #expect(model.preferences == preferences)
    #expect(try String(contentsOf: noteURL, encoding: .utf8) == "Keep this note exactly.")

    let saved = store.load().state
    #expect(saved.vaults.map(\.id) == [first.id, second.id])
    #expect(saved.vaults.allSatisfy { $0.configuration == nil && $0.rules.isEmpty })
    #expect(saved.preferences == preferences)
}
