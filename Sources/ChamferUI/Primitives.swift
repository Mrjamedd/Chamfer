import ChamferCore
import SwiftUI

// MARK: - Card

/// The one surface in the system. Everything that sits on the canvas sits in
/// one of these, so elevation never has to be reinvented per screen.
public struct Card<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    public init(padding: CGFloat = Chamfer.Space.roomy, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Chamfer.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
                    .strokeBorder(Chamfer.Palette.stroke, lineWidth: 1)
            )
    }
}

// MARK: - Pill

public struct Pill: View {
    public enum Tone {
        case neutral, accent, positive, danger

        var foreground: Color {
            switch self {
            case .neutral: Chamfer.Palette.textSecondary
            case .accent: Chamfer.Palette.accent
            case .positive: Chamfer.Palette.positive
            case .danger: Chamfer.Palette.danger
            }
        }

        var background: Color {
            switch self {
            case .neutral: Chamfer.Palette.sunken
            case .accent: Chamfer.Palette.accentSoft
            case .positive: Chamfer.Palette.positiveSoft
            case .danger: Chamfer.Palette.dangerSoft
            }
        }
    }

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
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, Chamfer.Space.snug)
        .padding(.vertical, Chamfer.Space.tight)
        .background(tone.background)
        .clipShape(Capsule())
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
        case .primary: Chamfer.Palette.surface
        case .secondary: Chamfer.Palette.textPrimary
        case .quiet: Chamfer.Palette.textSecondary
        }
    }

    private var background: Color {
        switch emphasis {
        case .primary: Chamfer.Palette.accent
        case .secondary: Chamfer.Palette.surface
        case .quiet: .clear
        }
    }

    private var border: Color {
        switch emphasis {
        case .primary: .clear
        case .secondary: Chamfer.Palette.stroke
        case .quiet: .clear
        }
    }
}

// MARK: - Section header

public struct SectionHeader: View {
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
                .kerning(0.6)
                .foregroundStyle(Chamfer.Palette.textTertiary)
            if let count {
                Text("\(count)")
                    .font(Chamfer.TypeScale.captionStrong)
                    .foregroundStyle(Chamfer.Palette.textTertiary)
                    .padding(.horizontal, Chamfer.Space.tight + 1)
                    .padding(.vertical, 1)
                    .background(Chamfer.Palette.sunken)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

// MARK: - Empty state

public struct EmptyState: View {
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
                .foregroundStyle(Chamfer.Palette.textTertiary)
            VStack(spacing: Chamfer.Space.tight) {
                Text(title)
                    .font(Chamfer.TypeScale.title)
                    .foregroundStyle(Chamfer.Palette.textPrimary)
                Text(message)
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Chamfer.Space.section)
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
    private let state: RunState

    public init(_ state: RunState) {
        self.state = state
    }

    public var body: some View {
        switch state {
        case let .rewritingUnavailable(reason):
            banner(
                symbol: "exclamationmark.triangle.fill",
                tone: Chamfer.Palette.warning,
                background: Chamfer.Palette.accentSoft,
                title: "Rewrites are off",
                detail: reason
            )
        case let .failed(message):
            banner(
                symbol: "exclamationmark.octagon.fill",
                tone: Chamfer.Palette.danger,
                background: Chamfer.Palette.dangerSoft,
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
                    .foregroundStyle(Chamfer.Palette.textPrimary)
                Text(detail)
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.textSecondary)
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
