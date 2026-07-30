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
        /// Shown when this item is hovered. Empty means the bar stays closed.
        public let entries: [Entry]

        public init(id: String, symbol: String, label: String, entries: [Entry] = []) {
            self.id = id
            self.symbol = symbol
            self.label = label
            self.entries = entries
        }
    }

    @Binding private var selection: String
    @State private var hovered: String?

    private let items: [Item]

    private static let collapsedHeight: CGFloat = 62
    private static let radius: CGFloat = 22
    /// Close to the width of the destination row, so the status column lands
    /// near the slab's right edge instead of stranding empty space.
    private static let listWidth: CGFloat = 300

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
        VStack(spacing: 0) {
            if let entries = expandedEntries {
                list(entries)
                Rectangle()
                    .fill(Chamfer.Palette.barStroke.opacity(0.7))
                    .frame(height: 1)
                    .padding(.horizontal, Chamfer.Space.regular)
            }
            row
        }
        .background(Chamfer.Palette.bar)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Chamfer.Palette.barStroke, lineWidth: 1)
        )
        .chamferFloat(radius: 20, y: 8, opacity: 0.14)
        .fixedSize()
        .onHover { inside in
            if !inside { hovered = nil }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: hovered)
    }

    private var expandedEntries: [Entry]? {
        guard let hovered,
              let item = items.first(where: { $0.id == hovered }),
              !item.entries.isEmpty
        else { return nil }
        return item.entries
    }

    /// Menu density: 13pt, rows about 22pt tall, a rounded highlight under the
    /// pointer. The list is part of the bar, not a panel with its own voice.
    private func list(_ entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(entries) { entry in
                ListRow(entry: entry)
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
                    .font(.system(size: 13))
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Chamfer.Space.snug)
                Text(entry.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                    .lineLimit(1)
            }
            .padding(.horizontal, Chamfer.Space.snug)
            .padding(.vertical, Chamfer.Space.tight - 1)
            .frame(height: 22)
            .background(isHovered ? Chamfer.Palette.paper.opacity(0.75) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small - 2, style: .continuous))
            .contentShape(Rectangle())
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
                        guard inside else { return }
                        let next = item.entries.isEmpty ? nil : item.id
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
                HStack(spacing: Chamfer.Space.snug + 1) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .regular))
                    Text(item.label)
                        .font(.system(size: 15, weight: .medium))
                }
                // Every destination reads the same weight and colour; the bar
                // is one slab, not a segmented control. Which page you are on
                // is obvious from the page itself.
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .padding(.horizontal, Chamfer.Space.roomy)
                .padding(.vertical, Chamfer.Space.regular)
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
