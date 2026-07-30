import Foundation

/// A local language model that improves a passage of prose.
///
/// The protocol is the seam that keeps the backend undecided. Foundation
/// Models is the first implementation; Ollama or a bundled MLX model can be
/// added later without anything else in the app changing.
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
