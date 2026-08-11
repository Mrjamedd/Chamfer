import AppKit
import ChamferCore
import ChamferRewrite
import ChamferUI
import SwiftUI

/// The app shell.
///
/// Three surfaces, and deliberately only three: the window with the notes in
/// it, the settings window that keeps app-wide controls out of that window,
/// and the menu bar panel that keeps working when both are closed.
@main
struct ChamferApp: App {
    @NSApplicationDelegateAdaptor(ChamferAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootWindow(
                model: delegate.model,
                notes: delegate.notes,
                rewrites: delegate.rewrites
            )
                // The theme is a fixed cream; nothing in it has a dark
                // variant. Without this, system-drawn controls follow the
                // system appearance and come out light on cream.
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // An explicit item rather than the one the `Settings` scene
            // installs by default: a SwiftPM executable has no bundle, and
            // the automatic Command-comma cannot be relied on without one.
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Command-comma. App-wide controls live here rather than in the main
        // window, which keeps that window down to one page and a bar.
        Settings {
            SettingsWindow(
                model: delegate.model,
                clearAllVaultSettings: delegate.clearAllVaultSettings
            )
                .preferredColorScheme(.light)
        }
        // The view has a width and a natural height, so the window takes both
        // from it and changes size when the section does. Without this the
        // window kept whatever height it opened at, which is how the short
        // tabs ended in a field of empty paper.
        .windowResizability(.contentSize)
    }
}

private struct RootWindow: View {
    /// The only thing in the app that knows how to raise the `Settings` scene.
    /// `ChamferUI` is handed a closure instead, which is what lets the gutter
    /// control and the menu bar panel exist in a module that has no scenes.
    @Environment(\.openSettings) private var openSettings
    @Bindable var model: AppModel
    let notes: NoteService
    let rewrites: RewriteService

    var body: some View {
        // Everything in the window reads its "now" from here, so a rewrite
        // queued four minutes ago says so rather than saying "just now" until
        // the app is quit.
        LiveClock { dashboard }
    }

    private var dashboard: some View {
        DashboardView(
            state: $model.dashboard,
            navigationRequest: $model.requestedDestination,
            editing: ConnectedVaultNoteEditor(
                model: model,
                notes: notes
            ).configuration,
            onClose: { NSApp.keyWindow?.close() },
            onOpenSettings: { openSettings() },
            onConnectVault: connectVault,
            review: reviewActions,
            vaults: vaultActions
        )
        .frame(width: Chamfer.Window.width, height: Chamfer.Window.height)
        .environment(\.chamferScanProgress, notes.progress)
    }

    private func connectVault() {
        if VaultConnector.present(into: model) {
            model.flush()
            notes.vaultsChanged()
        }
    }

    private var vaultActions: VaultActions {
        VaultActions(
            openNote: { summary in
                model.showNote(at: summary.url)
            },
            updateConfiguration: { vaultID, policy in
                model.updateConfiguration(policy, for: vaultID)
                // Each picker records deliberate partial intent. Persist it
                // immediately, but do not rebuild the unchanged file index on
                // every selection.
                model.flush()
            },
            removeVault: { vaultID in
                model.removeVault(vaultID)
                model.flush()
                notes.vaultsChanged()
            },
            connectVault: connectVault,
            reconnectVault: { vaultID in
                guard let oldRoot = model.dashboard.vaults.first(where: {
                    $0.id == vaultID
                })?.url else { return }
                if VaultConnector.present(reconnecting: vaultID, into: model),
                   let newRoot = model.dashboard.vaults.first(where: {
                       $0.id == vaultID
                   })?.url {
                    notes.rebaseSettling(from: oldRoot, to: newRoot)
                    model.flush()
                    notes.vaultsChanged()
                }
            },
            chooseExcludedNotes: { vault in
                VaultExclusionPicker.present(within: vault)
            },
            updateRules: { vaultID, rules in
                model.updateRules(rules, for: vaultID)
                model.flush()
                notes.vaultsChanged()
            }
        )
    }

    /// The real verbs: these snapshot, write to the user's file, and record
    /// what was replaced. The gallery passes none of this and gets the page's
    /// in-memory versions instead.
    private var reviewActions: ReviewActions {
        ReviewActions(
            accept: { proposal, allowOutdated in
                rewrites.apply(
                    proposal,
                    as: .review,
                    allowOutdated: allowOutdated
                )
            },
            reject: { rewrites.reject($0) },
            regenerate: { rewrites.regenerate($0) },
            openNote: { summary in
                model.showNote(at: summary.url)
            },
            retry: { rewrites.regenerate($0) },
            restore: { rewrites.restore($0) }
        )
    }
}

private struct SettingsWindow: View {
    @Bindable var model: AppModel
    let clearAllVaultSettings: @MainActor () -> String?
    @LegacyState private var loginItemNote: String?

    var body: some View {
        SettingsView(
            preferences: $model.preferences,
            launchAtLoginNote: loginItemNote,
            vaultSettingsCount: model.dashboard.vaults.count {
                $0.configuration != nil
                    || !$0.rules.isEmpty
                    || $0.lastSweep != nil
                    || $0.folders.contains { $0.lastSweep != nil }
            },
            clearAllVaultSettings: clearAllVaultSettings
        )
        .onChange(of: model.preferences.launchAtLogin) { _, enabled in
            guard let enabled else { return }
            loginItemNote = LoginItem.set(enabled)
            if loginItemNote != nil {
                // The change did not take, so the toggle goes back rather than
                // showing an on switch for something that is off.
                model.preferences.launchAtLogin = LoginItem.isEnabled
            }
        }
    }
}

@MainActor
final class ChamferAppDelegate: NSObject, NSApplicationDelegate {
    /// Retained: a `DispatchSourceSignal` stops firing the moment it is
    /// released.
    private var signalSources: [DispatchSourceSignal] = []

    let model = AppModel()
    private(set) lazy var notes = NoteService(model: model)
    private(set) lazy var rewrites = RewriteService(model: model, notes: notes)
    private lazy var scheduler = ProcessingScheduler(
        model: model,
        notes: notes,
        rewrites: rewrites
    )
    private var menuBar: MenuBarController?
    private let notifications = NotificationCentre()

    func clearAllVaultSettings() -> String? {
        // Invalidate authority before mutating UI state, so a backend response
        // that lands during the reset cannot recreate cleared work.
        rewrites.invalidateInFlightWork()
        notes.clearProcessingTriggers()
        return model.clearAllVaultSettings()?.message
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()

        // A SwiftPM executable has no bundle, so it launches as an accessory
        // process behind everything else without this.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Before anything renders: the last session's vaults, settings, pending
        // queue and history come back, and each vault's bookmark is re-resolved
        // so its availability describes this moment rather than the last one.
        model.restore()
        lockWindows()

        // The local model is the app's intelligence and it needs a runtime, so
        // getting Ollama onto the Mac is Chamfer's job rather than the user's
        // errand. A no-op on every launch after the first — and after a failed
        // first, a retry.
        OllamaProvisioning.shared.startIfNeeded()

        // Watching begins at launch and continues with the window closed. The
        // scope is explicit that only quitting stops it.
        notes.start()
        scheduler.start()
        reportUnavailableVaults()

        let controller = MenuBarController(
            state: { [model] in model.dashboard },
            actions: MenuBarActions(
                openMainWindow: { [weak self] in self?.showMainWindow() },
                openReview: { [weak self] in
                    self?.model.requestedDestination = DashboardView.Tab.review
                    self?.showMainWindow()
                },
                openSettings: { [weak self] in self?.showSettings() },
                togglePause: { [weak self] in self?.model.togglePause() },
                quit: { NSApp.terminate(nil) }
            )
        )
        controller.install()
        menuBar = controller
        observePendingCount()
    }

    /// Keeps the status item's glyph in step with the queue.
    ///
    /// The icon is the only part of Chamfer visible when everything is closed,
    /// so it has to be right the moment a rewrite arrives rather than the next
    /// time the panel is opened.
    private func observePendingCount() {
        withObservationTracking {
            _ = model.dashboard.proposals
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                menuBar?.refreshIcon()
                observePendingCount()
            }
        }
    }

    /// Closing the window leaves the app watching. The scope is explicit that
    /// monitoring continues while the main window is closed and stops only
    /// when the app is quit, and this is the line that says so.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The debounced save will not have fired for a change made a moment ago,
    /// so quitting forces it. Nothing the user did in their last half second
    /// should be the thing that gets lost.
    func applicationWillTerminate(_ notification: Notification) {
        scheduler.stop()
        notes.stop()
        model.flush()
        stopLocalRuntime()
    }

    /// Stops the local runtime, whatever route the app is leaving by.
    ///
    /// The runtime is Chamfer's child process and must not outlive it —
    /// orphaning it leaves a server holding a model in memory, which is exactly
    /// the leftover-daemon behaviour that installing the standalone server
    /// instead of `Ollama.app` was meant to avoid.
    ///
    /// Synchronous on purpose, and deliberately not routed through the
    /// installer actor. Both callers run on the main queue while the app is
    /// leaving; hopping to an executor that will never be serviced again meant
    /// the shutdown never ran and the server outlived its parent.
    private func stopLocalRuntime() {
        LocalRuntimeSupervisor.terminate()
    }

    /// `applicationWillTerminate` covers Quit. It does **not** cover a signal:
    /// `kill`, a logout, or a system shutdown deliver SIGTERM straight to the
    /// process and AppKit never runs its delegate. Without these the runtime
    /// survived its parent — verified, not theorised.
    ///
    /// SIGKILL and a hard crash remain uncatchable by anyone. Those are handled
    /// on the way back in: a runtime already answering on Chamfer's private port
    /// is adopted rather than duplicated, so the next clean exit collects it.
    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            // The default disposition has to go, or the process dies before the
            // source ever fires.
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.stopLocalRuntime()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// A vault that did not come back is worth saying out loud once at launch.
    ///
    /// The Vaults page shows it too, but someone whose external disk is
    /// unplugged may go a week without opening that page while Chamfer quietly
    /// watches nothing.
    private func reportUnavailableVaults() {
        for vault in model.dashboard.vaults where !vault.availability.isAvailable {
            notifications.folderUnavailable(
                vaultName: vault.name,
                preferences: model.preferences
            )
        }
    }

    /// The composition is fixed at 780×860 and the window must not be pulled
    /// out of it. `windowResizability` stops the frame being dragged, but the
    /// zoom button and full screen would still resize it, so both go too.
    ///
    /// The gallery has done this since it was built; the shipping app was the
    /// one that could still be zoomed into a shape nothing was designed for.
    private func lockWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.styleMask.remove(.resizable)
                window.collectionBehavior.insert(.fullScreenNone)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                Self.imposeDesignedSize(on: window)
            }
        }
    }

    /// Puts the window back to the size the composition is drawn at.
    ///
    /// macOS saves a window's frame and restores it on the next launch, and a
    /// restored frame outlives a change to the designed size — so a window that
    /// was 892 tall before the Dock clamp existed came back at 892 tall
    /// afterwards, clipping the bar exactly as before. The saved frame is a
    /// memory of where the window *was*; the code is the authority on how big
    /// it should be.
    private static func imposeDesignedSize(on window: NSWindow) {
        guard window.canBecomeMain else { return }

        let designed = NSSize(
            width: Chamfer.Window.width,
            height: Chamfer.Window.height
        )
        guard window.frame.size != designed else { return }
        window.setContentSize(designed)

        // Resizing from a restored origin can push the window off the bottom of
        // the screen, so it is nudged back into the visible area afterwards.
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }
        var frame = window.frame
        frame.origin.y = max(frame.origin.y, visible.minY)
        frame.origin.y = min(frame.origin.y, visible.maxY - frame.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        window.setFrameOrigin(frame.origin)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    /// The AppKit route to the `Settings` scene rather than `openSettings`.
    ///
    /// The menu bar panel is an `NSHostingController` built here, outside the
    /// scene tree, so the SwiftUI environment action is not populated in it —
    /// the gutter control in the main window uses `openSettings` precisely
    /// because that one *is* inside the tree. Activation first because the
    /// panel is non-activating: without it the window opens behind whatever
    /// the user was in.
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
