import ChamferCore
import SwiftUI

private struct ChamferScanProgressKey: EnvironmentKey {
    static let defaultValue: ScanProgress? = nil
}

private struct ChamferNowKey: EnvironmentKey {
    /// The fallback for anything rendered outside a `LiveClock`.
    ///
    /// A `static let` is evaluated once per process, which is exactly what the
    /// gallery wants — fixture screenshots have to be reproducible — and
    /// exactly what the app does not: every "just now" in Review, History, the
    /// versions sheet and the menu bar stayed "just now" until the app was
    /// quit. `LiveClock` is what the app wraps around them instead.
    static let defaultValue = Date()
}

/// Keeps every relative timestamp beneath it honest.
///
/// One ticker for the whole subtree rather than a timer per row: a hundred
/// history entries each watching the clock is a hundred redraws a minute for a
/// label that changes four times an hour.
public struct LiveClock<Content: View>: View {
    private let interval: TimeInterval
    private let content: Content

    /// Half a minute. The shortest thing any of these labels distinguishes is a
    /// minute, so this is fast enough that no reading is ever wrong for long
    /// and slow enough to cost nothing.
    public init(every interval: TimeInterval = 30, @ViewBuilder content: () -> Content) {
        self.interval = interval
        self.content = content()
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            content.environment(\.chamferNow, context.date)
        }
    }
}

private struct ChamferSurfaceKey: EnvironmentKey {
    static let defaultValue = SurfaceMode.paper
}

private struct ChamferModelsRuntimeProbeKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// The "now" every relative timestamp is measured against.
    var chamferNow: Date {
        get { self[ChamferNowKey.self] }
        set { self[ChamferNowKey.self] = newValue }
    }

    /// The surface the current view is drawn on. Components recolour from this
    /// value without each one needing to know what contains it.
    var chamferSurface: SurfaceMode {
        get { self[ChamferSurfaceKey.self] }
        set { self[ChamferSurfaceKey.self] = newValue }
    }

    /// Whether the Models page may ask the runtime what is installed.
    ///
    /// Always true in the app. The design harness turns it off when it has been
    /// given a model situation to draw, so a machine with no Ollama can still
    /// show the downloading, ready and active states — otherwise the probe
    /// lands a moment after launch and overwrites every one of them with
    /// "not installed".
    var chamferModelsRuntimeProbe: Bool {
        get { self[ChamferModelsRuntimeProbeKey.self] }
        set { self[ChamferModelsRuntimeProbeKey.self] = newValue }
    }

    /// The vault currently being walked, and how far through it we are.
    ///
    /// Environment rather than a field on `DashboardState` because it is
    /// transient: it exists for the few seconds a sweep takes, belongs to no
    /// saved state, and must never be written to disk as though a sweep were
    /// still running after a relaunch.
    var chamferScanProgress: ScanProgress? {
        get { self[ChamferScanProgressKey.self] }
        set { self[ChamferScanProgressKey.self] = newValue }
    }
}
