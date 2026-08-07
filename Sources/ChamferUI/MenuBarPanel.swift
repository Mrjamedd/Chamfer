import ChamferCore
import SwiftUI

public struct MenuBarActions: Sendable {
    public var openMainWindow: @MainActor () -> Void
    public var openReview: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var togglePause: @MainActor () -> Void
    public var quit: @MainActor () -> Void

    public init(
        openMainWindow: @escaping @MainActor () -> Void = {},
        openReview: @escaping @MainActor () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {},
        togglePause: @escaping @MainActor () -> Void = {},
        quit: @escaping @MainActor () -> Void = {}
    ) {
        self.openMainWindow = openMainWindow
        self.openReview = openReview
        self.openSettings = openSettings
        self.togglePause = togglePause
        self.quit = quit
    }
}

/// What the menu bar shows.
///
/// A small mirror of the Review page rather than a second interface: what is
/// waiting, what just happened, and the two controls you would reach for
/// without opening the window. It costs the main window nothing because it is
/// outside it, which is exactly why the things that would have crowded the
/// window live here instead.
///
/// The surrounding `NSStatusItem` and transparent `NSPanel` live in the app
/// target; this view is only its contents, so it can be exercised without a
/// status item existing.
public struct MenuBarPanel: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let state: DashboardState
    private let actions: MenuBarActions
    private let onDismiss: () -> Void

    public init(
        state: DashboardState,
        actions: MenuBarActions = MenuBarActions(),
        onDismiss: @escaping () -> Void = {}
    ) {
        self.state = state
        self.actions = actions
        self.onDismiss = onDismiss
    }

    /// Only the last handful. The panel is a glance, and anything that wants
    /// scrolling wants the window instead.
    private static let recentLimit = 4

    private var recent: [HistoryEntry] {
        Array(HistoryWindow.recent(state.history, limit: Self.recentLimit))
    }

    private var pending: [Proposal] {
        state.pendingProposals.sorted { $0.createdAt > $1.createdAt }
    }

    private var isPaused: Bool {
        state.runState == .paused
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            header

            RunStateBanner(state.runState)

            if pending.isEmpty && recent.isEmpty {
                Text("Nothing waiting, nothing changed yet.")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                    .padding(.vertical, Chamfer.Space.snug)
            } else {
                if !pending.isEmpty {
                    section(title: "Waiting on you", count: pending.count) {
                        ForEach(pending.prefix(Self.recentLimit)) { proposal in
                            PanelRow(
                                symbol: "checkmark.circle",
                                tint: Chamfer.Palette.brass,
                                title: proposal.note.title,
                                detail: "\(proposal.mode.title) · \(RelativeTime.string(proposal.createdAt, since: now))",
                                isWarning: state.isOutdated(proposal)
                            )
                        }
                        if pending.count > Self.recentLimit {
                            Text("+ \(pending.count - Self.recentLimit) more")
                                .font(Chamfer.TypeScale.caption)
                                .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                        }
                    }
                }

                if !recent.isEmpty {
                    section(title: "Just done", count: nil) {
                        ForEach(recent) { entry in
                            PanelRow(
                                symbol: entry.outcome.failure == nil ? "checkmark" : "exclamationmark.octagon.fill",
                                tint: entry.outcome.failure == nil
                                    ? Chamfer.Palette.positive
                                    : Chamfer.Palette.danger,
                                title: entry.note.title,
                                detail: "\(entry.mode.title) · \(RelativeTime.string(entry.occurredAt, since: now))",
                                isWarning: false
                            )
                        }
                    }
                }
            }

            Divider().overlay(Chamfer.Palette.paperStroke)
            controls
        }
        .padding(Chamfer.Space.roomy)
        .frame(width: 300)
        .background(Chamfer.Palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
                .strokeBorder(Chamfer.Palette.paperStroke, lineWidth: 1)
        )
        // Escape always closes it, the same as clicking away.
        .background {
            Button("", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
        .accessibilityLabel("Chamfer status")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.snug) {
            Text("Chamfer")
                .font(Chamfer.TypeScale.title)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
            Spacer(minLength: 0)
            RunStateBadge(state.runState)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            SectionHeader(title, count: count)
            content()
        }
    }

    private var controls: some View {
        HStack(spacing: Chamfer.Space.snug) {
            Button(pending.isEmpty ? "Open" : "Review \(pending.count)") {
                Haptics.commit()
                actions.openReview()
                onDismiss()
            }
            .buttonStyle(ChamferButtonStyle(.primary))

            Button(isPaused ? "Resume" : "Pause") {
                Haptics.commit()
                actions.togglePause()
            }
            .buttonStyle(ChamferButtonStyle(.secondary))

            Spacer(minLength: 0)

            // A glyph rather than a fourth word. The row is 300pt wide and
            // already carries three labels; "Settings" spelled out would push
            // Quit into the corner and make the footer read as a toolbar.
            Button {
                Haptics.pop()
                actions.openSettings()
                onDismiss()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(ChamferButtonStyle(.quiet))
            .help("Chamfer Settings")
            .accessibilityLabel("Settings")

            Button("Quit") {
                Haptics.commit()
                actions.quit()
            }
            .buttonStyle(ChamferButtonStyle(.quiet))
        }
    }

    /// Haptic on the way out, matching every other dismissal in the app.
    private func dismiss() {
        Haptics.commit()
        onDismiss()
    }
}

private struct PanelRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let isWarning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: isWarning ? "clock.badge.exclamationmark" : symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isWarning ? Chamfer.Palette.brass : tint)
                .frame(width: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isWarning ? "\(detail) · source changed" : detail)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
