import ChamferCore
import SwiftUI

// MARK: - Card

/// The one surface in the system: a beige card floating on beige canvas.
///
/// On hover it lifts, inverts to ink, and a pink sheen sweeps across it — a
/// chamfered edge catching the light. Everything inside recolours itself,
/// because the card publishes its surface through the environment rather than
/// telling each child what to do.
public struct Card<Content: View>: View {
    @State private var isHovered = false
    @State private var shinePhase: CGFloat = 0

    private let content: Content
    private let padding: CGFloat
    private let interactive: Bool

    public init(
        padding: CGFloat = Chamfer.Space.roomy,
        interactive: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.interactive = interactive
        self.content = content()
    }

    private var surface: SurfaceMode { isHovered ? .ink : .paper }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
    }

    public var body: some View {
        content
            .environment(\.chamferSurface, surface)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface.background)
            .overlay {
                if isHovered {
                    Shine(phase: shinePhase)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(surface.stroke, lineWidth: 1))
            .shadow(
                color: .black.opacity(isHovered ? 0.20 : 0.08),
                radius: isHovered ? 20 : 9,
                y: isHovered ? 11 : 4
            )
            .shadow(
                color: Chamfer.Palette.pink.opacity(isHovered ? 0.26 : 0),
                radius: 26,
                y: 8
            )
            .offset(y: isHovered ? -3 : 0)
            .animation(Chamfer.Motion.lift, value: isHovered)
            .onHover { hovering in
                guard interactive else { return }
                isHovered = hovering
                if hovering {
                    shinePhase = 0
                    withAnimation(Chamfer.Motion.shine) { shinePhase = 1 }
                } else {
                    shinePhase = 0
                }
            }
    }
}

/// A narrow diagonal band of pink light travelling left to right.
private struct Shine: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let band = max(width * 0.42, 110)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Chamfer.Palette.pink.opacity(0.10), location: 0.35),
                    .init(color: Chamfer.Palette.pink.opacity(0.55), location: 0.5),
                    .init(color: Chamfer.Palette.pink.opacity(0.10), location: 0.65),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            .scaleEffect(y: 2.4)
            .rotationEffect(.degrees(16))
            .offset(x: -band + phase * (width + band * 2))
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Pill

public struct Pill: View {
    @Environment(\.chamferSurface) private var surface

    public enum Tone { case neutral, accent, positive, danger }

    private let text: String
    private let symbol: String?
    private let tone: Tone

    public init(_ text: String, symbol: String? = nil, tone: Tone = .neutral) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: Chamfer.Space.tight) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(text).font(Chamfer.TypeScale.captionStrong)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Chamfer.Space.snug)
        .padding(.vertical, Chamfer.Space.tight)
        .background(background)
        .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: surface.textSecondary
        case .accent: surface.accent
        case .positive: surface.positive
        case .danger: surface.danger
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: surface.sunken
        case .accent: surface.accentSoft
        case .positive: surface.positiveSoft
        case .danger: surface.dangerSoft
        }
    }
}

// MARK: - Buttons

public struct ChamferButtonStyle: ButtonStyle {
    public enum Emphasis { case primary, secondary, quiet }

    private let emphasis: Emphasis

    public init(_ emphasis: Emphasis) {
        self.emphasis = emphasis
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, emphasis: emphasis)
    }

    /// A nested view so the style can read the surface from the environment.
    /// Not named `Body` — that collides with `ButtonStyle`'s associated type.
    private struct StyledLabel: View {
        @Environment(\.chamferSurface) private var surface

        let configuration: Configuration
        let emphasis: Emphasis

        var body: some View {
            configuration.label
                .font(Chamfer.TypeScale.bodyStrong)
                .foregroundStyle(foreground)
                .padding(.horizontal, Chamfer.Space.regular)
                .padding(.vertical, Chamfer.Space.snug - 1)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.72 : 1)
                .animation(Chamfer.Motion.quick, value: configuration.isPressed)
        }

        private var foreground: Color {
            switch emphasis {
            case .primary: surface == .ink ? Chamfer.Palette.ink : Chamfer.Palette.paper
            case .secondary: surface.textPrimary
            case .quiet: surface.textSecondary
            }
        }

        private var background: Color {
            switch emphasis {
            case .primary: surface.accent
            case .secondary: surface.sunken
            case .quiet: .clear
            }
        }

        private var border: Color {
            switch emphasis {
            case .primary: .clear
            case .secondary: surface.stroke
            case .quiet: .clear
            }
        }
    }
}

// MARK: - Section header

public struct SectionHeader: View {
    @Environment(\.chamferSurface) private var surface

    private let title: String
    private let count: Int?

    public init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(spacing: Chamfer.Space.snug) {
            Text(title.uppercased())
                .font(Chamfer.TypeScale.captionStrong)
                .kerning(0.8)
                .foregroundStyle(surface.textFaint)
            if let count {
                Text("\(count)")
                    .font(Chamfer.TypeScale.captionStrong)
                    .foregroundStyle(surface.textSecondary)
                    .padding(.horizontal, Chamfer.Space.tight + 1)
                    .padding(.vertical, 1)
                    .background(Chamfer.Palette.canvasDeep)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

// MARK: - Empty state

public struct EmptyState: View {
    @Environment(\.chamferSurface) private var surface

    private let symbol: String
    private let title: String
    private let message: String

    public init(symbol: String, title: String, message: String) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Chamfer.Space.regular) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(surface.textFaint)
            VStack(spacing: Chamfer.Space.tight) {
                Text(title)
                    .font(Chamfer.TypeScale.title)
                    .foregroundStyle(surface.textPrimary)
                Text(message)
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(surface.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Chamfer.Space.loose)
    }
}

// MARK: - Run state

public struct RunStateBadge: View {
    private let state: RunState

    public init(_ state: RunState) {
        self.state = state
    }

    public var body: some View {
        switch state {
        case .idle:
            Pill("Watching", symbol: "eye", tone: .positive)
        case let .sweeping(completed, total):
            Pill("Sweeping \(completed)/\(total)", symbol: "arrow.triangle.2.circlepath", tone: .accent)
        case let .rewriting(title):
            Pill("Rewriting \(title)", symbol: "sparkles", tone: .accent)
        case .paused:
            Pill("Paused", symbol: "pause.fill", tone: .neutral)
        case .rewritingUnavailable:
            Pill("Rules only", symbol: "exclamationmark.triangle", tone: .neutral)
        case .failed:
            Pill("Failed", symbol: "exclamationmark.octagon", tone: .danger)
        }
    }
}

/// The full-width explanation shown under the header when something is wrong.
/// Degraded states get words, not just a colour.
public struct RunStateBanner: View {
    @Environment(\.chamferSurface) private var surface

    private let state: RunState

    public init(_ state: RunState) {
        self.state = state
    }

    public var body: some View {
        switch state {
        case let .rewritingUnavailable(reason):
            banner(
                symbol: "exclamationmark.triangle.fill",
                tone: surface.accent,
                background: surface.accentSoft,
                title: "Rewrites are off",
                detail: reason
            )
        case let .failed(message):
            banner(
                symbol: "exclamationmark.octagon.fill",
                tone: surface.danger,
                background: surface.dangerSoft,
                title: "Couldn't finish",
                detail: message
            )
        default:
            EmptyView()
        }
    }

    private func banner(
        symbol: String,
        tone: Color,
        background: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: Chamfer.Space.regular) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tone)
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(title)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(surface.textPrimary)
                Text(detail)
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(surface.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Chamfer.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous))
    }
}
