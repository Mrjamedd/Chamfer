import AppKit

/// Trackpad feedback for the moments where something appears or is dismissed.
///
/// Only fires on hardware with a Force Touch trackpad; on anything else these
/// calls are silently ignored, which is why there is no availability check.
public enum Haptics {
    /// Something popped out: the bar expanding, the sidebar appearing.
    public static func pop() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Something was dismissed or committed.
    public static func commit() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
