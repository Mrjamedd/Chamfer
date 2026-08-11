import ChamferCore
import ChamferRewrite
import ChamferWatch
import Foundation
import Testing

@testable import Chamfer

private actor SweepSuspension {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var releaseRequested = false

    func run() async {
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

private struct SuspendedSweepRewriter: Rewriter {
    let suspension: SweepSuspension

    var isAvailable: Bool { get async { true } }

    func rewrite(_ section: String, instructions: String) async throws -> String {
        await suspension.run()
        return section.replacingOccurrences(of: "teh", with: "the")
    }
}

private struct ImmediateSweepRewriter: Rewriter {
    var isAvailable: Bool { get async { true } }

    func rewrite(_ section: String, instructions: String) async throws -> String {
        section.replacingOccurrences(of: "teh", with: "the")
    }
}

private struct SchedulerBench {
    let directory: URL
    let root: URL
    let noteURL: URL
    let vault: Vault

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        root = directory.appending(path: "Vault")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        noteURL = root.appending(path: "Kickoff.md")
        // Scheduler/AI lifecycle tests start structurally clean so the
        // deterministic rule pass does not obscure the model event under test.
        try Data("teh note\n".utf8).write(to: noteURL)
        vault = Vault(
            url: root,
            noteCount: 1,
            lastSweep: nil,
            configuration: VaultConfiguration(
                mode: .spelling,
                application: .review,
                runTrigger: .schedule,
                sweep: .everyHours(1),
                preserved: .standard
            )
        )
    }

    @MainActor
    func model() -> AppModel {
        AppModel(
            dashboard: DashboardState(
                runState: .idle,
                folders: [],
                proposals: [],
                recentlyCleaned: [],
                vaults: [vault]
            ),
            preferences: AppPreferences(notifications: [])
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@Test @MainActor
func pausingAnActiveSweepLeavesTheSweepOwed() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    model.dashboard.vaults[0].folders = [
        WatchedFolder(url: bench.root, noteCount: 1, lastSweep: nil)
    ]
    let notes = NoteService(model: model)
    let suspension = SweepSuspension()
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedSweepRewriter(suspension: suspension)
            )
        },
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)

    let task = Task { await scheduler.runOnce() }
    await suspension.waitUntilStarted()
    model.togglePause()
    await suspension.release()
    _ = await task.value

    #expect(model.dashboard.runState == .paused)
    #expect(model.dashboard.vaults[0].lastSweep == nil)
    #expect(model.dashboard.vaults[0].folders[0].lastSweep == nil)
}

@Test @MainActor
func aSweepIsRecordedOnlyAfterEveryEligibleNoteFinishes() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    model.dashboard.vaults[0].folders = [
        WatchedFolder(url: bench.root, noteCount: 1, lastSweep: nil)
    ]
    let notes = NoteService(model: model)
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(modelID: "test", rewriter: ImmediateSweepRewriter())
        },
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)

    await scheduler.runOnce()

    #expect(model.dashboard.vaults[0].lastSweep != nil)
    #expect(
        model.dashboard.vaults[0].folders[0].lastSweep
            == model.dashboard.vaults[0].lastSweep
    )
    #expect(model.dashboard.actionableProposals.count == 1)
}

@Test @MainActor
func aSweepWithNoConfiguredModelRemainsOwed() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    let notes = NoteService(model: model)
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { nil }
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)

    await scheduler.runOnce()

    #expect(model.dashboard.vaults[0].lastSweep == nil)
    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func aSettledNoteWithNoConfiguredModelKeepsItsRewriteTrigger() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    model.dashboard.vaults[0].configuration?.runTrigger = .inactivity
    model.dashboard.vaults[0].configuration?.inactivityDelay = 0
    model.dashboard.vaults[0].configuration?.sweep = nil
    let notes = NoteService(model: model)
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        writer: NoteWriter(
            snapshots: SnapshotStore(directory: bench.directory.appending(path: "Snapshots"))
        ),
        activeModelID: { nil }
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)
    let changedAt = Date(timeIntervalSince1970: 1_800_000_000)
    try Data("teh note".utf8).write(to: bench.noteURL, options: .atomic)
    notes.handleChange(NoteChange(url: bench.noteURL, detectedAt: changedAt))

    await scheduler.runOnce(now: changedAt.addingTimeInterval(1))

    #expect(notes.settling[bench.noteURL.standardizedFileURL] == changedAt)
    #expect(model.dashboard.proposals.isEmpty)
    // Offline deterministic rules still run, including the final-newline rule.
    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "teh note\n")
}

@Test @MainActor
func changingPolicyDuringASweepLeavesTheSweepOwed() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    let notes = NoteService(model: model)
    let suspension = SweepSuspension()
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedSweepRewriter(suspension: suspension)
            )
        },
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)

    let task = Task { await scheduler.runOnce() }
    await suspension.waitUntilStarted()
    model.dashboard.vaults[0].configuration?.mode = .grammar
    await suspension.release()
    _ = await task.value

    #expect(model.dashboard.vaults[0].lastSweep == nil)
}

@Test @MainActor
func indexingAVaultDoesNotPretendItsRewriteSweepCompleted() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    let notes = NoteService(model: model)

    await notes.performFullScan()

    #expect(model.dashboard.vaults[0].lastSweep == nil)
    #expect(model.dashboard.vaults[0].folders.allSatisfy { $0.lastSweep == nil })
}

@Test @MainActor
func anEditArrivingDuringARewriteRemainsOwedAfterTheOlderWorkFinishes() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    model.dashboard.vaults[0].configuration = VaultConfiguration(
        mode: .spelling,
        application: .review,
        runTrigger: .inactivity,
        inactivityDelay: 0,
        preserved: .standard
    )
    let notes = NoteService(model: model)
    let suspension = SweepSuspension()
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedSweepRewriter(suspension: suspension)
            )
        },
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)
    let firstChange = Date(timeIntervalSince1970: 1_800_000_000)
    let secondChange = firstChange.addingTimeInterval(30)
    notes.handleChange(NoteChange(url: bench.noteURL, detectedAt: firstChange))

    let task = Task {
        await scheduler.runOnce(now: firstChange.addingTimeInterval(1))
    }
    await suspension.waitUntilStarted()
    try Data("user changed this".utf8).write(to: bench.noteURL, options: .atomic)
    notes.handleChange(NoteChange(url: bench.noteURL, detectedAt: secondChange))
    await suspension.release()
    _ = await task.value

    #expect(notes.settling[bench.noteURL.standardizedFileURL] == secondChange)
}

@Test @MainActor
func scheduledVaultIgnoresInactivityEventsUntilItsSweepIsDue() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    model.dashboard.vaults[0].lastSweep = Date(timeIntervalSince1970: 1_800_000_000)
    let notes = NoteService(model: model)
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(modelID: "test", rewriter: ImmediateSweepRewriter())
        },
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)
    let changedAt = Date(timeIntervalSince1970: 1_800_000_100)
    notes.handleChange(NoteChange(url: bench.noteURL, detectedAt: changedAt))

    await scheduler.runOnce(now: changedAt.addingTimeInterval(1))

    #expect(model.dashboard.proposals.isEmpty)
    #expect(notes.settling[bench.noteURL.standardizedFileURL] == nil)
}

@Test @MainActor
func inactivityVaultNeverStartsAScheduledSweep() async throws {
    let bench = try SchedulerBench()
    defer { bench.tearDown() }
    let model = bench.model()
    model.dashboard.vaults[0].configuration?.runTrigger = .inactivity
    model.dashboard.vaults[0].configuration?.inactivityDelay = 0
    model.dashboard.vaults[0].configuration?.sweep = nil
    let notes = NoteService(model: model)
    let rewrites = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(modelID: "test", rewriter: ImmediateSweepRewriter())
        },
    )
    let scheduler = ProcessingScheduler(model: model, notes: notes, rewrites: rewrites)

    await scheduler.runOnce()

    #expect(model.dashboard.proposals.isEmpty)
    #expect(model.dashboard.vaults[0].lastSweep == nil)
}
