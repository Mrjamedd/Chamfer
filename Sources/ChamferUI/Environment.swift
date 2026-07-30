import SwiftUI

private struct ChamferNowKey: EnvironmentKey {
    /// Evaluated once per launch, so relative times stay stable while a window
    /// is open. The gallery overrides it with the fixture clock.
    static let defaultValue = Date()
}

public extension EnvironmentValues {
    /// The "now" every relative timestamp is measured against.
    var chamferNow: Date {
        get { self[ChamferNowKey.self] }
        set { self[ChamferNowKey.self] = newValue }
    }
}
