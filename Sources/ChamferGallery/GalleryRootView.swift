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
    @State private var scheme = Launch.scheme

    /// `swift run ChamferGallery --scenario flooded --dark` opens straight
    /// into one state. Saves clicking through the sidebar on every rebuild,
    /// and makes a screenshot of a given state reproducible.
    enum Launch {
        static var selection: GallerySection {
            guard let index = CommandLine.arguments.firstIndex(of: "--scenario"),
                  let raw = CommandLine.arguments[safe: index + 1]
            else { return .scenario(.typical) }
            if raw == "components" { return .components }
            return Scenario(rawValue: raw).map(GallerySection.scenario) ?? .scenario(.typical)
        }

        static var scheme: ColorScheme {
            CommandLine.arguments.contains("--dark") ? .dark : .light
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .environment(\.chamferNow, Fixtures.now)
        .preferredColorScheme(scheme)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Appearance", selection: $scheme) {
                    Image(systemName: "sun.max").tag(ColorScheme.light)
                    Image(systemName: "moon").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("States") {
                ForEach(Scenario.allCases) { scenario in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scenario.title)
                        Text(scenario.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .tag(GallerySection.scenario(scenario))
                }
            }
            Section("System") {
                Text("Components").tag(GallerySection.components)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
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
