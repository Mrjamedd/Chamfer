import SwiftUI

/// Shared page chrome: the same measure and margins everywhere, so every
/// destination reads as the same sheet of paper.
///
/// Lives here rather than inside `DashboardView` because it is now the thing
/// that makes Review, Vaults and History look like one app. A page that set
/// its own margins would be visible as a different page the moment you
/// switched to it.
struct PageScroll<Content: View>: View {
    let title: String
    /// Sits to the right of the title, on its baseline. Only for controls that
    /// act on the whole page — a bulk action, a count. Anything about a single
    /// row belongs on that row.
    var accessory: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.regular) {
                    Text(title)
                        .font(Chamfer.TypeScale.pageTitle)
                        .foregroundStyle(Chamfer.Palette.pageText)
                    if let accessory {
                        Spacer(minLength: Chamfer.Space.regular)
                        accessory
                    }
                }
                .padding(.bottom, Chamfer.Space.loose)
                content
            }
            .frame(maxWidth: Chamfer.Page.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Chamfer.Page.margin)
            .padding(.top, 64)
            .padding(.bottom, 56)
        }
        .scrollContentBackground(.hidden)
    }
}

/// The page's own empty state: one note waiting in the same quiet glow as Home,
/// always saying what would put something here.
///
/// Takes an optional action, because most of this app's empty states are not
/// waiting for time to pass — they are waiting for the user to connect a vault,
/// and telling somebody what to do while giving them no way to do it is the
/// difference between an empty state and a dead end. The shipping app opened on
/// exactly that dead end.
struct PageMessage: View {
    let title: String
    let detail: String
    var footerLabel: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @LegacyState private var hasEntered = false

    init(
        title: String,
        detail: String,
        footerLabel: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.footerLabel = footerLabel
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        WaitingCardScene(
            title: title,
            detail: detail,
            footerLabel: footerLabel ?? actionTitle?.uppercased() ?? "NOTHING HERE YET",
            action: action,
            isPresented: hasEntered
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            hasEntered = false
            Task { @MainActor in
                await Task.yield()
                hasEntered = true
            }
        }
    }
}

/// The two depths in an empty page do not start from the same place.
///
/// The card is the content, so it begins closer to rest and arrives first; the
/// broader glow follows and settles behind it. Reduced motion keeps the
/// cross-fade but removes the travel from both layers.
enum EmptyStateMotion {
    static func glowScale(isPresented: Bool, reduceMotion: Bool) -> CGFloat {
        guard !isPresented, !reduceMotion else { return 1 }
        return 0.92
    }

    static func cardScale(isPresented: Bool, reduceMotion: Bool) -> CGFloat {
        guard !isPresented, !reduceMotion else { return 1 }
        return 0.94
    }
}

/// The shared empty-page composition: one note waiting on the page, with the
/// same low ambient warmth as Home's empty wall.
///
/// Keeping the positioning and entry motion here means Review, Notes and
/// Vaults cannot slowly become three different versions of the same state.
struct WaitingCardScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let detail: String
    let footerLabel: String
    let action: (() -> Void)?
    let isPresented: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AmbientClusterGlow()
                    .frame(
                        width: geometry.size.width * 0.72,
                        height: geometry.size.height * 0.66
                    )
                    .position(
                        x: geometry.size.width * 0.52,
                        y: geometry.size.height * 0.46
                    )
                    // There is nothing here to light, so the empty page keeps
                    // the same quieter glow as Home's waiting wall.
                    .opacity(isPresented ? 0.55 : 0)
                    .scaleEffect(
                        EmptyStateMotion.glowScale(
                            isPresented: isPresented,
                            reduceMotion: reduceMotion
                        )
                    )
                    // The glow is atmosphere rather than content. Letting it
                    // settle last keeps the card itself in the foreground.
                    .animation(
                        Chamfer.Motion.reduce(
                            Chamfer.Motion.navigation.delay(0.04),
                            when: reduceMotion
                        ),
                        value: isPresented
                    )

                EmptyStateCard(
                    title: title,
                    detail: detail,
                    footerLabel: footerLabel,
                    action: action
                )
                .position(
                    x: geometry.size.width * 0.52,
                    y: geometry.size.height * 0.42
                )
                .opacity(isPresented ? 1 : 0)
                .scaleEffect(
                    EmptyStateMotion.cardScale(
                        isPresented: isPresented,
                        reduceMotion: reduceMotion
                    )
                )
                .animation(
                    Chamfer.Motion.reduce(
                        Chamfer.Motion.navigation,
                        when: reduceMotion
                    ),
                    value: isPresented
                )
            }
        }
    }
}

/// The one card on an otherwise empty page.
///
/// Built from the same fill, tape, tilt and contact shadow as a real Home note,
/// so an empty destination reads as waiting for content rather than failing to
/// load it. The copy varies by page; the physical object does not.
private struct EmptyStateCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var isHovered = false

    let title: String
    let detail: String
    let footerLabel: String
    let action: (() -> Void)?

    /// One card needs a stable hand of its own. It hangs slightly straighter
    /// than a real note, which is the only hint that it is not one.
    private let hand = HomeNoteHand(id: "chamfer.empty-wall")

    var body: some View {
        Group {
            if let action {
                Button {
                    Haptics.pop()
                    action()
                } label: {
                    card
                }
                .buttonStyle(.plain)
                .chamferFocusable(radius: 5)
                .accessibilityLabel("\(title). \(detail). \(footerLabel)")
            } else {
                card
                    .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Straighter than a real note, and it straightens further under the
        // pointer exactly as the actionable Home notes do.
        .rotationEffect(
            .degrees(isHovered && !reduceMotion ? hand.rotation * 0.3 : hand.rotation)
        )
        .scaleEffect(isHovered ? 1.018 : 1)
        .offset(y: isHovered && !reduceMotion ? -5 : 0)
        .onHover { isHovered = $0 && action != nil }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: isHovered
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageText)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.system(size: 11, weight: .regular, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Chamfer.Space.snug)

            Spacer(minLength: 6)

            Text(footerLabel)
                .font(Chamfer.TypeScale.eyebrow)
                .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .padding(.top, 20)
        .padding(.bottom, 14)
        // The Home card established 176pt as the quiet minimum. PageMessage
        // copy is not capped, though: errors and longer explanations grow the
        // same piece of paper instead of silently losing their last lines.
        .frame(width: 220, alignment: .topLeading)
        .frame(minHeight: 176, alignment: .topLeading)
        .background(HomeNoteSlotPalette.fill(for: 0))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Chamfer.Palette.ink.opacity(0.07), lineWidth: 0.8)
        }
        // The waiting card is the first thing many people meet, so its tape
        // lands with the same small imperfection as the real notes on Home.
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.white.opacity(hand.tapeOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(Chamfer.Palette.ink.opacity(0.055), lineWidth: 0.6)
                }
                .frame(width: hand.tapeWidth, height: 9)
                .rotationEffect(.degrees(hand.tapeRotation))
                .offset(x: hand.tapeOffset.width, y: hand.tapeOffset.height)
        }
        .shadow(
            color: Chamfer.Palette.ink.opacity(isHovered ? 0.24 : 0.19),
            radius: isHovered ? 9 : 6,
            x: 1,
            y: isHovered ? 8 : 5
        )
    }
}

/// The warmth behind both populated and waiting note clusters.
///
/// Deliberately weak. The glow is atmosphere; attaching a note to the page is
/// the job of that note's own contact shadow.
struct AmbientClusterGlow: View {
    var body: some View {
        ZStack {
            GlowField(
                color: Color(red: 0.99, green: 0.25, blue: 0.55),
                opacity: 0.20
            )
                .scaleEffect(x: 0.74, y: 0.78)
                .offset(x: 20, y: -44)

            GlowField(
                color: Color(red: 1.00, green: 0.48, blue: 0.28),
                opacity: 0.18
            )
                .scaleEffect(x: 1.04, y: 0.88)
                .offset(x: -88, y: -14)

            GlowField(
                color: Color(red: 1.00, green: 0.64, blue: 0.16),
                opacity: 0.14
            )
                .scaleEffect(x: 0.96, y: 0.76)
                .offset(x: -56, y: 76)

            GlowField(
                color: Color(red: 1.00, green: 0.46, blue: 0.64),
                opacity: 0.09
            )
                .scaleEffect(x: 0.62, y: 0.74)
                .offset(x: 124, y: -6)
        }
            .compositingGroup()
            .blur(radius: 72)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct GlowField: View {
    let color: Color
    let opacity: Double

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0.52), location: 0.42),
                        .init(color: color.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 260
                )
            )
            .opacity(opacity)
    }
}

/// A quiet division between stretches of a page.
///
/// A hairline rather than a heading where the change of subject is obvious —
/// the timeline's drop from "waiting on you" into "already done" reads from
/// the content itself, and a second big title there would compete with the
/// page's own.
struct PageRule: View {
    var body: some View {
        Rectangle()
            .fill(Chamfer.Palette.paperStroke)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
