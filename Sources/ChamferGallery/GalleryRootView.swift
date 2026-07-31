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
    private let selection = Launch.selection

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
        ZStack {
            Chamfer.Palette.canvas.ignoresSafeArea()
            detail
        }
        .frame(width: Chamfer.Window.width, height: Chamfer.Window.height)
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
}
