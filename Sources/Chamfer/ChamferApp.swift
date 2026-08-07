import AppKit
import ChamferCore
import ChamferUI
import SwiftUI

/// The app shell.
///
/// Three surfaces, and deliberately only three: the window with the notes in
/// it, the settings window that keeps the global defaults out of that window,
/// and the menu bar panel that keeps working when both are closed.
@main
struct ChamferApp: App {
    @NSApplicationDelegateAdaptor(ChamferAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootWindow(model: delegate.model)
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

        // Command-comma. Global defaults live here rather than in the main
        // window, which is what keeps that window down to one page and a bar.
        Settings {
            SettingsWindow(model: delegate.model)
                .preferredColorScheme(.light)
        }
    }
}

private struct RootWindow: View {
    /// The only thing in the app that knows how to raise the `Settings` scene.
    /// `ChamferUI` is handed a closure instead, which is what lets the gutter
    /// control and the menu bar panel exist in a module that has no scenes.
    @Environment(\.openSettings) private var openSettings
    @Bindable var model: AppModel

    var body: some View {
        DashboardView(
            state: model.dashboard,
            onClose: { NSApp.keyWindow?.close() },
            onOpenSettings: { openSettings() }
        )
        .frame(width: Chamfer.Window.width, height: Chamfer.Window.height)
    }
}

private struct SettingsWindow: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsView(
            policy: $model.dashboard.globalPolicy,
            preferences: $model.preferences
        )
    }
}

@MainActor
final class ChamferAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable has no bundle, so it launches as an accessory
        // process behind everything else without this.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let controller = MenuBarController(
            state: { [model] in model.dashboard },
            actions: MenuBarActions(
                openMainWindow: { [weak self] in self?.showMainWindow() },
                openReview: { [weak self] in self?.showMainWindow() },
                openSettings: { [weak self] in self?.showSettings() },
                togglePause: { [weak self] in self?.model.togglePause() },
                quit: { NSApp.terminate(nil) }
            )
        )
        controller.install()
        menuBar = controller
    }

    /// Closing the window leaves the app watching. The scope is explicit that
    /// monitoring continues while the main window is closed and stops only
    /// when the app is quit, and this is the line that says so.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
