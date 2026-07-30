import SwiftUI

/// The bar under the page: a tan slab of three destinations.
///
/// Hovering a destination that has entries grows the slab upward and lists
/// them, so you can see what is waiting without leaving the page you are on.
/// It grows out of its own layout bounds rather than pushing the page, which
/// would reflow the note under the pointer.
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

    // Proportioned off the reference: the slab is a little under four times
    // the cap height of its labels, not six.
    private static let collapsedHeight: CGFloat = 40
    private static let radius: CGFloat = 14
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

    public init(items: [Item], selection: Binding<String>) {
        self.items = items
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
            .barSurface(radius: Self.radius)

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
                withAnimation(Self.splitCurve) { isSplit = false }
            }
        }
        .onExitCommand(perform: endSearch)
        .fixedSize()
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

    static let openCurve = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let searchCurve = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let splitCurve = Animation.spring(response: 0.34, dampingFraction: 0.7)

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
    }

    private func pointer(inList: Bool) {
        pointerInList = inList
        inList ? cancelClose() : scheduleClose()
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
            .barSurface(radius: Self.collapsedHeight / 2)
            .frame(width: isSplit ? Self.collapsedHeight : 0)
            .opacity(isSplit ? 1 : 0)
            .contentShape(Circle())
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private var row: some View {
        HStack(spacing: Chamfer.Space.snug) {
            ForEach(items) { item in
                BarButton(
                    item: item,
                    isSelected: item.id == selection,
                    onHover: { inside in
                        guard inside, !isSearching else { return }
                        let opens = !item.entries.isEmpty || item.showsSearch
                        let next = opens ? item.id : nil
                        guard next != hovered else { return }
                        if next != nil, hovered == nil { Haptics.pop() }
                        withAnimation(Self.openCurve) { hovered = next }
                    },
                    action: { selection = item.id }
                )
            }
        }
        .padding(.horizontal, Chamfer.Space.snug)
        .frame(height: Self.collapsedHeight)
    }

    private struct BarButton: View {
        @State private var isHovered = false

        let item: Item
        let isSelected: Bool
        let onHover: (Bool) -> Void
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Chamfer.Space.snug - 1) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .regular))
                    Text(item.label)
                        .font(.system(size: 13, weight: .medium))
                }
                // Every destination reads the same weight and colour; the bar
                // is one slab, not a segmented control. Which page you are on
                // is obvious from the page itself.
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .padding(.horizontal, Chamfer.Space.regular + 2)
                .padding(.vertical, Chamfer.Space.tight + 2)
                // Only the pointer fills a destination. Nothing is marked as
                // selected: the reference bar has no selected state, and the
                // page already says which one you are on.
                .background(isHovered ? Chamfer.Palette.paper.opacity(0.6) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { inside in
                isHovered = inside
                onHover(inside)
            }
            .animation(Chamfer.Motion.quick, value: isHovered)
        }
    }
}

private extension View {
    /// The bar's material: tan fill, hairline edge, soft float. Shared so the
    /// field and the detached close button read as pieces of the same object.
    func barSurface(radius: CGFloat) -> some View {
        background(Chamfer.Palette.bar)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Chamfer.Palette.barStroke, lineWidth: 1)
            )
            .chamferFloat(radius: 20, y: 8, opacity: 0.14)
    }
}

/// The dismiss control that floats above the page, revealed on approach.
public struct FloatingCloseButton: View {
    @State private var isHovered = false

    private let action: () -> Void

    public init(action: @escaping () -> Void) {
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
        .chamferFloat(radius: 14, y: 6, opacity: 0.18)
        .onHover { isHovered = $0 }
        .animation(Chamfer.Motion.quick, value: isHovered)
    }
}
