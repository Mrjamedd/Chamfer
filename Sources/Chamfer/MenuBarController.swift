import AppKit
import ChamferUI
import SwiftUI

/// The menu bar surface.
///
/// An `NSStatusItem` with a transparent `NSPanel`, not `MenuBarExtra`: on
/// macOS 26 `MenuBarExtra` draws a glass sheet behind its window that cannot
/// be removed, and Chamfer's panel is a cream card with its own shadow. Lintel
/// hit this and had to migrate; this app starts where that ended up.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private let model: AppModel
    private let actions: MenuBarActions

    init(model: AppModel, actions: MenuBarActions) {
        self.model = model
        self.actions = actions
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "chevron.left.slash.chevron.right",
            accessibilityDescription: "Chamfer"
        )
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item
    }

    /// Clicking the item again closes it, the same as clicking away. Two
    /// routes to the same state, punctuated identically.
    @objc private func toggle() {
        if panel?.isVisible == true {
            dismiss()
        } else {
            present()
        }
    }

    private func present() {
        let content = MenuBarPanel(
            state: model.dashboard,
            actions: actions,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        .preferredColorScheme(.light)

        let hosting = NSHostingController(rootView: content)
        // The panel is only ever as big as the card inside it, and the card
        // draws its own background, so the window itself must contribute
        // nothing — no titlebar, no material, no opaque fill.
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        // Clicking anywhere else closes it, which is what a menu bar popover
        // is expected to do and what nothing in AppKit does for a bare panel.
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private var monitor: Any?

    /// Anchored under the status item, and nudged back on screen if the item
    /// is close enough to the right edge that the card would hang off it.
    private func position(_ panel: NSPanel) {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        let size = panel.contentViewController?.view.fittingSize ?? .zero
        panel.setContentSize(size)

        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = CGPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - size.height - 6
        )

        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
    }

    func dismiss() {
        guard let panel else { return }
        Haptics.commit()
        panel.orderOut(nil)
        self.panel = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
