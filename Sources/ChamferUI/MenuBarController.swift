import AppKit
import ChamferCore
import SwiftUI

/// The menu bar surface.
///
/// An `NSStatusItem` with a transparent `NSPanel`, not `MenuBarExtra`: on
/// macOS 26 `MenuBarExtra` draws a glass sheet behind its window that cannot
/// be removed, and Chamfer's panel is a cream card with its own shadow. Lintel
/// hit this and had to migrate; this app starts where that ended up.
///
/// Lives in `ChamferUI` rather than the app target so the gallery installs the
/// same status item from the same code. It is chrome, and all the other chrome
/// is already here — a menu bar that only existed in one of the two builds is
/// a surface the harness could never review.
///
/// State arrives as a closure rather than a value so the panel is built from
/// whatever is current at the moment it opens. `DashboardState` is a struct, so
/// holding one would freeze the panel at install time; the app passes its
/// model's property and the gallery passes its fixtures, and neither has to
/// tell this class which it is.
@MainActor
public final class MenuBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private let state: @MainActor () -> DashboardState
    private let actions: MenuBarActions
    private var monitor: Any?

    public init(
        state: @escaping @MainActor () -> DashboardState,
        actions: MenuBarActions
    ) {
        self.state = state
        self.actions = actions
        super.init()
    }

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item
        refreshIcon()
    }

    /// The glyph, and whether anything is waiting.
    ///
    /// `square.on.square.badge.checkmark` — one sheet over another with a tick —
    /// says "a copy of this has been looked at", which is the whole app. The
    /// previous glyph was `chevron.left.slash.chevron.right`, a source-code
    /// symbol on a note-cleaning app.
    ///
    /// Filled when rewrites are waiting. A weight change rather than a red dot:
    /// the menu bar is somebody's own space, and a badge there is a demand
    /// where a heavier glyph is a mention.
    public func refreshIcon() {
        let pending = state().actionableProposals.count
        let name = pending > 0
            ? "square.fill.on.square.badge.checkmark"
            : "square.on.square.badge.checkmark"

        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: pending > 0
                ? "Chamfer — \(pending) waiting for review"
                : "Chamfer"
        ) ?? NSImage(
            // Not every symbol exists on every macOS. A missing glyph must not
            // mean a status item with nothing in it that cannot be clicked.
            systemSymbolName: "checkmark.seal",
            accessibilityDescription: "Chamfer"
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = pending > 0
            ? "Chamfer — \(pending) rewrite\(pending == 1 ? "" : "s") waiting"
            : "Chamfer"
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
        let content = LiveClock {
            MenuBarPanel(
                state: state,
                actions: actions,
                // The SwiftUI content punctuates its own explicit actions.
                // Outside clicks and status-item toggles still come through
                // `dismiss()` below, so every route gets one haptic, not two.
                onDismiss: { [weak self] in self?.dismissFromContent() }
            )
        }
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
        // Starts where it will end and is animated in from a slightly small,
        // transparent version of itself. Setting the final frame first means
        // the anchoring maths above never has to know about the animation.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        animateIn(panel)
        self.panel = panel

        // Clicking anywhere else closes it, which is what a menu bar popover
        // is expected to do and what nothing in AppKit does for a bare panel.
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

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

    public func dismiss() {
        dismiss(performHaptic: true)
    }

    private func dismissFromContent() {
        dismiss(performHaptic: false)
    }

    private func dismiss(performHaptic: Bool) {
        guard let panel else { return }
        // Fired at the start of the animation rather than at its end, so the
        // feedback answers the click instead of trailing it.
        if performHaptic { Haptics.commit() }
        self.panel = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        animateOut(panel)
    }

    // MARK: - Motion

    /// A menu bar popover appears and leaves; it does not blink. The panel used
    /// `orderFrontRegardless` and `orderOut` directly, which meant the one
    /// surface the user reaches for most had no transition at all.
    ///
    /// Snappy and unbounced, which is the macOS convention for a transient
    /// overlay — a popover that springs past its mark reads as iOS.
    private static let openDuration: TimeInterval = 0.30
    private static let closeDuration: TimeInterval = 0.25
    /// How small it starts and ends, scaled about the anchor above it so the
    /// card reads as coming out of the status item rather than out of the air.
    private static let collapsedScale: CGFloat = 0.94

    private func animateIn(_ panel: NSPanel) {
        guard !reduceMotionIsOn else {
            panel.alphaValue = 1
            return
        }
        let settled = panel.frame
        panel.setFrame(Self.collapsed(settled), display: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.openDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            panel.animator().alphaValue = 1
            panel.animator().setFrame(settled, display: true)
        }
    }

    private func animateOut(_ panel: NSPanel) {
        guard !reduceMotionIsOn else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.closeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            // Leaves along the path it arrived by, back towards the status
            // item, rather than fading on the spot.
            panel.animator().setFrame(Self.collapsed(panel.frame), display: true)
        } completionHandler: {
            // The completion handler is nonisolated, and the panel is not.
            MainActor.assumeIsolated {
                panel.orderOut(nil)
            }
        }
    }

    /// The same frame, smaller, pinned by its top edge — the edge nearest the
    /// status item it belongs to.
    private static func collapsed(_ frame: NSRect) -> NSRect {
        let width = frame.width * collapsedScale
        let height = frame.height * collapsedScale
        return NSRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    private var reduceMotionIsOn: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
