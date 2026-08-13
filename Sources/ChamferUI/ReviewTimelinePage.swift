import ChamferCore
import SwiftUI

/// What the Review page can do to the world.
///
/// Closures rather than a delegate so the page stays a pure function of state
/// in tests and in the gallery: pass no-ops and it renders, pass real ones and
/// it works.
public struct ReviewActions: Sendable {
    public var accept: @MainActor (Proposal, Bool) -> Void
    public var reject: @MainActor (Proposal) -> Void
    public var setHunkSelected: @MainActor (Proposal, UUID, Bool) -> Void
    public var regenerate: @MainActor (Proposal) -> Void
    public var openNote: @MainActor (NoteSummary) -> Void
    public var retry: @MainActor (Proposal) -> Void
    /// Undo: put the previous version back on disk.
    public var restore: @MainActor (HistoryEntry) -> Void

    public init(
        accept: @escaping @MainActor (Proposal, Bool) -> Void = { _, _ in },
        reject: @escaping @MainActor (Proposal) -> Void = { _ in },
        setHunkSelected: @escaping @MainActor (Proposal, UUID, Bool) -> Void = {
            _, _, _ in
        },
        regenerate: @escaping @MainActor (Proposal) -> Void = { _ in },
        openNote: @escaping @MainActor (NoteSummary) -> Void = { _ in },
        retry: @escaping @MainActor (Proposal) -> Void = { _ in },
        restore: @escaping @MainActor (HistoryEntry) -> Void = { _ in }
    ) {
        self.accept = accept
        self.reject = reject
        self.setHunkSelected = setHunkSelected
        self.regenerate = regenerate
        self.openNote = openNote
        self.retry = retry
        self.restore = restore
    }
}

/// What the timeline looks like, for animation purposes only.
///
/// Animating against `ReviewTimeline` itself would mean re-running the curve
/// every time any proposal's metadata changed. What the page cares about is the
/// arrangement: which rewrites are waiting, and how much is behind them.
private struct TimelineShape: Equatable {
    let pending: [UUID]
    let pastCount: Int

    init(_ timeline: ReviewTimeline) {
        pending = timeline.pending.flatMap { $0.proposals.map(\.id) }
        pastCount = timeline.past.count
    }
}

/// Review and History as one page.
///
/// Pending rewrites sit at the top grouped by vault; below a hairline, every
/// rewrite or restore that already happened, newest first. The full stored history is the
/// end of the same scroll rather than somewhere else to go.
struct ReviewTimelinePage: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: DashboardState
    var actions = ReviewActions()
    /// Set only when there is no vault connected, which is the one case where
    /// this page's emptiness has a cause the user can do something about.
    var onConnectVault: (@MainActor () -> Void)?

    @LegacyState private var selection = ReviewSelection()
    @LegacyState private var showingEverything = false
    /// Set while the user is being warned that a rewrite is built on text that
    /// has since changed. Holding the proposal rather than a flag means the
    /// warning can name it.
    @LegacyState private var confirmingOutdated: Proposal?
    @FocusState private var confirmationTrigger: UUID?

    private var timeline: ReviewTimeline {
        state.timeline(limit: showingEverything ? .max : HistoryWindow.standardLimit)
    }

    var body: some View {
        let timeline = timeline

        Group {
            if timeline.isEmpty {
                if let onConnectVault {
                    PageMessage(
                        title: "Nothing to review yet",
                        detail: "Rewrites wait here for your judgement, and everything Chamfer has already changed stays below them. Connect a folder of notes and it will start watching.",
                        actionTitle: "Connect a vault…",
                        action: onConnectVault
                    )
                } else {
                    // A connected vault with nothing waiting is not a problem
                    // to solve — it is the app working — so it gets no button.
                    PageMessage(
                        title: "Nothing yet",
                        detail: "Rewrites waiting on your judgement appear here, and everything Chamfer has already changed stays below them.",
                        footerLabel: "WAITING FOR REWRITES"
                    )
                }
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
                    // Pending and past are one list in two tenses, so a rewrite
                    // that is accepted should be seen to move from the first
                    // into the second rather than vanishing from one and
                    // appearing in the other. Animating the whole stack against
                    // the timeline's shape is what makes the two halves read as
                    // the same list.
                    .animation(
                        Chamfer.Motion.reduce(
                            Chamfer.Motion.navigation,
                            when: reduceMotion
                        ),
                        value: TimelineShape(timeline)
                    )
                }
            }
        }
        .disabled(confirmingOutdated != nil)
        .overlay {
            if let proposal = confirmingOutdated {
                OutdatedConfirmation(
                    proposal: proposal,
                    onApply: {
                        dismissConfirmation(performHaptic: false)
                        commit { actions.accept(proposal, true) }
                    },
                    onRegenerate: {
                        dismissConfirmation(performHaptic: false)
                        commit { actions.regenerate(proposal) }
                    },
                    onCancel: { dismissConfirmation() }
                )
            }
        }
        .onChange(of: state.proposals) {
            // A tick left on a rewrite that has since been judged must never
            // widen the next bulk action.
            selection.prune(against: state.proposals)
        }
    }

    // MARK: Pending

    @ViewBuilder
    private func pendingGroup(_ group: ReviewTimeline.PendingGroup) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
            SectionHeader(
                group.vaultName,
                count: group.proposals.count,
                surface: .page
            )

            ForEach(group.proposals) { proposal in
                PendingRewriteRow(
                    proposal: proposal,
                    isOutdated: state.isOutdated(proposal),
                    isSelected: selection.contains(proposal.id),
                    onToggleSelection: { selection.toggle(proposal.id) },
                    onAccept: { accept(proposal) },
                    onReject: { commit { actions.reject(proposal) } },
                    onSetHunkSelected: { hunkID, selected in
                        actions.setHunkSelected(proposal, hunkID, selected)
                    },
                    onRegenerate: { commit { actions.regenerate(proposal) } },
                    onRetry: { commit { actions.retry(proposal) } },
                    onOpen: { actions.openNote(proposal.note) },
                    acceptFocus: $confirmationTrigger
                )
                // Judged rewrites leave upward, towards the past section they
                // are joining. A row that faded on the spot read as being
                // deleted rather than as moving on.
                .transition(rowTransition)
            }
        }
    }

    private var rowTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity
                .combined(with: .offset(y: -12))
                .combined(with: .scale(scale: 0.97, anchor: .top))
        )
    }

    /// Sits on the page title's baseline, and only while something is ticked.
    /// Bulk actions are never available by accident.
    ///
    /// Always returned, and empty when nothing is selected, so the accessory
    /// slot keeps its height. While this returned nil the title reflowed every
    /// time a tick was pressed — the one element on the page that should never
    /// move was the one moving.
    private func bulkBar(_ timeline: ReviewTimeline) -> AnyView? {
        let chosen = selection.isEmpty ? [] : selection.resolve(in: state.proposals)
        let safeToAccept = chosen.filter {
            !state.isOutdated($0) && $0.changeCount > 0
        }

        return AnyView(
            HStack(spacing: Chamfer.Space.snug) {
                if !chosen.isEmpty {
                    Text("\(chosen.count) selected")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    Button("Accept") {
                        commit {
                            safeToAccept.forEach { actions.accept($0, false) }
                        }
                        safeToAccept.forEach { selection.toggle($0.id) }
                    }
                    .buttonStyle(ChamferButtonStyle(.primary))
                    .disabled(safeToAccept.isEmpty)
                    Button("Reject") {
                        commit { chosen.forEach(actions.reject) }
                        selection.clear()
                    }
                    .buttonStyle(ChamferButtonStyle(.secondary))
                }
            }
            // Reserved whether or not anything is selected. The controls come
            // and go inside a slot that does not.
            .frame(height: Self.bulkBarHeight, alignment: .center)
            .padding(.horizontal, Chamfer.Space.snug)
            .background(Chamfer.Palette.pageInset)
            .clipShape(
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                    .strokeBorder(Chamfer.Palette.pageInsetStroke, lineWidth: 1)
            }
            .opacity(chosen.isEmpty ? 0 : 1)
            .animation(
                Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
                value: chosen.count
            )
        )
    }

    /// Tall enough for the buttons inside it, so the title's baseline is fixed
    /// whether or not they are there.
    private static let bulkBarHeight: CGFloat = 28

    // MARK: The past

    @ViewBuilder
    private func pastSection(_ timeline: ReviewTimeline) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
            SectionHeader(
                "Already done",
                count: timeline.storedCount,
                surface: .page
            )

            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                ForEach(timeline.past) { entry in
                    HistoryEntryRow(
                        entry: entry,
                        isNoteAvailable: state.isHistoryNoteAvailable(entry),
                        canRestore: state.isHistoryActionable(entry),
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
            commit { actions.accept(proposal, false) }
            return
        }
        Haptics.pop()
        confirmationTrigger = proposal.id
        withAnimation(sheetArrivalAnimation) {
            confirmingOutdated = proposal
        }
    }

    private func dismissConfirmation(performHaptic: Bool = true) {
        if performHaptic { Haptics.commit() }
        let trigger = confirmingOutdated?.id
        withAnimation(sheetDepartureAnimation) {
            confirmingOutdated = nil
        }
        if let trigger { confirmationTrigger = trigger }
    }

    private var sheetArrivalAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.sheetArrival, when: reduceMotion)
    }

    private var sheetDepartureAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.sheetDeparture, when: reduceMotion)
    }

    /// One punctuation mark per decision, wherever the decision came from.
    private func commit(_ work: () -> Void) {
        Haptics.commit()
        work()
    }
}

// MARK: - Pending row

enum PendingRewriteCardTone: Equatable {
    case neutral
    case heldForReview
    case outdated
    case failed

    /// Failure still wins over attention because a row that cannot proceed is
    /// the first thing the eye needs to find. Outdated comes next because it
    /// can overwrite newer writing, while a held rewrite has lost nothing and
    /// only needs a quiet mark. Intentional Review is ordinary work, so it
    /// remains entirely in the paper-and-stroke family.
    static func resolve(for proposal: Proposal, isOutdated: Bool) -> Self {
        if proposal.state.failure != nil { return .failed }
        if isOutdated { return .outdated }
        if proposal.automaticReviewReason != nil { return .heldForReview }
        return .neutral
    }

    var tint: ChamferCardSurface.Tint {
        switch self {
        case .neutral:
            ChamferCardSurface.Tint(
                primary: Chamfer.Palette.paperStroke,
                secondary: Chamfer.Palette.paperSunken
            )
        case .heldForReview:
            // Pink is the brand's non-warning accent and stays unmistakable
            // beside amber even after the surface lowers both opacities.
            ChamferCardSurface.Tint(
                primary: Chamfer.Palette.pink,
                secondary: Chamfer.Palette.pinkSoft
            )
        case .outdated:
            ChamferCardSurface.Tint(
                primary: Chamfer.Palette.attention,
                secondary: Chamfer.Palette.brass
            )
        case .failed:
            ChamferCardSurface.Tint(
                primary: Chamfer.Palette.danger,
                secondary: Chamfer.Palette.dangerSoft
            )
        }
    }
}

struct PendingRewriteRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let proposal: Proposal
    let isOutdated: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
    let onSetHunkSelected: (UUID, Bool) -> Void
    let onRegenerate: () -> Void
    let onRetry: () -> Void
    let onOpen: () -> Void
    var showsSelection = true
    var showsOpenAction = true
    var acceptFocus: FocusState<UUID?>.Binding?

    @LegacyState private var isHovered = false
    @LegacyState private var showingEveryChange = false
    @LegacyState private var navigation = KeyboardNavigation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
                header
                metadata
            }
            .padding(.bottom, Chamfer.Space.roomy)

            PageRule()

            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                if isOutdated {
                    InlineNotice(
                        symbol: "clock.arrow.circlepath",
                        tone: .accent,
                        text: "The note changed after this rewrite was made. Regenerate it, or apply it and replace what you wrote since."
                    )
                }

                if let reason = proposal.automaticReviewReason {
                    InlineNotice(
                        symbol: "shield.lefthalf.filled",
                        tone: .accent,
                        text: reason.explanation(for: proposal.mode)
                    )
                }

                if let failure = proposal.state.failure {
                    InlineNotice(
                        symbol: "exclamationmark.octagon.fill",
                        tone: .danger,
                        text: "\(failure.title). \(failure.detail)"
                    )
                }

                if ProcessingGuard.isCloud(proposal.modelID) {
                    InlineNotice(
                        symbol: "cloud",
                        tone: .accent,
                        text: "This rewrite was produced by the cloud model, so the note left this Mac."
                    )
                }

                if proposal.changeCount == 0, !proposal.hunks.isEmpty {
                    InlineNotice(
                        symbol: "minus.circle",
                        tone: .accent,
                        text: "No changes are selected, so there is nothing to apply. Select a change, or reject this rewrite outright."
                    )
                }

                if proposal.state == .regenerating {
                    RegeneratingPlaceholder()
                } else {
                    changes
                }
            }
            .padding(.vertical, Chamfer.Space.roomy)

            PageRule()

            actionRow
                .padding(.top, Chamfer.Space.roomy)
        }
        .padding(Chamfer.Space.roomy)
        .background {
            ChamferCardSurface(
                tint: cardTint,
                radius: Chamfer.Radius.card,
                presentation: ModelsSurfaceResponse.presentation(
                    for: .local,
                    isActive: false,
                    isHovered: false
                )
            )
        }
        .contentShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.card, style: .continuous)
        )
        .environment(\.chamferSurface, .paper)
        .chamferHoverLift(isActive: isHovered)
        .onHover { hovering in
            withAnimation(Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion)) {
                isHovered = hovering
            }
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion),
            value: showingEveryChange
        )
        // The row is a title, a line of metadata, its notices and a
        // diff. Left as separate elements, VoiceOver walks all of it before
        // reaching the buttons; combined, the whole rewrite is one thing to
        // judge, which is what it is.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var cardTint: ChamferCardSurface.Tint {
        PendingRewriteCardTone.resolve(for: proposal, isOutdated: isOutdated).tint
    }

    private var accessibilitySummary: String {
        var parts = [proposal.note.title, metadataText]
        if isOutdated {
            parts.append("Based on text that has since changed")
        }
        if let failure = proposal.state.failure {
            parts.append(failure.title)
        }
        if let reason = proposal.automaticReviewReason {
            parts.append(reason.explanation(for: proposal.mode))
        }
        parts.append(
            proposal.changeCount == 0 ? "No changes selected" : changeCountText
        )
        return parts.joined(separator: ". ")
    }

    private var changeCountText: String {
        proposal.changeCount == 1
            ? "1 change"
            : "\(proposal.changeCount) changes"
    }

    /// Every change in the note, unfolded in place.
    ///
    /// The first is always shown and the rest are one click away. A hunk the
    /// user has unticked remains unfolded even after "Show less": hiding a
    /// staged selection would conceal the decision it carries.
    @ViewBuilder
    private var changes: some View {
        let firstID = proposal.hunks.first?.id
        let collapsed = proposal.hunks.filter {
            $0.id == firstID || proposal.excludedHunkIDs.contains($0.id)
        }
        let visible = showingEveryChange ? proposal.hunks : collapsed
        let hiddenCount = proposal.hunks.count - visible.count

        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            ForEach(visible) { hunk in
                HunkDecisionRow(
                    hunk: hunk,
                    isSelected: !proposal.excludedHunkIDs.contains(hunk.id),
                    onSetSelected: { selected in
                        onSetHunkSelected(hunk.id, selected)
                    }
                )
            }

            if showingEveryChange || hiddenCount > 0 {
                Button {
                    Haptics.pop()
                    withAnimation(
                        Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
                    ) {
                        showingEveryChange.toggle()
                    }
                } label: {
                    HStack(spacing: Chamfer.Space.tight) {
                        Image(systemName: showingEveryChange ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(
                            showingEveryChange
                                ? "Show less"
                                : "Show \(hiddenCount) more change\(hiddenCount == 1 ? "" : "s")"
                        )
                    }
                }
                .buttonStyle(ChamferButtonStyle(.quiet))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.regular) {
            if showsSelection {
                SelectionTick(isSelected: isSelected, action: onToggleSelection)
                    // The card's rise says where the pointer is; the tick
                    // appears in response so bulk selection does not become a
                    // permanent column of controls down the page.
                    .opacity(isSelected || isHovered || navigation.isActive ? 1 : 0)
            }

            Text(proposal.note.title)
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Chamfer.Space.snug)

            Pill(
                proposal.changeCount == 0 ? "No changes selected" : changeCountText,
                tone: .neutral
            )
            if isOutdated {
                Pill("Outdated", symbol: "clock.badge.exclamationmark", tone: .accent)
            }
            if proposal.automaticReviewReason != nil {
                Pill("Held for review", symbol: "shield.lefthalf.filled", tone: .accent)
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
            } else if proposal.changeCount == 0 {
                Button("Reject rewrite", action: onReject)
                    .buttonStyle(ChamferButtonStyle(.primary))
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(ChamferButtonStyle(.quiet))
            } else {
                acceptButton
                Button("Reject", action: onReject)
                    .buttonStyle(ChamferButtonStyle(.secondary))
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(ChamferButtonStyle(.quiet))
            }
            Spacer(minLength: 0)
            if showsOpenAction {
                Button("Open note", action: onOpen)
                    .buttonStyle(ChamferButtonStyle(.quiet))
            }
        }
    }

    @ViewBuilder
    private var acceptButton: some View {
        let button = Button(acceptButtonTitle, action: onAccept)
            .buttonStyle(ChamferButtonStyle(.primary))

        if let acceptFocus {
            button.focused(acceptFocus, equals: proposal.id)
        } else {
            button
        }
    }

    private var acceptButtonTitle: String {
        guard proposal.changeCount != proposal.hunks.count else { return "Accept" }
        return "Accept \(proposal.changeCount) of \(proposal.hunks.count) changes"
    }
}

/// One offered change with the same always-visible selection language as the
/// rewrite that contains it.
private struct HunkDecisionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hunk: Hunk
    let isSelected: Bool
    let onSetSelected: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.regular) {
            SelectionTick(isSelected: isSelected, action: toggle)
                .padding(.top, Chamfer.Space.regular)
            DiffHunkView(hunk, isSelected: isSelected)
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: isSelected
        )
    }

    private func toggle() {
        Haptics.pop()
        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion)
        ) {
            onSetSelected(!isSelected)
        }
    }
}

// MARK: - History row

private struct HistoryEntryRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: HistoryEntry
    let isNoteAvailable: Bool
    let canRestore: Bool
    let onRestore: () -> Void
    let onOpen: () -> Void

    @LegacyState private var isHovered = false

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
                }
                Text(detail)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Chamfer.Space.snug)

            // The hover fill is shared with the versions sheet's row, so the two
            // history lists agree about what a row is. The resting opacity of
            // the controls is deliberately not shared, because the two lists are
            // not the same length: the sheet shows one note's handful of
            // versions, where a faint Restore is a useful hint, and this shows
            // every change Chamfer has ever made. Two hundred rows each holding
            // a ghosted Undo and Open is a column of repeated words down the
            // right-hand edge, so here they stay out of sight until the pointer
            // names a row.
            HStack(spacing: Chamfer.Space.tight) {
                if canRestore {
                    Button("Undo", action: onRestore)
                        .buttonStyle(ChamferButtonStyle(.quiet))
                }
                if isNoteAvailable {
                    Button("Open", action: onOpen)
                        .buttonStyle(ChamferButtonStyle(.quiet))
                }
            }
            .opacity(isHovered ? 1 : 0)

            Text(RelativeTime.string(entry.occurredAt, since: now))
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(Chamfer.Space.snug)
        .background(isHovered ? Chamfer.Palette.paperSunken : .clear)
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(entry.note.title). \(detail). \(RelativeTime.string(entry.occurredAt, since: now))"
        )
    }

    private var symbol: String {
        if entry.action.isRestore { return "arrow.uturn.backward" }
        if !entry.ruleIDs.isEmpty, case .applied = entry.outcome {
            return "wrench.and.screwdriver"
        }
        return switch entry.outcome {
        case .applied: entry.application == .automatic ? "wand.and.stars" : "checkmark"
        case .failed: "exclamationmark.octagon.fill"
        case .reverted: "arrow.uturn.backward"
        }
    }

    private var tint: Color {
        if entry.action.isRestore { return Chamfer.Palette.pageTextSoft }
        return switch entry.outcome {
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
struct OutdatedConfirmation: View {
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
            .chamferRing(radius: Chamfer.Radius.large)
            .chamferFloat()
            .transition(sheetTransition)
        }
    }

    /// Grows from slightly small and fades, and leaves the same way it came.
    private var sheetTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
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
            .padding(Chamfer.Control.hitPadding(for: 15))
            .contentShape(Rectangle())
            .padding(-Chamfer.Control.hitPadding(for: 15))
        }
        .buttonStyle(.plain)
        .chamferFocusableCircle()
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion),
            value: isSelected
        )
        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }
}

/// What sits where the diff was while a rewrite is being generated again.
///
/// A band of the diff's own shape rather than a line of grey text, with a slow
/// sheen crossing it. The point is that the row keeps its height: replacing a
/// three-line diff with one sentence made the whole page jump every time
/// somebody pressed Regenerate.
private struct RegeneratingPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            Text("Generating again from the current text…")
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)

            ZStack {
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                    .fill(Chamfer.Palette.paperSunken)
                if !reduceMotion {
                    sheen
                }
            }
            .frame(height: 52)
            .clipShape(
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Generating a new rewrite from the current text")
        .onAppear {
            guard !reduceMotion else { return }
            // Slow, and never bouncing. This is something to notice out of the
            // corner of the eye while reading the rest of the page, not
            // something asking to be watched.
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }

    private var sheen: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Chamfer.Palette.paper.opacity(0.85), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.55)
            .offset(x: phase * geometry.size.width)
        }
        .allowsHitTesting(false)
    }
}
