import ChamferCore
import ChamferRewrite
import ChamferUI
import ChamferWatch
import Foundation
import Observation

/// Generating rewrites, and applying the ones the user accepts.
///
/// The two halves are deliberately in one place because they share the rule
/// that matters: a rewrite is generated from text that was read at a known
/// moment, and it may only be applied to a file that still says what it said
/// then. Splitting generation from application would put that check somewhere
/// it could be forgotten.
@MainActor
@Observable
final class RewriteService {
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let notes: NoteService
    @ObservationIgnored private let writer: NoteWriter
    @ObservationIgnored private let notifications: NotificationCentre
    @ObservationIgnored private let rewriterResolver: (@MainActor (String) -> NamedRewriter?)?
    @ObservationIgnored private let activeModelID: @MainActor () -> String?
    /// How hard the model is asked to work, read fresh for every note.
    @ObservationIgnored private let modelEffort: @MainActor () -> ModelEffort

    /// Notes with a rewrite in flight. Stops the same note being sent to a
    /// model twice because a sweep and an inactivity timer both came due.
    @ObservationIgnored private var inFlight = Set<URL>()
    @ObservationIgnored private var resetGeneration: UInt64 = 0

    init(
        model: AppModel,
        notes: NoteService,
        writer: NoteWriter = NoteWriter(),
        notifications: NotificationCentre = NotificationCentre(),
        activeModelID: @escaping @MainActor () -> String? = {
            ModelsSelection.activeModelID()
        },
        modelEffort: @escaping @MainActor () -> ModelEffort = {
            ModelsSelection.effort()
        },
        rewriterResolver: (@MainActor (String) -> NamedRewriter?)? = nil
    ) {
        self.model = model
        self.notes = notes
        self.writer = writer
        self.notifications = notifications
        self.activeModelID = activeModelID
        self.modelEffort = modelEffort
        self.rewriterResolver = rewriterResolver
    }

    // MARK: - Generating

    /// Produces a rewrite for one note and files it according to the policy
    /// that governs it — into the queue, or straight onto disk.
    @discardableResult
    func process(url: URL, replacing existing: Proposal? = nil) async -> Bool {
        let key = url.standardizedFileURL
        guard !inFlight.contains(key) else { return false }
        guard model.dashboard.runState != .paused else { return false }

        if let existing {
            guard model.dashboard.proposals.contains(where: {
                $0.id == existing.id && $0.state.isActionable
            }) else { return false }
        } else if model.dashboard.actionableProposals.contains(where: {
            $0.note.url.standardizedFileURL == key
        }) {
            return false
        }

        guard let sourceVault = vault(containing: url), sourceVault.availability.isAvailable,
              let relative = NoteEligibility.relativePath(of: url, under: sourceVault.url),
              NoteEligibility.isEligible(relativePath: relative, rules: sourceVault.rules)
        else {
            if let existing {
                reconcileUnstartable(existing, at: url)
            }
            return false
        }
        // A connected vault remains read-only until every per-vault choice is
        // explicit. The deterministic rules do not need an AI model, so their
        // scheduling policy is resolved independently from model selection.
        guard let triggerPolicy = triggerPolicy(for: sourceVault) else {
            return false
        }
        let configurationGeneration = model.configurationGeneration
        let capturedResetGeneration = resetGeneration

        guard let source = readNote(url) else {
            if let existing {
                reconcileUnstartable(existing, at: url)
            } else {
                notes.handleChange(NoteChange(url: url, detectedAt: Date()))
            }
            return false
        }
        var document = source.document
        var summary = source.summary
        var claimedRewriteTrigger: Date?

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let previousState = model.dashboard.runState
        model.dashboard.runState = .rewriting(
            noteTitle: summary.title
        )
        defer {
            if case .rewriting = model.dashboard.runState {
                model.dashboard.runState = previousState
            }
        }

        let cleanup = CleanupRules.apply(
            to: document.text,
            preserving: triggerPolicy.preserved
        )
        if cleanup.changedAnything {
            let unsettled = notes.expectOwnWrite(to: document.url)
            claimedRewriteTrigger = unsettled
            if let failure = writer.write(
                cleanup.text,
                to: document.url,
                expectedModification: summary.modifiedAt,
                expectedText: document.text
            ) {
                notes.cancelExpectedOwnWrite(to: document.url, restoring: unsettled)
                record(
                    failure: failure,
                    for: document,
                    summary: summary,
                    policy: triggerPolicy,
                    vault: sourceVault,
                    replacing: existing
                )
                return true
            }
            notes.finishExpectedOwnWrite(to: document.url)

            let appliedAt = Date()
            model.dashboard.history.insert(
                HistoryEntry(
                    note: summary,
                    path: document.url,
                    vaultID: sourceVault.id,
                    occurredAt: appliedAt,
                    mode: .formatting,
                    modelID: "Chamfer rules",
                    previousText: document.text,
                    appliedText: cleanup.text,
                    application: .automatic,
                    ruleIDs: cleanup.appliedRuleIDs
                ),
                at: 0
            )
            model.dashboard.recentlyCleaned.insert(
                CleanupRecord(
                    note: summary,
                    rules: cleanup.appliedRuleIDs,
                    appliedAt: appliedAt
                ),
                at: 0
            )
            notes.refreshAfterOwnWrite(document.url)
            model.flush()

            guard let refreshed = readNote(document.url) else { return true }
            document = refreshed.document
            summary = refreshed.summary
        }

        // Rules still work with no AI selected. AI rewriting stays disabled
        // until the separate global model choice is explicit.
        guard let policy = resolvedPolicy(for: url, in: sourceVault) else {
            // `expectOwnWrite` consumed the edit that brought this note here.
            // The rules were allowed to finish without AI, but the rewrite is
            // still owed once the user deliberately activates a model.
            if let claimedRewriteTrigger {
                notes.restoreSettling(
                    for: document.url,
                    ifMissing: claimedRewriteTrigger
                )
            }
            if let existing {
                record(
                    failure: .modelUnavailable(model: "No active model"),
                    for: document,
                    summary: summary,
                    policy: triggerPolicy,
                    vault: sourceVault,
                    replacing: existing
                )
            }
            return true
        }

        guard let primary = resolveRewriter(policy.modelID) else {
            record(
                failure: .modelUnavailable(model: policy.modelID),
                for: document,
                summary: summary,
                policy: policy,
                vault: sourceVault,
                replacing: existing
            )
            return true
        }

        let outcome = await RewritePipeline.run(
            text: document.text,
            documentTitle: summary.title,
            policy: policy,
            model: primary,
            // Read here rather than captured at init, so changing the mode on
            // the Models page takes effect on the next note rather than on the
            // next launch.
            effort: modelEffort()
        )

        // A reset is an authority boundary. Work that started before it may
        // finish in the backend, but it may not recreate a proposal or touch a
        // file after the user cleared the settings that authorised it.
        guard configurationGeneration == model.configurationGeneration,
              capturedResetGeneration == resetGeneration
        else { return true }

        if let existing,
           !model.dashboard.proposals.contains(where: {
               $0.id == existing.id && $0.state == .regenerating
           }) {
            return true
        }

        guard var currentVault = model.dashboard.vaults.first(where: {
            $0.id == sourceVault.id
        }) else { return true }

        if currentVault.url.standardizedFileURL != sourceVault.url.standardizedFileURL {
            if let existing {
                fail(existing, with: .fileChangedDuringProcessing)
            }
            return true
        }

        guard currentVault.availability.isAvailable else {
            record(
                failure: .vaultUnavailable,
                for: document,
                summary: summary,
                policy: policy,
                vault: currentVault,
                replacing: existing
            )
            return true
        }

        guard let relative = NoteEligibility.relativePath(of: url, under: currentVault.url),
              NoteEligibility.isEligible(relativePath: relative, rules: currentVault.rules)
        else {
            notes.handleChange(NoteChange(url: url, detectedAt: Date()))
            model.flush()
            return true
        }

        let current = readNote(url)
        if current == nil {
            _ = notes.refreshVaultLocations()
            guard let refreshedVault = model.dashboard.vaults.first(where: {
                $0.id == sourceVault.id
            }) else { return true }
            currentVault = refreshedVault

            if currentVault.url.standardizedFileURL != sourceVault.url.standardizedFileURL {
                if let existing {
                    fail(existing, with: .fileChangedDuringProcessing)
                }
                return true
            }
            guard currentVault.availability.isAvailable else {
                record(
                    failure: .vaultUnavailable,
                    for: document,
                    summary: summary,
                    policy: policy,
                    vault: currentVault,
                    replacing: existing
                )
                return true
            }

            notes.handleChange(NoteChange(url: url, detectedAt: Date()))
            model.flush()
            return true
        }

        guard let current else { return true }

        if current.document.text != document.text {
            record(
                failure: .fileChangedDuringProcessing,
                for: current.document,
                summary: current.summary,
                policy: resolvedPolicy(for: url, in: currentVault) ?? policy,
                vault: currentVault,
                replacing: existing
            )
            return true
        }

        // The vault may have been reconfigured, or unconfigured entirely, while
        // the model was thinking. Either way the result was produced under
        // rules that no longer apply and must not be written.
        guard let currentPolicy = resolvedPolicy(for: url, in: currentVault),
              currentPolicy.mode == policy.mode,
              currentPolicy.preserved == policy.preserved,
              currentPolicy.modelID == policy.modelID
        else {
            record(
                failure: .fileChangedDuringProcessing,
                for: current.document,
                summary: current.summary,
                policy: policy,
                vault: currentVault,
                replacing: existing
            )
            return true
        }

        switch outcome {
        case .unchanged:
            // Nothing to decide. If this was a regeneration, the old proposal
            // goes rather than sitting there claiming changes that no longer
            // exist.
            if let existing {
                model.dashboard.proposals.removeAll { $0.id == existing.id }
                model.flush()
            }

        case let .failed(failure):
            record(
                failure: failure,
                for: document,
                summary: summary,
                policy: policy,
                vault: currentVault,
                replacing: existing
            )

        case let .proposed(product):
            let applicationDecision = RewriteApplicationDecision.decide(
                requested: currentPolicy.application,
                recommendation: product.reviewRecommendation
            )
            let automaticReviewReason: RewriteReviewRecommendation?
            switch applicationDecision {
            case let .queueForReview(reason):
                automaticReviewReason = reason
            case .applyAutomatically:
                automaticReviewReason = nil
            }

            let proposal = Proposal(
                id: existing?.id ?? UUID(),
                note: summary,
                hunks: product.hunks,
                baseText: document.text,
                proposedText: product.text,
                createdAt: Date(),
                sourceModifiedAt: summary.modifiedAt,
                mode: currentPolicy.mode,
                modelID: product.modelID,
                vaultID: sourceVault.id,
                retryCount: existing.map { $0.retryCount + 1 } ?? 0,
                automaticReviewReason: automaticReviewReason
            )

            switch applicationDecision {
            case .queueForReview:
                upsert(proposal)
                notifications.rewriteReady(
                    noteTitle: proposal.note.title,
                    preferences: model.preferences
                )
            case .applyAutomatically:
                // Automatic still snapshots first, and still refuses if the
                // file moved while the model was thinking.
                upsert(proposal)
                if let failure = apply(proposal, as: .automatic, text: product.text) {
                    notifications.rewriteFailed(
                        noteTitle: proposal.note.title,
                        failure: failure,
                        preferences: model.preferences
                    )
                } else {
                    notifications.automaticApplied(
                        noteTitle: proposal.note.title,
                        preferences: model.preferences
                    )
                }
            }
        }
        return true
    }

    /// Regenerates a queued rewrite from the note as it is now.
    func regenerate(_ proposal: Proposal) {
        guard model.dashboard.runState != .paused,
              let current = model.dashboard.proposals.first(where: {
                  $0.id == proposal.id && $0.state.isActionable && $0.state != .regenerating
              })
        else { return }
        update(current.id) { $0.state = .regenerating }
        model.flush()
        Task { await process(url: current.note.url, replacing: current) }
    }

    // MARK: - Applying

    /// Accepting: snapshot, write, and file what was replaced.
    ///
    /// `text` is the pipeline's own complete output when it is to hand, which
    /// is the version that was actually checked by the gate. Without it the
    /// hunks are replayed against the file, and that is refused outright if the
    /// file no longer matches.
    @discardableResult
    func apply(
        _ proposal: Proposal,
        as application: RewriteApplication,
        text: String? = nil,
        allowOutdated: Bool = false
    ) -> RewriteFailure? {
        guard model.dashboard.proposals.contains(where: {
            $0.id == proposal.id && $0.state == .pending
        }) else { return nil }

        guard let currentRead = readNote(proposal.note.url) else {
            notes.handleChange(NoteChange(url: proposal.note.url, detectedAt: Date()))
            if model.dashboard.proposals.contains(where: { $0.id == proposal.id }) {
                fail(proposal, with: .vaultUnavailable)
            } else {
                model.flush()
            }
            return .vaultUnavailable
        }
        let current = currentRead.document
        let wasOutdated = proposal.isOutdated(
            currentModification: currentRead.summary.modifiedAt
        )

        // Replacing edits made after generation is separate authority from
        // ordinary acceptance. Only the explicit warning action opts in.
        guard !wasOutdated || allowOutdated else {
            return .fileChangedDuringProcessing
        }

        let rewritten: String
        if let proposed = text ?? proposal.proposedText {
            if !allowOutdated, let base = proposal.baseText, base != current.text {
                fail(proposal, with: .fileChangedDuringProcessing)
                return .fileChangedDuringProcessing
            }
            rewritten = proposed
        } else {
            // Legacy proposals can be replayed only against the unchanged
            // source. Without an exact candidate, applying them over newer
            // writing would be guesswork.
            guard !allowOutdated,
                  let replayed = TextDiff.apply(proposal.hunks, to: current.text)
            else {
                fail(proposal, with: .fileChangedDuringProcessing)
                return .fileChangedDuringProcessing
            }
            rewritten = replayed
        }

        let unsettled = notes.expectOwnWrite(to: proposal.note.url)
        if let failure = writer.write(
            rewritten,
            to: proposal.note.url,
            // Nil when the user has explicitly approved an outdated rewrite:
            // they have been warned and have chosen to replace what they wrote
            // since, and a stale-file check would refuse the thing they asked
            // for.
            expectedModification: allowOutdated ? nil : proposal.sourceModifiedAt,
            expectedText: current.text
        ) {
            notes.cancelExpectedOwnWrite(to: proposal.note.url, restoring: unsettled)
            fail(proposal, with: failure)
            return failure
        }
        notes.finishExpectedOwnWrite(to: proposal.note.url)

        model.dashboard.history.insert(
            HistoryEntry(
                note: proposal.note,
                path: proposal.note.url,
                vaultID: proposal.vaultID,
                occurredAt: Date(),
                mode: proposal.mode,
                modelID: proposal.modelID,
                previousText: current.text,
                appliedText: rewritten,
                application: application,
                sourceWasOutdated: wasOutdated,
                retryCount: proposal.retryCount
            ),
            at: 0
        )
        model.dashboard.proposals.removeAll { $0.id == proposal.id }
        notes.refreshAfterOwnWrite(proposal.note.url)
        model.flush()
        return nil
    }

    func reject(_ proposal: Proposal) {
        model.dashboard.proposals.removeAll { $0.id == proposal.id }
        model.flush()
    }

    /// Undo: put the earlier text back, and snapshot what it replaces on the
    /// way — undoing an undo has to work too.
    @discardableResult
    func restore(_ entry: HistoryEntry) -> RewriteFailure? {
        guard let entry = model.dashboard.history.first(where: { $0.id == entry.id }),
              model.dashboard.isHistoryActionable(entry)
        else {
            return .vaultUnavailable
        }
        let unsettled = notes.expectOwnWrite(to: entry.path)
        if let failure = writer.restore(text: entry.previousText, to: entry.path) {
            notes.cancelExpectedOwnWrite(to: entry.path, restoring: unsettled)
            if failure == .vaultUnavailable {
                notes.handleChange(NoteChange(url: entry.path, detectedAt: Date()))
                model.flush()
            }
            return failure
        }
        notes.finishExpectedOwnWrite(to: entry.path)

        guard let index = model.dashboard.history.firstIndex(where: { $0.id == entry.id })
        else { return nil }

        model.dashboard.history[index] = HistoryEntry(
            id: entry.id,
            note: entry.note,
            path: entry.path,
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
            outcome: .reverted(at: Date())
        )
        notes.refreshAfterOwnWrite(entry.path)
        model.flush()
        return nil
    }

    // MARK: - Policy and models

    func vault(containing url: URL) -> Vault? {
        model.dashboard.vaults
            .filter { NoteEligibility.relativePath(of: url, under: $0.url) != nil }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }
    }

    /// Global, then vault, then the folder the note is actually in.
    /// What this vault does, or nil because nobody has said.
    ///
    /// Optional is the whole point. There is no hierarchy left to resolve
    /// through and no defaults to fall back on: an unconfigured vault produces
    /// no policy, and every caller therefore does nothing to its notes.
    func resolvedPolicy(for _: URL, in vault: Vault) -> RewritePolicy? {
        resolvedPolicy(for: vault)
    }

    /// The AI policy for a vault, or nil while its separate model/privacy
    /// choices do not authorise a rewrite. Folder overrides no longer exist,
    /// so the note URL does not change this result.
    func resolvedPolicy(for vault: Vault) -> RewritePolicy? {
        guard var policy = vault.configuration?.resolve(
            modelID: activeModelID()
        ) else { return nil }

        // The app-wide local-only switch outranks whatever the vault asked for.
        // "Never send my notes anywhere" is a promise Chamfer makes, and no
        // per-vault setting may overturn it.
        guard let permitted = ProcessingGuard.permittedModel(
            for: policy,
            preferences: model.preferences
        ) else { return nil }
        policy.modelID = permitted

        return policy
    }

    /// Fully configured per-vault behaviour without inventing a model. Used by
    /// the scheduler and offline deterministic rule pass.
    func triggerPolicy(for vault: Vault) -> RewritePolicy? {
        vault.configuration?.resolve(modelID: "chamfer.rules")
    }

    private func resolveRewriter(_ modelID: String) -> NamedRewriter? {
        if let rewriterResolver {
            return rewriterResolver(modelID)
        }
        guard !(model.preferences.localProcessingOnly == true
            && ProcessingGuard.isCloud(modelID))
        else { return nil }

        guard let configuration = RewriterFactory.configuration(
            for: modelID,
            localModelID: ModelsSelection.localModelID(),
            cloudProvider: ModelsSelection.cloudProvider()
        ),
        let rewriter = try? RewriterFactory.make(configuration: configuration)
        else { return nil }

        return NamedRewriter(modelID: modelID, rewriter: rewriter)
    }

    // MARK: - Bookkeeping

    private func read(_ url: URL) -> NoteDocument? {
        readNote(url)?.document
    }

    private func readNote(_ url: URL) -> (summary: NoteSummary, document: NoteDocument)? {
        guard let vault = vault(containing: url), vault.availability.isAvailable,
              let relative = NoteEligibility.relativePath(of: url, under: vault.url),
              NoteEligibility.isEligible(relativePath: relative, rules: vault.rules)
        else { return nil }
        return VaultBookmark.withAccess(to: vault.url) {
            guard let read = VaultScanner.read(url), let document = read.document else {
                return nil
            }
            return (read.summary, document)
        }
    }

    func isProcessing(_ url: URL) -> Bool {
        inFlight.contains(url.standardizedFileURL)
    }

    /// Invalidates results already awaiting an external model without
    /// pretending those tasks can be synchronously cancelled.
    func invalidateInFlightWork() {
        resetGeneration &+= 1
    }

    private func upsert(_ proposal: Proposal) {
        if let index = model.dashboard.proposals.firstIndex(where: { $0.id == proposal.id }) {
            model.dashboard.proposals[index] = proposal
        } else {
            model.dashboard.proposals.insert(proposal, at: 0)
        }
        model.flush()
    }

    private func update(_ id: UUID, _ change: (inout Proposal) -> Void) {
        guard let index = model.dashboard.proposals.firstIndex(where: { $0.id == id })
        else { return }
        change(&model.dashboard.proposals[index])
    }

    private func fail(_ proposal: Proposal, with failure: RewriteFailure) {
        update(proposal.id) { $0.state = .failed(failure) }
        model.flush()
    }

    private func reconcileUnstartable(_ proposal: Proposal, at url: URL) {
        guard model.dashboard.proposals.contains(where: {
            $0.id == proposal.id && $0.state.isActionable
        }) else { return }

        guard let vaultID = proposal.vaultID,
              let currentVault = model.dashboard.vaults.first(where: { $0.id == vaultID })
        else {
            model.dashboard.proposals.removeAll { $0.id == proposal.id }
            model.flush()
            return
        }

        guard currentVault.url.standardizedFileURL == vault(containing: url)?.url.standardizedFileURL
        else {
            fail(proposal, with: .fileChangedDuringProcessing)
            return
        }
        guard currentVault.availability.isAvailable else {
            fail(proposal, with: .vaultUnavailable)
            return
        }

        notes.handleChange(NoteChange(url: url, detectedAt: Date()))
        if model.dashboard.proposals.contains(where: { $0.id == proposal.id }) {
            fail(proposal, with: .vaultUnavailable)
        } else {
            model.flush()
        }
    }

    /// A failure becomes a visible, retryable queue entry rather than silence.
    ///
    /// The scope is explicit that a failure is recorded and never written up as
    /// a success, so this deliberately does not touch history: nothing
    /// happened to the file.
    private func record(
        failure: RewriteFailure,
        for document: NoteDocument,
        summary: NoteSummary?,
        policy: RewritePolicy,
        vault: Vault,
        replacing existing: Proposal?
    ) {
        let proposal = Proposal(
            id: existing?.id ?? UUID(),
            note: summary ?? Self.summary(for: document),
            hunks: existing?.hunks ?? [],
            createdAt: existing?.createdAt ?? Date(),
            sourceModifiedAt: summary?.modifiedAt ?? Date(),
            mode: policy.mode,
            modelID: policy.modelID,
            vaultID: vault.id,
            retryCount: existing.map { $0.retryCount + 1 } ?? 0,
            state: .failed(failure)
        )
        upsert(proposal)

        // A model being off is its own category: it is about the app's setup
        // rather than about this note, and someone who has switched off
        // failure notifications may still want to know their model is down.
        if case .modelUnavailable = failure {
            notifications.modelUnavailable(
                modelID: policy.modelID,
                preferences: model.preferences
            )
        } else {
            notifications.rewriteFailed(
                noteTitle: proposal.note.title,
                failure: failure,
                preferences: model.preferences
            )
        }
    }

    private static func summary(for document: NoteDocument) -> NoteSummary {
        NoteSummary(
            url: document.url,
            title: VaultScanner.title(for: document.url, text: document.text),
            wordCount: VaultScanner.wordCount(of: document.text),
            modifiedAt: Date()
        )
    }
}
