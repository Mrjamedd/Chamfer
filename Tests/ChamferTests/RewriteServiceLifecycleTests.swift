import ChamferCore
import ChamferRewrite
import ChamferWatch
import Foundation
import Testing

@testable import Chamfer

private final class RewriteRecordingObserver: FolderObserving, @unchecked Sendable {
    private(set) var expectedWrites = Set<URL>()

    func start(onChange: @escaping @Sendable (NoteChange) -> Void) throws {}
    func stop() {}
    func expectOwnWrite(to url: URL) { expectedWrites.insert(url.standardizedFileURL) }
    func cancelExpectedOwnWrite(to url: URL) {
        expectedWrites.remove(url.standardizedFileURL)
    }
}

private actor SuspendedRewrite {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var releaseRequested = false

    func run(output: String) async -> String {
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
        return output
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

private struct SuspendedTestRewriter: Rewriter {
    let suspended: SuspendedRewrite
    let output: String

    var isAvailable: Bool { get async { true } }

    func rewrite(_ section: String, instructions: String) async throws -> String {
        await suspended.run(output: output)
    }
}

private actor RewriteCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

private struct CountingTestRewriter: Rewriter {
    let calls: RewriteCalls
    let output: String

    var isAvailable: Bool { get async { true } }

    func rewrite(_ section: String, instructions: String) async throws -> String {
        await calls.record()
        return output
    }
}

private struct RewriteBench {
    let directory: URL
    let root: URL
    let noteURL: URL
    let vault: Vault
    let summary: NoteSummary
    let proposal: Proposal

    init(subfolder: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let createdRoot = directory.appending(path: "Vault")
        root = createdRoot
        let folder = subfolder.map { createdRoot.appending(path: $0) } ?? createdRoot
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        noteURL = folder.appending(path: "Kickoff.md")
        try Data("teh note".utf8).write(to: noteURL)
        summary = try #require(VaultScanner.read(noteURL)?.summary)
        vault = Vault(
            url: root,
            noteCount: 1,
            configuration: VaultConfiguration(
                mode: .spelling,
                application: .review,
                runTrigger: .inactivity,
                inactivityDelay: 0,
                preserved: .standard
            )
        )
        proposal = Proposal(
            note: summary,
            hunks: [Hunk(before: "teh note", after: "the note", startLine: 1)],
            baseText: "teh note",
            proposedText: "the note",
            createdAt: Date(),
            sourceModifiedAt: summary.modifiedAt,
            mode: .spelling,
            modelID: "test",
            vaultID: vault.id
        )
    }

    @MainActor
    func model(
        proposals: [Proposal]? = nil,
        runState: RunState = .idle,
        rules: [VaultRule] = []
    ) -> AppModel {
        var configuredVault = vault
        configuredVault.rules = rules
        return AppModel(
            dashboard: DashboardState(
                runState: runState,
                folders: [],
                proposals: proposals ?? [],
                recentlyCleaned: [],
                recentNotes: [summary],
                searchableNotes: [NoteDocument(url: noteURL, text: "teh note")],
                openNote: NoteDocument(url: noteURL, text: "teh note"),
                vaults: [configuredVault],
                existingNoteURLs: [noteURL]
            ),
            preferences: AppPreferences(notifications: [])
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@Test @MainActor
func acceptingAProposalRemovesItAndCannotApplyItTwice() throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    let notes = NoteService(model: model)
    let snapshots = bench.directory.appending(path: "Snapshots")
    let service = RewriteService(
        model: model,
        notes: notes,
        writer: NoteWriter(snapshots: SnapshotStore(directory: snapshots)),
        modelEffort: { .base }
    )

    #expect(service.apply(bench.proposal, as: .review) == nil)
    #expect(service.apply(bench.proposal, as: .review) == nil)

    #expect(model.dashboard.proposals.isEmpty)
    #expect(model.dashboard.history.count == 1)
    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "the note")
}

@Test @MainActor
func outdatedProposalRequiresExplicitApprovalAndThenWritesExactCandidate() throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    let snapshots = bench.directory.appending(path: "Snapshots")
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        writer: NoteWriter(snapshots: SnapshotStore(directory: snapshots)),
        modelEffort: { .base }
    )

    try Data("my newer edit".utf8).write(to: bench.noteURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.modificationDate: bench.summary.modifiedAt.addingTimeInterval(10)],
        ofItemAtPath: bench.noteURL.path
    )

    #expect(
        service.apply(bench.proposal, as: .review)
            == .fileChangedDuringProcessing
    )
    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "my newer edit")
    #expect(model.dashboard.proposals == [bench.proposal])

    #expect(
        service.apply(bench.proposal, as: .review, allowOutdated: true) == nil
    )
    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "the note")
    let entry = try #require(model.dashboard.history.first)
    #expect(entry.previousText == "my newer edit")
    #expect(entry.appliedText == "the note")
    #expect(entry.sourceWasOutdated)
}

@Test @MainActor
func deterministicRulesWriteSnapshotAndHistoryWithoutAnAIModel() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("teh note   ".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model()
    let snapshots = bench.directory.appending(path: "Snapshots")
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        writer: NoteWriter(snapshots: SnapshotStore(directory: snapshots)),
        activeModelID: { nil },
        modelEffort: { .base }
    )

    #expect(await service.process(url: bench.noteURL))
    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "teh note\n")
    #expect(model.dashboard.proposals.isEmpty)
    let entry = try #require(model.dashboard.history.first)
    #expect(entry.previousText == "teh note   ")
    #expect(entry.appliedText == "teh note\n")
    #expect(entry.ruleIDs.contains("whitespace.trailing"))
    #expect(entry.ruleIDs.contains("file.finalNewline"))
    #expect(model.dashboard.recentlyCleaned.first?.rules == entry.ruleIDs)
    #expect(try FileManager.default.contentsOfDirectory(atPath: snapshots.path).count == 1)
}

@Test @MainActor
func rejectingAProposalRemovesItAndCannotRejectItTwice() throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    let service = RewriteService(model: model, notes: NoteService(model: model))

    service.reject(bench.proposal)
    service.reject(bench.proposal)

    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func acceptingAProposalForADeletedNoteRemovesTheDeadQueueEntry() throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    let service = RewriteService(model: model, notes: NoteService(model: model))
    try FileManager.default.removeItem(at: bench.noteURL)

    #expect(service.apply(bench.proposal, as: .review) == .vaultUnavailable)
    #expect(model.dashboard.proposals.isEmpty)
    #expect(model.dashboard.history.isEmpty)
}

@Test @MainActor
func aRewriteResultIsDiscardedWhenItsNoteIsDeletedInFlight() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model()
    let notes = NoteService(model: model)
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    let task = Task { await service.process(url: bench.noteURL) }
    await suspended.waitUntilStarted()
    try FileManager.default.removeItem(at: bench.noteURL)
    notes.handleChange(NoteChange(url: bench.noteURL, detectedAt: Date()))
    await suspended.release()
    _ = await task.value

    #expect(model.dashboard.proposals.isEmpty)
    #expect(model.dashboard.history.isEmpty)
}

@Test @MainActor
func clearingVaultSettingsInvalidatesARewriteAlreadyWaitingOnTheModel() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model()
    let notes = NoteService(model: model)
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    let task = Task { await service.process(url: bench.noteURL) }
    await suspended.waitUntilStarted()
    service.invalidateInFlightWork()
    notes.clearProcessingTriggers()
    _ = model.clearAllVaultSettings()
    await suspended.release()
    _ = await task.value

    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "plain note\n")
    #expect(model.dashboard.proposals.isEmpty)
    #expect(model.dashboard.history.isEmpty)
}

@Test @MainActor
func deletingANoteDuringRegenerationDoesNotLeaveItStuckInTheQueue() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model(proposals: [bench.proposal])
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    service.regenerate(bench.proposal)
    await suspended.waitUntilStarted()
    try FileManager.default.removeItem(at: bench.noteURL)
    await suspended.release()
    while service.isProcessing(bench.noteURL) { await Task.yield() }

    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func renamingAVaultDuringRegenerationKeepsItsRebasedProposalRetryable() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model(proposals: [bench.proposal])
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    service.regenerate(bench.proposal)
    await suspended.waitUntilStarted()
    let renamedRoot = bench.directory.appending(path: "Renamed")
    try FileManager.default.moveItem(at: bench.root, to: renamedRoot)
    model.dashboard.rebaseVault(bench.vault.id, to: renamedRoot)
    await suspended.release()
    while service.isProcessing(bench.noteURL) { await Task.yield() }

    let proposal = try #require(model.dashboard.proposals.first)
    #expect(proposal.note.url == renamedRoot.appending(path: "Kickoff.md").standardizedFileURL)
    #expect(proposal.state == .failed(.fileChangedDuringProcessing))
}

@Test @MainActor
func aRewriteResultIsDiscardedWhenRulesExcludeItsNoteInFlight() async throws {
    let bench = try RewriteBench(subfolder: "Archive")
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model()
    let notes = NoteService(model: model)
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    let task = Task { await service.process(url: bench.noteURL) }
    await suspended.waitUntilStarted()
    model.updateRules([VaultRule(kind: .exclude, path: "Archive")], for: bench.vault.id)
    await notes.performFullScan()
    await suspended.release()
    _ = await task.value

    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func changingToReviewWhileAModelRunsPreventsTheObsoleteAutomaticWrite() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model()
    model.dashboard.vaults[0].configuration?.application = .automatic
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    let task = Task { await service.process(url: bench.noteURL) }
    await suspended.waitUntilStarted()
    model.dashboard.vaults[0].configuration?.application = .review
    await suspended.release()
    _ = await task.value

    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "plain note\n")
    #expect(model.dashboard.history.isEmpty)
    #expect(model.dashboard.proposals.count == 1)
    #expect(model.dashboard.proposals[0].state == .pending)
    #expect(model.dashboard.proposals[0].automaticReviewReason == nil)
}

@Test @MainActor
func suspiciousAutomaticRewriteIsHeldForReviewWithAnExplanation() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let source = "Use compact controls and keep the interface calm.\n"
    try Data(source.utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model()
    model.dashboard.vaults[0].configuration?.application = .automatic
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: CountingTestRewriter(
                    calls: RewriteCalls(),
                    output: "Adopt dramatic visuals and make the interface energetic."
                )
            )
        },
    )

    _ = await service.process(url: bench.noteURL)

    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == source)
    #expect(model.dashboard.history.isEmpty)
    #expect(model.dashboard.proposals.count == 1)
    #expect(model.dashboard.proposals[0].state == .pending)
    #expect(
        model.dashboard.proposals[0].automaticReviewReason
            == .broaderThanExpectedForMode
    )
}

@Test @MainActor
func aFileChangedInFlightProducesARetryableFailureInsteadOfAStaleProposal() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model()
    let notes = NoteService(model: model)
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: notes,
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    let task = Task { await service.process(url: bench.noteURL) }
    await suspended.waitUntilStarted()
    try Data("user changed this".utf8).write(to: bench.noteURL, options: .atomic)
    notes.handleChange(NoteChange(url: bench.noteURL, detectedAt: Date()))
    await suspended.release()
    _ = await task.value

    #expect(model.dashboard.proposals.count == 1)
    #expect(model.dashboard.proposals[0].state == .failed(.fileChangedDuringProcessing))
}

@Test @MainActor
func regenerationCannotStartWhilePausedOrLeaveAProposalStuckRegenerating() throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal], runState: .paused)
    let service = RewriteService(model: model, notes: NoteService(model: model))

    service.regenerate(bench.proposal)
    #expect(model.dashboard.proposals[0].state == .pending)
}

@Test @MainActor
func processingCannotBeStartedDirectlyWhilePaused() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(runState: .paused)
    let calls = RewriteCalls()
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: CountingTestRewriter(calls: calls, output: "the note")
            )
        },
    )

    #expect(await service.process(url: bench.noteURL) == false)
    #expect(await calls.count == 0)
    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func deletingANoteBeforeRegenerationStartsRemovesItsDeadProposal() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    model.dashboard.proposals[0].state = .regenerating
    let service = RewriteService(model: model, notes: NoteService(model: model))
    try FileManager.default.removeItem(at: bench.noteURL)

    _ = await service.process(url: bench.noteURL, replacing: bench.proposal)

    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func aRuleChangeBeforeRegenerationStartsRemovesTheNowIneligibleProposal() async throws {
    let bench = try RewriteBench(subfolder: "Archive")
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    model.dashboard.proposals[0].state = .regenerating
    model.updateRules(
        [VaultRule(kind: .exclude, path: "Archive")],
        for: bench.vault.id
    )
    let service = RewriteService(model: model, notes: NoteService(model: model))

    _ = await service.process(url: bench.noteURL, replacing: bench.proposal)

    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func rejectingARegenerationPreventsItsLateResultFromReappearing() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("plain note\n".utf8).write(to: bench.noteURL, options: .atomic)
    let model = bench.model(proposals: [bench.proposal])
    let suspended = SuspendedRewrite()
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: SuspendedTestRewriter(
                    suspended: suspended,
                    output: "rewritten note\n"
                )
            )
        },
    )

    service.regenerate(bench.proposal)
    await suspended.waitUntilStarted()
    service.reject(bench.proposal)
    await suspended.release()
    while service.isProcessing(bench.noteURL) { await Task.yield() }

    #expect(model.dashboard.proposals.isEmpty)
}

@Test @MainActor
func anAlreadyQueuedNoteCannotBeSentToTheModelAgain() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    let calls = RewriteCalls()
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        activeModelID: { "test" },
        modelEffort: { .base },
        rewriterResolver: { _ in
            NamedRewriter(
                modelID: "test",
                rewriter: CountingTestRewriter(calls: calls, output: "the note")
            )
        },
    )

    _ = await service.process(url: bench.noteURL)

    #expect(await calls.count == 0)
    #expect(model.dashboard.proposals == [bench.proposal])
}

@Test @MainActor
func aFailedWriteCancelsEchoSuppressionSoTheNextRealEditIsNotLost() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    let observer = RewriteRecordingObserver()
    let notes = NoteService(model: model, observerFactory: { _ in observer })
    await notes.performFullScan()
    let impossibleSnapshots = bench.directory.appending(path: "not-a-directory")
    try Data("file".utf8).write(to: impossibleSnapshots)
    let stillOwed = Date(timeIntervalSince1970: 1_800_000_123)
    notes.handleChange(NoteChange(url: bench.noteURL, detectedAt: stillOwed))
    let service = RewriteService(
        model: model,
        notes: notes,
        writer: NoteWriter(snapshots: SnapshotStore(directory: impossibleSnapshots))
    )

    #expect(service.apply(bench.proposal, as: .review)?.isRetryable == true)
    #expect(observer.expectedWrites.isEmpty)
    #expect(notes.settling[bench.noteURL.standardizedFileURL] == stillOwed)
}

@Test @MainActor
func successfulWritesEndEchoSuppressionBeforeTheNextUserEdit() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let model = bench.model(proposals: [bench.proposal])
    let observer = RewriteRecordingObserver()
    let notes = NoteService(model: model, observerFactory: { _ in observer })
    await notes.performFullScan()
    let service = RewriteService(
        model: model,
        notes: notes,
        writer: NoteWriter(
            snapshots: SnapshotStore(directory: bench.directory.appending(path: "Snapshots"))
        )
    )

    #expect(service.apply(bench.proposal, as: .review) == nil)
    #expect(observer.expectedWrites.isEmpty)

    let entry = try #require(model.dashboard.history.first)
    #expect(service.restore(entry) == nil)
    #expect(observer.expectedWrites.isEmpty)
}

@Test @MainActor
func unavailableHistoryIsRefusedBeforeAnyWriteIsAnnounced() async throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    var unavailableVault = bench.vault
    unavailableVault.availability = .offline
    let entry = HistoryEntry(
        note: bench.summary,
        path: bench.noteURL,
        vaultID: bench.vault.id,
        occurredAt: Date(),
        mode: .spelling,
        modelID: "test",
        previousText: "teh note",
        appliedText: "the note",
        application: .review
    )
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [unavailableVault],
            history: [entry],
            existingNoteURLs: [bench.noteURL]
        )
    )
    let observer = RewriteRecordingObserver()
    let notes = NoteService(model: model, observerFactory: { _ in observer })
    let service = RewriteService(model: model, notes: notes)

    #expect(service.restore(entry) == .vaultUnavailable)
    #expect(observer.expectedWrites.isEmpty)
}

@Test @MainActor
func restoringADeletedNoteKeepsHistoryButMakesItNonActionable() throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    let entry = HistoryEntry(
        note: bench.summary,
        path: bench.noteURL,
        vaultID: bench.vault.id,
        occurredAt: Date(),
        mode: .spelling,
        modelID: "test",
        previousText: "teh note",
        appliedText: "the note",
        application: .review
    )
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [bench.vault],
            history: [entry],
            existingNoteURLs: [bench.noteURL]
        )
    )
    let service = RewriteService(model: model, notes: NoteService(model: model))
    try FileManager.default.removeItem(at: bench.noteURL)

    #expect(service.restore(entry) == .vaultUnavailable)
    #expect(model.dashboard.history == [entry])
    #expect(!model.dashboard.isHistoryActionable(entry))
}

@Test @MainActor
func aRevertedHistoryEntryCannotBeRestoredAgainThroughAStaleValue() throws {
    let bench = try RewriteBench()
    defer { bench.tearDown() }
    try Data("the note".utf8).write(to: bench.noteURL, options: .atomic)
    let entry = HistoryEntry(
        note: bench.summary,
        path: bench.noteURL,
        vaultID: bench.vault.id,
        occurredAt: Date(),
        mode: .spelling,
        modelID: "test",
        previousText: "teh note",
        appliedText: "the note",
        application: .review
    )
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [bench.vault],
            history: [entry],
            existingNoteURLs: [bench.noteURL]
        )
    )
    let service = RewriteService(
        model: model,
        notes: NoteService(model: model),
        writer: NoteWriter(
            snapshots: SnapshotStore(directory: bench.directory.appending(path: "Snapshots"))
        )
    )

    #expect(service.restore(entry) == nil)
    try Data("user edit".utf8).write(to: bench.noteURL, options: .atomic)

    #expect(service.restore(entry) == .vaultUnavailable)
    #expect(try String(contentsOf: bench.noteURL, encoding: .utf8) == "user edit")
}
