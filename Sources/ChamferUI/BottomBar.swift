import SwiftUI

/// The floating bar: a beige capsule sitting over the page.
public struct BottomBar: View {
    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        public let symbol: String
        public let label: String

        public init(id: String, symbol: String, label: String) {
            self.id = id
            self.symbol = symbol
            self.label = label
        }
    }

    @Binding private var selection: String

    private let items: [Item]

    public init(items: [Item], selection: Binding<String>) {
        self.items = items
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: Chamfer.Space.tight) {
            ForEach(items) { item in
                BarButton(item: item, isSelected: item.id == selection) {
                    selection = item.id
                }
            }
        }
        .padding(Chamfer.Space.tight + 1)
        .background(Chamfer.Palette.paperSunken)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Chamfer.Palette.paperStroke.opacity(0.8), lineWidth: 1))
        .chamferFloat(radius: 22, y: 10, opacity: 0.16)
    }

    private struct BarButton: View {
        @State private var isHovered = false

        let item: Item
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Chamfer.Space.snug) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .medium))
                    Text(item.label)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .padding(.horizontal, Chamfer.Space.roomy)
                .padding(.vertical, Chamfer.Space.snug + 2)
                .background(background)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(Chamfer.Motion.quick, value: isHovered)
        }

        private var background: Color {
            if isSelected {
                Chamfer.Palette.paper
            } else if isHovered {
                Chamfer.Palette.paper.opacity(0.5)
            } else {
                .clear
            }
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
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .frame(width: 32, height: 32)
                .background(isHovered ? Chamfer.Palette.paper : Chamfer.Palette.paperSunken)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Chamfer.Palette.paperStroke.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .chamferFloat(radius: 14, y: 6, opacity: 0.18)
        .onHover { isHovered = $0 }
        .animation(Chamfer.Motion.quick, value: isHovered)
    }
}
