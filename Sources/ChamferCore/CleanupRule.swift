import Foundation

/// One deterministic formatting fix.
///
/// Rules are pure: the same input always produces the same output, and a rule
/// never performs I/O. That is what makes it safe to apply them to a note
/// without asking the user first, and what makes them testable as golden files.
public protocol CleanupRule: Sendable {
    /// Stable identifier used in settings and in history entries.
    var identifier: String { get }

    /// Returns the corrected text, or the input unchanged when the rule does
    /// not apply.
    func apply(to text: String) -> String
}
