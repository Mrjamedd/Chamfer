import AppKit
import ChamferCore
import ChamferFixtures
import ChamferUI
import ChamferWatch
import SwiftUI

enum GallerySection: Hashable {
    case scenario(Scenario)
    case components
    /// The global defaults. In the shipping app these live in their own
    /// window behind Command-comma; here they are just another thing to look
    /// at, so the whole interface can be reviewed without switching apps.
    case settings
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct GalleryRootView: View {
    /// The harness answers Command-comma with the same `Settings` scene the app
    /// does, so the gutter's control has somewhere real to go. Without this the
    /// gear was drawn and did nothing here — a control that only works in one
    /// of the two builds is exactly what the harness exists to catch.
    @Environment(\.openSettings) private var openSettings

    private let selection: GallerySection
    private let dashboardState: DashboardState?
    private let editing: NoteEditingConfiguration?
    private let noteLoadError: String?

    init() {
        let selection = Launch.selection
        let store = ExampleNoteStore()

        self.selection = selection

        if case let .scenario(scenario) = selection {
            let launch = Self.loadDashboard(
                for: scenario,
                store: store
            )
            dashboardState = launch.state
            editing = launch.editing
            noteLoadError = launch.errorMessage
        } else {
            dashboardState = nil
            editing = nil
            noteLoadError = nil
        }
    }

    /// `swift run ChamferGallery --scenario flooded` opens straight into one
    /// state. Saves clicking through on every rebuild, and makes a screenshot
    /// of a given state reproducible.
    enum Launch {
        static var selection: GallerySection {
            guard let index = CommandLine.arguments.firstIndex(of: "--scenario"),
                  let raw = CommandLine.arguments[safe: index + 1]
            else { return .scenario(.typical) }
            if raw == "components" { return .components }
            if raw == "settings" { return .settings }
            return Scenario(rawValue: raw).map(GallerySection.scenario) ?? .scenario(.typical)
        }
    }

    var body: some View {
        ZStack {
            Chamfer.Palette.canvas.ignoresSafeArea()
            detail
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .environment(\.chamferNow, Fixtures.now)
    }

    /// Settings ships in a smaller window than the note one, so the harness
    /// shows it at that size rather than centring it in a field of cream —
    /// otherwise the gallery would be reviewing a composition the app never
    /// actually draws.
    private var windowSize: CGSize {
        switch selection {
        case .settings:
            CGSize(
                width: Chamfer.SettingsWindow.width,
                height: Chamfer.SettingsWindow.height
            )
        case .scenario, .components:
            CGSize(width: Chamfer.Window.width, height: Chamfer.Window.height)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case let .scenario(scenario):
            DashboardView(
                state: dashboardState ?? Fixtures.state(for: scenario),
                editing: editing,
                noteLoadError: noteLoadError,
                onClose: { NSApp.keyWindow?.close() },
                onOpenSettings: { openSettings() }
            )
        case .components:
            ComponentCatalog()
        case .settings:
            GallerySettingsHost()
        }
    }

    private struct DashboardLaunch {
        let state: DashboardState
        let editing: NoteEditingConfiguration?
        let errorMessage: String?
    }

    private static func loadDashboard(
        for scenario: Scenario,
        store: ExampleNoteStore
    ) -> DashboardLaunch {
        var state = Fixtures.state(for: scenario)
        guard state.openNote != nil else {
            return DashboardLaunch(
                state: state,
                editing: nil,
                errorMessage: nil
            )
        }

        do {
            let example = try store.loadOrCreate(
                seedText: Fixtures.openNote.text
            )

            state.openNote = example
            if let index = state.searchableNotes.firstIndex(where: {
                $0.url.lastPathComponent == Fixtures.openNote.url.lastPathComponent
            }) {
                state.searchableNotes[index] = example
            }

            return DashboardLaunch(
                state: state,
                editing: NoteEditingConfiguration(
                    documentURL: example.url
                ) { document in
                    try store.save(text: document.text)
                },
                errorMessage: nil
            )
        } catch {
            state.openNote = nil
            return DashboardLaunch(
                state: state,
                editing: nil,
                errorMessage: error.localizedDescription
            )
        }
    }
}


/// Holds the settings state the gallery has no model to keep it in.
///
/// The app owns this in `AppModel`; here it starts from the shipping defaults
/// so what you see on launch is exactly what a new install would show.
struct GallerySettingsHost: View {
    @State private var policy = RewritePolicy.standard
    @State private var preferences = AppPreferences.standard

    var body: some View {
        SettingsView(policy: $policy, preferences: $preferences)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
