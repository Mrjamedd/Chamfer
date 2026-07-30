import ChamferFixtures
import ChamferUI
import SwiftUI

enum GallerySection: Hashable {
    case scenario(Scenario)
    case components
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// How far out the scenario panel is.
enum SidebarPhase {
    /// Out of sight entirely.
    case hidden
    /// Popped out far enough to be noticed and clicked.
    case peeking
    /// Fully out.
    case open
}

struct GalleryRootView: View {
    @State private var selection = Launch.selection
    @State private var phase = SidebarPhase.hidden

    private static let width: CGFloat = 290
    private static let peek: CGFloat = 62

    /// `swift run ChamferGallery --scenario flooded` opens straight into one
    /// state. Saves clicking through on every rebuild, and makes a screenshot
    /// of a given state reproducible.
    enum Launch {
        static var selection: GallerySection {
            guard let index = CommandLine.arguments.firstIndex(of: "--scenario"),
                  let raw = CommandLine.arguments[safe: index + 1]
            else { return .scenario(.typical) }
            if raw == "components" { return .components }
            return Scenario(rawValue: raw).map(GallerySection.scenario) ?? .scenario(.typical)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Chamfer.Palette.canvas.ignoresSafeArea()
            detail
            edgeSensor
            panel
        }
        .environment(\.chamferNow, Fixtures.now)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case let .scenario(scenario):
            DashboardView(state: Fixtures.state(for: scenario))
        case .components:
            ComponentCatalog()
        }
    }

    /// A strip along the window's left edge. Brushing it pops the panel out.
    private var edgeSensor: some View {
        Color.clear
            .frame(width: 20)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside, phase == .hidden else { return }
                withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                    phase = .peeking
                }
            }
            .allowsHitTesting(phase == .hidden)
    }

    private var panel: some View {
        SidebarPanel(selection: $selection)
            .frame(width: Self.width)
            .offset(x: offset)
            .overlay {
                // While peeking, the whole sliver is one target: clicking it
                // brings the panel the rest of the way out rather than
                // selecting whatever row happens to be under the pointer.
                if phase == .peeking {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                phase = .open
                            }
                        }
                }
            }
            .onHover { inside in
                guard !inside, phase != .hidden else { return }
                withAnimation(.easeOut(duration: 0.22)) { phase = .hidden }
            }
    }

    private var offset: CGFloat {
        switch phase {
        case .hidden: -(Self.width + 30)
        case .peeking: -(Self.width - Self.peek)
        case .open: 0
        }
    }
}

private struct SidebarPanel: View {
    @Binding var selection: GallerySection

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
                    SectionHeader("States")
                        .padding(.bottom, Chamfer.Space.tight)
                    ForEach(Scenario.allCases) { scenario in
                        SidebarRow(
                            title: scenario.title,
                            note: scenario.note,
                            isSelected: selection == .scenario(scenario)
                        ) {
                            selection = .scenario(scenario)
                        }
                    }
                    SectionHeader("System")
                        .padding(.top, Chamfer.Space.roomy)
                        .padding(.bottom, Chamfer.Space.tight)
                    SidebarRow(
                        title: "Components",
                        note: "Every component, on paper and on ink.",
                        isSelected: selection == .components
                    ) {
                        selection = .components
                    }
                }
                .padding(Chamfer.Space.roomy)
                .padding(.top, Chamfer.Space.section)
            }
            .scrollContentBackground(.hidden)

            // The grip on the outer edge, so the sliver reads as something to
            // pull rather than as a stray rectangle.
            Capsule()
                .fill(Chamfer.Palette.paperStroke)
                .frame(width: 4, height: 42)
                .padding(.trailing, Chamfer.Space.snug)
        }
        .background(Chamfer.Palette.canvasDeep)
        .clipShape(
            UnevenRoundedRectangle(
                bottomTrailingRadius: Chamfer.Radius.large,
                topTrailingRadius: Chamfer.Radius.large,
                style: .continuous
            )
        )
        .chamferFloat(radius: 26, y: 0, opacity: 0.18)
    }
}

struct SidebarRow: View {
    @State private var isHovered = false

    let title: String
    let note: String
    let isSelected: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(title)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                Text(note)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Chamfer.Space.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Chamfer.Palette.paper : Chamfer.Palette.paper.opacity(0.5))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? Chamfer.Palette.brass.opacity(0.55) : Chamfer.Palette.paperStroke.opacity(0.6),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .chamferHoverLift(isActive: isHovered, lift: 3)
        .onHover { isHovered = $0 }
    }
}
