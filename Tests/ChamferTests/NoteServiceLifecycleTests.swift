import ChamferCore
import ChamferWatch
import Foundation
import Testing

@testable import Chamfer

private final class RecordingObserver: FolderObserving, @unchecked Sendable {
    private(set) var stopped = false
    private(set) var expectedWrites = Set<URL>()
    private var onChange: (@Sendable (NoteChange) -> Void)?

    func start(onChange: @escaping @Sendable (NoteChange) -> Void) throws {
        self.onChange = onChange
    }
    func stop() { stopped = true }
    func expectOwnWrite(to url: URL) { expectedWrites.insert(url.standardizedFileURL) }
    func cancelExpectedOwnWrite(to url: URL) {
        expectedWrites.remove(url.standardizedFileURL)
    }

    func emit(_ change: NoteChange) {
        onChange?(change)
    }
}

private struct ObserverStartFailure: Error {}

private final class FailingObserver: FolderObserving, @unchecked Sendable {
    func start(onChange: @escaping @Sendable (NoteChange) -> Void) throws {
        throw ObserverStartFailure()
    }

    func stop() {}
    func expectOwnWrite(to url: URL) {}
    func cancelExpectedOwnWrite(to url: URL) {}
}

@MainActor
private final class ObserverRecorder {
    private(set) var roots: [[URL]] = []
    private(set) var observers: [RecordingObserver] = []

    func make(roots: [URL]) -> any FolderObserving {
        self.roots.append(roots.map(\.standardizedFileURL))
        let observer = RecordingObserver()
        observers.append(observer)
        return observer
    }
}

private struct NoteServiceSandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ relative: String, text: String = "teh note") throws -> URL {
        let url = root.appending(path: relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
        return url
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor SuspendedServiceScan {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var releaseRequested = false

    func run(_ result: VaultScan) async -> VaultScan {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            if releaseRequested {
                releaseRequested = false
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
        return result
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        if let releaseContinuation {
            releaseContinuation.resume()
            self.releaseContinuation = nil
        } else {
            releaseRequested = true
        }
    }
}

private actor ImmediateServiceScan {
    let result: VaultScan
    private(set) var calls = 0

    init(result: VaultScan) {
        self.result = result
    }

    func run() -> VaultScan {
        calls += 1
        return result
    }
}

private func serviceSummary(_ url: URL) -> NoteSummary {
    NoteSummary(url: url, title: "Note", wordCount: 2, modifiedAt: Date())
}

private func serviceProposal(_ url: URL, vaultID: UUID) -> Proposal {
    Proposal(
        note: serviceSummary(url),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: Date(),
        vaultID: vaultID
    )
}

private func serviceHistory(_ url: URL, vaultID: UUID) -> HistoryEntry {
    HistoryEntry(
        note: serviceSummary(url),
        path: url,
        vaultID: vaultID,
        occurredAt: Date(),
        mode: .spelling,
        modelID: "test",
        previousText: "teh",
        appliedText: "the",
        application: .review
    )
}

@Test @MainActor
func aScanWhilePausedUpdatesTheIndexWithoutClearingPause() async throws {
    let sandbox = try NoteServiceSandbox()
    defer { sandbox.tearDown() }
    let noteURL = try sandbox.write("Kickoff.md")
    let vault = Vault(url: sandbox.root, noteCount: 0)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .paused,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [vault]
        )
    )
    let recorder = ObserverRecorder()
    let service = NoteService(model: model, observerFactory: recorder.make)

    await service.performFullScan()

    #expect(model.dashboard.runState == .paused)
    #expect(model.dashboard.searchableNotes.map { $0.url.standardizedFileURL }
        == [noteURL.standardizedFileURL])
}

@Test @MainActor
func aFailedScanPreservesTheLastKnownIndexAndNoteCount() async {
    let missingRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let noteURL = missingRoot.appending(path: "Kickoff.md")
    let vault = Vault(url: missingRoot, noteCount: 7)
    let document = NoteDocument(url: noteURL, text: "cached")
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            recentNotes: [serviceSummary(noteURL)],
            searchableNotes: [document],
            vaults: [vault],
            existingNoteURLs: [noteURL]
        )
    )
    let recorder = ObserverRecorder()
    let service = NoteService(model: model, observerFactory: recorder.make)

    await service.performFullScan()

    #expect(model.dashboard.vaults[0].noteCount == 7)
    #expect(model.dashboard.searchableNotes == [document])
    #expect(model.dashboard.existingNoteURLs == [noteURL])
    #expect(model.dashboard.vaults[0].availability == .permissionDenied)
    #expect(recorder.roots.isEmpty)
}

@Test @MainActor
func aWatcherStartFailureRemainsVisibleAfterTheScanFinishes() async throws {
    let sandbox = try NoteServiceSandbox()
    defer { sandbox.tearDown() }
    _ = try sandbox.write("Kickoff.md")
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [Vault(url: sandbox.root, noteCount: 0)]
        )
    )
    let service = NoteService(model: model, observerFactory: { _ in FailingObserver() })

    await service.performFullScan()

    guard case .failed = model.dashboard.runState else {
        Issue.record("The observer failure was overwritten by an idle state")
        return
    }
}

@Test @MainActor
func aWatcherStartFailureCannotClearPause() async throws {
    let sandbox = try NoteServiceSandbox()
    defer { sandbox.tearDown() }
    _ = try sandbox.write("Kickoff.md")
    let model = AppModel(
        dashboard: DashboardState(
            runState: .paused,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [Vault(url: sandbox.root, noteCount: 0)]
        )
    )
    let service = NoteService(model: model, observerFactory: { _ in FailingObserver() })

    await service.performFullScan()

    #expect(model.dashboard.runState == .paused)
}

@Test @MainActor
func changesObservedDuringAScanAreReplayedAfterItsSnapshot() async throws {
    let sandbox = try NoteServiceSandbox()
    defer { sandbox.tearDown() }
    let noteURL = try sandbox.write("Kickoff.md", text: "old text")
    let oldSummary = try #require(VaultScanner.read(noteURL)?.summary)
    let vault = Vault(url: sandbox.root, noteCount: 1)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            recentNotes: [oldSummary],
            searchableNotes: [NoteDocument(url: noteURL, text: "old text")],
            openNote: NoteDocument(url: noteURL, text: "old text"),
            vaults: [vault],
            existingNoteURLs: [noteURL]
        )
    )
    let recorder = ObserverRecorder()
    let suspended = SuspendedServiceScan()
    let stale = VaultScan(
        vaultID: vault.id,
        documents: [NoteDocument(url: noteURL, text: "old text")],
        summaries: [oldSummary],
        existingNoteURLs: [noteURL],
        folders: [sandbox.root]
    )
    let service = NoteService(
        model: model,
        observerFactory: recorder.make,
        scanRunner: { _, _, _, _ in await suspended.run(stale) }
    )

    let task = Task { await service.performFullScan() }
    await suspended.waitUntilStarted()
    #expect(recorder.observers.count == 1)
    try Data("new text".utf8).write(to: noteURL, options: .atomic)
    let observedAt = Date(timeIntervalSince1970: 1_800_000_111)
    recorder.observers[0].emit(NoteChange(url: noteURL, detectedAt: observedAt))
    while model.dashboard.searchableNotes.first?.text != "new text" {
        await Task.yield()
    }
    await suspended.release()
    _ = await task.value

    #expect(model.dashboard.searchableNotes.first?.text == "new text")
    #expect(model.dashboard.openNote?.text == "new text")
    #expect(service.settling[noteURL.standardizedFileURL] == observedAt)
}

@Test @MainActor
func aStructuralWatchEventTriggersWholeVaultReconciliation() async throws {
    let sandbox = try NoteServiceSandbox()
    defer { sandbox.tearDown() }
    let oldURL = try sandbox.write("Old.md", text: "old")
    let newURL = sandbox.root.appending(path: "New.md")
    try FileManager.default.moveItem(at: oldURL, to: newURL)
    let vault = Vault(url: sandbox.root, noteCount: 1)
    let newRead = try #require(VaultScanner.read(newURL))
    let scan = VaultScan(
        vaultID: vault.id,
        documents: [try #require(newRead.document)],
        summaries: [newRead.summary],
        existingNoteURLs: [newURL],
        folders: [sandbox.root]
    )
    let scanner = ImmediateServiceScan(result: scan)
    let recorder = ObserverRecorder()
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            recentNotes: [serviceSummary(oldURL)],
            searchableNotes: [NoteDocument(url: oldURL, text: "old")],
            openNote: NoteDocument(url: oldURL, text: "old"),
            vaults: [vault],
            existingNoteURLs: [oldURL]
        )
    )
    let service = NoteService(
        model: model,
        observerFactory: recorder.make,
        scanRunner: { _, _, _, _ in await scanner.run() }
    )

    service.handleChange(
        NoteChange(url: sandbox.root, detectedAt: Date(), requiresRescan: true)
    )
    while await scanner.calls == 0 || model.dashboard.searchableNotes.first?.url != newURL {
        await Task.yield()
    }

    #expect(model.dashboard.searchableNotes.map(\.url) == [newURL])
    #expect(model.dashboard.recentNotes.map(\.url) == [newURL])
    #expect(model.dashboard.openNote == nil)
    #expect(model.dashboard.existingNoteURLs == [newURL])
}

@Test @MainActor
func deletingANoteClearsItsQueueAndOpenPageButNeverItsHistory() {
    let root = URL(filePath: "/Vault")
    let noteURL = root.appending(path: "Deleted.md")
    let vault = Vault(url: root, noteCount: 1)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [serviceProposal(noteURL, vaultID: vault.id)],
            recentlyCleaned: [],
            recentNotes: [serviceSummary(noteURL)],
            searchableNotes: [NoteDocument(url: noteURL, text: "cached")],
            openNote: NoteDocument(url: noteURL, text: "cached"),
            vaults: [vault],
            history: [serviceHistory(noteURL, vaultID: vault.id)],
            existingNoteURLs: [noteURL]
        )
    )
    let service = NoteService(model: model)

    service.handleChange(NoteChange(url: noteURL, detectedAt: Date()))

    #expect(model.dashboard.searchableNotes.isEmpty)
    #expect(model.dashboard.recentNotes.isEmpty)
    #expect(model.dashboard.proposals.isEmpty)
    #expect(model.dashboard.openNote == nil)
    #expect(model.dashboard.history.count == 1)
    #expect(!model.dashboard.isHistoryActionable(model.dashboard.history[0]))
}

@Test @MainActor
func disconnectingAVaultRestartsTheObserverWithoutItsRoot() async throws {
    let first = try NoteServiceSandbox()
    let second = try NoteServiceSandbox()
    defer {
        first.tearDown()
        second.tearDown()
    }
    _ = try first.write("One.md")
    _ = try second.write("Two.md")
    let firstVault = Vault(url: first.root, noteCount: 0)
    let secondVault = Vault(url: second.root, noteCount: 0)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [firstVault, secondVault]
        )
    )
    let recorder = ObserverRecorder()
    let service = NoteService(model: model, observerFactory: recorder.make)
    await service.performFullScan()

    model.removeVault(firstVault.id)
    await service.performFullScan()

    #expect(recorder.roots.last == [second.root.standardizedFileURL])
    #expect(recorder.observers.dropLast().allSatisfy { $0.stopped })
}

@Test @MainActor
func deletingAnExcludedNoteMakesItsDurableHistoryNonActionable() throws {
    let sandbox = try NoteServiceSandbox()
    defer { sandbox.tearDown() }
    let noteURL = try sandbox.write("Archive/Old.md")
    let activeURL = try sandbox.write("Active.md")
    let vault = Vault(
        url: sandbox.root,
        noteCount: 1,
        rules: [VaultRule(kind: .exclude, path: "Archive")]
    )
    let entry = serviceHistory(noteURL, vaultID: vault.id)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            recentNotes: [serviceSummary(activeURL)],
            searchableNotes: [NoteDocument(url: activeURL, text: "teh note")],
            vaults: [vault],
            history: [entry],
            existingNoteURLs: [noteURL, activeURL]
        )
    )
    let service = NoteService(model: model)
    try FileManager.default.removeItem(at: noteURL)

    service.handleChange(NoteChange(url: noteURL, detectedAt: Date()))

    #expect(model.dashboard.history == [entry])
    #expect(!model.dashboard.isHistoryActionable(entry))
    #expect(model.dashboard.vaults[0].noteCount == 1)
}

@Test @MainActor
func anUnreadableEligibleNoteIsIndexedButNeverScheduledForRewrite() throws {
    let sandbox = try NoteServiceSandbox()
    defer { sandbox.tearDown() }
    let noteURL = sandbox.root.appending(path: "Binary.md")
    try Data([0xff, 0xfe, 0xfd]).write(to: noteURL)
    let vault = Vault(url: sandbox.root, noteCount: 0)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [vault]
        )
    )
    let service = NoteService(model: model)

    service.handleChange(NoteChange(url: noteURL, detectedAt: Date()))

    #expect(model.dashboard.recentNotes.map(\.url) == [noteURL])
    #expect(model.dashboard.searchableNotes.isEmpty)
    #expect(service.settling[noteURL.standardizedFileURL] == nil)
}
