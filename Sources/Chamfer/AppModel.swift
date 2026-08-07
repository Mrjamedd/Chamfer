import ChamferCore
import Foundation
import Observation

/// The one place the app's state lives.
///
/// Everything the interface renders hangs off `DashboardState`, exactly as the
/// design intended: fixtures fill it today, the watcher fills it later, and no
/// view changes in between. Settings and preferences sit alongside it rather
/// than inside it because they outlive any particular vault.
@MainActor
@Observable
final class AppModel {
    var dashboard: DashboardState
    var preferences: AppPreferences

    /// Kept on `dashboard` so vault and folder overrides resolve against it
    /// without anything having to reach across to the model.
    var globalPolicy: RewritePolicy {
        get { dashboard.globalPolicy }
        set { dashboard.globalPolicy = newValue }
    }

    init(
        dashboard: DashboardState = .empty,
        preferences: AppPreferences = .standard
    ) {
        self.dashboard = dashboard
        self.preferences = preferences
    }

    var pendingCount: Int { dashboard.pendingProposals.count }

    var isPaused: Bool { dashboard.runState == .paused }

    /// Pausing stops new work being picked up. It is deliberately not the same
    /// as quitting: the scope is explicit that quitting stops monitoring
    /// altogether, and a pause that survived a quit would be a promise the app
    /// cannot keep.
    func togglePause() {
        dashboard.runState = isPaused ? .idle : .paused
    }

    /// The model that will actually run, after the app-wide local-only switch
    /// has had its say. Nil means the user's settings rule out every option,
    /// which the interface reports rather than quietly resolving to the cloud.
    var effectiveModelID: String? {
        ProcessingGuard.permittedModel(for: globalPolicy, preferences: preferences)
    }
}

extension DashboardState {
    static let empty = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: []
    )
}
