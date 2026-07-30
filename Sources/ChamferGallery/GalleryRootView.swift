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

struct GalleryRootView: View {
    @State private var selection = Launch.selection

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
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .environment(\.chamferNow, Fixtures.now)
    }

    private var sidebar: some View {
        ZStack {
            Chamfer.Palette.canvasDeep.ignoresSafeArea()
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
                // Room for the glow to bloom without being clipped by the
                // scroll view's bounds.
                .padding(Chamfer.Space.roomy)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 340)
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
}

/// Same hover language as the cards: rises, keeps its beige, blooms pink.
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
        .chamferHoverGlow(isActive: isHovered, cornerRadius: Chamfer.Radius.medium, lift: 3)
        .onHover { isHovered = $0 }
    }
}
