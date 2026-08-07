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
    @Bindable var model: AppModel

    var body: some View {
        DashboardView(
            state: model.dashboard,
            onClose: { NSApp.keyWindow?.close() }
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
            model: model,
            actions: MenuBarActions(
                openMainWindow: { [weak self] in self?.showMainWindow() },
                openReview: { [weak self] in self?.showMainWindow() },
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
}
