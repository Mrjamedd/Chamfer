import AppKit
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
        }
        .defaultSize(width: 1_280, height: 860)
        // No title bar, so the window is one continuous field of beige rather
        // than beige under a strip of system chrome.
        .windowStyle(.hiddenTitleBar)
    }
}

final class GalleryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable has no bundle, so it launches as an accessory
        // process behind everything else without this.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
