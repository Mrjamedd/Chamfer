import SwiftUI

public enum ChamferFocusShape: Sendable {
    case roundedRectangle(radius: CGFloat)
    case circle
}

/// The hover treatment, shared by anything that can be pointed at: the surface
/// rises off the canvas and its shadow deepens. Nothing recolours.
public struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(
                Chamfer.Motion.reduce(Chamfer.Motion.lift, when: reduceMotion),
                value: isActive
            )
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
        modifier(
            FocusRing(
                isFocused: isFocused,
                shape: .roundedRectangle(radius: radius)
            )
        )
    }

    /// The same keyboard treatment, following the edge of a circular control.
    func chamferFocusRingCircle(_ isFocused: Bool) -> some View {
        modifier(FocusRing(isFocused: isFocused, shape: .circle))
    }
}

/// The ring itself, as a modifier so it can read the keyboard-navigation state
/// without every call site knowing that state exists.
public struct FocusRing: ViewModifier {
    private let isFocused: Bool
    private let shape: ChamferFocusShape

    @LegacyState private var navigation = KeyboardNavigation.shared

    public init(isFocused: Bool, shape: ChamferFocusShape) {
        self.isFocused = isFocused
        self.shape = shape
    }

    private var isVisible: Bool { isFocused && navigation.isActive }

    public func body(content: Content) -> some View {
        content
            .overlay { ring }
            .animation(Chamfer.Motion.quick, value: isVisible)
    }

    @ViewBuilder
    private var ring: some View {
        switch shape {
        case let .roundedRectangle(radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    Chamfer.Palette.focusRing.opacity(isVisible ? 1 : 0),
                    lineWidth: Chamfer.Palette.focusRingWidth
                )
                .allowsHitTesting(false)
        case .circle:
            Circle()
                .strokeBorder(
                    Chamfer.Palette.focusRing.opacity(isVisible ? 1 : 0),
                    lineWidth: Chamfer.Palette.focusRingWidth
                )
                .allowsHitTesting(false)
        }
    }
}

/// Gives a control the app's focus treatment without every call site repeating
/// the `@FocusState` plumbing.
public struct ChamferFocusable: ViewModifier {
    @FocusState private var isFocused: Bool

    private let shape: ChamferFocusShape
    private let isEnabled: Bool

    public init(
        radius: CGFloat = Chamfer.Radius.small,
        isEnabled: Bool = true
    ) {
        self.shape = .roundedRectangle(radius: radius)
        self.isEnabled = isEnabled
    }

    public init(shape: ChamferFocusShape, isEnabled: Bool = true) {
        self.shape = shape
        self.isEnabled = isEnabled
    }

    public func body(content: Content) -> some View {
        content
            .focusable(isEnabled)
            .focusEffectDisabled()
            .focused($isFocused)
            .modifier(FocusRing(isFocused: isFocused, shape: shape))
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

    /// Focusable, with a ring that follows a circular control rather than
    /// enclosing it in a rounded rectangle.
    func chamferFocusableCircle(_ isEnabled: Bool = true) -> some View {
        modifier(ChamferFocusable(shape: .circle, isEnabled: isEnabled))
    }

    /// The programmatic form is reserved for dismissal triggers. The modifier
    /// still owns the focus appearance; its caller only names where focus must
    /// return once the transient surface is gone.
    func chamferFocusable<Value: Hashable>(
        radius: CGFloat = Chamfer.Radius.small,
        focused binding: FocusState<Value>.Binding,
        equals value: Value
    ) -> some View {
        focusable()
            .focusEffectDisabled()
            .focused(binding, equals: value)
            .chamferFocusRing(binding.wrappedValue == value, radius: radius)
    }

    func chamferFocusableCircle<Value: Hashable>(
        focused binding: FocusState<Value>.Binding,
        equals value: Value
    ) -> some View {
        focusable()
            .focusEffectDisabled()
            .focused(binding, equals: value)
            .chamferFocusRingCircle(binding.wrappedValue == value)
    }
}
