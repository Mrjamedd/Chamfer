import SwiftUI

/// The hover treatment, shared by anything that can be pointed at: the surface
/// rises off the canvas and its shadow deepens. Nothing recolours.
public struct HoverLift: ViewModifier {
    private let isActive: Bool
    private let lift: CGFloat

    public init(isActive: Bool, lift: CGFloat = 5) {
        self.isActive = isActive
        self.lift = lift
    }

    public func body(content: Content) -> some View {
        content
            .offset(y: isActive ? -lift : 0)
            .shadow(
                color: .black.opacity(isActive ? 0.20 : 0.07),
                radius: isActive ? 22 : 7,
                y: isActive ? 14 : 3
            )
            .animation(Chamfer.Motion.lift, value: isActive)
    }
}

public extension View {
    /// Rises and deepens its shadow while `isActive`.
    func chamferHoverLift(isActive: Bool, lift: CGFloat = 5) -> some View {
        modifier(HoverLift(isActive: isActive, lift: lift))
    }

    /// A faint pink ring traced around a surface.
    ///
    /// The two surfaces the app is built from — the page and the bar — wear it
    /// permanently, which is where the colour comes from. Everything
    /// interactive inside them wears it only under the pointer. Same ring
    /// either way, so it always means "this is a thing", never anything else.
    func chamferRing(radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Chamfer.Palette.ring, lineWidth: Chamfer.Palette.ringWidth)
                .allowsHitTesting(false)
        )
    }

    /// The same ring, shown only while the pointer is on the surface.
    func chamferHoverRing(_ isActive: Bool, radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Chamfer.Palette.ring, lineWidth: Chamfer.Palette.ringWidth)
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(false)
        )
        .animation(Chamfer.Motion.quick, value: isActive)
    }

    /// Circular surfaces get the same ring.
    func chamferHoverRingCircle(_ isActive: Bool) -> some View {
        overlay(
            Circle()
                .strokeBorder(Chamfer.Palette.ring, lineWidth: Chamfer.Palette.ringWidth)
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(false)
        )
        .animation(Chamfer.Motion.quick, value: isActive)
    }

    /// The resting shadow for anything floating on the canvas.
    func chamferFloat(radius: CGFloat = 26, y: CGFloat = 14, opacity: Double = 0.13) -> some View {
        shadow(color: .black.opacity(opacity), radius: radius, y: y)
    }
}
