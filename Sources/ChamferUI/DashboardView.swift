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
        modelsState: ModelsLandscapeState = ModelsLandscapeState()
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
                    title: state.vaults.isEmpty ? "Connect a vault…" : "Manage vaults…",
                    symbol: "folder"
                )
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
    @State private var modelsState: ModelsLandscapeState
    @State private var state: DashboardState
    @State private var editorModel: NoteEditorModel?
    @State private var showingVersions = false

    private let editing: NoteEditingConfiguration?
    private let noteLoadError: String?
    private let onClose: () -> Void
    /// Injected rather than reached for directly so `ChamferUI` stays ignorant
    /// of the `Settings` scene — the same arrangement `onClose` already uses.
    /// The gallery leaves it at its default and the control does nothing there,
    /// which is correct: the harness has no settings window to open.
    private let onOpenSettings: () -> Void

    private static let topGutter: CGFloat = 52

    public init(
        state: DashboardState,
        tab: String = Tab.notes,
        editing: NoteEditingConfiguration? = nil,
        noteLoadError: String? = nil,
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.editing = editing
        self.noteLoadError = noteLoadError
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        _tab = State(initialValue: tab)
        _state = State(initialValue: state)
        _modelsState = State(initialValue: ModelsPreferences.loadState())
        _displayedNote = State(initialValue: state.openNote)
        _editorModel = State(
            initialValue: state.openNote.flatMap { document in
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

            versionsOverlay
        }
        .background {
            TrackpadPanGesture(onEnded: handleTabGesture)
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: showingVersions
        )
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
            HomeScreenView(state: state, onOpenNote: openDocument)
        } else {
            switch tab {
            case Tab.review:
                ReviewTimelinePage(state: state, actions: reviewActions)
            case Tab.vaults:
                VaultsPage(
                    vaults: state.vaults,
                    globalPolicy: state.globalPolicy,
                    actions: vaultActions
                )
            case Tab.models:
                ModelsPage(runState: state.runState, state: $modelsState)
            default:
                if let noteLoadError, displayedNote == nil {
                    PageMessage(
                        title: "Couldn’t open Example.md",
                        detail: noteLoadError
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

    /// Versions of whatever note is on the page, newest first. Empty for every
    /// destination that is not a note, which is what keeps the control out of
    /// the gutter everywhere it would mean nothing.
    private var versionsForOpenNote: [HistoryEntry] {
        guard tab == Tab.notes, !showingHome, let note = displayedNote else { return [] }
        return HistoryWindow.forNote(at: note.url, in: state.history)
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

                    versionsControl
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
        // Versions comes and goes with the note under it, which can happen
        // while the gutter is already open — switching tabs, or closing the
        // note. Without its own trigger that change had no curve to animate
        // on and the control simply blinked out.
        .animation(gutterCurve, value: versionsForOpenNote.isEmpty)
    }

    /// Reserved whether or not there is a note, so the cluster is symmetric
    /// and close cannot be nudged off centre by its neighbour appearing.
    @ViewBuilder
    private var versionsControl: some View {
        let versions = versionsForOpenNote
        ZStack(alignment: .leading) {
            Color.clear
            if !versions.isEmpty {
                FloatingVersionsButton(count: versions.count) {
                    showingVersions = true
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
    private var versionsOverlay: some View {
        if showingVersions, let note = displayedNote {
            NoteVersionsSheet(
                noteTitle: note.url.deletingPathExtension().lastPathComponent,
                entries: versionsForOpenNote,
                onRestore: { entry in
                    restore(entry)
                    dismissVersions()
                },
                onDismiss: dismissVersions
            )
        }
    }

    private func dismissVersions() {
        Haptics.commit()
        showingVersions = false
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
            tab = Tab.notes
            showingHome = false
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

    /// What the Review page does when the user judges a rewrite.
    ///
    /// The state changes live here rather than in the page so the page stays a
    /// renderer, and so the same page can be driven by fixtures in the gallery
    /// and by the watcher in the app without knowing which it is.
    private var reviewActions: ReviewActions {
        ReviewActions(
            accept: { proposal in
                apply(proposal, as: .review)
            },
            reject: { proposal in
                update(proposal.id) { $0.state = .rejected }
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
        VaultActions(
            openVault: { vault in
                guard let document = state.searchableNotes.first(where: {
                    $0.url.path().hasPrefix(vault.url.path())
                }) else { return }
                openDocument(document)
            },
            updatePolicy: { vaultID, override in
                guard let index = state.vaults.firstIndex(where: { $0.id == vaultID })
                else { return }
                state.vaults[index].policy = override
            },
            updateFolderPolicy: { vaultID, folderID, override in
                guard let vaultIndex = state.vaults.firstIndex(where: { $0.id == vaultID }),
                      let folderIndex = state.vaults[vaultIndex].folders.firstIndex(
                          where: { $0.id == folderID }
                      )
                else { return }
                state.vaults[vaultIndex].folders[folderIndex].policy = override
            },
            removeVault: { vaultID in
                state.vaults.removeAll { $0.id == vaultID }
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
    private func apply(_ proposal: Proposal, as application: RewriteApplication) {
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
            appliedText: proposal.hunks.reduce(previous) { text, hunk in
                text.replacingOccurrences(of: hunk.before, with: hunk.after)
            },
            application: application,
            sourceWasOutdated: state.isOutdated(proposal),
            fallback: proposal.fallback,
            retryCount: proposal.retryCount
        )

        withAnimation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion)
        ) {
            state.history.insert(entry, at: 0)
            update(proposal.id) { $0.state = .accepted }
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
                fallback: entry.fallback,
                retryCount: entry.retryCount,
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
        NoteEditorModel(document: document) { text in
            try editing.save(NoteDocument(url: document.url, text: text))
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

