import ChamferCore
import Foundation
import Testing

@testable import ChamferWatch

// MARK: - Helpers

private let clock = Date(timeIntervalSince1970: 1_800_000_000)

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func note(_ title: String) -> NoteSummary {
    NoteSummary(
        url: URL(filePath: "/Vault/\(title).md"),
        title: title,
        wordCount: 120,
        modifiedAt: clock
    )
}

private func proposal(_ title: String, state: ProposalState = .pending) -> Proposal {
    Proposal(
        note: note(title),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: clock,
        state: state
    )
}

private func entry(_ title: String) -> HistoryEntry {
    HistoryEntry(
        note: note(title),
        path: URL(filePath: "/Vault/\(title).md"),
        occurredAt: clock,
        mode: .fullCleanup,
        modelID: "local.ollama",
        previousText: "teh old text",
        appliedText: "the old text",
        application: .review
    )
}

// MARK: - Round trips

@Test func anAbsentStoreIsAFreshInstallRatherThanAFailure() {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let loaded = StateStore(directory: directory).load()

    #expect(loaded.failure == nil)
    #expect(loaded.state == .empty)
    #expect(loaded.history.isEmpty)
}

@Test func settingsVaultsAndTheQueueSurviveARoundTrip() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    let policy = VaultConfiguration(
        mode: .spelling,
        application: .review,
        runTrigger: .inactivity,
        inactivityDelay: 1_200,
        preserved: .standard
    )

    let written = StoredState(
        vaults: [
            StoredVault(
                bookmark: Data([0x01, 0x02]),
                path: "/Users/someone/Notes",
                noteCount: 42,
                lastSweep: clock,
                configuration: policy,
                rules: [VaultRule(kind: .exclude, path: "Archive")]
            )
        ],
        preferences: AppPreferences(launchAtLogin: true, localProcessingOnly: true),
        proposals: [proposal("Kickoff")]
    )

    try store.save(written)
    let loaded = store.load()

    #expect(loaded.failure == nil)
    #expect(loaded.state == written)
    #expect(loaded.state.vaults.first?.rules.first?.path == "Archive")
    #expect(loaded.state.vaults.first?.configuration?.mode == .spelling)
    #expect(loaded.state.preferences.localProcessingOnly == true)
}

@Test func aPartialVaultConfigurationSurvivesARoundTripWithoutDefaults() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    let partial = VaultConfiguration(
        mode: .clarity,
        runTrigger: .schedule,
        sweep: .dailyAt(hour: 4)
    )

    try store.save(
        StoredState(
            vaults: [
                StoredVault(
                    bookmark: Data([0xA1]),
                    path: "/Users/someone/Notes",
                    configuration: partial
                )
            ]
        )
    )

    let restored = try #require(store.load().state.vaults.first?.configuration)
    #expect(restored == partial)
    #expect(restored.application == nil)
    #expect(restored.runTrigger == .schedule)
    #expect(restored.inactivityDelay == nil)
    #expect(restored.preserved == nil)
    #expect(!restored.isComplete)
}

@Test func versionOneCompletePoliciesMigrateWithoutChangingTheirChoices() throws {
    struct LegacyVault: Codable {
        let id: UUID
        let bookmark: Data
        let path: String
        let noteCount: Int
        let lastSweep: Date?
        let configuration: RewritePolicy?
        let folders: [WatchedFolder]
        let rules: [VaultRule]
    }
    struct LegacyState: Codable {
        let version: Int
        let vaults: [LegacyVault]
        let preferences: AppPreferences
        let proposals: [Proposal]
    }

    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = StateStore(directory: directory)
    let legacyPolicy = RewritePolicy(
        mode: .grammar,
        application: .automatic,
        inactivityDelay: 420,
        sweep: .everyHours(6),
        preserved: [.links, .frontMatter],
        modelID: "cloud.anthropic"
    )
    let legacy = LegacyState(
        version: 1,
        vaults: [
            LegacyVault(
                id: UUID(),
                bookmark: Data([0xB2]),
                path: "/Users/someone/Legacy",
                noteCount: 8,
                lastSweep: clock,
                configuration: legacyPolicy,
                folders: [],
                rules: []
            )
        ],
        preferences: AppPreferences(localProcessingOnly: true),
        proposals: []
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(legacy).write(to: store.stateURL, options: .atomic)

    let load = store.load()
    let migrated = try #require(load.state.vaults.first?.configuration)
    #expect(load.failure == nil)
    #expect(load.state.version == StoredState.currentVersion)
    #expect(migrated.mode == .grammar)
    #expect(migrated.application == .automatic)
    #expect(migrated.runTrigger == .schedule)
    #expect(migrated.inactivityDelay == 420)
    #expect(migrated.sweep == .everyHours(6))
    #expect(migrated.preserved == [.links, .frontMatter])
}

@Test func aFailedProposalKeepsItsReasonAcrossALaunch() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    try store.save(
        StoredState(proposals: [proposal("Kickoff", state: .failed(.vaultUnavailable))])
    )

    #expect(
        store.load().state.proposals.first?.state == .failed(.vaultUnavailable)
    )
}

@Test func anExactProposalKeepsItsOriginalAndCandidateAcrossALaunch() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    let exact = Proposal(
        note: note("Kickoff"),
        hunks: [Hunk(before: "teh plan", after: "the plan", startLine: 3)],
        baseText: "# Kickoff\n\nteh plan\n",
        proposedText: "# Kickoff\n\nthe plan\n",
        createdAt: clock,
        sourceModifiedAt: clock,
        mode: .spelling,
        modelID: "local.ollama"
    )

    try store.save(StoredState(proposals: [exact]))
    let restored = try #require(store.load().state.proposals.first)

    #expect(restored.baseText == exact.baseText)
    #expect(restored.proposedText == exact.proposedText)
    #expect(restored.hunks == exact.hunks)
}

@Test func historyRoundTripsWithBothTextsIntact() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    try store.save(history: [entry("Kickoff"), entry("Retro")])
    let loaded = store.load()

    #expect(loaded.history.count == 2)
    #expect(loaded.history.first?.previousText == "teh old text")
    #expect(loaded.history.first?.appliedText == "the old text")
    #expect(loaded.failure == nil)
}

@Test func historyStoredBeforeActionsWereRecordedStillDecodes() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    try store.save(history: [entry("Kickoff")])
    let stored = try Data(contentsOf: store.historyURL)
    var records = try #require(
        JSONSerialization.jsonObject(with: stored) as? [[String: Any]]
    )
    records[0].removeValue(forKey: "action")
    try JSONSerialization.data(withJSONObject: records)
        .write(to: store.historyURL, options: .atomic)

    let loaded = store.load()

    #expect(loaded.failure == nil)
    #expect(loaded.history.count == 1)
    #expect(loaded.history[0].action == .rewrite)
    #expect(loaded.history[0].previousText == "teh old text")
    #expect(loaded.history[0].appliedText == "the old text")
}

@Test func historyIsWrittenSeparatelyFromSettings() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    try store.save(history: [entry("Kickoff")])

    // Saving settings must not disturb a history file it never read. The two
    // are written on completely different rhythms.
    try store.save(StoredState(proposals: [proposal("Retro")]))

    let loaded = store.load()
    #expect(loaded.history.count == 1)
    #expect(loaded.state.proposals.count == 1)
}

// MARK: - Damage

@Test func aDamagedStoreIsSetAsideRatherThanOverwritten() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    try Data("{ this is not json".utf8).write(to: store.stateURL)

    let loaded = store.load()

    #expect(loaded.failure != nil)
    #expect(loaded.state == .empty)
    // The unreadable file must still exist somewhere: it may be the only copy
    // of something, so it is renamed rather than deleted.
    #expect(!FileManager.default.fileExists(atPath: store.stateURL.path))
    let siblings = try FileManager.default.contentsOfDirectory(
        atPath: directory.path
    )
    #expect(siblings.contains { $0.contains("damaged") })
}

@Test func damagedHistoryDoesNotTakeSettingsDownWithIt() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    try store.save(StoredState(proposals: [proposal("Kickoff")]))
    try Data("nonsense".utf8).write(to: store.historyURL)

    let loaded = store.load()

    #expect(loaded.failure != nil)
    #expect(loaded.history.isEmpty)
    #expect(loaded.state.proposals.count == 1)
}

@Test func aFileFromANewerChamferIsRefusedRatherThanMisread() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)

    var future = StoredState(proposals: [proposal("Kickoff")])
    future.version = StoredState.currentVersion + 1
    try store.save(future)

    let loaded = store.load()

    #expect(
        loaded.failure == .fromTheFuture(version: StoredState.currentVersion + 1)
    )
    #expect(loaded.state == .empty)
    // Refused, not destroyed: an older Chamfer must not eat a newer one's data.
    #expect(FileManager.default.fileExists(atPath: store.stateURL.path))
}

@Test func newerSettingsCannotHideOtherwiseReadableHistory() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    var future = StoredState(proposals: [proposal("Kickoff")])
    future.version = StoredState.currentVersion + 1
    let durableEntry = entry("Kickoff")
    try store.save(future)
    try store.save(history: [durableEntry])

    let loaded = store.load()

    #expect(loaded.state == .empty)
    #expect(loaded.history == [durableEntry])
    #expect(
        loaded.failure == .fromTheFuture(version: StoredState.currentVersion + 1)
    )
}
