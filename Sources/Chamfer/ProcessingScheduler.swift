import ChamferCore
import ChamferWatch
import Foundation

/// The clock that decides when work actually happens.
///
/// One timer rather than one per note or per vault. A thousand notes settling
/// would otherwise be a thousand timers, and a tick that examines a dictionary
/// is cheaper than any of them.
@MainActor
final class ProcessingScheduler {
    /// How often the two questions are asked. Well under the shortest
    /// inactivity delay the interface offers, and far too coarse to matter for
    /// a sweep measured in hours.
    private static let tick = Duration.seconds(20)

    private let model: AppModel
    private let notes: NoteService
    private let rewrites: RewriteService
    private var task: Task<Void, Never>?

    init(model: AppModel, notes: NoteService, rewrites: RewriteService) {
        self.model = model
        self.notes = notes
        self.rewrites = rewrites
    }

    func start() {
        stop()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard !Task.isCancelled else { return }
                await self?.runOnce()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// One pass over both routes into processing.
    func runOnce(now: Date = Date()) async {
        if notes.refreshVaultLocations() {
            notes.vaultsChanged()
            return
        }

        // Pausing stops new work being picked up. It does not cancel what is
        // already in flight, which would be a different and worse promise.
        guard model.dashboard.runState != .paused else { return }

        await processSettledNotes(now: now)
        guard !Task.isCancelled, model.dashboard.runState != .paused else { return }
        await runDueSweeps(now: now)
    }

    // MARK: - Notes that have gone quiet

    private func processSettledNotes(now: Date) async {
        for (url, lastChanged) in notes.settling {
            if model.dashboard.actionableProposals.contains(where: {
                $0.note.url.standardizedFileURL == url.standardizedFileURL
            }) {
                notes.clearSettling(for: url, ifUnchangedSince: lastChanged)
                continue
            }
            guard let vault = rewrites.vault(containing: url) else {
                notes.clearSettling(for: url, ifUnchangedSince: lastChanged)
                continue
            }
            // No configuration, no processing — however long the note has
            // been quiet. A vault waits for the user, not the clock.
            guard let policy = rewrites.triggerPolicy(for: vault) else {
                continue
            }
            guard policy.runTrigger == .inactivity else {
                // A scheduled vault deliberately has no edit timer. Discard
                // the watcher event so it cannot spring to life later as a
                // second, hidden trigger.
                notes.clearSettling(for: url, ifUnchangedSince: lastChanged)
                continue
            }
            guard ProcessingSchedule.hasSettled(
                lastChanged: lastChanged,
                delay: policy.inactivityDelay,
                now: now
            ) else { continue }

            // The deterministic rules may still make an offline-safe change,
            // but a note whose AI configuration is missing remains owed. If
            // it were cleared here, intentionally activating a model later
            // would lose the edit that originally triggered the rewrite.
            let canRewrite = rewrites.resolvedPolicy(for: vault) != nil
            let started = await rewrites.process(url: url)
            if started && canRewrite {
                // A save that arrived during the rewrite has a newer timestamp
                // and remains owed; only the exact work just claimed leaves.
                notes.clearSettling(for: url, ifUnchangedSince: lastChanged)
            }
            guard !Task.isCancelled, model.dashboard.runState != .paused else { return }
        }
    }

    // MARK: - Sweeps

    private func runDueSweeps(now: Date) async {
        for vault in model.dashboard.vaults where vault.availability.isAvailable {
            guard !Task.isCancelled, model.dashboard.runState != .paused else { return }
            // A vault nobody has configured is never swept. This is the whole
            // meaning of requiring per-vault setup: the requirement is only
            // real if the app refuses to act without it.
            guard let policy = rewrites.triggerPolicy(for: vault),
                  policy.runTrigger == .schedule,
                  rewrites.resolvedPolicy(for: vault) != nil
            else { continue }
            guard ProcessingSchedule.isSweepDue(
                policy.sweep,
                lastSweep: vault.lastSweep,
                now: now
            ) else { continue }

            await sweep(vault)
        }
    }

    /// Walks one vault and offers every note to the pipeline.
    ///
    /// Notes already in the queue are skipped. A sweep that queued a second
    /// rewrite of a note already waiting for judgement would put the same
    /// decision in front of the user twice.
    private func sweep(_ vault: Vault) async {
        let localProcessingOnly = model.preferences.localProcessingOnly
        let queued = Set(
            model.dashboard.actionableProposals.map(\.note.url.standardizedFileURL)
        )

        let scan = await VaultScanner.scan(
            vaultID: vault.id,
            root: vault.url,
            rules: vault.rules
        )
        guard scan.failure == nil,
              !Task.isCancelled,
              model.dashboard.runState != .paused
        else { return }

        for summary in scan.summaries {
            guard !Task.isCancelled else { return }
            guard model.dashboard.runState != .paused else { return }
            guard !queued.contains(summary.url.standardizedFileURL) else { continue }
            await rewrites.process(url: summary.url)
            guard !Task.isCancelled, model.dashboard.runState != .paused else { return }
        }

        guard let current = model.dashboard.vaults.first(where: { $0.id == vault.id }),
              current.availability.isAvailable,
              current.url.standardizedFileURL == vault.url.standardizedFileURL,
              current.rules == vault.rules,
              current.configuration == vault.configuration,
              current.folders == vault.folders,
              model.preferences.localProcessingOnly == localProcessingOnly
        else { return }
        markSwept(vault.id, at: Date())
    }

    private func markSwept(_ vaultID: UUID, at date: Date) {
        guard let index = model.dashboard.vaults.firstIndex(where: { $0.id == vaultID })
        else { return }
        model.dashboard.vaults[index].lastSweep = date
        for folderIndex in model.dashboard.vaults[index].folders.indices {
            model.dashboard.vaults[index].folders[folderIndex].lastSweep = date
        }
    }
}
