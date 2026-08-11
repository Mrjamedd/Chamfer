import AppKit
import ChamferCore
import ChamferFixtures
import ChamferUI
import SwiftUI

/// Source-built Chamfer window and component gallery for a Command Line Tools
/// machine. The typical scenario includes the real autosaved example note.
@main
struct ChamferGalleryApp: App {
    @NSApplicationDelegateAdaptor(GalleryAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Chamfer Gallery") {
            GalleryRootView()
                // The theme is a fixed cream; nothing in it has a dark variant.
                // Without this, system-drawn controls — the search field's text
                // and caret above all — follow the system appearance and come
                // out light on cream.
                .preferredColorScheme(.light)
        }
        // No title bar, so the window is one continuous field of beige rather
        // than beige under a strip of system chrome.
        .windowStyle(.hiddenTitleBar)
        // The root view is a fixed frame, so tying the window to its content
        // size is what makes the window unresizable.
        .windowResizability(.contentSize)
        .commands {
            // The `Settings` scene below normally installs its own
            // Command-comma item. This replaces it with an explicit one
            // because a SwiftPM executable has no bundle, and the automatic
            // item cannot be relied on to appear without one.
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // The same settings view the app ships, in its own window, so the
        // harness answers Command-comma exactly as the real app does.
        Settings {
            GallerySettingsHost()
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class GalleryAppDelegate: NSObject, NSApplicationDelegate {
    /// The panel's data, held mutably so Pause actually pauses here. The app
    /// keeps the same thing in `AppModel`; this is the fixture-backed twin of
    /// it, and it is the only difference between the two menu bars.
    private var dashboard = Fixtures.state(for: GalleryAppDelegate.launchScenario)
    private var menuBar: MenuBarController?

    /// Whatever `--scenario` the window opened on, so the panel mirrors what
    /// is on screen rather than describing some other state.
    private static var launchScenario: Scenario {
        if case let .scenario(scenario) = GalleryRootView.Launch.selection {
            return scenario
        }
        return .typical
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable has no bundle, so it launches as an accessory
        // process behind everything else without this.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        lockWindows()

        // The same status item the app installs, from the same controller.
        // Identical on purpose: the harness is meant to show what ships.
        let controller = MenuBarController(
            state: { [weak self] in
                self?.dashboard ?? Fixtures.state(for: GalleryAppDelegate.launchScenario)
            },
            actions: MenuBarActions(
                openMainWindow: { [weak self] in self?.showMainWindow() },
                openReview: { [weak self] in self?.showMainWindow() },
                openSettings: { [weak self] in self?.showSettings() },
                togglePause: { [weak self] in self?.togglePause() },
                quit: { NSApp.terminate(nil) }
            )
        )
        controller.install()
        menuBar = controller
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    /// The AppKit route, for the same reason the app uses it: the panel is
    /// hosted outside the scene tree, so `openSettings` is not populated in it.
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func togglePause() {
        dashboard.runState = dashboard.runState == .paused ? .idle : .paused
    }

    /// `windowResizability` stops the frame being dragged, but the zoom button
    /// and full screen would still resize it. Both are removed here so the
    /// composition can only ever be seen at the size it was designed for.
    private func lockWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.styleMask.remove(.resizable)
                window.collectionBehavior.insert(.fullScreenNone)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
