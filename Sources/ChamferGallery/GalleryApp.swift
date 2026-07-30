import AppKit
import ChamferUI
import SwiftUI

/// Stands in for the Xcode preview canvas, which isn't available on a
/// Command Line Tools machine. Run it, look at every component in every state
/// at once, edit, run again.
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
    }
}

final class GalleryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable has no bundle, so it launches as an accessory
        // process behind everything else without this.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        lockWindows()
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
