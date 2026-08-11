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
    /// permanently as quiet brand framing. Interactive controls use the
    /// separate dark hover treatment below.
    func chamferRing(
        radius: CGFloat,
        color: Color = Chamfer.Palette.ring
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: Chamfer.Palette.ringWidth)
                .allowsHitTesting(false)
        )
    }

    /// A soft dark shadow shown only while the pointer is on an interactive
    /// surface. There is deliberately no border inside the shadow.
    func chamferHoverRing(_ isActive: Bool, radius: CGFloat) -> some View {
        shadow(
            color: .black.opacity(isActive ? 0.16 : 0),
            radius: isActive ? 8 : 0,
            y: isActive ? 3 : 0
        )
        .animation(Chamfer.Motion.quick, value: isActive)
    }

    /// Circular surfaces get the same dark hover treatment.
    func chamferHoverRingCircle(_ isActive: Bool) -> some View {
        shadow(
            color: .black.opacity(isActive ? 0.16 : 0),
            radius: isActive ? 8 : 0,
            y: isActive ? 3 : 0
        )
        .animation(Chamfer.Motion.quick, value: isActive)
    }

    /// The resting shadow for anything floating on the canvas.
    func chamferFloat(radius: CGFloat = 26, y: CGFloat = 14, opacity: Double = 0.13) -> some View {
        shadow(color: .black.opacity(opacity), radius: radius, y: y)
    }

    /// The keyboard's version of the hover ring.
    ///
    /// Every control in the app is `.plain`-styled and answers only to the
    /// pointer, so tabbing through Review showed nothing at all — the keyboard
    /// user had no idea what Return would press. This is the same pink the
    /// pointer gets, drawn solid rather than as a shadow so it survives on the
    /// tan bar as well as on paper.
    ///
    /// Drawn only while the keyboard is actually being used to move around.
    /// SwiftUI focuses the first control in a window the moment it opens, so
    /// keying off `isFocused` alone put a ring on Settings' first button before
    /// anyone had pressed a key — a stuck selection rather than a focus state.
    func chamferFocusRing(_ isFocused: Bool, radius: CGFloat) -> some View {
        modifier(FocusRing(isFocused: isFocused, radius: radius))
    }
}

/// The ring itself, as a modifier so it can read the keyboard-navigation state
/// without every call site knowing that state exists.
public struct FocusRing: ViewModifier {
    private let isFocused: Bool
    private let radius: CGFloat

    @LegacyState private var navigation = KeyboardNavigation.shared

    public init(isFocused: Bool, radius: CGFloat) {
        self.isFocused = isFocused
        self.radius = radius
    }

    private var isVisible: Bool { isFocused && navigation.isActive }

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Chamfer.Palette.focusRing.opacity(isVisible ? 1 : 0),
                        lineWidth: Chamfer.Palette.focusRingWidth
                    )
                    .allowsHitTesting(false)
            )
            .animation(Chamfer.Motion.quick, value: isVisible)
    }
}

/// Gives a control the app's focus treatment without every call site repeating
/// the `@FocusState` plumbing.
public struct ChamferFocusable: ViewModifier {
    @FocusState private var isFocused: Bool

    private let radius: CGFloat

    public init(radius: CGFloat = Chamfer.Radius.small) {
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .chamferFocusRing(isFocused, radius: radius)
    }
}

public extension View {
    /// Focusable, with the system's own focus ring replaced by Chamfer's.
    ///
    /// The system ring is a blue rounded rectangle that knows nothing about the
    /// shape it is drawn around, and on a cream capsule it looked like a
    /// selection artefact rather than a focus state.
    func chamferFocusable(radius: CGFloat = Chamfer.Radius.small) -> some View {
        modifier(ChamferFocusable(radius: radius))
    }
}
