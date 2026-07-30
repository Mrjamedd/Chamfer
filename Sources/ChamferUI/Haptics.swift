import AppKit

/// Trackpad feedback for the moments where something appears or is dismissed.
///
/// Only fires on hardware with a Force Touch trackpad; on anything else these
/// calls are silently ignored, which is why there is no availability check.
@MainActor
public enum Haptics {
    /// Feedback is a punctuation mark, never a texture. Anything arriving
    /// inside this window of the last pulse is dropped, so a hover that
    /// flickers can never turn into a burst against the user's hand.
    private static let minimumInterval: TimeInterval = 0.25
    private static var lastFired = Date.distantPast

    /// Something popped out: the bar expanding, the sidebar appearing.
    public static func pop() {
        fire(.alignment)
    }

    /// Something was dismissed or committed.
    public static func commit() {
        fire(.levelChange)
    }

    private static func fire(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        let now = Date()
        guard now.timeIntervalSince(lastFired) >= minimumInterval else { return }
        lastFired = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
