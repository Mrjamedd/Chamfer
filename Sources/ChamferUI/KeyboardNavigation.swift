import AppKit
import Observation
import SwiftUI

/// Whether the user is currently driving the app from the keyboard.
///
/// SwiftUI puts focus on the first focusable view as soon as a window opens,
/// so a focus ring drawn purely from `isFocused` appears the instant Settings
/// is shown — before anybody has touched Tab. That reads as a stuck selection
/// rather than as a focus state, which is exactly what macOS itself avoids: a
/// native window shows no ring until you navigate to something.
///
/// So the ring needs two facts, not one. This is the second: has the keyboard
/// been used to move around since the last time the pointer was.
@MainActor
@Observable
final class KeyboardNavigation {
    static let shared = KeyboardNavigation()

    /// True once a navigation key has been pressed, false again as soon as the
    /// pointer is used. Rings appear when you tab and disappear when you click,
    /// which is the behaviour of every other Mac app.
    private(set) var isActive = false

    @ObservationIgnored private var monitor: Any?

    private init() {
        install()
    }

    /// The keys that mean "I am moving around without the mouse".
    ///
    /// Space and Return are deliberately absent: they activate whatever is
    /// already focused rather than moving focus, and treating them as
    /// navigation would raise rings on a window nobody has tabbed into.
    private static let navigationKeys: Set<UInt16> = [
        48,  // tab
        123, // left
        124, // right
        125, // down
        126  // up
    ]

    private func install() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
            // Observing only. Returning the event unchanged leaves every
            // existing shortcut, button and field behaving exactly as before.
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard Self.navigationKeys.contains(event.keyCode) else { return }
            guard !isActive else { return }
            isActive = true
        case .leftMouseDown, .rightMouseDown:
            guard isActive else { return }
            isActive = false
        default:
            break
        }
    }
}
