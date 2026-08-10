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

/// The arithmetic behind the gutter's cluster of three.
///
/// Extracted because both of its properties are claims rather than
/// preferences — close sits at the exact centre, and no two hit areas
/// overlap — and a claim that is only true in a view is one nobody notices
/// going false.
enum DashboardGutterLayout {
    /// What the round controls read as.
    static let controlDiameter: CGFloat = 32
    /// How far each control's hit area extends past its own edge, so that a
    /// 32pt circle answers to the 44pt the guideline asks for.
    static let hitInset: CGFloat = 6
    static let gap = Chamfer.Space.roomy
    /// Reserved on each side of close, equal by construction.
    static let slot: CGFloat = 72

    static var clusterWidth: CGFloat {
        slot * 2 + gap * 2 + controlDiameter
    }

    /// Close's centre, measured from the cluster's leading edge.
    static var closeCentre: CGFloat {
        slot + gap + controlDiameter / 2
    }

    /// Dead space between one control's hit area and the next one's. Zero is
    /// the point at which they abut; below zero a click between two controls
    /// is ambiguous.
    static var hitAreaClearance: CGFloat {
        gap - hitInset * 2
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
            targetIndex = max(currentIndex - 1, orderedIDs.startIndex)
        case .right:
            targetIndex = min(currentIndex + 1, orderedIDs.index(before: orderedIDs.endIndex))
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
        modelsState: ModelsDashboardState = ModelsDashboardState()
    ) -> [BottomBar.Item] {
        [
            .init(
                id: DashboardView.Tab.notes,
                symbol: "doc.text",
                label: "Notes",
                entries: recentNoteEntries(from: state.recentNotes),
                showsSearch: true,
                // Where the Vaults page is reached from. It sits at the foot
                // of the list the notes are already in, because a vault is
                // where notes come from — not a fourth thing the bar is about.
                footAction: .init(
                    id: DashboardView.FootAction.manageVaults,
                    title: footActionTitle(for: state),
                    symbol: "folder"
                ),
                // Vaults is reached from this list, so the dot belongs on this
                // item: it is visible from Notes, Review and Models alike
                // rather than only on the page you would have to already be on.
                needsAttention: state.needsConfiguration
            ),
            .init(
                id: DashboardView.Tab.review,
                symbol: "checkmark.circle",
                label: "Review",
                entries: state.actionableProposals.map { proposal in
                    .init(
                        id: proposal.id.uuidString,
                        title: proposal.note.title,
                        detail: "\(proposal.hunks.count) change\(proposal.hunks.count == 1 ? "" : "s")"
                    )
                },
                // The one destination that accumulates. A full queue and an
                // empty one used to look identical until you pointed at them.
                count: state.actionableProposals.count
            ),
            .init(
                id: DashboardView.Tab.models,
                symbol: "cpu",
                label: "Models",
                entries: Backend.all(state: modelsState).map {
                    .init(id: $0.name, title: $0.shortName, detail: $0.status)
                }
            )
        ]
    }

    private static func footActionTitle(for state: DashboardState) -> String {
        if state.vaults.isEmpty { return "Connect a vault…" }
        let waiting = state.unconfiguredVaults.count
        guard waiting > 0 else { return "Manage vaults…" }
        return waiting == 1
            ? "1 vault needs setting up…"
            : "\(waiting) vaults need setting up…"
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

    @LegacyState private var tab: String
    @LegacyState private var pointerAtTop = false
    @LegacyState private var closeHovered = false
    @LegacyState private var showingHome = false
    @LegacyState private var displayedNote: NoteDocument?
    @LegacyState private var isSearching = false
    @LegacyState private var modelsState: ModelsDashboardState
    /// Bound rather than copied. While this was `@LegacyState` the page was working
    /// on a private duplicate: accepting a rewrite updated the timeline on
    /// screen and nothing else, so the menu bar still offered it, Settings
    /// still resolved against the old policy, and none of it survived a quit.
    /// The model owns the state; this view renders and edits it in place.
    @Binding private var state: DashboardState
    @Binding private var navigationRequest: String?
    @LegacyState private var editorModel: NoteEditorModel?
    @LegacyState private var showingChangeHistory = false

    private let editing: NoteEditingConfiguration?
    private let noteLoadError: String?
    private let onClose: () -> Void
    /// Injected rather than reached for directly so `ChamferUI` stays ignorant
    /// of the `Settings` scene — the same arrangement `onClose` already uses.
    /// The gallery leaves it at its default and the control does nothing there,
    /// which is correct: the harness has no settings window to open.
    private let onOpenSettings: () -> Void
    /// Raising a folder picker means `NSOpenPanel`, which means AppKit and a
    /// running application — neither of which a view should assume. Injected
    /// for the same reason as the two above.
    ///
    /// Spelled `@MainActor @Sendable` rather than bare because it is handed
    /// straight to `VaultActions`, which is `Sendable` — the panel is raised on
    /// the main thread and the compiler is entitled to be told so.
    private let onConnectVault: @MainActor @Sendable () -> Void
    /// What Review's verbs actually do.
    ///
    /// The app passes real ones — snapshot, write, record — and the gallery
    /// passes none, falling back to the in-memory versions below so the page
    /// can be exercised on fixtures without a disk. The page itself does not
    /// know which it has, which is the point.
    private let injectedReview: ReviewActions?
    private let injectedVaults: VaultActions?

    private static let topGutter: CGFloat = 52

    public init(
        state: Binding<DashboardState>,
        navigationRequest: Binding<String?> = .constant(nil),
        tab: String = Tab.notes,
        /// Seeds the Models page instead of reading preferences. Only the
        /// design harness passes this, so a given model state can be put on
        /// screen without a real Ollama install behind it.
        modelsState: ModelsDashboardState? = nil,
        editing: NoteEditingConfiguration? = nil,
        noteLoadError: String? = nil,
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onConnectVault: @escaping @MainActor @Sendable () -> Void = {},
        review: ReviewActions? = nil,
        vaults: VaultActions? = nil
    ) {
        self.editing = editing
        self.noteLoadError = noteLoadError
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onConnectVault = onConnectVault
        self.injectedReview = review
        self.injectedVaults = vaults
        _tab = State(initialValue: tab)
        _state = state
        _navigationRequest = navigationRequest
        _modelsState = State(
            initialValue: modelsState ?? ModelsPreferences.loadState()
        )
        _displayedNote = State(initialValue: state.wrappedValue.openNote)
        _editorModel = State(
            initialValue: state.wrappedValue.openNote.flatMap { document in
                guard let editing, editing.canEdit(document.url) else {
                    return nil
                }
                return Self.makeEditor(for: document, editing: editing)
            }
        )
    }

    public enum Tab {
        public static let notes = "notes"
        public static let review = "review"
        public static let models = "models"
        /// A destination without a bar item.
        ///
        /// Vaults is reached from the foot of the Notes list, so the bar stays
        /// at three. It is deliberately absent from `orderedIDs`, which keeps
        /// it out of the swipe gesture as well as off the bar — a page you can
        /// arrive at by trackpad but never leave the same way would be worse
        /// than one you cannot swipe to at all.
        public static let vaults = "vaults"
    }

    public enum FootAction {
        public static let manageVaults = "notes.manageVaults"
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
                    onSelectFootAction: handleFootAction,
                    onSelectEntry: handleBarEntry,
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

            changeHistoryOverlay
        }
        .background {
            TrackpadPanGesture(onEnded: handleTabGesture)
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: showingChangeHistory
        )
        .onChange(of: state.openNote) { _, note in
            synchronizeOpenNote(note)
        }
        .onChange(of: navigationRequest) { _, destination in
            consumeNavigationRequest(destination)
        }
        .onAppear {
            consumeNavigationRequest(navigationRequest)
        }
    }

    private func consumeNavigationRequest(_ destination: String?) {
        guard let destination else { return }
        let valid = [Tab.notes, Tab.review, Tab.models, Tab.vaults]
        guard valid.contains(destination) else {
            navigationRequest = nil
            return
        }
        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
        ) {
            tab = destination
            showingHome = false
            isSearching = false
        }
        navigationRequest = nil
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
            HomeScreenView(
                state: state,
                onOpenNote: openDocument,
                onConnectVault: state.vaults.isEmpty ? onConnectVault : nil
            )
        } else {
            switch tab {
            case Tab.review:
                ReviewTimelinePage(
                    state: state,
                    actions: reviewActions,
                    onConnectVault: state.vaults.isEmpty ? onConnectVault : nil
                )
            case Tab.vaults:
                VaultsPage(
                    vaults: state.vaults,
                    notes: state.recentNotes,
                    activeModelConfigured: activeModelConfigured,
                    actions: vaultActions,
                    onOpenModels: openModels
                )
            case Tab.models:
                ModelsPage(state: $modelsState)
            default:
                if let noteLoadError, displayedNote == nil {
                    PageMessage(
                        title: "Couldn’t open Example.md",
                        detail: noteLoadError
                    )
                } else if displayedNote == nil, state.vaults.isEmpty {
                    // The first thing a new install shows. It used to say
                    // "pick a note from your vault" to somebody who had no
                    // vault and no way to get one from this page.
                    PageMessage(
                        title: "Nothing to work on yet",
                        detail: "Point Chamfer at a folder of Markdown or plain-text notes. It watches everything inside, including subfolders, and leaves every file alone until you say otherwise.",
                        actionTitle: "Connect a vault…",
                        action: onConnectVault
                    )
                } else if let note = displayedNote {
                    if let editorModel,
                       editing?.canEdit(note.url) == true {
                        NotePageView(model: editorModel) { text in
                            retainDraft(text, for: note.url)
                        }
                        .id(note.url)
                    } else {
                        ReadOnlyNotePageView(document: note)
                            .id(note.url)
                    }
                } else {
                    PageMessage(
                        title: "No note open",
                        detail: "Pick a note from your vault and it will appear here."
                    )
                }
            }
        }
    }

    private var activeModelConfigured: Bool {
        switch modelsState.active {
        case .local:
            // Activation already required the model to be on disk. Nothing
            // else has to be configured: which model runs is the device's
            // answer, not a setting anyone left half-filled.
            return true
        case .cloud:
            return ModelsPreferences.loadCloudProvider() != nil
        case nil:
            return false
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

    /// Queued and recorded changes for the note on the page. Nil for every
    /// non-note destination, which keeps the control out of the gutter where
    /// it would have no object. An empty value is still a note history: the
    /// stable zero-state control is how the feature remains discoverable.
    private var changesForOpenNote: NoteChangeHistory? {
        guard DashboardNoteHistoryControlVisibility.shouldShow(
            showingNotes: tab == Tab.notes,
            showingHome: showingHome,
            hasOpenNote: displayedNote != nil
        ), let note = displayedNote else {
            return nil
        }
        return state.changes(forNoteAt: note.url)
    }

    /// The gutter's three controls, as one cluster rather than three errands.
    ///
    /// They are one family — everything here acts *on* the page rather than in
    /// it — so they are reached with one movement of the pointer instead of
    /// three. Ordered by what each one's change touches, widening outward from
    /// the middle: the app's defaults, this page, this note.
    ///
    /// Close keeps the exact centre it has always had. The two flanking slots
    /// are a fixed, equal width, which is what pins it there: versions can
    /// arrive, leave, or grow a digit without the control the hand already
    /// knows moving even slightly.
    private var closeZone: some View {
        ZStack {
            if DashboardCloseControlVisibility.shouldShow(
                pointerAtTop: pointerAtTop,
                showingHome: showingHome
            ) {
                HStack(spacing: DashboardGutterLayout.gap) {
                    FloatingSettingsButton(action: onOpenSettings)
                        .frame(
                            width: DashboardGutterLayout.slot,
                            alignment: .trailing
                        )

                    FloatingCloseButton(
                        onHover: { closeHovered = $0 },
                        action: handleClose
                    )

                    historyControl
                        .frame(
                            width: DashboardGutterLayout.slot,
                            alignment: .leading
                        )
                }
                .transition(gutterTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.topGutter)
        .contentShape(Rectangle())
        .onHover { pointerAtTop = $0 }
        .animation(gutterCurve, value: pointerAtTop)
        // History comes and goes with the note under it, which can happen
        // while the gutter is already open — switching tabs, or closing the
        // note. Without its own trigger that change had no curve to animate
        // on and the control simply blinked out.
        .animation(gutterCurve, value: changesForOpenNote?.noteURL)
    }

    /// Reserved whether or not there is a note, so the cluster is symmetric
    /// and close cannot be nudged off centre by its neighbour appearing.
    @ViewBuilder
    private var historyControl: some View {
        ZStack(alignment: .leading) {
            Color.clear
            if let changes = changesForOpenNote {
                FloatingHistoryButton(count: changes.count) {
                    // A decision here can write the note immediately. Land the
                    // user's pending draft first so it either becomes the
                    // proposal's current source or is safely recognised as an
                    // outdated rewrite instead of overwriting the decision a
                    // fraction of a second later.
                    editorModel?.flush()
                    showingChangeHistory = true
                }
                .transition(gutterTransition)
            }
        }
    }

    /// The cluster arrives as one object, so it is one curve and one
    /// transition rather than three staggered ones — a group that assembles
    /// itself in pieces is not read as a group.
    private var gutterCurve: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.quick, when: reduceMotion)
    }

    private var gutterTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .offset(y: 6))
    }

    @ViewBuilder
    private var changeHistoryOverlay: some View {
        if showingChangeHistory, let note = displayedNote {
            NoteChangeHistorySheet(
                note: note,
                state: state,
                actions: reviewActions,
                onDismiss: dismissChangeHistory
            )
        }
    }

    private func dismissChangeHistory() {
        Haptics.commit()
        showingChangeHistory = false
    }

    private func handleClose() {
        if showingHome {
            onClose()
        } else {
            closeHovered = false
            withAnimation(
                Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
            ) {
                showingHome = true
            }
        }
    }

    /// Clicking away from the field ends the search exactly as Escape does, so
    /// it is punctuated the same way. Without this the two routes out of the
    /// same state felt different under the hand.
    private func dismissSearch() {
        guard isSearching else { return }
        Haptics.commit()
        withAnimation(BottomBar.searchCurve) {
            isSearching = false
        }
    }

    private func openSearchResult(_ document: NoteDocument) {
        openDocument(document)
    }

    private func openDocument(_ document: NoteDocument) {
        let current = state.searchableNotes.first {
            $0.url == document.url
        } ?? document

        if let editing, editing.canEdit(current.url), editorModel == nil {
            editorModel = Self.makeEditor(for: current, editing: editing)
        }

        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
        ) {
            displayedNote = current
            state.openNote = current
            tab = Tab.notes
            showingHome = false
        }
    }

    private func synchronizeOpenNote(_ document: NoteDocument?) {
        guard let document else {
            displayedNote = nil
            editorModel = nil
            showingChangeHistory = false
            return
        }
        let isDifferentNote = displayedNote?.url.standardizedFileURL
            != document.url.standardizedFileURL

        if isDifferentNote {
            displayedNote = document
            if let editing, editing.canEdit(document.url) {
                editorModel = Self.makeEditor(for: document, editing: editing)
            } else {
                editorModel = nil
            }
        } else if editorModel == nil {
            displayedNote = document
        } else if let editorModel,
                  !editorModel.hasUnsavedChanges,
                  editorModel.text != document.text {
            // A review action or another editor changed the backing file. A
            // clean editor follows that new truth; a dirty one keeps its draft
            // and lets the compare-before-save guard report the conflict.
            displayedNote = document
            self.editorModel = editing.map {
                Self.makeEditor(for: document, editing: $0)
            }
        }

        // Whatever set `openNote` was asking for that note to be *shown*, and
        // it is usually a page that is not Notes: the Vaults page's "Open a
        // note", or Review's "Open note". Loading the document without moving
        // to the page that draws it is why both of those buttons did nothing —
        // the note arrived, behind whatever you were already looking at.
        guard tab != Tab.notes || showingHome else { return }
        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
        ) {
            tab = Tab.notes
            showingHome = false
        }
    }

    /// Something in the bar's hover list was clicked.
    ///
    /// Each destination's list means something different, so each is answered
    /// differently: a note opens, a pending rewrite goes to the page where it
    /// can be judged, a backend goes to the page where it is configured. Before
    /// this, all three did nothing at all.
    private func handleBarEntry(itemID: String, entryID: String) {
        switch itemID {
        case Tab.notes:
            // The entry's id is the note's standardized URL, which is how the
            // list was built. Matched rather than parsed, so a note that has
            // since gone simply does not open.
            guard let document = state.searchableNotes.first(where: {
                $0.url.standardizedFileURL.absoluteString == entryID
            }) else { return }
            openDocument(document)

        case Tab.review, Tab.models:
            // Neither page can be scrolled to a particular row yet, so this
            // takes the user to the page rather than pretending otherwise.
            withAnimation(
                Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
            ) {
                tab = itemID
                showingHome = false
            }

        default:
            break
        }
    }

    private func handleFootAction(_ id: String) {
        guard id == FootAction.manageVaults else { return }
        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
        ) {
            tab = Tab.vaults
            showingHome = false
        }
    }

    private func openModels() {
        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
        ) {
            tab = Tab.models
            showingHome = false
            isSearching = false
        }
    }

    /// What the Review page does when the user judges a rewrite.
    ///
    /// The state changes live here rather than in the page so the page stays a
    /// renderer, and so the same page can be driven by fixtures in the gallery
    /// and by the watcher in the app without knowing which it is.
    private var reviewActions: ReviewActions {
        injectedReview ?? inMemoryReviewActions
    }

    private var inMemoryReviewActions: ReviewActions {
        ReviewActions(
            accept: { proposal, allowOutdated in
                apply(proposal, as: .review, allowOutdated: allowOutdated)
            },
            reject: { proposal in
                state.proposals.removeAll { $0.id == proposal.id }
            },
            regenerate: { proposal in
                update(proposal.id) { $0.state = .regenerating }
            },
            openNote: { summary in
                guard let document = state.searchableNotes.first(
                    where: { $0.url == summary.url }
                ) else { return }
                openDocument(document)
            },
            retry: { proposal in
                update(proposal.id) { $0.state = .regenerating }
            },
            restore: { entry in
                restore(entry)
            }
        )
    }

    private var vaultActions: VaultActions {
        injectedVaults ?? inMemoryVaultActions
    }

    private var inMemoryVaultActions: VaultActions {
        VaultActions(
            openNote: { summary in
                guard let document = state.searchableNotes.first(where: {
                    $0.url.standardizedFileURL == summary.url.standardizedFileURL
                }) else { return }
                openDocument(document)
            },
            updateConfiguration: { vaultID, policy in
                guard let index = state.vaults.firstIndex(where: { $0.id == vaultID })
                else { return }
                state.vaults[index].configuration = policy
            },
            removeVault: { vaultID in
                state.disconnectVault(vaultID)
            },
            connectVault: onConnectVault,
            reconnectVault: { _ in onConnectVault() },
            updateRules: { vaultID, rules in
                guard let index = state.vaults.firstIndex(where: { $0.id == vaultID })
                else { return }
                state.vaults[index].rules = rules
            }
        )
    }

    private func update(_ id: UUID, _ change: (inout Proposal) -> Void) {
        guard let index = state.proposals.firstIndex(where: { $0.id == id })
        else { return }
        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion)
        ) {
            change(&state.proposals[index])
        }
    }

    /// Accepting writes the rewrite and files what it replaced.
    ///
    /// The history entry is created here, before anything else, because it is
    /// the only copy of the text being replaced — the scope's rule that a
    /// snapshot precedes every applied rewrite is this ordering, not a
    /// separate step that could be skipped.
    private func apply(
        _ proposal: Proposal,
        as application: RewriteApplication,
        allowOutdated: Bool = false
    ) {
        let previous = state.searchableNotes
            .first { $0.url == proposal.note.url }?
            .text ?? ""
        let entry = HistoryEntry(
            note: proposal.note,
            path: proposal.note.url,
            vaultID: proposal.vaultID,
            occurredAt: Date(),
            mode: proposal.mode,
            modelID: proposal.modelID,
            previousText: previous,
            // Positional, via the diff engine. A search-and-replace over the
            // hunks edits the first line that happens to match, and notes
            // repeat lines constantly — blank ones, `## Notes`, `- [ ]`.
            appliedText: proposal.proposedText
                ?? TextDiff.apply(proposal.hunks, to: previous)
                ?? previous,
            application: application,
            sourceWasOutdated: allowOutdated && state.isOutdated(proposal),
            retryCount: proposal.retryCount
        )

        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion)
        ) {
            state.history.insert(entry, at: 0)
            state.proposals.removeAll { $0.id == proposal.id }
        }
    }

    private func restore(_ entry: HistoryEntry) {
        guard let index = state.history.firstIndex(where: { $0.id == entry.id })
        else { return }
        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion)
        ) {
            state.history[index] = HistoryEntry(
                id: entry.id,
                note: entry.note,
                path: entry.path,
                vaultID: entry.vaultID,
                occurredAt: entry.occurredAt,
                mode: entry.mode,
                modelID: entry.modelID,
                previousText: entry.previousText,
                appliedText: entry.appliedText,
                application: entry.application,
                sourceWasOutdated: entry.sourceWasOutdated,
                retryCount: entry.retryCount,
                ruleIDs: entry.ruleIDs,
                outcome: .reverted(at: Date())
            )
        }
    }

    private func retainDraft(_ text: String, for url: URL) {
        let document = NoteDocument(url: url, text: text)
        displayedNote = document
        DashboardNoteDrafts.retain(document, in: &state)
    }

    private static func makeEditor(
        for document: NoteDocument,
        editing: NoteEditingConfiguration
    ) -> NoteEditorModel {
        NoteEditorModel(document: document) { text, expectedText in
            try editing.save(
                NoteDocument(url: document.url, text: text),
                replacing: expectedText
            )
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
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
        ) {
            tab = transition.tab
            isSearching = transition.isSearching
            showingHome = transition.showingHome
        }
    }
}
