import ChamferCore
import SwiftUI

/// The gutter's second control: this note's queued work and recorded history.
///
/// Shaped exactly like `FloatingCloseButton` because it answers the same
/// gesture. The gutter is already the place you move the pointer when you want
/// something done *to* the page rather than *in* it, so change history belongs
/// there and nowhere on the page itself.
public struct FloatingHistoryButton: View {
    @LegacyState private var isHovered = false

    private let count: Int
    private let action: () -> Void
    private let onHover: (Bool) -> Void
    private let focus: FocusState<Bool>.Binding?

    public init(
        count: Int,
        onHover: @escaping (Bool) -> Void = { _ in },
        focus: FocusState<Bool>.Binding? = nil,
        action: @escaping () -> Void
    ) {
        self.count = count
        self.onHover = onHover
        self.focus = focus
        self.action = action
    }

    public var body: some View {
        focusableControl
    }

    @ViewBuilder
    private var focusableControl: some View {
        if let focus {
            control.chamferFocusable(
                radius: Chamfer.Radius.pill,
                focused: focus,
                equals: true
            )
        } else {
            control.chamferFocusable(radius: Chamfer.Radius.pill)
        }
    }

    private var control: some View {
        Button {
            Haptics.pop()
            action()
        } label: {
            HStack(spacing: Chamfer.Space.tight + 1) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(Chamfer.TypeScale.captionStrong)
                    .monospacedDigit()
            }
            .foregroundStyle(Chamfer.Palette.textOnPaper)
            .padding(.horizontal, Chamfer.Space.regular)
            .frame(height: 32)
            .background {
                Capsule()
                    .fill(Chamfer.Palette.bar)
                    .overlay {
                        Capsule()
                            .fill(Chamfer.Palette.hoverTint)
                            .opacity(isHovered ? 1 : 0)
                    }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Chamfer.Palette.barStroke, lineWidth: 1))
            // Same trick as the close button: reads small, answers big.
            .padding(6)
            .contentShape(Rectangle())
            .padding(-6)
        }
        .buttonStyle(.plain)
        .chamferHoverRing(isHovered, radius: Chamfer.Radius.pill)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .help("Change history and queued rewrites")
        .accessibilityLabel("Change history, \(count) item\(count == 1 ? "" : "s")")
        .accessibilityHint("Shows queued rewrites and earlier versions of this note")
    }
}

/// One note's complete change surface: decisions still waiting at the top and
/// restorable applied history below.
struct NoteChangeHistorySheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let note: NoteDocument
    let state: DashboardState
    let actions: ReviewActions
    let onDismiss: () -> Void

    @LegacyState private var confirmingOutdated: Proposal?
    @FocusState private var confirmationTrigger: UUID?

    private var changes: NoteChangeHistory {
        state.changes(forNoteAt: note.url)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Chamfer.Space.section) {
                        if changes.isEmpty {
                            emptyState
                        }

                        if !changes.queued.isEmpty {
                            queuedSection
                        }

                        if !changes.queued.isEmpty && !changes.history.isEmpty {
                            Rectangle()
                                .fill(Chamfer.Palette.paperStroke)
                                .frame(height: 1)
                        }

                        if !changes.history.isEmpty {
                            historySection
                        }
                    }
                }
                .frame(maxHeight: 560)

                HStack {
                    Text("Restoring keeps a snapshot of the version it replaces.")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                    Spacer()
                    Button("Done", action: onDismiss)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(Chamfer.Space.loose)
            .frame(width: 660)
            .background(Chamfer.Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous))
            .chamferRing(radius: Chamfer.Radius.large)
            .chamferFloat()
            .transition(sheetTransition)
        }
        .disabled(confirmingOutdated != nil)
        .overlay {
            if let proposal = confirmingOutdated {
                OutdatedConfirmation(
                    proposal: proposal,
                    onApply: {
                        dismissConfirmation(restoringFocus: true)
                        commit { actions.accept(proposal, true) }
                    },
                    onRegenerate: {
                        dismissConfirmation(restoringFocus: true)
                        commit { actions.regenerate(proposal) }
                    },
                    onCancel: {
                        Haptics.commit()
                        dismissConfirmation(restoringFocus: true)
                    }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
            Text("Change history")
                .font(Chamfer.TypeScale.title)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
            Text(note.url.deletingPathExtension().lastPathComponent)
                .font(Chamfer.TypeScale.bodyStrong)
                .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(summary)
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
        }
    }

    private var summary: String {
        let queued = changes.queued.count
        let recorded = changes.history.count
        return "\(queued) queued · \(recorded) recorded"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
            Text("No changes yet")
                .font(Chamfer.TypeScale.bodyStrong)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
            Text("Queued rewrites will appear here for review. Once a change is applied, its restorable version stays in this history.")
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Chamfer.Space.regular)
    }

    private var queuedSection: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            SectionHeader(
                "Queued changes",
                count: changes.queued.count,
                surface: .page
            )

            ForEach(changes.queued) { proposal in
                PendingRewriteRow(
                    proposal: proposal,
                    isOutdated: state.isOutdated(proposal),
                    isSelected: false,
                    onToggleSelection: {},
                    onAccept: { accept(proposal) },
                    onReject: { commit { actions.reject(proposal) } },
                    onSetHunkSelected: { hunkID, selected in
                        actions.setHunkSelected(proposal, hunkID, selected)
                    },
                    onRegenerate: { commit { actions.regenerate(proposal) } },
                    onRetry: { commit { actions.retry(proposal) } },
                    onOpen: {},
                    showsSelection: false,
                    showsOpenAction: false,
                    acceptFocus: $confirmationTrigger
                )
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            SectionHeader(
                "Change history",
                count: changes.history.count,
                surface: .page
            )

            ForEach(changes.history) { entry in
                NoteHistoryRow(
                    entry: entry,
                    canRestore: state.isHistoryActionable(entry),
                    onRestore: { commit { actions.restore(entry) } }
                )
            }
        }
    }

    private func accept(_ proposal: Proposal) {
        guard state.isOutdated(proposal) else {
            commit { actions.accept(proposal, false) }
            return
        }
        Haptics.pop()
        confirmationTrigger = proposal.id
        withAnimation(sheetArrivalAnimation) {
            confirmingOutdated = proposal
        }
    }

    private func dismissConfirmation(restoringFocus: Bool) {
        let trigger = confirmingOutdated?.id
        withAnimation(sheetDepartureAnimation) {
            confirmingOutdated = nil
        }
        if restoringFocus, let trigger { confirmationTrigger = trigger }
    }

    private func commit(_ work: () -> Void) {
        Haptics.commit()
        work()
    }

    private var sheetTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
    }

    private var sheetArrivalAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.sheetArrival, when: reduceMotion)
    }

    private var sheetDepartureAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.sheetDeparture, when: reduceMotion)
    }
}

private struct NoteHistoryRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var isHovered = false
    @LegacyState private var showingChanges = false

    let entry: HistoryEntry
    let canRestore: Bool
    let onRestore: () -> Void

    private var hunks: [Hunk] {
        TextDiff.hunks(from: entry.previousText, to: entry.appliedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            HStack(alignment: .top, spacing: Chamfer.Space.regular) {
                VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                    Text(RelativeTime.string(entry.occurredAt, since: now))
                        .font(Chamfer.TypeScale.bodyStrong)
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                    Text(detail)
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Chamfer.Space.snug)

                HStack(spacing: Chamfer.Space.tight) {
                    if !hunks.isEmpty {
                        Button(showingChanges ? "Hide changes" : "View changes") {
                            Haptics.pop()
                            showingChanges.toggle()
                        }
                        .buttonStyle(ChamferButtonStyle(.quiet))
                    }
                    if canRestore {
                        Button("Restore") {
                            Haptics.commit()
                            onRestore()
                        }
                        .buttonStyle(ChamferButtonStyle(.secondary))
                    }
                }
                .opacity(isHovered ? 1 : 0.45)
            }

            if showingChanges {
                VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
                    ForEach(hunks) { hunk in
                        DiffHunkView(hunk)
                    }
                }
                .transition(changeTransition)
            }
        }
        .padding(Chamfer.Space.snug)
        .background(isHovered ? Chamfer.Palette.paperSunken : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            // Kept identical to the Review timeline: history is actionable in
            // either place, so its fill and control reveal should answer the
            // pointer with the same interruptible response.
            withAnimation(Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion)) {
                isHovered = hovering
            }
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion),
            value: showingChanges
        )
    }

    private var detail: String {
        if let failure = entry.outcome.failure {
            return "\(failure.title). \(failure.detail)"
        }
        return entry.summary(since: now)
    }

    private var changeTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .offset(y: -4))
    }
}
