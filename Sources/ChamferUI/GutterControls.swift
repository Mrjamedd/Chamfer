import SwiftUI

/// The gutter's third control: the app's own defaults.
///
/// Shaped exactly like `FloatingCloseButton`, because the gutter has one
/// vocabulary and a control that invented a second one would read as having
/// arrived from somewhere else. It sits at the leading edge, mirroring
/// `FloatingVersionsButton` at the trailing one, with close held in the middle
/// where it has always been — so neither of the two controls added since
/// moves the one the hand already knows.
///
/// Settings is a window rather than a page, which is why it belongs here and
/// not on the page: the gutter is where you reach when you want something done
/// *to* what you are looking at rather than *in* it.
public struct FloatingSettingsButton: View {
    @State private var isHovered = false

    private let action: () -> Void
    private let onHover: (Bool) -> Void

    public init(
        onHover: @escaping (Bool) -> Void = { _ in },
        action: @escaping () -> Void
    ) {
        self.onHover = onHover
        self.action = action
    }

    public var body: some View {
        Button {
            // `pop`, not `commit`. Close punctuates a dismissal; this opens
            // something, and matches the versions button it is paired with.
            Haptics.pop()
            action()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Chamfer.Palette.bar)
                        .overlay {
                            Circle()
                                .fill(Chamfer.Palette.hoverTint)
                                .opacity(isHovered ? 1 : 0)
                        }
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Chamfer.Palette.barStroke, lineWidth: 1))
                // Reads at 32pt, answers at 44 — the same trick the other two
                // gutter controls use, and for the same reason.
                .padding(6)
                .contentShape(Rectangle())
                .padding(-6)
        }
        .buttonStyle(.plain)
        .chamferHoverRingCircle(isHovered)
        .chamferFloat(radius: 14, y: 6, opacity: 0.18)
        .onHover { inside in
            isHovered = inside
            onHover(inside)
        }
        .animation(Chamfer.Motion.quick, value: isHovered)
        .help("Chamfer Settings")
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens Chamfer's defaults in a separate window")
    }
}
