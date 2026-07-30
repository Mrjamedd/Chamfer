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
    @State private var query = ""
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
    /// The right-hand strip of the field that splits the close button off.
    private static let splitZone: CGFloat = 96

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

    private var slab: some View {
        Group {
            if isSearching {
                searchLayer
            } else {
                destinations
                    .barSurface(radius: Self.radius)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
            }
        }
        .fixedSize()
        // Searching lifts the bar clear of the bottom edge so the field sits
        // where you are looking rather than at the foot of the window.
        .offset(y: isSearching ? -Self.searchLift : 0)
        .onHover { inside in
            if !inside, !isSearching { hovered = nil }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: hovered)
        .animation(.spring(response: 0.48, dampingFraction: 0.76), value: isSearching)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isSplit)
    }

    private var destinations: some View {
        VStack(spacing: 0) {
            if let item = expandedItem {
                list(item)
                Rectangle()
                    .fill(Chamfer.Palette.barStroke.opacity(0.7))
                    .frame(height: 1)
                    .padding(.horizontal, Chamfer.Space.regular)
            }
            row
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

    /// The field, and — once the pointer reaches the right-hand end — a close
    /// button that detaches from it into its own circle. The pair always
    /// occupies the same total width, so the field gives up exactly the space
    /// the circle takes and nothing jumps sideways.
    private var searchLayer: some View {
        HStack(spacing: isSplit ? Chamfer.Space.snug + 2 : 0) {
            field
                .frame(width: fieldWidth, height: Self.collapsedHeight)
                .barSurface(radius: Self.radius)
            if isSplit {
                Button(action: endSearch) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                        .frame(width: Self.collapsedHeight, height: Self.collapsedHeight)
                }
                .buttonStyle(.plain)
                .barSurface(radius: Self.collapsedHeight / 2)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: Self.searchWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onContinuousHover { hover in
            switch hover {
            case let .active(location):
                let near = location.x > Self.searchWidth - Self.splitZone
                if near, !isSplit { Haptics.pop() }
                isSplit = near
            case .ended:
                isSplit = false
            }
        }
        .onExitCommand(perform: endSearch)
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
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
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .focused($searchFocused)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Chamfer.Space.roomy)
    }

    private func beginSearch() {
        Haptics.pop()
        hovered = nil
        isSearching = true
        // The field only exists once the bubble is on screen.
        DispatchQueue.main.async { searchFocused = true }
    }

    private func endSearch() {
        Haptics.commit()
        searchFocused = false
        query = ""
        isSplit = false
        isSearching = false
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
                        if next != nil, hovered == nil { Haptics.pop() }
                        hovered = next
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
