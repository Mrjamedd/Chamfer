import ChamferCore
import SwiftUI

/// What the Review page can do to the world.
///
/// Closures rather than a delegate so the page stays a pure function of state
/// in tests and in the gallery: pass no-ops and it renders, pass real ones and
/// it works.
public struct ReviewActions: Sendable {
    public var accept: @MainActor (Proposal) -> Void
    public var reject: @MainActor (Proposal) -> Void
    public var regenerate: @MainActor (Proposal) -> Void
    public var openNote: @MainActor (NoteSummary) -> Void
    public var retry: @MainActor (Proposal) -> Void
    /// Undo: put the previous version back on disk.
    public var restore: @MainActor (HistoryEntry) -> Void

    public init(
        accept: @escaping @MainActor (Proposal) -> Void = { _ in },
        reject: @escaping @MainActor (Proposal) -> Void = { _ in },
        regenerate: @escaping @MainActor (Proposal) -> Void = { _ in },
        openNote: @escaping @MainActor (NoteSummary) -> Void = { _ in },
        retry: @escaping @MainActor (Proposal) -> Void = { _ in },
        restore: @escaping @MainActor (HistoryEntry) -> Void = { _ in }
    ) {
        self.accept = accept
        self.reject = reject
        self.regenerate = regenerate
        self.openNote = openNote
        self.retry = retry
        self.restore = restore
    }
}

/// Review and History as one page.
///
/// Pending rewrites sit at the top grouped by vault; below a hairline, every
/// rewrite that already happened, newest first. The full stored history is the
/// end of the same scroll rather than somewhere else to go.
struct ReviewTimelinePage: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: DashboardState
    var actions = ReviewActions()

    @State private var selection = ReviewSelection()
    @State private var showingEverything = false
    /// Set while the user is being warned that a rewrite is built on text that
    /// has since changed. Holding the proposal rather than a flag means the
    /// warning can name it.
    @State private var confirmingOutdated: Proposal?

    private var timeline: ReviewTimeline {
        state.timeline(limit: showingEverything ? .max : HistoryWindow.standardLimit)
    }

    var body: some View {
        let timeline = timeline

        Group {
            if timeline.isEmpty {
                PageMessage(
                    title: "Nothing yet",
                    detail: "Rewrites waiting on your judgement appear here, and everything Chamfer has already changed stays below them."
                )
            } else {
                PageScroll(title: "Review", accessory: bulkBar(timeline)) {
                    VStack(alignment: .leading, spacing: Chamfer.Space.section) {
                        ForEach(timeline.pending) { group in
                            pendingGroup(group)
                        }

                        if !timeline.pending.isEmpty && !timeline.past.isEmpty {
                            PageRule()
                        }

                        if !timeline.past.isEmpty {
                            pastSection(timeline)
                        }
                    }
                }
            }
        }
        .overlay {
            if let proposal = confirmingOutdated {
                OutdatedConfirmation(
                    proposal: proposal,
                    onApply: {
                        dismissConfirmation()
                        commit { actions.accept(proposal) }
                    },
                    onRegenerate: {
                        dismissConfirmation()
                        commit { actions.regenerate(proposal) }
                    },
                    onCancel: dismissConfirmation
                )
            }
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: confirmingOutdated?.id
        )
        .onChange(of: state.proposals.count) {
            // A tick left on a rewrite that has since been judged must never
            // widen the next bulk action.
            selection.prune(against: state.proposals)
        }
    }

    // MARK: Pending

    @ViewBuilder
    private func pendingGroup(_ group: ReviewTimeline.PendingGroup) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
            PageSectionHeader(title: group.vaultName, count: group.proposals.count)

            ForEach(group.proposals) { proposal in
                PendingRewriteRow(
                    proposal: proposal,
                    isOutdated: state.isOutdated(proposal),
                    isSelected: selection.contains(proposal.id),
                    onToggleSelection: { selection.toggle(proposal.id) },
                    onAccept: { accept(proposal) },
                    onReject: { commit { actions.reject(proposal) } },
                    onRegenerate: { commit { actions.regenerate(proposal) } },
                    onRetry: { commit { actions.retry(proposal) } },
                    onOpen: { actions.openNote(proposal.note) }
                )
            }
        }
    }

    /// Sits on the page title's baseline, and only while something is ticked.
    /// Bulk actions are never available by accident.
    private func bulkBar(_ timeline: ReviewTimeline) -> AnyView? {
        guard !selection.isEmpty else { return nil }
        let chosen = selection.resolve(in: state.proposals)
        guard !chosen.isEmpty else { return nil }

        return AnyView(
            HStack(spacing: Chamfer.Space.snug) {
                Text("\(chosen.count) selected")
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                Button("Accept") {
                    commit { chosen.forEach(actions.accept) }
                    selection.clear()
                }
                .buttonStyle(ChamferButtonStyle(.primary))
                Button("Reject") {
                    commit { chosen.forEach(actions.reject) }
                    selection.clear()
                }
                .buttonStyle(ChamferButtonStyle(.secondary))
            }
            .transition(.opacity)
        )
    }

    // MARK: The past

    @ViewBuilder
    private func pastSection(_ timeline: ReviewTimeline) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
            PageSectionHeader(title: "Already done", count: timeline.storedCount)

            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                ForEach(timeline.past) { entry in
                    HistoryEntryRow(
                        entry: entry,
                        onRestore: { commit { actions.restore(entry) } },
                        onOpen: { actions.openNote(entry.note) }
                    )
                }
            }

            if timeline.hasMoreStored {
                Button("Show all \(timeline.storedCount.formatted()) changes") {
                    Haptics.pop()
                    withAnimation(
                        Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
                    ) {
                        showingEverything = true
                    }
                }
                .buttonStyle(ChamferButtonStyle(.quiet))
                .padding(.top, Chamfer.Space.snug)
            } else if showingEverything && timeline.storedCount > HistoryWindow.standardLimit {
                Text("That's everything Chamfer has stored.")
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .padding(.top, Chamfer.Space.snug)
            }
        }
    }

    // MARK: Actions

    /// Accepting an outdated rewrite replaces text the user has written since,
    /// so it asks first. Everything else commits immediately.
    private func accept(_ proposal: Proposal) {
        guard state.isOutdated(proposal) else {
            commit { actions.accept(proposal) }
            return
        }
        Haptics.pop()
        confirmingOutdated = proposal
    }

    private func dismissConfirmation() {
        Haptics.commit()
        confirmingOutdated = nil
    }

    /// One punctuation mark per decision, wherever the decision came from.
    private func commit(_ work: () -> Void) {
        Haptics.commit()
        work()
    }
}

// MARK: - Pending row

private struct PendingRewriteRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let proposal: Proposal
    let isOutdated: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
    let onRegenerate: () -> Void
    let onRetry: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            header
            metadata

            if isOutdated {
                InlineNotice(
                    symbol: "clock.arrow.circlepath",
                    tint: Chamfer.Palette.brass,
                    background: Chamfer.Palette.brassSoft,
                    text: "The note changed after this rewrite was made. Regenerate it, or apply it and replace what you wrote since."
                )
            }

            if let failure = proposal.state.failure {
                InlineNotice(
                    symbol: "exclamationmark.octagon.fill",
                    tint: Chamfer.Palette.danger,
                    background: Chamfer.Palette.dangerSoft,
                    text: "\(failure.title). \(failure.detail)"
                )
            }

            if let fallback = proposal.fallback {
                InlineNotice(
                    symbol: fallback.leftDevice ? "cloud" : "cpu",
                    tint: Chamfer.Palette.brass,
                    background: Chamfer.Palette.brassSoft,
                    text: fallback.leftDevice
                        ? "\(fallback.requestedModel) was unavailable, so \(fallback.usedModel) wrote this — and it ran in the cloud."
                        : "\(fallback.requestedModel) was unavailable, so \(fallback.usedModel) wrote this."
                )
            }

            if proposal.state == .regenerating {
                Text("Generating again from the current text…")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
            } else if let first = proposal.hunks.first {
                DiffHunkView(first)
                if proposal.hunks.count > 1 {
                    Text("+ \(proposal.hunks.count - 1) more change\(proposal.hunks.count == 2 ? "" : "s") in this note")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                }
            }

            actionRow
        }
        .padding(.vertical, Chamfer.Space.snug)
        .onHover { hovering in
            withAnimation(Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion)) {
                isHovered = hovering
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.regular) {
            SelectionTick(isSelected: isSelected, action: onToggleSelection)
                // The tick is for bulk work, so it stays out of sight until
                // the pointer is on the row or something is already ticked.
                .opacity(isSelected || isHovered ? 1 : 0)

            Text(proposal.note.title)
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Chamfer.Space.snug)

            if isOutdated {
                Pill("Outdated", symbol: "clock.badge.exclamationmark", tone: .accent)
            }
            if proposal.state.failure != nil {
                Pill("Failed", symbol: "exclamationmark.octagon", tone: .danger)
            }
        }
    }

    /// Location, mode, model and age, as one quiet line. The scope asks for
    /// all of it; a row of pills for every rewrite would drown the page.
    private var metadata: some View {
        Text(metadataText)
            .font(Chamfer.TypeScale.caption)
            .foregroundStyle(Chamfer.Palette.pageTextSoft)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var metadataText: String {
        var parts = [
            proposal.note.url.deletingLastPathComponent().lastPathComponent,
            proposal.mode.title,
            proposal.modelID,
            RelativeTime.string(proposal.createdAt, since: now)
        ]
        if proposal.retryCount > 0 {
            parts.append("retried \(proposal.retryCount)×")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: Chamfer.Space.snug) {
            if proposal.state.failure != nil {
                if proposal.state.failure?.isRetryable == true {
                    Button("Try again", action: onRetry)
                        .buttonStyle(ChamferButtonStyle(.primary))
                }
                Button("Dismiss", action: onReject)
                    .buttonStyle(ChamferButtonStyle(.secondary))
            } else if proposal.state == .regenerating {
                Button("Reject", action: onReject)
                    .buttonStyle(ChamferButtonStyle(.secondary))
            } else {
                Button("Accept", action: onAccept)
                    .buttonStyle(ChamferButtonStyle(.primary))
                Button("Reject", action: onReject)
                    .buttonStyle(ChamferButtonStyle(.secondary))
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(ChamferButtonStyle(.quiet))
            }
            Spacer(minLength: 0)
            Button("Open note", action: onOpen)
                .buttonStyle(ChamferButtonStyle(.quiet))
        }
    }
}

// MARK: - History row

private struct HistoryEntryRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: HistoryEntry
    let onRestore: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.regular) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                HStack(spacing: Chamfer.Space.snug) {
                    Text(entry.note.title)
                        .font(Chamfer.TypeScale.bodyStrong)
                        .foregroundStyle(Chamfer.Palette.pageText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if case .reverted = entry.outcome {
                        Pill("Undone", tone: .neutral)
                    }
                }
                Text(detail)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Chamfer.Space.snug)

            // Undo is the one control that matters here, and it appears on the
            // row the pointer is on rather than on all two hundred at once.
            HStack(spacing: Chamfer.Space.tight) {
                if entry.canRestore {
                    Button("Undo", action: onRestore)
                        .buttonStyle(ChamferButtonStyle(.quiet))
                }
                Button("Open", action: onOpen)
                    .buttonStyle(ChamferButtonStyle(.quiet))
            }
            .opacity(isHovered ? 1 : 0)

            Text(RelativeTime.string(entry.occurredAt, since: now))
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion)) {
                isHovered = hovering
            }
        }
    }

    private var symbol: String {
        switch entry.outcome {
        case .applied: entry.application == .automatic ? "wand.and.stars" : "checkmark"
        case .failed: "exclamationmark.octagon.fill"
        case .reverted: "arrow.uturn.backward"
        }
    }

    private var tint: Color {
        switch entry.outcome {
        case .applied: Chamfer.Palette.positive
        case .failed: Chamfer.Palette.danger
        case .reverted: Chamfer.Palette.pageTextSoft
        }
    }

    private var detail: String {
        if let failure = entry.outcome.failure {
            return "\(failure.title). \(failure.detail)"
        }
        return entry.summary(since: now)
    }
}

// MARK: - Outdated confirmation

/// The warning before an outdated rewrite is applied.
///
/// Not a system alert: the scope requires the user be told exactly what they
/// are about to lose and offered the regenerate instead, and an alert with two
/// buttons cannot make the third option as easy as the destructive one.
private struct OutdatedConfirmation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let proposal: Proposal
    let onApply: () -> Void
    let onRegenerate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Clicking away is the same as cancelling, so the two routes out
            // are punctuated identically.
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                Text("This rewrite is out of date")
                    .font(Chamfer.TypeScale.title)
                    .foregroundStyle(Chamfer.Palette.textOnPaper)

                Text("“\(proposal.note.title)” has changed since this rewrite was made. Applying it will replace what you have written since.")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Text("The version being replaced stays in history, so this can be undone.")
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Chamfer.Space.snug) {
                    Button("Regenerate", action: onRegenerate)
                        .buttonStyle(ChamferButtonStyle(.primary))
                    Button("Apply anyway", action: onApply)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ChamferButtonStyle(.quiet))
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, Chamfer.Space.tight)
            }
            .padding(Chamfer.Space.loose)
            .frame(maxWidth: 420)
            .background(Chamfer.Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous))
            .chamferFloat()
            .transition(sheetTransition)
        }
    }

    /// Grows from slightly small and fades, and leaves the same way it came.
    private var sheetTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
    }
}

// MARK: - Small parts

/// The bulk-selection tick. A ring that fills, rather than a system checkbox,
/// so it belongs to the page it sits on.
private struct SelectionTick: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? Chamfer.Palette.ink : Chamfer.Palette.paperStroke,
                        lineWidth: 1.5
                    )
                    .background(Circle().fill(isSelected ? Chamfer.Palette.ink : .clear))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Chamfer.Palette.paper)
                }
            }
            .frame(width: 15, height: 15)
        }
        .buttonStyle(.plain)
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion),
            value: isSelected
        )
        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }
}

/// A tinted line of explanation inside a row — the outdated warning, a
/// failure, a fallback disclosure.
private struct InlineNotice: View {
    let symbol: String
    let tint: Color
    let background: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Chamfer.Space.snug)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous))
    }
}
