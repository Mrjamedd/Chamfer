import ChamferCore
import ChamferUI
import ChamferWatch
import Foundation
import Observation

/// The one place the app's state lives.
///
/// Everything the interface renders hangs off `DashboardState`, exactly as the
/// design intended: the view is handed a binding into this object rather than a
/// copy of it, so a rewrite accepted on the Review page is the same rewrite the
/// menu bar stops offering and the same one that is on disk a moment later.
/// Settings and preferences sit alongside it rather than inside it because they
/// outlive any particular vault.
@MainActor
@Observable
final class AppModel {
    var dashboard: DashboardState
    var preferences: AppPreferences
    /// One-shot request from chrome outside the SwiftUI scene (the menu bar)
    /// to select a main-window destination.
    var requestedDestination: String?
    /// Set when something was on disk but could not be read. The interface says
    /// so rather than presenting a wiped app as though it were a fresh install.
    private(set) var storeFailure: StoreLoadFailure?
    /// Invalidates asynchronous work created under older vault settings.
    /// This is session-only authority, not another setting to persist.
    private(set) var configurationGeneration: UInt64 = 0

    /// Security-scoped bookmarks, keyed by vault. Held apart from `Vault`
    /// because a bookmark is a fact about this machine's sandbox rather than
    /// about the vault, and nothing that renders should be able to see it.
    @ObservationIgnored private var bookmarks: [UUID: Data] = [:]

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isRestoring = false

    /// How long a burst of changes is allowed to settle before it is written.
    ///
    /// Dragging a slider or typing in a field produces a change per frame, and
    /// a store that answered each one would spend the app's life writing JSON.
    /// Short enough that a quit a second later still catches it, and `flush()`
    /// exists for the quit that does not wait.
    @ObservationIgnored private static let saveDebounce = Duration.milliseconds(600)

    init(
        dashboard: DashboardState = .empty,
        preferences: AppPreferences = .unconfigured,
        store: StateStore = StateStore()
    ) {
        self.dashboard = dashboard
        self.preferences = preferences
        requestedDestination = nil
        self.store = store
    }

    var pendingCount: Int { dashboard.actionableProposals.count }

    var isPaused: Bool { dashboard.runState == .paused }

    /// Pausing stops new work being picked up. It is deliberately not the same
    /// as quitting: the scope is explicit that quitting stops monitoring
    /// altogether, and a pause that survived a quit would be a promise the app
    /// cannot keep.
    func togglePause() {
        dashboard.runState = isPaused ? .idle : .paused
    }

    /// The model a given vault will actually run, after the app-wide local-only
    /// switch has had its say. Nil means either the vault is not set up, or the
    /// user's settings rule out every option — both of which the interface
    /// reports rather than quietly resolving to the cloud.
    func effectiveModelID(for vault: Vault) -> String? {
        guard let policy = vault.configuration?.resolve(
            modelID: ModelsSelection.activeModelID()
        ) else { return nil }
        return ProcessingGuard.permittedModel(for: policy, preferences: preferences)
    }

    // MARK: - Restoring

    /// Reads the last session back in, then starts watching for changes.
    ///
    /// Vault availability is not restored from the file: it is re-derived by
    /// resolving each bookmark now. A vault that was reachable when the app
    /// last quit may be on a disk that is no longer plugged in, and a stored
    /// "Watching" would be a lie the interface had no way to catch.
    func restore() {
        let loaded = store.load()
        storeFailure = loaded.failure

        isRestoring = true
        defer {
            isRestoring = false
            observeChanges()
        }

        preferences = loaded.state.preferences
        bookmarks.removeAll()
        dashboard = DashboardState(
            runState: .idle,
            folders: [],
            proposals: Self.restorableProposals(loaded.state.proposals),
            recentlyCleaned: [],
            history: loaded.history
        )

        for stored in loaded.state.vaults {
            let resolution = VaultBookmark.resolve(stored.bookmark)
            bookmarks[stored.id] = resolution.refreshedBookmark ?? stored.bookmark
            let storedURL = URL(fileURLWithPath: stored.path).standardizedFileURL
            dashboard.vaults.append(
                Vault(
                    id: stored.id,
                    url: storedURL,
                    availability: resolution.availability,
                    noteCount: stored.noteCount,
                    lastSweep: stored.lastSweep,
                    configuration: stored.configuration,
                    folders: stored.folders,
                    rules: stored.rules
                )
            )
            if let resolvedURL = resolution.url?.standardizedFileURL,
               resolvedURL != storedURL {
                dashboard.rebaseVault(stored.id, to: resolvedURL)
            }
        }
    }

    /// Records a newly connected folder and its bookmark.
    @discardableResult
    func addVault(_ vault: Vault, bookmark: Data) -> Bool {
        guard !dashboard.vaults.contains(where: {
            Self.overlaps($0.url, vault.url)
        }) else { return false }
        bookmarks[vault.id] = bookmark
        dashboard.vaults.append(vault)
        return true
    }

    func removeVault(_ id: UUID) {
        bookmarks[id] = nil
        dashboard.disconnectVault(id)
    }

    @discardableResult
    func reconnectVault(_ id: UUID, to url: URL, bookmark: Data) -> Bool {
        guard let index = dashboard.vaults.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard !dashboard.vaults.contains(where: {
            $0.id != id && Self.overlaps($0.url, url)
        }) else { return false }
        bookmarks[id] = bookmark
        dashboard.rebaseVault(id, to: url.standardizedFileURL)
        dashboard.vaults[index].availability = .available
        return true
    }

    func updateRules(_ rules: [VaultRule], for id: UUID) {
        guard let index = dashboard.vaults.firstIndex(where: { $0.id == id }) else {
            return
        }
        dashboard.vaults[index].rules = rules
        configurationGeneration &+= 1
    }

    /// Sets what a vault does. The first call is what makes it eligible to be
    /// worked on at all — before it, the vault is watched and nothing else.
    func updateConfiguration(_ configuration: VaultConfiguration?, for id: UUID) {
        guard let index = dashboard.vaults.firstIndex(where: { $0.id == id }) else {
            return
        }
        dashboard.vaults[index].configuration = configuration
        configurationGeneration &+= 1
    }

    /// Clears only settings that belong to connected vaults.
    ///
    /// Bookmarks, the searchable index, global preferences, model selection,
    /// files, snapshots and durable history are deliberately untouched.
    @discardableResult
    func clearAllVaultSettings() -> StoreLoadFailure? {
        configurationGeneration &+= 1

        for vaultIndex in dashboard.vaults.indices {
            dashboard.vaults[vaultIndex].configuration = nil
            dashboard.vaults[vaultIndex].rules = []
            dashboard.vaults[vaultIndex].lastSweep = nil
            for folderIndex in dashboard.vaults[vaultIndex].folders.indices {
                dashboard.vaults[vaultIndex].folders[folderIndex].lastSweep = nil
            }
        }
        dashboard.proposals.removeAll()
        switch dashboard.runState {
        case .sweeping, .rewriting, .rewritingUnavailable:
            dashboard.runState = .idle
        case .idle, .paused, .failed:
            break
        }

        flush()
        return storeFailure
    }

    /// Re-resolving is what turns a bookmark-tracked Finder rename into a new
    /// root before a scan or observer can keep using the path that disappeared.
    @discardableResult
    func refreshVaultLocations() -> Bool {
        var changed = false
        for id in dashboard.vaults.map(\.id) {
            guard let bookmark = bookmarks[id],
                  let index = dashboard.vaults.firstIndex(where: { $0.id == id })
            else { continue }

            let resolution = VaultBookmark.resolve(bookmark)
            if let refreshed = resolution.refreshedBookmark {
                bookmarks[id] = refreshed
            }
            if let url = resolution.url?.standardizedFileURL,
               url != dashboard.vaults[index].url.standardizedFileURL {
                dashboard.rebaseVault(id, to: url)
                changed = true
            }
            if dashboard.vaults[index].availability != resolution.availability {
                dashboard.vaults[index].availability = resolution.availability
                changed = true
            }
        }
        return changed
    }

    func bookmark(for vaultID: UUID) -> Data? {
        bookmarks[vaultID]
    }

    private static func overlaps(_ first: URL, _ second: URL) -> Bool {
        let first = first.standardizedFileURL
        let second = second.standardizedFileURL
        return first == second
            || NoteEligibility.relativePath(of: first, under: second) != nil
            || NoteEligibility.relativePath(of: second, under: first) != nil
    }

    // MARK: - Persisting

    /// Writes immediately, for the moments that will not wait — quitting, or a
    /// change that must survive a crash a fraction of a second later.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persist()
    }

    private func observeChanges() {
        withObservationTracking {
            // Touching the whole value registers every nested field, so a
            // policy changed three levels down is caught without this having to
            // know the shape of the tree.
            _ = dashboard
            _ = preferences
        } onChange: { [weak self] in
            // `onChange` fires *before* the value is updated, so the save has
            // to happen a turn later or it writes what was already there.
            Task { @MainActor [weak self] in
                guard let self else { return }
                scheduleSave()
                observeChanges()
            }
        }
    }

    private func scheduleSave() {
        guard !isRestoring else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            persist()
            saveTask = nil
        }
    }

    private func persist() {
        if case .fromTheFuture = storeFailure {
            do {
                try store.save(history: dashboard.history)
            } catch {
                storeFailure = .unreadable(error.localizedDescription)
            }
            return
        }

        let missingBookmarks = dashboard.vaults.filter { bookmarks[$0.id] == nil }
        guard missingBookmarks.isEmpty else {
            do {
                try store.save(history: dashboard.history)
            } catch {
                storeFailure = .unreadable(error.localizedDescription)
                return
            }
            storeFailure = .unreadable(
                "Chamfer refused to save (missingBookmarks.count) vault\(missingBookmarks.count == 1 ? "" : "s") without lasting folder access."
            )
            return
        }

        let state = StoredState(
            vaults: dashboard.vaults.map { vault in
                let bookmark = bookmarks[vault.id]!
                return StoredVault(
                    id: vault.id,
                    bookmark: bookmark,
                    path: vault.url.path(percentEncoded: false),
                    noteCount: vault.noteCount,
                    lastSweep: vault.lastSweep,
                    configuration: vault.configuration,
                    folders: vault.folders,
                    rules: vault.rules
                )
            },
            preferences: preferences,
            proposals: Self.restorableProposals(dashboard.proposals)
        )

        do {
            // A stale proposal can be refused against the changed file after
            // relaunch; a missing record of replaced text can never be rebuilt.
            try store.save(history: dashboard.history)
            try store.save(state)
            storeFailure = nil
        } catch {
            // A failed write is worth reporting but never worth crashing over:
            // the app in memory is still correct, and the next change tries
            // again.
            storeFailure = .unreadable(error.localizedDescription)
        }
    }

    private static func restorableProposals(_ proposals: [Proposal]) -> [Proposal] {
        proposals.compactMap { proposal in
            guard proposal.state.isActionable else { return nil }
            var proposal = proposal
            // No model request survives a process exit. Returning the old
            // decision to pending keeps it usable instead of promising work
            // that no longer exists.
            if proposal.state == .regenerating {
                proposal.state = .pending
            }
            return proposal
        }
    }
}

extension DashboardState {
    static let empty = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: []
    )
}
