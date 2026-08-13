import AppKit
import SwiftUI

/// Strips the system title bar from whatever window a view finds itself in.
///
/// The main window gets this from `.windowStyle(.hiddenTitleBar)` on its scene.
/// The `Settings` scene has no such modifier available to it, so its window
/// arrived with a white title strip above a cream band — the one surface in the
/// app that did not look like the app.
///
/// Reaches for the window rather than for a scene modifier because that is the
/// only route SwiftUI leaves open here. Applied once, when the view is first
/// placed in a window.
private struct HidesTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window does not exist yet while `makeNSView` runs, so the
        // configuration waits for the view to be placed in one.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            apply(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        apply(to: window)
    }

    private func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // The traffic lights stay. They are the only way out of a window with
        // no title bar, and the tab band leaves room for them.
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isMovableByWindowBackground = true
        // The window is sized by its content, so the frame must not be
        // draggable — the composition has one width and one natural height.
        window.styleMask.remove(.resizable)

        // macOS restores the frame this window had on a previous launch, which
        // is a memory of a size the content no longer wants. Position is worth
        // keeping; the height is not, or a window that was fixed at 672 before
        // it learned to size itself would come back at 672 forever.
        window.setFrameAutosaveName("Chamfer.SettingsWindow")
        if let fitting = window.contentView?.fittingSize, fitting.height > 0 {
            window.setContentSize(fitting)
        }
    }
}

public extension View {
    /// Hides the host window's title bar and lets the content run to the top.
    func chamferHidesTitleBar() -> some View {
        background(HidesTitleBar().frame(width: 0, height: 0))
    }
}
