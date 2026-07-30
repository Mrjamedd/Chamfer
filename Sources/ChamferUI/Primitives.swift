import ChamferCore
import SwiftUI

// MARK: - Card

/// The one surface in the system: a pale beige card floating on deep beige
/// canvas.
///
/// Hovering does not recolour it. It rises and its shadow deepens — the card
/// stays beige throughout, so pointing at something never changes what it says.
public struct Card<Content: View>: View {
    @State private var isHovered = false

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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Chamfer.Palette.paper)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Chamfer.Palette.paperStroke, lineWidth: 1))
            .chamferHoverRing(isHovered, radius: Chamfer.Radius.large)
            .chamferHoverLift(isActive: isHovered)
            .onHover { hovering in
                guard interactive else { return }
                isHovered = hovering
            }
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
        @State private var isHovered = false

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
                .chamferHoverRing(isHovered, radius: Chamfer.Radius.small)
                .onHover { isHovered = $0 }
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
