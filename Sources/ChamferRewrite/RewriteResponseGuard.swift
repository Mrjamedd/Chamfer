import ChamferCore
import Foundation

/// The deterministic check on one model answer, run before anything is
/// reassembled. It is not a request to the model and cannot be talked out of.
enum RewriteResponseGuard {
    private static let placeholder = try! NSRegularExpression(
        pattern: #"\{\{CHAMFER-[0-9]+\}\}"#
    )

    /// A fence marker echoed back into the answer. The token is generated per
    /// request, so this pattern matches the shape rather than any fixed string
    /// — an answer that contains one is quoting the scaffolding rather than
    /// replacing the passage.
    private static let echoedBoundary = try! NSRegularExpression(
        pattern: #"<<<CHAMFER-[A-Z0-9]+:(?:END-)?(?:EDIT|CONTEXT|ORIGINAL|PROPOSED)>>>"#
    )

    private static let modelArtifacts = [
        #"(?is)^\s*I (?:cannot|can't|can not|do not have access)\b.{0,120}\b(?:edit|rewrite|comply|assist|follow|process|help)\b"#,
        #"(?i)^\s*I have reviewed the note\b"#,
        #"(?i)^\s*(?:Here(?:'s| is) (?:the )?(?:edited|revised|corrected)|Sure[,!])"#,
        #"(?im)^\s*(?:tool|prompt)\s*:"#,
        #"(?i)[\"']?tool_?calls?[\"']?\s*:"#,
        // The passage was answered rather than edited: the model has adopted a
        // role the document described, or acknowledged an order inside it.
        #"(?im)^\s*(?:Understood|Acknowledged|Got it|Certainly|Of course)\b[.,!]"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func inspect(original: String, candidate: String) -> RewriteFailure? {
        let expected = placeholders(in: original)
        let returned = placeholders(in: candidate)
        guard returned.isSubset(of: expected) else {
            return .localModelFailed(
                detail: "The model invented a protected placeholder, so the rewrite was discarded."
            )
        }

        if matches(echoedBoundary, candidate), !matches(echoedBoundary, original) {
            return .localModelFailed(
                detail: "The model returned Chamfer's own document markers instead of the edited passage, so the rewrite was discarded."
            )
        }

        for expression in modelArtifacts
        where matches(expression, candidate) && !matches(expression, original) {
            return .localModelFailed(
                detail: "The model returned commentary or a tool-style response instead of an edit, so the rewrite was discarded."
            )
        }
        return nil
    }

    /// Strips the fence markers a model may have wrapped its answer in.
    ///
    /// Deliberately narrow: only a marker on a line of its own is removed. A
    /// marker embedded in prose is left for `inspect` to reject, because at
    /// that point the answer is not a passage with decoration around it.
    static func removingBoundaryMarkers(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let kept = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return true }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = echoedBoundary.firstMatch(in: trimmed, range: range) else {
                return true
            }
            return match.range.length != range.length
        }
        guard kept.count != lines.count else { return text }
        return kept.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func placeholders(in text: String) -> Set<String> {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(placeholder.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        })
    }

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ) != nil
    }
}
