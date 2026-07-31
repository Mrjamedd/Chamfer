import ChamferCore
import SwiftUI

/// The bar under the page: a tan slab of three destinations.
///
/// Hovering a destination that has entries grows the slab upward and lists
/// them, so you can see what is waiting without leaving the page you are on.
/// It grows out of its own layout bounds rather than pushing the page, which
/// would reflow the note under the pointer.
/// How the bar behaves when nobody is touching it.
///
/// Everything about the idle treatment lives here. Passing `.off` to the bar
/// restores the always-labelled, full-opacity version exactly as it was — one
/// value to change, nothing to unpick.
public struct BarIdleBehaviour: Sendable {
    /// Set false and the bar never collapses or dims.
    public var collapses: Bool
    /// Quiet time before the labels fold away.
    public var delay: Duration
    /// How far the bar fades once it has settled.
    public var restingOpacity: Double
    /// Extra breadth given to the destination you are currently on.
    public var activeExtraPadding: CGFloat
    /// How far the icons draw down once the labels have gone.
    ///
    /// The labels are the only thing that leaves, so without this the resting
    /// bar is a shorter-worded bar rather than a smaller object — the glyphs
    /// are all that is left of it to shrink.
    public var idleIconScale: CGFloat
    /// The fold away. It happens unprompted, so it wants the long, soft end of
    /// the app's range: something seen to settle rather than to answer.
    public var curve: Animation
    /// The way back, which is answering the pointer and so is quicker. Leave
    /// it out and it matches the fold.
    public var wakeCurve: Animation

    public init(
        collapses: Bool,
        delay: Duration,
        restingOpacity: Double,
        activeExtraPadding: CGFloat,
        idleIconScale: CGFloat = 1,
        curve: Animation,
        wakeCurve: Animation? = nil
    ) {
        self.collapses = collapses
        self.delay = delay
        self.restingOpacity = restingOpacity
        self.activeExtraPadding = activeExtraPadding
        self.idleIconScale = idleIconScale
        self.curve = curve
        self.wakeCurve = wakeCurve ?? curve
    }

    public static let standard = BarIdleBehaviour(
        collapses: true,
        delay: .seconds(3.5),
        restingOpacity: 0.82,
        activeExtraPadding: 5,
        // Proportioned off the slab, which loses about a fifth of its height
        // when it settles. Much below this and the symbols stop being legible
        // at a glance, which is the one job the resting bar has.
        idleIconScale: 0.84,
        // Idle is unprompted and can remain softer than direct interaction.
        curve: .spring(duration: 0.28, bounce: 0.02),
        // Waking answers the pointer immediately.
        wakeCurve: Chamfer.Motion.interactive
    )

    /// The previous behaviour: always labelled, never dimmed.
    public static let off = BarIdleBehaviour(
        collapses: false,
        delay: .seconds(3.5),
        restingOpacity: 1,
        activeExtraPadding: 0,
        idleIconScale: 1,
        curve: Chamfer.Motion.interactive
    )
}

public enum BottomBarPointerTarget {
    public static func itemID(at x: CGFloat, frames: [String: CGRect]) -> String? {
        frames
            .sorted { $0.value.minX < $1.value.minX }
            .first { $0.value.minX <= x && x <= $0.value.maxX }?
            .key
    }
}

public enum BottomBarListLayout {
    public static let rowHeight: CGFloat = 20
    public static let rowSpacing: CGFloat = 1
    private static let listTopPadding: CGFloat = 8
    private static let listBottomPadding: CGFloat = 5
    private static let searchSeparatorHeight: CGFloat = 1
    private static let searchSeparatorVerticalPadding: CGFloat = 8
    private static let sectionDividerHeight: CGFloat = 1

    public static func visibleEntryLimit(showsSearch: Bool) -> Int {
        showsSearch ? 3 : 4
    }

    public static func needsScrolling(entryCount: Int, showsSearch: Bool) -> Bool {
        entryCount > visibleEntryLimit(showsSearch: showsSearch)
    }

    public static func entryViewportHeight(entryCount: Int, showsSearch: Bool) -> CGFloat {
        let count = min(entryCount, visibleEntryLimit(showsSearch: showsSearch))
        guard count > 0 else { return 0 }
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
    }

    public static func entryContentWidth(
        viewportWidth: CGFloat,
        needsScrolling: Bool
    ) -> CGFloat {
        max(viewportWidth - (needsScrolling ? 10 : 0), 0)
    }

    /// The exact height above the destination row. Giving the slab a numeric
    /// target lets it interpolate between sections instead of replacing one
    /// intrinsic list height with another in a single layout pass.
    public static func expandedContentHeight(
        entryCount: Int,
        showsSearch: Bool
    ) -> CGFloat {
        let viewport = entryViewportHeight(
            entryCount: entryCount,
            showsSearch: showsSearch
        )
        var content = viewport

        if showsSearch {
            if entryCount > 0 {
                content += rowSpacing
                    + searchSeparatorHeight
                    + searchSeparatorVerticalPadding
                    + rowSpacing
            }
            content += rowHeight
        }

        guard content > 0 else { return 0 }
        return content
            + listTopPadding
            + listBottomPadding
            + sectionDividerHeight
    }
}

public enum BottomBarScrollIndicator {
    public struct Metrics: Equatable, Sendable {
        public let thumbHeight: CGFloat
        public let thumbOffset: CGFloat
    }

    public static func shouldShow(
        needsScrolling: Bool,
        isHovered: Bool,
        isScrolling: Bool
    ) -> Bool {
        needsScrolling && (isHovered || isScrolling)
    }

    public static func metrics(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        contentOffset: CGFloat
    ) -> Metrics {
        guard contentHeight > viewportHeight, viewportHeight > 0 else {
            return Metrics(thumbHeight: max(viewportHeight, 0), thumbOffset: 0)
        }

        let thumbHeight = max(
            12,
            min(viewportHeight, viewportHeight * viewportHeight / contentHeight)
        )
        let maximumContentOffset = contentHeight - viewportHeight
        let progress = min(max(contentOffset / maximumContentOffset, 0), 1)
        return Metrics(
            thumbHeight: thumbHeight,
            thumbOffset: progress * (viewportHeight - thumbHeight)
        )
    }
}

public enum BottomBarScrollPrecision {
    public enum Tier: Equatable, Sendable {
        case oneRow
        case fewRows
        case native
    }

    public static func tier(entryCount: Int, visibleLimit: Int) -> Tier {
        let hiddenRows = max(entryCount - visibleLimit, 0)
        if hiddenRows <= 2 { return .oneRow }
        if hiddenRows <= 6 { return .fewRows }
        return .native
    }

    public static func behavior(
        entryCount: Int,
        visibleLimit: Int
    ) -> ViewAlignedScrollTargetBehavior {
        switch tier(entryCount: entryCount, visibleLimit: visibleLimit) {
        case .oneRow:
            ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByOne)
        case .fewRows:
            ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByFew)
        case .native:
            ViewAlignedScrollTargetBehavior(limitBehavior: .never)
        }
    }
}

public enum BottomBarSectionTransition {
    public enum Action: Equatable, Sendable {
        case open
        case swap
        case close
        case unchanged
    }

    public static func action(
        displayedID: String?,
        targetID: String?
    ) -> Action {
        switch (displayedID, targetID) {
        case (nil, .some):
            .open
        case (.some, nil):
            .close
        case let (.some(displayed), .some(target)) where displayed != target:
            .swap
        default:
            .unchanged
        }
    }
}

public enum BottomBarBounceProfile {
    public enum Direction: Sendable {
        case opening
        case closing
    }

    public static let restingScale: CGFloat = 1

    /// A real overshoot phase rather than a spring declaration that may never
    /// travel beyond its target once SwiftUI resolves the changing layout.
    public static func overshootScale(for direction: Direction) -> CGFloat {
        switch direction {
        case .opening:
            1.022
        case .closing:
            0.985
        }
    }

    /// Reciprocal scaling keeps the persistent destination row stationary
    /// while the slab surrounding it overshoots.
    public static func compensatingScale(for surfaceScale: CGFloat) -> CGFloat {
        guard surfaceScale != 0 else { return 1 }
        return 1 / surfaceScale
    }
}

public enum BottomBarContentMotion {
    public enum Direction: Equatable, Sendable {
        case forward
        case backward
        case stationary
    }

    public static func direction(
        from displayedID: String,
        to targetID: String,
        orderedIDs: [String]
    ) -> Direction {
        guard let displayedIndex = orderedIDs.firstIndex(of: displayedID),
              let targetIndex = orderedIDs.firstIndex(of: targetID)
        else { return .stationary }

        if targetIndex > displayedIndex { return .forward }
        if targetIndex < displayedIndex { return .backward }
        return .stationary
    }

    public static func outgoingOffset(for direction: Direction) -> CGFloat {
        switch direction {
        case .forward:
            -2
        case .backward:
            2
        case .stationary:
            0
        }
    }

    public static func incomingOffset(for direction: Direction) -> CGFloat {
        -outgoingOffset(for: direction)
    }
}

public enum BottomBarMotionTiming {
    /// Swap in under two 60 Hz frames, once the outgoing copy is nearly clear.
    public static let contentHandoffDelay: TimeInterval = 0
    public static let contentExitDuration: TimeInterval = 0.014
    public static let contentEntranceDuration: TimeInterval = 0.044
    public static let pointerExitDelay: TimeInterval = 0.055
    public static let searchDuration: TimeInterval = 0.30
    public static let searchCleanupDelay: TimeInterval = 0.31
}

public enum BottomBarSearchLayout {
    private static let visibleResultLimit = 4
    private static let resultRowHeight: CGFloat = 42
    private static let populatedResultsTopPadding: CGFloat = 4
    private static let dividerHeight: CGFloat = 1

    public static func fieldHeight(
        isSearching: Bool,
        hasQuery: Bool,
        matchCount: Int,
        barHeight: CGFloat
    ) -> CGFloat {
        guard isSearching, hasQuery else { return barHeight }

        let resultsHeight: CGFloat
        if matchCount == 0 {
            resultsHeight = resultRowHeight
        } else {
            resultsHeight = CGFloat(min(matchCount, visibleResultLimit))
                * resultRowHeight
                + populatedResultsTopPadding
        }
        return barHeight + dividerHeight + resultsHeight
    }
}

public enum BottomBarSearchTransition {
    public enum Direction: Sendable {
        case opening
        case closing
    }

    public enum Cleanup: Equatable, Sendable {
        case none
        case expandedSection
        case query
    }

    public static func cleanup(
        direction: Direction,
        geometrySettled: Bool
    ) -> Cleanup {
        guard geometrySettled else { return .none }
        switch direction {
        case .opening:
            return .expandedSection
        case .closing:
            return .query
        }
    }
}

public struct BottomBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let detail: String

        public init(id: String, title: String, detail: String) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }

    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        public let symbol: String
        public let label: String
        /// Shown when this item is hovered. Empty means the bar stays closed,
        /// unless it offers search.
        public let entries: [Entry]
        /// Adds a search action to the foot of this item's list.
        public let showsSearch: Bool

        public init(
            id: String,
            symbol: String,
            label: String,
            entries: [Entry] = [],
            showsSearch: Bool = false
        ) {
            self.id = id
            self.symbol = symbol
            self.label = label
            self.entries = entries
            self.showsSearch = showsSearch
        }
    }

    @Binding private var selection: String
    @Binding private var isSearching: Bool
    @State private var hovered: String?
    @State private var displayedItemID: String?
    @State private var listContentVisible = true
    @State private var listContentOffsetX: CGFloat = 0
    @State private var listTransitionDirection = BottomBarContentMotion.Direction.stationary
    @State private var listSwitchTask: Task<Void, Never>?
    @State private var expandedContentHeight: CGFloat = 0
    @State private var slabScale = BottomBarBounceProfile.restingScale
    @State private var bounceTask: Task<Void, Never>?
    @State private var isSplit = false
    @State private var closeHovered = false
    @State private var pressedItem: String?
    @State private var labelsShown = true
    @State private var idleTask: Task<Void, Never>?
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var pointerInRow = false
    @State private var pointerInList = false
    @State private var closeTask: Task<Void, Never>?
    @State private var query = ""
    @State private var searchTransitionTask: Task<Void, Never>?
    @State private var searchResetTask: Task<Void, Never>?
    /// The destinations' natural width, measured so the slab can animate
    /// between it and the field's width instead of jumping between an
    /// intrinsic size and a fixed one. Nil until the first measurement, which
    /// is the one case where the slab should simply take its natural size
    /// rather than glide to it.
    @State private var collapsedWidth: CGFloat?
    @FocusState private var searchFocused: Bool

    private let items: [Item]
    private let searchableNotes: [NoteDocument]
    private let onOpenSearchResult: (NoteDocument) -> Void
    private let idle: BarIdleBehaviour
    private let showsSelection: Bool

    // Proportioned off the reference: the slab is a little under four times
    // the cap height of its labels, not six.
    private static let collapsedHeight: CGFloat = 34
    /// Thinner once the labels have gone, so the resting bar is a slimmer
    /// object and not merely a shorter-worded one.
    private static let idleHeight: CGFloat = 27
    private static let radius: CGFloat = 12
    private static let idleRadius: CGFloat = 10
    /// Close to the width of the destination row, so the status column lands
    /// near the slab's right edge instead of stranding empty space.
    private static let listWidth: CGFloat = 262
    /// How far the bar rises when it becomes a search field, and how wide the
    /// field is once it gets there.
    private static let searchLift: CGFloat = 360
    private static let searchWidth: CGFloat = 420
    private static let searchResultHeight: CGFloat = 42
    private static let visibleSearchResultLimit = 4
    /// The right-hand strip of the field that splits the close button off, and
    /// how much further back the pointer must travel to close it again.
    private static let splitZone: CGFloat = 96
    private static let splitHysteresis: CGFloat = 40
    nonisolated private static let rowSpace = "chamfer.bar.row"

    public init(
        items: [Item],
        selection: Binding<String>,
        isSearching: Binding<Bool>,
        searchableNotes: [NoteDocument] = [],
        onOpenSearchResult: @escaping (NoteDocument) -> Void = { _ in },
        idle: BarIdleBehaviour = .standard,
        showsSelection: Bool = true
    ) {
        self.items = items
        self.searchableNotes = searchableNotes
        self.onOpenSearchResult = onOpenSearchResult
        self.idle = idle
        self.showsSelection = showsSelection
        _selection = selection
        _isSearching = isSearching
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.frame(height: Self.collapsedHeight)
            slab
        }
        // Bottom-aligned, or a frame this size centres the taller expanded
        // slab and it grows downwards as much as upwards.
        .frame(height: Self.collapsedHeight, alignment: .bottom)
        .onChange(of: isSearching) { wasSearching, searching in
            if searching {
                searchResetTask?.cancel()
                searchResetTask = nil
            } else if wasSearching {
                searchTransitionTask?.cancel()
                searchTransitionTask = nil
                searchFocused = false
                scheduleSearchReset()
            }
        }
    }

    /// One surface throughout, not two that swap.
    ///
    /// Searching widens this same slab and swaps what is inside it, so the bar
    /// rises and stretches into the field in a single motion. Cross-fading two
    /// separate surfaces reads as one thing vanishing and another arriving,
    /// which is what made it look like the field simply appeared.
    private var slab: some View {
        // Bottom-aligned, so the slab losing height when it settles takes the
        // top edge down and leaves the bottom one planted. Centred, the whole
        // bar would drift upward as it folds.
        HStack(alignment: .bottom, spacing: isSplit ? Chamfer.Space.snug + 2 : 0) {
            ZStack(alignment: .bottom) {
                destinations
                    .opacity(isSearching ? 0 : 1)
                    .allowsHitTesting(!isSearching)
                field
                    .opacity(isSearching ? 1 : 0)
                    .allowsHitTesting(isSearching)
            }
            .frame(width: isSearching ? fieldWidth : collapsedWidth)
            .barSurface(radius: surfaceRadius)
            .chamferRing(
                radius: surfaceRadius,
                color: Chamfer.Palette.barRing
            )
            .scaleEffect(slabScale, anchor: .bottom)

            closeCircle
        }
        .contentShape(Rectangle())
        // Measured against the pair's total width, which is constant whether
        // split or not — the field gives up exactly the space the circle
        // takes — so the boundary never moves under the pointer. Separate
        // thresholds for opening and closing, so a pointer resting on the
        // boundary cannot chatter the circle in and out.
        .onContinuousHover { hover in
            // Hover keeps arriving while the layer animates out; without this
            // the split survives the close and the next search opens already
            // split apart.
            guard isSearching, case let .active(location) = hover else { return }
            let opensAt = Self.searchWidth - Self.splitZone
            let closesAt = opensAt - Self.splitHysteresis
            if !isSplit, location.x > opensAt {
                Haptics.pop()
                withAnimation(Self.splitCurve) { isSplit = true }
            } else if isSplit, location.x < closesAt {
                closeHovered = false
                withAnimation(Self.splitCurve) { isSplit = false }
            }
        }
        .onExitCommand(perform: endSearch)
        .fixedSize()
        .opacity(labelsShown || isSearching ? 1 : idle.restingOpacity)
        .task { settle() }
        // Searching lifts the bar clear of the bottom edge so the field sits
        // where you are looking rather than at the foot of the window.
        .offset(y: isSearching ? -Self.searchLift : 0)
        // Deliberately no .onHover here. The slab's size depends on `hovered`,
        // so measuring the pointer against it feeds back: expanding moves the
        // edge past the pointer, which clears `hovered`, which collapses it,
        // which re-enters the button. Exit is detected on the row and the list
        // instead — neither changes size in response to this state.
        //
        // Nor any .animation(value:) modifiers. Every one of these states is
        // mutated inside an explicit withAnimation, which is what makes the
        // structural changes — a list being inserted, the field replacing the
        // destinations — animate rather than snap into place.
    }

    private var surfaceRadius: CGFloat {
        labelsShown || isSearching ? Self.radius : Self.idleRadius
    }

    /// The slab's height, and so the row's and the field's. One source, or the
    /// tallest of them silently wins and the others' values do nothing.
    private var barHeight: CGFloat {
        labelsShown || isSearching ? Self.collapsedHeight : Self.idleHeight
    }

    /// A short, lightly elastic macOS-style response. The small bounce lets
    /// the slab travel just beyond its resting size without looking playful.
    static let openCurve = Animation.spring(duration: 0.21, bounce: 0.035)
    static let closeCurve = Animation.spring(duration: 0.19, bounce: 0.025)
    static let resizeCurve = Animation.spring(duration: 0.18, bounce: 0.015)
    static let searchCurve = Animation.spring(
        duration: BottomBarMotionTiming.searchDuration,
        bounce: 0.02
    )
    static let splitCurve = Animation.spring(duration: 0.20, bounce: 0.06)
    /// Softly damped like a native macOS selection indicator: it follows the
    /// pointer continuously without snapping or wobbling at each destination.
    static let slideCurve = Chamfer.Motion.interactive

    private var sliderAnimation: Animation {
        reduceMotion ? Chamfer.Motion.quick : Self.slideCurve
    }

    private var sectionOpenAnimation: Animation {
        reduceMotion ? Chamfer.Motion.quick : Self.openCurve
    }

    private var sectionCloseAnimation: Animation {
        reduceMotion ? Chamfer.Motion.quick : Self.closeCurve
    }

    private var sectionResizeAnimation: Animation {
        reduceMotion ? Chamfer.Motion.quick : Self.resizeCurve
    }

    private var destinations: some View {
        VStack(spacing: 0) {
            if let item = expandedItem {
                VStack(spacing: 0) {
                    list(item)
                    Rectangle()
                        .fill(Chamfer.Palette.barStroke.opacity(0.7))
                        .frame(height: 1)
                        .padding(.horizontal, Chamfer.Space.regular)
                }
                // Section changes fade out, replace, then fade in. The old and
                // new glyph runs never share a frame, so text cannot morph
                // through itself while the slab keeps moving continuously.
                .opacity(listContentVisible ? 1 : 0)
                .offset(x: listContentOffsetX)
                .frame(height: expandedContentHeight, alignment: .bottom)
                .clipped()
                .onHover { pointer(inList: $0) }
                .id(item.id)
                .transition(listHandoffTransition)
            }
            row
                // The slab may overshoot, but its persistent black selection
                // pill remains locked to the destination row.
                .scaleEffect(
                    BottomBarBounceProfile.compensatingScale(for: slabScale),
                    anchor: .bottom
                )
                .onHover { pointer(inRow: $0) }
                // Measurement reports the *settled* layout the instant the
                // state flips, not the frame-by-frame interpolation, so a
                // bare assignment here teleports the surface to its new width
                // while the labels inside are still at full size — the row
                // spills out and is clipped by its own slab. Animating the
                // write puts the surface back on the same curve as its
                // contents, which is what makes the fold read as one object
                // shrinking rather than a lid closing over a row.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    guard width > 0, width != collapsedWidth else { return }
                    guard collapsedWidth != nil else {
                        collapsedWidth = width
                        return
                    }
                    withAnimation(labelsShown ? idle.wakeCurve : idle.curve) {
                        collapsedWidth = width
                    }
                }
        }
    }

    /// Closing is deferred rather than immediate.
    ///
    /// Inserting the list above the row rebuilds the row's tracking area, so
    /// SwiftUI reports a spurious exit and immediate re-entry within a frame
    /// or two. Closing on that exit oscillated — open, close, open — at screen
    /// refresh rate, which is what made the bar flicker and the haptics
    /// machine-gun. A short delay outlives the rebuild: the re-entry cancels
    /// the pending close and nothing happens. It doubles as hover intent, so
    /// cutting a corner across a destination no longer flashes its list open.
    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(BottomBarMotionTiming.pointerExitDelay)
            )
            guard !Task.isCancelled else { return }
            guard !pointerInRow, !pointerInList, !isSearching else { return }
            setSectionTarget(nil)
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func pointer(inRow: Bool) {
        pointerInRow = inRow
        inRow ? cancelClose() : scheduleClose()
        settle()
    }

    private func pointer(inList: Bool) {
        pointerInList = inList
        inList ? cancelClose() : scheduleClose()
        settle()
    }

    private func setSectionTarget(_ targetID: String?) {
        listSwitchTask?.cancel()
        listSwitchTask = nil
        hovered = targetID

        switch BottomBarSectionTransition.action(
            displayedID: displayedItemID,
            targetID: targetID
        ) {
        case .open:
            guard let targetID else { return }
            let targetHeight = expandedHeight(for: targetID)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedItemID = targetID
                expandedContentHeight = 0
                listContentVisible = false
                listContentOffsetX = 0
            }
            withAnimation(sectionOpenAnimation) {
                expandedContentHeight = targetHeight
            }
            withAnimation(.easeOut(duration: 0.08)) {
                listContentVisible = true
            }
            runBounce(.opening)

        case .swap:
            guard let currentItemID = displayedItemID, let targetID else { return }
            let direction = BottomBarContentMotion.direction(
                from: currentItemID,
                to: targetID,
                orderedIDs: items.map(\.id)
            )

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                listTransitionDirection = direction
            }
            // Identity-based replacement lets SwiftUI retarget rapid hover
            // changes immediately. There is no delayed blank state to cancel
            // and restart when the pointer crosses another destination.
            withAnimation(sectionResizeAnimation) {
                expandedContentHeight = expandedHeight(for: targetID)
            }
            withAnimation(
                .easeOut(duration: BottomBarMotionTiming.contentEntranceDuration)
            ) {
                displayedItemID = targetID
                listContentVisible = true
                listContentOffsetX = 0
            }

        case .close:
            withAnimation(.easeOut(duration: 0.065)) {
                listContentVisible = false
                listContentOffsetX = 0
            }
            withAnimation(sectionCloseAnimation) {
                expandedContentHeight = 0
            }
            runBounce(.closing)
            listSwitchTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                guard !Task.isCancelled, hovered == nil else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    displayedItemID = nil
                    listContentVisible = true
                    listContentOffsetX = 0
                }
            }

        case .unchanged:
            guard let targetID else { return }
            let wasCollapsed = expandedContentHeight == 0
            withAnimation(wasCollapsed ? sectionOpenAnimation : sectionResizeAnimation) {
                expandedContentHeight = expandedHeight(for: targetID)
            }
            withAnimation(.easeOut(duration: 0.07)) {
                listContentVisible = true
                listContentOffsetX = 0
            }
            if wasCollapsed { runBounce(.opening) }
        }
    }

    private func expandedHeight(for itemID: String?) -> CGFloat {
        guard let itemID,
              let item = items.first(where: { $0.id == itemID })
        else { return 0 }

        return BottomBarListLayout.expandedContentHeight(
            entryCount: item.entries.count,
            showsSearch: item.showsSearch
        )
    }

    private var listHandoffTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(
                with: .offset(
                    x: BottomBarContentMotion.incomingOffset(
                        for: listTransitionDirection
                    )
                )
            ),
            removal: .opacity.combined(
                with: .offset(
                    x: BottomBarContentMotion.outgoingOffset(
                        for: listTransitionDirection
                    )
                )
            )
        )
    }

    /// Explicitly travels past rest and returns within 250ms. Keeping this
    /// transform separate from the list-height spring makes the overshoot
    /// visible even when SwiftUI is simultaneously interpolating layout.
    private func runBounce(_ direction: BottomBarBounceProfile.Direction) {
        bounceTask?.cancel()
        bounceTask = nil

        guard !reduceMotion else {
            slabScale = BottomBarBounceProfile.restingScale
            return
        }

        withAnimation(.spring(duration: 0.125, bounce: 0.025)) {
            slabScale = BottomBarBounceProfile.overshootScale(for: direction)
        }
        bounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.15, bounce: 0)) {
                slabScale = BottomBarBounceProfile.restingScale
            }
        }
    }

    /// Wakes the bar and restarts the quiet clock. Once it runs out, and only
    /// if nothing is being pointed at, pressed or typed into, the labels fold
    /// away and the bar dims to its resting state.
    private func settle() {
        guard idle.collapses else { return }
        idleTask?.cancel()
        if !labelsShown {
            withAnimation(idle.wakeCurve) { labelsShown = true }
        }
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: idle.delay)
            guard !Task.isCancelled else { return }
            guard !pointerInRow, !pointerInList, !isSearching, pressedItem == nil else { return }
            withAnimation(idle.curve) { labelsShown = false }
        }
    }

    private var expandedItem: Item? {
        guard let displayedItemID,
              let item = items.first(where: { $0.id == displayedItemID }),
              !item.entries.isEmpty || item.showsSearch
        else { return nil }
        return item
    }

    // MARK: - Search

    /// The close button, always present so it is never being scaled by a
    /// transition at the moment you aim at it. Its width animates instead.
    private var closeCircle: some View {
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Chamfer.Palette.pageText)
            .frame(width: Self.collapsedHeight, height: Self.collapsedHeight)
            .barSurface(
                radius: Self.collapsedHeight / 2,
                fill: Chamfer.Palette.bar
            )
            .overlay {
                Circle()
                    .fill(Chamfer.Palette.hoverTint)
                    .opacity(closeHovered ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: isSplit ? Self.collapsedHeight : 0)
            .opacity(isSplit ? 1 : 0)
            .overlay(
                Circle()
                    .strokeBorder(Chamfer.Palette.barRing, lineWidth: Chamfer.Palette.ringWidth)
                    .opacity(isSplit ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .chamferHoverRingCircle(closeHovered)
            .contentShape(Circle())
            .onHover { inside in
                guard isSplit else { return }
                withAnimation(Chamfer.Motion.quick) { closeHovered = inside }
            }
            // A tap gesture rather than a Button: while the field holds focus,
            // the first click on a button is spent moving first responder
            // instead of activating it, which is why it took two.
            .onTapGesture { endSearch() }
            .allowsHitTesting(isSplit)
    }

    private var fieldWidth: CGFloat {
        isSplit
            ? Self.searchWidth - Self.collapsedHeight - (Chamfer.Space.snug + 2)
            : Self.searchWidth
    }

    private var searchMatches: [BottomBarSearchMatch] {
        BottomBarSearchIndex.matches(query: query, notes: searchableNotes)
    }

    private var hasSearchQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchFieldHeight: CGFloat {
        BottomBarSearchLayout.fieldHeight(
            isSearching: isSearching,
            hasQuery: hasSearchQuery,
            matchCount: searchMatches.count,
            barHeight: barHeight
        )
    }

    private var field: some View {
        VStack(spacing: 0) {
            if hasSearchQuery {
                searchResultList
                Rectangle()
                    .fill(Chamfer.Palette.barStroke.opacity(0.7))
                    .frame(height: 1)
                    .padding(.horizontal, Chamfer.Space.regular)
            }

            HStack(spacing: Chamfer.Space.regular) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                TextField("Search notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .tint(Chamfer.Palette.pageText)
                    .focused($searchFocused)
                    .onSubmit {
                        guard let first = searchMatches.first else { return }
                        selectSearchResult(first)
                    }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Chamfer.Space.roomy)
            .frame(height: barHeight)
        }
        // Search results are retained while the field returns to the bar, but
        // this numeric viewport closes around them on the same curve as the
        // surface. Intrinsic content can no longer disappear mid-morph.
        .frame(height: searchFieldHeight, alignment: .bottom)
        .clipped()
        .animation(
            .spring(duration: 0.18, bounce: 0),
            value: hasSearchQuery
        )
        .animation(
            .spring(duration: 0.18, bounce: 0),
            value: searchMatches.count
        )
    }

    @ViewBuilder
    private var searchResultList: some View {
        let matches = searchMatches

        if matches.isEmpty {
            Text("No matching notes")
                .font(.system(size: 12))
                .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Chamfer.Space.roomy)
                .frame(height: Self.searchResultHeight)
        } else {
            ScrollView(
                .vertical,
                showsIndicators: matches.count > Self.visibleSearchResultLimit
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { match in
                        SearchResultRow(match: match) {
                            selectSearchResult(match)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .frame(
                height: CGFloat(min(matches.count, Self.visibleSearchResultLimit))
                    * Self.searchResultHeight
            )
            .padding(.top, Chamfer.Space.tight)
            .scrollTargetBehavior(
                BottomBarScrollPrecision.behavior(
                    entryCount: matches.count,
                    visibleLimit: Self.visibleSearchResultLimit
                )
            )
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func beginSearch() {
        Haptics.pop()
        cancelClose()
        listSwitchTask?.cancel()
        listSwitchTask = nil
        searchTransitionTask?.cancel()
        searchTransitionTask = nil
        searchResetTask?.cancel()
        searchResetTask = nil
        bounceTask?.cancel()
        bounceTask = nil
        withAnimation(Self.searchCurve) {
            hovered = nil
            expandedContentHeight = 0
            listContentVisible = false
            listContentOffsetX = 0
            slabScale = BottomBarBounceProfile.restingScale
            isSearching = true
        }
        scheduleExpandedSectionCleanup()
        // The field only exists once the bubble is on screen.
        DispatchQueue.main.async { searchFocused = true }
    }

    private func endSearch() {
        Haptics.commit()
        searchTransitionTask?.cancel()
        searchTransitionTask = nil
        searchFocused = false
        withAnimation(Self.searchCurve) {
            isSplit = false
            isSearching = false
        }
    }

    private func scheduleExpandedSectionCleanup() {
        searchTransitionTask?.cancel()
        searchTransitionTask = Task { @MainActor in
            do {
                try await Task.sleep(
                    for: .seconds(BottomBarMotionTiming.searchCleanupDelay)
                )
            } catch {
                return
            }
            guard !Task.isCancelled, isSearching else { return }
            guard BottomBarSearchTransition.cleanup(
                direction: .opening,
                geometrySettled: true
            ) == .expandedSection else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedItemID = nil
                listContentVisible = true
                listContentOffsetX = 0
            }
        }
    }

    private func scheduleSearchReset() {
        searchResetTask?.cancel()
        searchResetTask = Task { @MainActor in
            do {
                try await Task.sleep(
                    for: .seconds(BottomBarMotionTiming.searchCleanupDelay)
                )
            } catch {
                return
            }
            guard !Task.isCancelled, !isSearching else { return }
            guard BottomBarSearchTransition.cleanup(
                direction: .closing,
                geometrySettled: true
            ) == .query else { return }
            resetSearchState()
        }
    }

    private func resetSearchState() {
        searchFocused = false
        query = ""
        closeHovered = false
        isSplit = false
        displayedItemID = nil
        expandedContentHeight = 0
        listContentVisible = true
        listContentOffsetX = 0
    }

    private func selectSearchResult(_ match: BottomBarSearchMatch) {
        onOpenSearchResult(match.document)
        endSearch()
    }

    /// Menu density: 12pt, 20pt rows, a rounded highlight under the pointer.
    /// The list is part of the bar, not a panel with its own voice.
    private func list(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if !item.entries.isEmpty {
                EntryViewport(
                    entries: item.entries,
                    showsSearch: item.showsSearch
                )
            }
            if item.showsSearch {
                if !item.entries.isEmpty {
                    Rectangle()
                        .fill(Chamfer.Palette.barStroke.opacity(0.6))
                        .frame(height: 1)
                        .padding(.vertical, Chamfer.Space.tight)
                }
                SearchRow(action: beginSearch)
            }
        }
        .frame(width: Self.listWidth, alignment: .leading)
        .padding(.horizontal, Chamfer.Space.snug)
        .padding(.top, Chamfer.Space.snug)
        .padding(.bottom, Chamfer.Space.tight + 1)
    }

    private struct EntryViewport: View {
        private struct ScrollSnapshot: Equatable {
            let contentHeight: CGFloat
            let viewportHeight: CGFloat
            let contentOffset: CGFloat
        }

        @State private var isHovered = false
        @State private var isScrolling = false
        @State private var indicatorMetrics = BottomBarScrollIndicator.Metrics(
            thumbHeight: 0,
            thumbOffset: 0
        )

        let entries: [Entry]
        let showsSearch: Bool

        private var needsScrolling: Bool {
            BottomBarListLayout.needsScrolling(
                entryCount: entries.count,
                showsSearch: showsSearch
            )
        }

        private var showsIndicator: Bool {
            BottomBarScrollIndicator.shouldShow(
                needsScrolling: needsScrolling,
                isHovered: isHovered,
                isScrolling: isScrolling
            )
        }

        private var contentWidth: CGFloat {
            BottomBarListLayout.entryContentWidth(
                viewportWidth: BottomBar.listWidth,
                needsScrolling: needsScrolling
            )
        }

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(
                    alignment: .leading,
                    spacing: BottomBarListLayout.rowSpacing
                ) {
                    ForEach(entries) { entry in
                        ListRow(entry: entry)
                            // The scroll thumb updates while the viewport is
                            // moving. Rows whose data has not changed should
                            // not be rebuilt for every sub-point of travel.
                            .equatable()
                            .frame(width: contentWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .frame(
                width: BottomBar.listWidth,
                height: BottomBarListLayout.entryViewportHeight(
                    entryCount: entries.count,
                    showsSearch: showsSearch
                )
            )
            // Preserve native trackpad momentum, then ease onto a complete
            // 20pt row at rest instead of stopping with clipped text.
            .scrollTargetBehavior(
                BottomBarScrollPrecision.behavior(
                    entryCount: entries.count,
                    visibleLimit: BottomBarListLayout.visibleEntryLimit(
                        showsSearch: showsSearch
                    )
                )
            )
            .scrollBounceBehavior(.basedOnSize)
            .onHover { isHovered = $0 }
            .onScrollPhaseChange { _, phase in
                withAnimation(.easeOut(duration: 0.12)) {
                    isScrolling = phase.isScrolling
                }
            }
            .onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
                ScrollSnapshot(
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height,
                    contentOffset: geometry.contentOffset.y
                )
            } action: { _, snapshot in
                let nextMetrics = BottomBarScrollIndicator.metrics(
                    contentHeight: snapshot.contentHeight,
                    viewportHeight: snapshot.viewportHeight,
                    contentOffset: snapshot.contentOffset
                )
                // One quarter point is below a physical pixel on a Retina
                // display. Smaller writes only invalidate the list hierarchy
                // without producing a visible improvement.
                guard abs(nextMetrics.thumbHeight - indicatorMetrics.thumbHeight) >= 0.25
                    || abs(nextMetrics.thumbOffset - indicatorMetrics.thumbOffset) >= 0.25
                else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    indicatorMetrics = nextMetrics
                }
            }
            .overlay(alignment: .topTrailing) {
                if needsScrolling {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Chamfer.Palette.pageText.opacity(0.20))
                        .frame(
                            width: 1.5,
                            height: indicatorMetrics.thumbHeight
                        )
                        .offset(y: indicatorMetrics.thumbOffset)
                        .padding(.trailing, 3)
                        .opacity(showsIndicator ? 1 : 0)
                        .animation(
                            .easeOut(duration: 0.12),
                            value: showsIndicator
                        )
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private struct ListRow: View, Equatable {
        @State private var isHovered = false

        let entry: Entry

        nonisolated static func == (lhs: ListRow, rhs: ListRow) -> Bool {
            lhs.entry == rhs.entry
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.regular) {
                Text(entry.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Chamfer.Space.snug)
                Text(entry.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                    .lineLimit(1)
            }
            .padding(.horizontal, Chamfer.Space.snug)
            .padding(.vertical, Chamfer.Space.tight - 1)
            .frame(height: 20)
            .background(isHovered ? Chamfer.Palette.hoverTint : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small - 2, style: .continuous))
            .chamferHoverRing(isHovered, radius: Chamfer.Radius.small - 2)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }
    }

    /// The action at the foot of a list. Same metrics as an entry so the list
    /// stays one rhythm, but led by an icon to mark it as a verb.
    private struct SearchRow: View {
        @State private var isHovered = false

        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Chamfer.Space.snug) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                        .frame(width: 13)
                    Text("Search notes")
                        .font(.system(size: 12))
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Chamfer.Space.snug)
                .frame(height: 20)
                .background(isHovered ? Chamfer.Palette.hoverTint : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small - 2, style: .continuous))
                .chamferHoverRing(isHovered, radius: Chamfer.Radius.small - 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private struct SearchResultRow: View {
        @State private var isHovered = false

        let match: BottomBarSearchMatch
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                        .lineLimit(1)
                    Text(match.snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Chamfer.Space.roomy)
                .frame(height: BottomBar.searchResultHeight)
                .background(isHovered ? Chamfer.Palette.hoverTint : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    /// Press and hold anywhere on the row and a glass pill forms under the
    /// pointer; drag and it slides between destinations, committing whichever
    /// it is over on release. A plain click is the degenerate case of that —
    /// press and release without travelling — so there is one gesture rather
    /// than a button and a drag competing for the same pixels.
    private var row: some View {
        HStack(spacing: Chamfer.Space.tight) {
            ForEach(items) { item in
                BarButton(
                    item: item,
                    isPressed: item.id == pressedItem,
                    isActive: item.id == selection,
                    isSliderTarget: showsSelection && item.id == (pressedItem ?? selection),
                    showsLabel: labelsShown,
                    extraPadding: idle.activeExtraPadding,
                    idleIconScale: idle.idleIconScale,
                    onHover: { inside in
                        guard inside, !isSearching, pressedItem == nil else { return }
                        let opens = !item.entries.isEmpty || item.showsSearch
                        let next = opens ? item.id : nil
                        guard next != hovered else { return }
                        if next != nil, displayedItemID == nil { Haptics.pop() }
                        setSectionTarget(next)
                    }
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.rowSpace)) } action: { frame in
                    itemFrames[item.id] = frame
                }
            }
        }
        .padding(.horizontal, Chamfer.Space.tight + 1)
        .frame(height: barHeight)
        .coordinateSpace(.named(Self.rowSpace))
        .background(alignment: .topLeading) { selectionSlider }
        .gesture(slide)
    }

    /// One persistent rounded rectangle follows the selected or pressed
    /// destination. Because the same view animates between numeric frames,
    /// differently sized destinations glide rather than replacing one another.
    @ViewBuilder
    private var selectionSlider: some View {
        let target = pressedItem ?? selection
        if showsSelection, let frame = itemFrames[target] {
            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                .fill(Chamfer.Palette.selectionTint)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .animation(sliderAnimation, value: frame)
                .allowsHitTesting(false)
        }
    }

    private var slide: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.rowSpace))
            .onChanged { value in
                guard !isSearching else { return }
                settle()
                let landed = item(at: value.location.x)
                guard landed != pressedItem else { return }
                if landed != nil { Haptics.pop() }
                withAnimation(sliderAnimation) { pressedItem = landed }
            }
            .onEnded { value in
                guard !isSearching else { return }
                if let landed = item(at: value.location.x) {
                    Haptics.commit()
                    withAnimation(sliderAnimation) { selection = landed }
                }
                withAnimation(sliderAnimation) { pressedItem = nil }
            }
    }

    /// Which destination sits under this x, by measured frame rather than by
    /// dividing the row into equal parts — the labels are different widths.
    private func item(at x: CGFloat) -> String? {
        BottomBarPointerTarget.itemID(at: x, frames: itemFrames)
    }

    private struct BarButton: View {
        @State private var isHovered = false
        /// The label's natural width, measured from a hidden copy that is
        /// never squeezed. Animating a real width is what makes the collapse
        /// smooth — inserting and removing the label instead makes the text
        /// pop while the pill catches up behind it.
        @State private var labelWidth: CGFloat = 0

        let item: Item
        let isPressed: Bool
        /// The destination currently being shown, which is given a little more
        /// room than its neighbours.
        let isActive: Bool
        /// The destination currently underneath the moving black selector.
        let isSliderTarget: Bool
        let showsLabel: Bool
        let extraPadding: CGFloat
        /// How far the icon draws down once the label has gone.
        let idleIconScale: CGFloat
        let onHover: (Bool) -> Void

        private static let iconFont = Font.system(size: 11, weight: .regular)
        private static let labelFont = Font.system(size: 12.5, weight: .medium)
        private static let gap = Chamfer.Space.tight + 2
        /// Idle pulls the pill in around the smaller glyph. Without it the
        /// symbol shrinks inside a slot the width of the old one, which reads
        /// as the icon receding rather than as the bar settling.
        private static let pad = Chamfer.Space.regular - 1
        private static let idlePad = Chamfer.Space.snug + 1

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
        }

        var body: some View {
            // The gap lives in the stack's spacing, not inside the label's
            // frame — folded into the frame it is counted against the text's
            // own width and clips the last glyph.
            HStack(spacing: showsLabel ? Self.gap : 0) {
                Image(systemName: item.symbol)
                    .font(Self.iconFont)
                    // Scaled rather than re-sized. A font change swaps one
                    // rendering of the glyph for another halfway through the
                    // move, which reads as a snap however long the curve is;
                    // a scale is one continuous transform, the same way the
                    // page answers the close control. Drawn at the labelled
                    // size and taken down from there, because a glyph scaled
                    // down stays clean where one scaled up goes soft.
                    .scaleEffect(showsLabel ? 1 : idleIconScale)
                Text(item.label)
                    .font(Self.labelFont)
                    .fixedSize()
                    .opacity(showsLabel ? 1 : 0)
                    // The label keeps its place in the layout and gives up its
                    // width instead of leaving it, so the pill closes around it
                    // in one continuous move.
                    .frame(width: showsLabel ? labelWidth : 0, alignment: .leading)
                    .clipped()
            }
            .foregroundStyle(
                isSliderTarget ? Color.white : Chamfer.Palette.textOnPaper
            )
            .padding(.horizontal, (showsLabel ? Self.pad : Self.idlePad) + (isActive ? extraPadding : 0))
            .padding(.vertical, Chamfer.Space.tight)
            // The selected capsule already carries the tint and outline.
            .background(
                isHovered && !isPressed && !isSliderTarget
                    ? Chamfer.Palette.hoverTint
                    : .clear
            )
            .clipShape(shape)
            .chamferHoverRing(isHovered && !isPressed, radius: Chamfer.Radius.small)
            .contentShape(shape)
            .background(alignment: .topLeading) { measurer }
            .onHover { inside in
                isHovered = inside
                onHover(inside)
            }
            .animation(Chamfer.Motion.quick, value: isHovered)
        }

        /// A copy of the label at its natural size, drawn nowhere. Backgrounds
        /// do not affect the parent's layout, so measuring here is free.
        private var measurer: some View {
            Text(item.label)
                .font(Self.labelFont)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    guard width > 0 else { return }
                    // A hair of slack: a frame measured to the exact rendered
                    // width can still clip the final glyph's antialiasing.
                    labelWidth = width + 1
                }
        }
    }
}

private extension View {
    /// The bar's material: tan fill, hairline edge, soft float. Shared so the
    /// field and the detached close button read as pieces of the same object.
    func barSurface(
        radius: CGFloat,
        fill: Color = Chamfer.Palette.bar,
        stroke: Color = Chamfer.Palette.barStroke,
        strokeWidth: CGFloat = 1
    ) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: strokeWidth)
            )
            .chamferFloat(radius: 20, y: 8, opacity: 0.14)
    }
}

/// The dismiss control that floats above the page, revealed on approach.
public struct FloatingCloseButton: View {
    @State private var isHovered = false

    private let action: () -> Void
    private let onHover: (Bool) -> Void

    public init(onHover: @escaping (Bool) -> Void = { _ in }, action: @escaping () -> Void) {
        self.onHover = onHover
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.commit()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Chamfer.Palette.bar)
                        .overlay {
                            Circle()
                                .fill(Chamfer.Palette.hoverTint)
                                .opacity(isHovered ? 1 : 0)
                        }
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Chamfer.Palette.barStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .chamferHoverRingCircle(isHovered)
        .chamferFloat(radius: 14, y: 6, opacity: 0.18)
        .onHover { inside in
            isHovered = inside
            onHover(inside)
        }
        .animation(Chamfer.Motion.quick, value: isHovered)
    }
}
