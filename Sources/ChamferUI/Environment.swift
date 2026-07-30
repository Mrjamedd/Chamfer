import SwiftUI

private struct ChamferNowKey: EnvironmentKey {
    /// Evaluated once per launch, so relative times stay stable while a window
    /// is open. The gallery overrides it with the fixture clock.
    static let defaultValue = Date()
}

private struct ChamferSurfaceKey: EnvironmentKey {
    static let defaultValue = SurfaceMode.paper
}

public extension EnvironmentValues {
    /// The "now" every relative timestamp is measured against.
    var chamferNow: Date {
        get { self[ChamferNowKey.self] }
        set { self[ChamferNowKey.self] = newValue }
    }

    /// The surface the current view is drawn on. `Card` flips this to `.ink`
    /// while hovered, and every component inside recolours itself.
    var chamferSurface: SurfaceMode {
        get { self[ChamferSurfaceKey.self] }
        set { self[ChamferSurfaceKey.self] = newValue }
    }
}
