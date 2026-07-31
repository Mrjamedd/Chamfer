import ChamferCore
import SwiftUI

enum DashboardCloseControlVisibility {
    static func shouldShow(pointerAtTop: Bool, showingHome: Bool) -> Bool {
        pointerAtTop && !showingHome
    }
}

enum DashboardBottomBarSelectionVisibility {
    static func shouldShow(showingHome: Bool) -> Bool {
        !showingHome
    }
}

enum DashboardTabGesture {
    struct Transition: Equatable {
        let tab: String
        let isSearching: Bool
        let showingHome: Bool
    }

    static func destination(
        from currentID: String,
        direction: TrackpadPanDirection,
        orderedIDs: [String]
    ) -> String {
        guard let currentIndex = orderedIDs.firstIndex(of: currentID) else {
            return currentID
        }

        let targetIndex: Int
        switch direction {
        case .left:
            targetIndex = min(currentIndex + 1, orderedIDs.index(before: orderedIDs.endIndex))
        case .right:
            targetIndex = max(currentIndex - 1, orderedIDs.startIndex)
        case .up, .down:
            return currentID
        }
        return orderedIDs[targetIndex]
    }

    static func transition(
        from currentID: String,
        isSearching: Bool,
        showingHome: Bool,
        direction: TrackpadPanDirection,
        orderedIDs: [String]
    ) -> Transition {
        Transition(
            tab: destination(
                from: currentID,
                direction: direction,
                orderedIDs: orderedIDs
            ),
            isSearching: isSearching,
            showingHome: false
        )
    }
}

enum DashboardBottomBarItems {
    private static let recentNoteLimit = 10

    static func make(
        for state: DashboardState,
        modelsState: ModelsLandscapeState = ModelsLandscapeState()
    ) -> [BottomBar.Item] {
        [
            .init(
                id: DashboardView.Tab.notes,
                symbol: "doc.text",
                label: "Notes",
                entries: recentNoteEntries(from: state.recentNotes),
                showsSearch: true
            ),
            .init(
                id: DashboardView.Tab.review,
                symbol: "checkmark.circle",
                label: "Review",
                entries: state.pendingProposals.map { proposal in
                    .init(
                        id: proposal.id.uuidString,
                        title: proposal.note.title,
                        detail: "\(proposal.hunks.count) change\(proposal.hunks.count == 1 ? "" : "s")"
                    )
                }
            ),
            .init(
                id: DashboardView.Tab.models,
                symbol: "cpu",
                label: "Models",
                entries: Backend.all(
                    runState: state.runState,
                    landscapeState: modelsState
                ).map {
                    .init(id: $0.name, title: $0.shortName, detail: $0.status)
                }
            )
        ]
    }

    private static func recentNoteEntries(
        from notes: [NoteSummary]
    ) -> [BottomBar.Entry] {
        var seenURLs = Set<URL>()

        return notes
            .sorted { left, right in
                if left.modifiedAt != right.modifiedAt {
                    return left.modifiedAt > right.modifiedAt
                }
                return left.url.path < right.url.path
            }
            .filter { seenURLs.insert($0.url.standardizedFileURL).inserted }
            .prefix(recentNoteLimit)
            .map { note in
                .init(
                    id: note.url.standardizedFileURL.absoluteString,
                    title: note.title,
                    detail: "\(note.wordCount.formatted()) words"
                )
            }
    }
}

/// The whole window: one page floating on beige, a bar sitting under it, and a
/// close control that only appears when you reach for it.
public struct DashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: String
    @State private var pointerAtTop = false
    @State private var closeHovered = false
    @State private var showingHome = false
    @State private var displayedNote: NoteDocument?
    @State private var isSearching = false
    @State private var modelsState = ModelsLandscapeState()

    private let state: DashboardState
    private let onClose: () -> Void

    private static let topGutter: CGFloat = 52

    public init(state: DashboardState, tab: String = Tab.notes, onClose: @escaping () -> Void = {}) {
        self.state = state
        self.onClose = onClose
        _tab = State(initialValue: tab)
        _displayedNote = State(initialValue: state.openNote)
    }

    public enum Tab {
        public static let notes = "notes"
        public static let review = "review"
        public static let models = "models"
    }

    private var items: [BottomBar.Item] {
        DashboardBottomBarItems.make(for: state, modelsState: modelsState)
    }

    private var tabSelection: Binding<String> {
        Binding(
            get: { tab },
            set: { selection in
                tab = selection
                showingHome = false
            }
        )
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Chamfer.Palette.canvas
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissSearch)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: Self.topGutter)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissSearch)
                page
                    .overlay {
                        if isSearching {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: dismissSearch)
                        }
                    }
                // Pass `.off` here to get the always-labelled, undimmed bar
                // back; nothing else needs touching.
                BottomBar(
                    items: items,
                    selection: tabSelection,
                    isSearching: $isSearching,
                    searchableNotes: state.searchableNotes,
                    onOpenSearchResult: openSearchResult,
                    idle: .standard,
                    showsSelection: DashboardBottomBarSelectionVisibility.shouldShow(
                        showingHome: showingHome
                    )
                )
                    .padding(.top, Chamfer.Space.loose)
                    // Lifted clear of the window's bottom edge so the pill
                    // reads as floating rather than as resting on the sill.
                    .padding(.bottom, Chamfer.Space.section + 2)
                    .zIndex(2)
            }
            .padding(.horizontal, Chamfer.Space.section)

            // The close control lives in the gutter above the page and is
            // revealed by moving towards it, so nothing sits over the note
            // while you are reading.
            closeZone
        }
        .background {
            TrackpadPanGesture(onEnded: handleTabGesture)
        }
    }

    @ViewBuilder
    private var page: some View {
        if showingHome {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(homeScreenTransition)
        } else {
            // Reaching for the close control shrinks the page a little, so the
            // gesture is answered before it is committed.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Chamfer.Palette.page)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .chamferRing(radius: 24)
                .chamferFloat()
                .scaleEffect(closeHovered ? 0.975 : 1)
                .animation(Chamfer.Motion.interactive, value: closeHovered)
                .transition(notePageTransition)
        }
    }

    @ViewBuilder
    private var content: some View {
        if showingHome {
            HomeScreenView(state: state) { document in
                withAnimation(
                    reduceMotion
                        ? Chamfer.Motion.quick
                        : Chamfer.Motion.navigation
                ) {
                    displayedNote = document
                    tab = Tab.notes
                    showingHome = false
                }
            }
        } else {
            switch tab {
            case Tab.review:
                ReviewPage(proposals: state.pendingProposals)
            case Tab.models:
                ModelsPage(runState: state.runState, state: $modelsState)
            default:
                if let note = displayedNote {
                    NotePageView(note)
                } else {
                    PageMessage(
                        title: "No note open",
                        detail: "Pick a note from your vault and it will appear here."
                    )
                }
            }
        }
    }

    private var notePageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(scale: 0.94, anchor: .center)
                .combined(with: .opacity),
            removal: .scale(scale: 0.90, anchor: .center)
                .combined(with: .opacity)
        )
    }

    private var homeScreenTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(
            with: .scale(scale: 0.985, anchor: .center)
        )
    }

    private var closeZone: some View {
        ZStack {
            if DashboardCloseControlVisibility.shouldShow(
                pointerAtTop: pointerAtTop,
                showingHome: showingHome
            ) {
                FloatingCloseButton(onHover: { closeHovered = $0 }, action: handleClose)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.topGutter)
        .contentShape(Rectangle())
        .onHover { pointerAtTop = $0 }
        .animation(Chamfer.Motion.quick, value: pointerAtTop)
    }

    private func handleClose() {
        if showingHome {
            onClose()
        } else {
            closeHovered = false
            withAnimation(
                reduceMotion
                    ? Chamfer.Motion.quick
                    : Chamfer.Motion.navigation
            ) {
                showingHome = true
            }
        }
    }

    private func dismissSearch() {
        guard isSearching else { return }
        withAnimation(BottomBar.searchCurve) {
            isSearching = false
        }
    }

    private func openSearchResult(_ document: NoteDocument) {
        withAnimation(
            reduceMotion
                ? Chamfer.Motion.quick
                : Chamfer.Motion.navigation
        ) {
            displayedNote = document
            tab = Tab.notes
            showingHome = false
        }
    }

    private func handleTabGesture(_ direction: TrackpadPanDirection) {
        let transition = DashboardTabGesture.transition(
            from: tab,
            isSearching: isSearching,
            showingHome: showingHome,
            direction: direction,
            orderedIDs: [Tab.notes, Tab.review, Tab.models]
        )
        guard transition.tab != tab else { return }

        Haptics.commit()
        withAnimation(
            reduceMotion
                ? Chamfer.Motion.quick
                : Chamfer.Motion.navigation
        ) {
            tab = transition.tab
            isSearching = transition.isSearching
            showingHome = transition.showingHome
        }
    }
}

// MARK: - Page contents

private struct PageMessage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Chamfer.Space.snug) {
            Text(title)
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
            Text(detail)
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReviewPage: View {
    let proposals: [Proposal]

    var body: some View {
        if proposals.isEmpty {
            PageMessage(
                title: "Nothing to review",
                detail: "Rewrites waiting on your judgement will appear here."
            )
        } else {
            PageScroll(title: "Pending review") {
                ForEach(proposals) { proposal in
                    VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                        Text(proposal.note.title)
                            .font(Chamfer.TypeScale.pageHeading)
                            .foregroundStyle(Chamfer.Palette.pageText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let first = proposal.hunks.first {
                            DiffHunkView(first)
                        }
                        HStack(spacing: Chamfer.Space.snug) {
                            Button("Accept") {}.buttonStyle(ChamferButtonStyle(.primary))
                            Button("Reject") {}.buttonStyle(ChamferButtonStyle(.secondary))
                        }
                    }
                    .padding(.bottom, Chamfer.Space.section)
                }
            }
        }
    }
}

/// Shared page chrome: the same measure and margins everywhere, so every tab
/// reads as the same sheet of paper.
private struct PageScroll<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Chamfer.TypeScale.pageTitle)
                    .foregroundStyle(Chamfer.Palette.pageText)
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
