import ChamferCore
import SwiftUI

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
    public enum Tone { case neutral, danger }

    private let emphasis: Emphasis
    private let tone: Tone

    public init(_ emphasis: Emphasis, tone: Tone = .neutral) {
        self.emphasis = emphasis
        self.tone = tone
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, emphasis: emphasis, tone: tone)
    }

    /// A nested view so the style can read the surface from the environment.
    /// Not named `Body` — that collides with `ButtonStyle`'s associated type.
    private struct StyledLabel: View {
        @Environment(\.chamferSurface) private var surface
        @LegacyState private var isHovered = false

        let configuration: Configuration
        let emphasis: Emphasis
        let tone: Tone

        var body: some View {
            let shape = RoundedRectangle(
                cornerRadius: Chamfer.Radius.small,
                style: .continuous
            )

            configuration.label
                .font(Chamfer.TypeScale.bodyStrong)
                .foregroundStyle(foreground)
                .padding(.horizontal, Chamfer.Space.regular)
                .frame(height: Chamfer.Control.compactFieldHeight)
                .background {
                    shape
                        .fill(background)
                        .overlay {
                            shape
                                .fill(Chamfer.Palette.hoverTint)
                                .opacity(isHovered && !usesDangerHover ? 1 : 0)
                        }
                }
                .clipShape(shape)
                .overlay(
                    shape.strokeBorder(border, lineWidth: 1)
                )
                .chamferHoverRing(isHovered, radius: Chamfer.Radius.small)
                // Every button in the app goes through this style, so the
                // keyboard gets its treatment here once rather than at ninety
                // call sites. The system's own ring is switched off: it draws a
                // blue rectangle that knows nothing about the shape underneath.
                .chamferFocusable(radius: Chamfer.Radius.small)
                .onHover { isHovered = $0 }
                // Dimming alone reads as the button being disabled rather than
                // being pushed. The give under the pointer is what says the
                // press landed. Matched to the sheet's buttons, not taken to
                // the 0.95 the guideline suggests — at this size that reads as
                // a flinch, and the two button styles appear side by side.
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.72 : 1)
                .animation(Chamfer.Motion.quick, value: isHovered)
                .animation(Chamfer.Motion.quick, value: configuration.isPressed)
                .padding(
                    Chamfer.Control.hitPadding(
                        for: Chamfer.Control.compactFieldHeight
                    )
                )
                .contentShape(Rectangle())
                .padding(
                    -Chamfer.Control.hitPadding(
                        for: Chamfer.Control.compactFieldHeight
                    )
                )
        }

        private var foreground: Color {
            if usesDangerHover { return surface.danger }
            return switch emphasis {
            case .primary: surface == .ink ? Chamfer.Palette.ink : Chamfer.Palette.paper
            case .secondary: surface.textPrimary
            case .quiet: surface.textSecondary
            }
        }

        private var background: Color {
            if usesDangerHover { return surface.dangerSoft }
            return switch emphasis {
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

        /// Destructive quiet actions remain quiet at rest. The danger colour
        /// appears only once the pointer has named the action, which separates
        /// warning from decoration without making the row shout continuously.
        private var usesDangerHover: Bool {
            guard isHovered else { return false }
            if case .danger = tone { return true }
            return false
        }
    }
}

// MARK: - Section header

/// The app's one counted group heading. Pages exchange the compact card's
/// deeper badge fill for paper's own sunken colour without changing the type,
/// tracking, or capsule vocabulary.
public struct SectionHeader: View {
    public enum Surface { case card, page }

    @Environment(\.chamferSurface) private var surfaceMode

    private let title: String
    private let count: Int?
    private let surface: Surface

    public init(
        _ title: String,
        count: Int? = nil,
        surface: Surface = .card
    ) {
        self.title = title
        self.count = count
        self.surface = surface
    }

    public var body: some View {
        HStack(spacing: Chamfer.Space.snug) {
            Text(title.uppercased())
                .font(Chamfer.TypeScale.captionStrong)
                .kerning(0.8)
                .foregroundStyle(headerForeground)
            if let count {
                Text("\(count)")
                    .font(Chamfer.TypeScale.captionStrong)
                    .foregroundStyle(countForeground)
                    .padding(.horizontal, Chamfer.Space.tight + 1)
                    .padding(.vertical, 1)
                    .background(countBackground)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private var headerForeground: Color {
        switch surface {
        case .card: surfaceMode.textFaint
        case .page: Chamfer.Palette.pageTextSoft
        }
    }

    private var countForeground: Color {
        switch surface {
        case .card: surfaceMode.textSecondary
        case .page: Chamfer.Palette.pageTextSoft
        }
    }

    private var countBackground: Color {
        switch surface {
        case .card: Chamfer.Palette.canvasDeep
        case .page: Chamfer.Palette.paperSunken
        }
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

/// A tinted line of explanation inside a surface — enough shape and colour to
/// be found without giving a local message the weight of a page-wide banner.
public struct InlineNotice: View {
    @Environment(\.chamferSurface) private var surface

    public enum Tone { case accent, danger }

    private let symbol: String
    private let tone: Tone
    private let text: String

    public init(symbol: String, tone: Tone, text: String) {
        self.symbol = symbol
        self.tone = tone
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(surface.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Chamfer.Space.snug)
        .background(background)
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
        )
    }

    private var tint: Color {
        switch tone {
        case .accent: surface.accent
        case .danger: surface.danger
        }
    }

    private var background: Color {
        switch tone {
        case .accent: surface.accentSoft
        case .danger: surface.dangerSoft
        }
    }
}
