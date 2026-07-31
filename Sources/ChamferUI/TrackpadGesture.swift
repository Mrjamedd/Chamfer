import AppKit
import CoreGraphics
import SwiftUI

public enum TrackpadPanDirection: Equatable, Sendable {
    case left
    case right
    case up
    case down
}

public enum TrackpadPanClassifier {
    public static func direction(
        touchCount: Int,
        requiredTouchCount: Int,
        translation: CGSize,
        velocity: CGSize
    ) -> TrackpadPanDirection? {
        guard touchCount == requiredTouchCount else { return nil }

        let horizontalTravel = abs(translation.width)
        let verticalTravel = abs(translation.height)
        let horizontalVelocity = abs(velocity.width)
        let verticalVelocity = abs(velocity.height)
        let minimumTravel: CGFloat = 36
        let minimumFlickTravel: CGFloat = 18
        let minimumFlickVelocity: CGFloat = 420
        let dominance: CGFloat = 1.4

        if horizontalTravel >= verticalTravel * dominance {
            guard horizontalTravel >= minimumTravel
                || (horizontalTravel >= minimumFlickTravel
                    && horizontalVelocity >= minimumFlickVelocity)
            else { return nil }
            return translation.width < 0 ? .left : .right
        }

        if verticalTravel >= horizontalTravel * dominance {
            guard verticalTravel >= minimumTravel
                || (verticalTravel >= minimumFlickTravel
                    && verticalVelocity >= minimumFlickVelocity)
            else { return nil }
            return translation.height > 0 ? .up : .down
        }

        return nil
    }
}

public enum TrackpadScrollPhase: Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
}

/// Turns the pixel-precise scroll stream produced by a two-finger trackpad
/// gesture into one deliberate direction. Momentum is deliberately excluded
/// so a single swipe can never advance more than one destination.
public struct TrackpadScrollAccumulator: Sendable {
    private var translation = CGSize.zero
    private var didEmit = false
    private var isActive = false

    public init() {}

    public mutating func update(
        phase: TrackpadScrollPhase,
        physicalDelta: CGSize,
        isMomentum: Bool
    ) -> TrackpadPanDirection? {
        guard !isMomentum else { return nil }

        switch phase {
        case .began:
            reset()
            isActive = true
            accumulate(physicalDelta)
        case .changed:
            if !isActive {
                isActive = true
            }
            accumulate(physicalDelta)
        case .ended:
            guard isActive else { return nil }
            accumulate(physicalDelta)
            let direction = emitDirectionIfReady()
            reset()
            return direction
        case .cancelled:
            reset()
            return nil
        }

        return emitDirectionIfReady()
    }

    private mutating func accumulate(_ delta: CGSize) {
        translation.width += delta.width
        translation.height += delta.height
    }

    private mutating func emitDirectionIfReady() -> TrackpadPanDirection? {
        guard !didEmit else { return nil }
        guard let direction = TrackpadPanClassifier.direction(
            touchCount: 2,
            requiredTouchCount: 2,
            translation: translation,
            velocity: .zero
        ) else { return nil }
        didEmit = true
        return direction
    }

    private mutating func reset() {
        translation = .zero
        didEmit = false
        isActive = false
    }
}

/// A zero-visual-footprint bridge for two-finger trackpad scrolling. It
/// observes precise scroll events without consuming them, so normal vertical
/// page and list scrolling continue to work unchanged.
public struct TrackpadPanGesture: NSViewRepresentable {
    private let onEnded: (TrackpadPanDirection) -> Void

    public init(onEnded: @escaping (TrackpadPanDirection) -> Void) {
        self.onEnded = onEnded
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onEnded: onEnded)
    }

    public func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.coordinator = context.coordinator
        return view
    }

    public func updateNSView(_ view: AttachmentView, context: Context) {
        context.coordinator.update(onEnded: onEnded)
        context.coordinator.attach(marker: view)
    }

    public static func dismantleNSView(_ view: AttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    public final class AttachmentView: NSView {
        fileprivate weak var coordinator: Coordinator?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(marker: self)
        }
    }

    @MainActor
    public final class Coordinator: NSObject {
        private weak var marker: AttachmentView?
        private var eventMonitor: Any?
        private var accumulator = TrackpadScrollAccumulator()
        private var onEnded: (TrackpadPanDirection) -> Void

        fileprivate init(onEnded: @escaping (TrackpadPanDirection) -> Void) {
            self.onEnded = onEnded
        }

        fileprivate func update(onEnded: @escaping (TrackpadPanDirection) -> Void) {
            self.onEnded = onEnded
        }

        fileprivate func attach(marker: AttachmentView) {
            self.marker = marker
            guard marker.window != nil, eventMonitor == nil else { return }

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                self?.handle(event)
                return event
            }
        }

        fileprivate func detach() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
            marker = nil
            accumulator = TrackpadScrollAccumulator()
        }

        private func handle(_ event: NSEvent) {
            guard let marker,
                  marker.window === event.window,
                  event.hasPreciseScrollingDeltas,
                  marker.bounds.contains(marker.convert(event.locationInWindow, from: nil))
            else { return }

            if event.phase.contains(.mayBegin) {
                _ = accumulator.update(
                    phase: .cancelled,
                    physicalDelta: .zero,
                    isMomentum: false
                )
                return
            }

            let phase: TrackpadScrollPhase
            if event.phase.contains(.cancelled) {
                phase = .cancelled
            } else if event.phase.contains(.ended) {
                phase = .ended
            } else if event.phase.contains(.began) {
                phase = .began
            } else {
                phase = .changed
            }

            let deviceDirection: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
            let physicalDelta = CGSize(
                width: event.scrollingDeltaX * deviceDirection,
                height: event.scrollingDeltaY * deviceDirection
            )
            let isMomentum = !event.momentumPhase.isEmpty

            guard let direction = accumulator.update(
                phase: phase,
                physicalDelta: physicalDelta,
                isMomentum: isMomentum
            ) else { return }

            onEnded(direction)
        }
    }
}
