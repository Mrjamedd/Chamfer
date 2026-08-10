import ChamferCore
import ChamferWatch
import Foundation
import Observation

/// The layer between the disk and the interface.
///
/// `AppModel` holds what is true; this keeps it true. It walks the connected
/// vaults, watches them for changes, and folds what it finds back into
/// `DashboardState` — which is the only thing any view has ever known about, so
/// the entire interface went from fixtures to real notes without a single view
/// changing.
///
/// Everything here is `@MainActor` because it writes to the model. The work
/// that is actually slow — walking a four-thousand-note vault, reading files —
/// happens inside detached scanner calls that hop back here only to report.
@MainActor
@Observable
final class NoteService {
    typealias ScanRunner = @MainActor (
        UUID,
        URL,
        [VaultRule],
        (@Sendable (ScanProgress) -> Void)?
    ) async -> VaultScan

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var observer: (any FolderObserving)?
    @ObservationIgnored private var observerRoots: [URL] = []
    @ObservationIgnored private var expectedOwnWrites = Set<URL>()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let observerFactory: @MainActor ([URL]) -> any FolderObserving
    @ObservationIgnored private let scanRunner: ScanRunner
    @ObservationIgnored private var activeScanID: UUID?
    @ObservationIgnored private var changesDuringScan: [URL: NoteChange] = [:]
    @ObservationIgnored private var scanNeedsRestart = false

    /// Notes that have changed and not yet gone quiet for long enough to be
    /// worth processing. The value is when we last saw the file move.
    @ObservationIgnored private(set) var settling: [URL: Date] = [:]

    /// Live progress for the vault currently being walked, so a row can say
    /// "240 of 4,000" instead of "not swept yet" for the seconds it takes.
    private(set) var progress: ScanProgress?

    init(
        model: AppModel,
        observerFactory: @escaping @MainActor ([URL]) -> any FolderObserving = {
            FolderObserver(roots: $0)
        },
        scanRunner: @escaping ScanRunner = { vaultID, root, rules, onProgress in
            await VaultScanner.scan(
                vaultID: vaultID,
                root: root,
                rules: rules,
                onProgress: onProgress
            )
        }
    ) {
        self.model = model
        self.observerFactory = observerFactory
        self.scanRunner = scanRunner
    }

    // MARK: - Lifecycle

    func start() {
        rescanEverything()
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        observer?.stop()
        observer = nil
        observerRoots = []
        expectedOwnWrites = []
        activeScanID = nil
        changesDuringScan = [:]
        scanNeedsRestart = false
        progress = nil
        model.dashboard.runState = .idle
    }

    /// Called after a vault is connected or disconnected: the watch has to
    /// cover a different set of folders, and the index has to be rebuilt.
    func vaultsChanged() {
        settling = settling.filter { url, _ in
            guard let vault = vault(containing: url),
                  let relative = NoteEligibility.relativePath(of: url, under: vault.url)
            else { return false }
            return NoteEligibility.isEligible(relativePath: relative, rules: vault.rules)
        }
        rescanEverything()
    }

    @discardableResult
    func refreshVaultLocations() -> Bool {
        let previous = Dictionary(
            uniqueKeysWithValues: model.dashboard.vaults.map {
                ($0.id, $0.url.standardizedFileURL)
            }
        )
        let changed = model.refreshVaultLocations()
        guard changed else { return false }

        for vault in model.dashboard.vaults {
            guard let oldRoot = previous[vault.id],
                  oldRoot != vault.url.standardizedFileURL
            else { continue }
            rebaseSettling(from: oldRoot, to: vault.url)
        }
        return true
    }

    func rebaseSettling(from oldRoot: URL, to newRoot: URL) {
        var rebased: [URL: Date] = [:]
        for (url, date) in settling {
            guard let relative = NoteEligibility.relativePath(of: url, under: oldRoot) else {
                rebased[url] = date
                continue
            }
            rebased[newRoot.appending(path: relative).standardizedFileURL] = date
        }
        settling = rebased
    }

    // MARK: - Scanning

    func rescanEverything() {
        scanTask?.cancel()
        scanTask = Task { @MainActor [weak self] in
            await self?.performFullScan()
        }
    }

    func performFullScan() async {
        let scanID = UUID()
        activeScanID = scanID
        changesDuringScan = [:]
        scanNeedsRestart = false

        _ = refreshVaultLocations()
        let vaults = model.dashboard.vaults
        let reachable = vaults.filter { $0.availability.isAvailable }
        let reportsActivity = model.dashboard.runState != .paused

        defer {
            if activeScanID == scanID {
                let changes = changesDuringScan.values.sorted {
                    $0.detectedAt < $1.detectedAt
                }
                let needsRestart = scanNeedsRestart
                activeScanID = nil
                changesDuringScan = [:]
                scanNeedsRestart = false
                for change in changes {
                    reconcile(change)
                }
                progress = nil
                if case .sweeping = model.dashboard.runState {
                    model.dashboard.runState = .idle
                }
                if needsRestart {
                    rescanEverything()
                }
            }
        }

        if reportsActivity, !reachable.isEmpty {
            model.dashboard.runState = .sweeping(completed: 0, total: reachable.count)
        }

        // Still scan absent roots so their availability becomes an actionable
        // error, but do not create an FSEvents stream for a path that already
        // does not exist.
        restartObserver(over: reachable.map(\.url).filter {
            FileManager.default.fileExists(atPath: $0.path)
        })

        guard !reachable.isEmpty else {
            return
        }

        for (index, vault) in reachable.enumerated() {
            if Task.isCancelled { return }

            let scan = await scanRunner(
                vault.id,
                vault.url,
                vault.rules,
                { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.progress = progress
                    }
                }
            )

            if Task.isCancelled { return }

            apply(scan, to: vault.id)

            if reportsActivity, case .sweeping = model.dashboard.runState {
                model.dashboard.runState = .sweeping(
                    completed: index + 1,
                    total: reachable.count
                )
            }
        }

        model.dashboard.limitRecentNotes()
    }

    /// Folds one vault's scan into the model.
    ///
    /// A scan that failed updates availability rather than note counts: a vault
    /// that briefly could not be read must not be reported as having become
    /// empty, because "0 notes" and "we could not look" are different facts and
    /// only one of them should ever make the interface stop offering it.
    private func apply(_ scan: VaultScan, to vaultID: UUID) {
        guard let index = model.dashboard.vaults.firstIndex(where: { $0.id == vaultID })
        else { return }

        if let failure = scan.failure {
            model.dashboard.vaults[index].availability =
                failure == .filePermissionDenied ? .permissionDenied : .missing
            return
        }

        model.dashboard.vaults[index].availability = .available
        model.dashboard.vaults[index].noteCount = scan.noteCount
        model.dashboard.vaults[index].folders = Self.merge(
            existing: model.dashboard.vaults[index].folders,
            found: scan.folders,
            summaries: scan.summaries
        )
        model.dashboard.reconcileVaultScan(
            vaultID: vaultID,
            documents: scan.documents,
            summaries: scan.summaries,
            existingNoteURLs: scan.existingNoteURLs
        )
    }

    /// Keeps a folder's identity and its overrides across a rescan.
    ///
    /// A folder that has been given its own settings must come back as the same
    /// folder, or the override is silently lost every time a vault is swept.
    private static func merge(
        existing: [WatchedFolder],
        found: [URL],
        summaries: [NoteSummary]
    ) -> [WatchedFolder] {
        let byURL = Dictionary(
            existing.map { ($0.url.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var counts: [URL: Int] = [:]
        for summary in summaries {
            let parent = summary.url.deletingLastPathComponent().standardizedFileURL
            counts[parent, default: 0] += 1
        }

        let folders = found.map { url -> WatchedFolder in
            let standardized = url.standardizedFileURL
            let previous = byURL[standardized]
            return WatchedFolder(
                id: previous?.id ?? UUID(),
                url: standardized,
                noteCount: counts[standardized] ?? 0,
                isReachable: true,
                lastSweep: previous?.lastSweep
            )
        }

        // A folder that has gone is simply gone. It used to be kept when it
        // carried an override, so a disk being unplugged could not delete the
        // user's settings — folders no longer carry any.

        return folders.sorted {
            $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
    }

    private static func mostRecent(_ summaries: [NoteSummary], limit: Int = 40) -> [NoteSummary] {
        summaries
            .sorted { left, right in
                if left.modifiedAt != right.modifiedAt {
                    return left.modifiedAt > right.modifiedAt
                }
                return left.url.path < right.url.path
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Watching

    private func restartObserver(over roots: [URL]) {
        let roots = roots
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
        guard roots != observerRoots || observer == nil else { return }
        guard !roots.isEmpty else {
            observer?.stop()
            observer = nil
            observerRoots = []
            return
        }

        let created = observerFactory(roots)
        for url in expectedOwnWrites {
            created.expectOwnWrite(to: url)
        }
        do {
            try created.start { [weak self] change in
                Task { @MainActor [weak self] in
                    self?.handleChange(change)
                }
            }
            let previous = observer
            observer = created
            observerRoots = roots
            previous?.stop()
        } catch {
            created.stop()
            if model.dashboard.runState != .paused {
                model.dashboard.runState = .failed(
                    message: "Chamfer couldn't watch your vaults for changes. Reconnecting them usually fixes it."
                )
            }
        }
    }

    /// One note settled on disk.
    ///
    /// Re-read rather than re-scanned: a keystroke in one note is not a reason
    /// to walk four thousand others. The vault's rules are applied here because
    /// the observer reports what moved without knowing whose rules govern it.
    func handleChange(_ change: NoteChange) {
        if activeScanID != nil {
            if change.requiresRescan {
                scanNeedsRestart = true
                return
            }
            changesDuringScan[change.url.standardizedFileURL] = change
        } else if change.requiresRescan {
            rescanEverything()
            return
        }
        reconcile(change)
    }

    private func reconcile(_ change: NoteChange) {
        guard let vault = vault(containing: change.url) else { return }
        guard let relative = NoteEligibility.relativePath(
            of: change.url,
            under: vault.url
        ) else { return }
        guard NoteEligibility.isEligible(relativePath: relative, rules: vault.rules) else {
            let exists = VaultBookmark.withAccess(to: vault.url) {
                FileManager.default.fileExists(atPath: change.url.path)
            }
            if exists {
                model.dashboard.removeIndexedNote(at: change.url, fileStillExists: true)
            } else if vaultStillOwnsReachableURL(vault.id, root: vault.url) {
                forget(change.url, in: vault.id)
                return
            }
            settling[change.url.standardizedFileURL] = nil
            return
        }

        guard let read = VaultScanner.read(change.url) else {
            if vaultStillOwnsReachableURL(vault.id, root: vault.url) {
                // The file is gone. Drop it from the index rather than leaving a
                // note in search that opens onto nothing.
                forget(change.url, in: vault.id)
            } else {
                settling[change.url.standardizedFileURL] = nil
            }
            return
        }

        upsert(summary: read.summary, document: read.document)
        settling[change.url.standardizedFileURL] = read.document == nil
            ? nil
            : change.detectedAt
    }

    private func vaultStillOwnsReachableURL(_ id: UUID, root: URL) -> Bool {
        _ = refreshVaultLocations()
        guard let current = model.dashboard.vaults.first(where: { $0.id == id }) else {
            return false
        }
        return current.availability.isAvailable
            && current.url.standardizedFileURL == root.standardizedFileURL
    }

    private func vault(containing url: URL) -> Vault? {
        model.dashboard.vaults
            .filter { NoteEligibility.relativePath(of: url, under: $0.url) != nil }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }
    }

    private func upsert(summary: NoteSummary, document: NoteDocument?) {
        let key = summary.url.standardizedFileURL
        let wasKnown = model.dashboard.existingNoteURLs.contains(key)
        model.dashboard.existingNoteURLs.insert(key)

        if !wasKnown,
           let vaultIndex = model.dashboard.vaults.firstIndex(where: {
               NoteEligibility.relativePath(of: summary.url, under: $0.url) != nil
           }) {
            model.dashboard.vaults[vaultIndex].noteCount += 1
        }

        if let index = model.dashboard.recentNotes.firstIndex(where: {
            $0.url.standardizedFileURL == key
        }) {
            // The stored identifier is kept so the row does not animate as a
            // brand-new note every time the user saves.
            model.dashboard.recentNotes[index] = NoteSummary(
                id: model.dashboard.recentNotes[index].id,
                url: summary.url,
                title: summary.title,
                wordCount: summary.wordCount,
                modifiedAt: summary.modifiedAt
            )
        } else {
            model.dashboard.recentNotes.insert(summary, at: 0)
            model.dashboard.recentNotes = Array(model.dashboard.recentNotes.prefix(40))
        }

        guard let document else {
            model.dashboard.removeIndexedNote(at: summary.url, fileStillExists: true)
            model.dashboard.recentNotes.insert(summary, at: 0)
            model.dashboard.limitRecentNotes()
            return
        }
        if let index = model.dashboard.searchableNotes.firstIndex(where: {
            $0.url.standardizedFileURL == key
        }) {
            model.dashboard.searchableNotes[index] = document
        } else {
            model.dashboard.searchableNotes.append(document)
        }

        if model.dashboard.openNote?.url.standardizedFileURL == key {
            model.dashboard.openNote = document
        }
    }

    private func forget(_ url: URL, in vaultID: UUID) {
        let key = url.standardizedFileURL
        let wasKnown = model.dashboard.existingNoteURLs.contains(key)
        let wasCounted = model.dashboard.vaults.first(where: { $0.id == vaultID }).map {
            guard let relative = NoteEligibility.relativePath(of: url, under: $0.url) else {
                return false
            }
            return NoteEligibility.isEligible(relativePath: relative, rules: $0.rules)
        } ?? false
        model.dashboard.removeNote(at: url)
        if wasKnown, wasCounted,
           let index = model.dashboard.vaults.firstIndex(where: { $0.id == vaultID }) {
            model.dashboard.vaults[index].noteCount = max(
                0,
                model.dashboard.vaults[index].noteCount - 1
            )
        }
        settling[key] = nil
    }

    /// Announces a write Chamfer is about to make, so the watcher does not
    /// report it back as the user's edit.
    @discardableResult
    func expectOwnWrite(to url: URL) -> Date? {
        let key = url.standardizedFileURL
        expectedOwnWrites.insert(key)
        observer?.expectOwnWrite(to: key)
        return settling.removeValue(forKey: key)
    }

    func cancelExpectedOwnWrite(to url: URL, restoring unsettled: Date? = nil) {
        let key = url.standardizedFileURL
        expectedOwnWrites.remove(key)
        observer?.cancelExpectedOwnWrite(to: key)
        if settling[key] == nil, let unsettled {
            settling[key] = unsettled
        }
    }

    func finishExpectedOwnWrite(to url: URL) {
        // The stream ignores this process's events itself. Keeping the backup
        // window open after the write would instead swallow a real edit made
        // immediately afterwards.
        let key = url.standardizedFileURL
        expectedOwnWrites.remove(key)
        observer?.cancelExpectedOwnWrite(to: key)
    }

    func refreshAfterOwnWrite(_ url: URL) {
        guard let read = VaultScanner.read(url) else { return }
        upsert(summary: read.summary, document: read.document)
    }

    /// Refreshes an edit made deliberately in Chamfer's note editor.
    ///
    /// This is not an "own write" in the rewrite sense: it is the user's new
    /// source text and should enter the same settling queue as an edit made in
    /// any other editor. Updating the index immediately keeps the open page and
    /// search results current even before FSEvents reports the atomic save.
    func refreshAfterUserEdit(_ url: URL, detectedAt: Date = Date()) {
        guard let vault = vault(containing: url), vault.availability.isAvailable,
              let relative = NoteEligibility.relativePath(of: url, under: vault.url),
              NoteEligibility.isEligible(relativePath: relative, rules: vault.rules),
              let read = VaultScanner.read(url)
        else { return }

        upsert(summary: read.summary, document: read.document)
        settling[url.standardizedFileURL] = detectedAt
    }

    /// Takes a note out of the waiting room, because it is being worked on now
    /// or because it turned out not to belong to any vault.
    func clearSettling(for url: URL) {
        settling[url.standardizedFileURL] = nil
    }

    func clearSettling(for url: URL, ifUnchangedSince date: Date) {
        let key = url.standardizedFileURL
        guard settling[key] == date else { return }
        settling[key] = nil
    }

    /// Puts back a trigger temporarily claimed by an offline rules write when
    /// the dependent AI configuration is still missing. A newer user edit
    /// always wins and is never replaced by the older timestamp.
    func restoreSettling(for url: URL, ifMissing date: Date) {
        let key = url.standardizedFileURL
        if settling[key] == nil {
            settling[key] = date
        }
    }

    /// Drops only rewrite-trigger bookkeeping. Connected roots stay observed
    /// and indexed because Clear All Vault Settings does not disconnect them.
    func clearProcessingTriggers() {
        settling.removeAll()
    }
}
