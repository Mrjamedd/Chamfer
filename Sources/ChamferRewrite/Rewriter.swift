import Foundation

/// A language-model backend that improves a passage of prose.
///
/// The protocol is the seam that keeps the backend undecided. Foundation
/// Apple Foundation Models, Ollama, and supported cloud providers all satisfy
/// this seam, so the cleanup pipeline does not handle credentials or HTTP.
public protocol Rewriter: Sendable {
    /// Whether this backend is usable right now, e.g. whether Apple
    /// Intelligence is enabled on this Mac.
    var isAvailable: Bool { get async }

    /// Returns an improved version of `section`, preserving meaning.
    ///
    /// Callers pass one section at a time with code, frontmatter and links
    /// already masked. Implementations must not be trusted to respect that on
    /// their own — the sanity gate in `ChamferCore` checks the result.
    func rewrite(_ section: String) async throws -> String
}
