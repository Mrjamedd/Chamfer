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
    public var curve: Animation

    public init(
        collapses: Bool,
        delay: Duration,
        restingOpacity: Double,
        activeExtraPadding: CGFloat,
        curve: Animation
    ) {
        self.collapses = collapses
        self.delay = delay
        self.restingOpacity = restingOpacity
        self.activeExtraPadding = activeExtraPadding
        self.curve = curve
    }

    public static let standard = BarIdleBehaviour(
        collapses: true,
        delay: .seconds(3.5),
        restingOpacity: 0.82,
        activeExtraPadding: 5,
        // ~280ms, soft and slightly over-damped so it settles rather than
        // bounces — the fold is a long move for a small object.
        curve: .spring(response: 0.28, dampingFraction: 0.92)
    )

    /// The previous behaviour: always labelled, never dimmed.
    public static let off = BarIdleBehaviour(
        collapses: false,
        delay: .seconds(3.5),
        restingOpacity: 1,
        activeExtraPadding: 0,
        curve: .spring(response: 0.22, dampingFraction: 0.86)
    )
}

public struct BottomBar: View {
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
    @State private var hovered: String?
    @State private var isSearching = false
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
    /// The destinations' natural width, measured once so the slab can animate
    /// between it and the field's width instead of jumping between an
    /// intrinsic size and a fixed one.
    @State private var collapsedWidth: CGFloat = 320
    @FocusState private var searchFocused: Bool

    private let items: [Item]
    private let idle: BarIdleBehaviour

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
    /// The right-hand strip of the field that splits the close button off, and
    /// how much further back the pointer must travel to close it again.
    private static let splitZone: CGFloat = 96
    private static let splitHysteresis: CGFloat = 40
    private static let rowSpace = "chamfer.bar.row"

    public init(
        items: [Item],
        selection: Binding<String>,
        idle: BarIdleBehaviour = .standard
    ) {
        self.items = items
        self.idle = idle
        _selection = selection
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.frame(height: Self.collapsedHeight)
            slab
        }
        // Bottom-aligned, or a frame this size centres the taller expanded
        // slab and it grows downwards as much as upwards.
        .frame(height: Self.collapsedHeight, alignment: .bottom)
    }

    /// One surface throughout, not two that swap.
    ///
    /// Searching widens this same slab and swaps what is inside it, so the bar
    /// rises and stretches into the field in a single motion. Cross-fading two
    /// separate surfaces reads as one thing vanishing and another arriving,
    /// which is what made it look like the field simply appeared.
    private var slab: some View {
        HStack(spacing: isSplit ? Chamfer.Space.snug + 2 : 0) {
            ZStack(alignment: .bottom) {
                destinations
                    .opacity(isSearching ? 0 : 1)
                    .allowsHitTesting(!isSearching)
                field
                    .frame(height: Self.collapsedHeight)
                    .opacity(isSearching ? 1 : 0)
                    .allowsHitTesting(isSearching)
            }
            .frame(width: isSearching ? fieldWidth : collapsedWidth)
            .barSurface(radius: surfaceRadius)
            .chamferRing(radius: surfaceRadius)

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

    static let openCurve = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let searchCurve = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let splitCurve = Animation.spring(response: 0.34, dampingFraction: 0.7)
    /// Quick and slightly loose, so the pill feels like it is being dragged
    /// rather than driven.
    static let slideCurve = Animation.spring(response: 0.26, dampingFraction: 0.74)

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
                .onHover { pointer(inList: $0) }
                // Without this the rows appear at full size the instant the
                // slab starts growing, which reads as a snap even though the
                // frame is animating underneath them.
                .transition(
                    .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.98, anchor: .bottom))
                )
            }
            row
                .onHover { pointer(inRow: $0) }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    guard width > 0 else { return }
                    collapsedWidth = width
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
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            guard !pointerInRow, !pointerInList, !isSearching else { return }
            withAnimation(Self.openCurve) { hovered = nil }
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

    /// Wakes the bar and restarts the quiet clock. Once it runs out, and only
    /// if nothing is being pointed at, pressed or typed into, the labels fold
    /// away and the bar dims to its resting state.
    private func settle() {
        guard idle.collapses else { return }
        idleTask?.cancel()
        if !labelsShown {
            withAnimation(idle.curve) { labelsShown = true }
        }
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: idle.delay)
            guard !Task.isCancelled else { return }
            guard !pointerInRow, !pointerInList, !isSearching, pressedItem == nil else { return }
            withAnimation(idle.curve) { labelsShown = false }
        }
    }

    private var expandedItem: Item? {
        guard let hovered,
              let item = items.first(where: { $0.id == hovered }),
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
            // Hover lightens the fill to paper, the same signal every row and
            // destination in the app uses.
            .barSurface(
                radius: Self.collapsedHeight / 2,
                fill: closeHovered ? Chamfer.Palette.paper : Chamfer.Palette.bar
            )
            .frame(width: isSplit ? Self.collapsedHeight : 0)
            .opacity(isSplit ? 1 : 0)
            .overlay(
                Circle()
                    .strokeBorder(Chamfer.Palette.ring, lineWidth: Chamfer.Palette.ringWidth)
                    .opacity(isSplit ? 1 : 0)
                    .allowsHitTesting(false)
            )
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

    private var field: some View {
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Chamfer.Space.roomy)
    }

    private func beginSearch() {
        Haptics.pop()
        cancelClose()
        withAnimation(Self.searchCurve) {
            hovered = nil
            isSearching = true
        }
        // The field only exists once the bubble is on screen.
        DispatchQueue.main.async { searchFocused = true }
    }

    private func endSearch() {
        Haptics.commit()
        searchFocused = false
        query = ""
        closeHovered = false
        withAnimation(Self.searchCurve) {
            isSplit = false
            isSearching = false
        }
    }

    /// Menu density: 12pt, 20pt rows, a rounded highlight under the pointer.
    /// The list is part of the bar, not a panel with its own voice.
    private func list(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(item.entries) { entry in
                ListRow(entry: entry)
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

    private struct ListRow: View {
        @State private var isHovered = false

        let entry: Entry

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
            .background(isHovered ? Chamfer.Palette.paper.opacity(0.75) : .clear)
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
                .background(isHovered ? Chamfer.Palette.paper.opacity(0.75) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small - 2, style: .continuous))
                .chamferHoverRing(isHovered, radius: Chamfer.Radius.small - 2)
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
                    showsLabel: labelsShown,
                    extraPadding: idle.activeExtraPadding,
                    onHover: { inside in
                        guard inside, !isSearching, pressedItem == nil else { return }
                        let opens = !item.entries.isEmpty || item.showsSearch
                        let next = opens ? item.id : nil
                        guard next != hovered else { return }
                        if next != nil, hovered == nil { Haptics.pop() }
                        withAnimation(Self.openCurve) { hovered = next }
                    }
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.rowSpace)) } action: { frame in
                    itemFrames[item.id] = frame
                }
            }
        }
        .padding(.horizontal, Chamfer.Space.tight + 1)
        .frame(height: labelsShown || isSearching ? Self.collapsedHeight : Self.idleHeight)
        .coordinateSpace(.named(Self.rowSpace))
        .overlay(alignment: .topLeading) { glassSlider }
        .gesture(slide)
    }

    /// The pill itself: real Liquid Glass, sized and placed from the measured
    /// frame of whichever destination the pointer is over.
    @ViewBuilder
    private var glassSlider: some View {
        if let pressedItem, let frame = itemFrames[pressedItem] {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
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
                withAnimation(Self.slideCurve) { pressedItem = landed }
            }
            .onEnded { value in
                guard !isSearching else { return }
                if let landed = item(at: value.location.x) {
                    Haptics.commit()
                    selection = landed
                }
                withAnimation(Self.slideCurve) { pressedItem = nil }
            }
    }

    /// Which destination sits under this x, by measured frame rather than by
    /// dividing the row into equal parts — the labels are different widths.
    private func item(at x: CGFloat) -> String? {
        itemFrames.first { $0.value.minX <= x && x <= $0.value.maxX }?.key
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
        /// room than its neighbours — the only thing that marks it.
        let isActive: Bool
        let showsLabel: Bool
        let extraPadding: CGFloat
        let onHover: (Bool) -> Void

        private static let labelFont = Font.system(size: 12.5, weight: .medium)
        private static let gap = Chamfer.Space.tight + 2

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
        }

        var body: some View {
            // The gap lives in the stack's spacing, not inside the label's
            // frame — folded into the frame it is counted against the text's
            // own width and clips the last glyph.
            HStack(spacing: showsLabel ? Self.gap : 0) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .regular))
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
            .foregroundStyle(Chamfer.Palette.textOnPaper)
            .padding(.horizontal, Chamfer.Space.regular - 1 + (isActive ? extraPadding : 0))
            .padding(.vertical, Chamfer.Space.tight)
            // The glass pill covers the fill while pressed, so the hover tint
            // would only muddy it.
            .background(isHovered && !isPressed ? Chamfer.Palette.paper.opacity(0.6) : .clear)
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
                .background(isHovered ? Chamfer.Palette.paper : Chamfer.Palette.bar)
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
