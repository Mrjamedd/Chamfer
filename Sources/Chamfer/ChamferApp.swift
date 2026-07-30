import SwiftUI

/// Placeholder app shell.
///
/// The real menu bar surface will be an `NSStatusItem` with a transparent
/// `NSPanel`, not `MenuBarExtra`: on macOS 26 `MenuBarExtra` draws a glass
/// sheet behind its window that cannot be removed. Lintel hit this and had to
/// migrate. See docs/superpowers/specs/2026-07-30-chamfer-design.md.
@main
struct ChamferApp: App {
    var body: some Scene {
        Settings {
            Text("Chamfer")
                .padding()
        }
    }
}
