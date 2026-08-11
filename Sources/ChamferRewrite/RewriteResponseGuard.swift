import ChamferCore
import Foundation

/// The deterministic check on one model answer, run before anything is
/// reassembled. It is not a request to the model and cannot be talked out of.
enum RewriteResponseGuard {
    private static let placeholder = try! NSRegularExpression(
        pattern: #"\{\{KEEP[0-9]+\}\}"#
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
        // A dropped placeholder is as wrong as an invented one, and used to pass
        // here because the empty set is a subset of everything. It then failed
        // later, at reassembly, where the only remaining move is to discard the
        // whole note's rewrite. Caught here, a checking pass that ate a heading
        // marker is simply not believed, and the answer it was checking — which
        // still has every placeholder — is what gets kept.
        guard returned == expected else {
            return .localModelFailed(
                detail: "The model dropped a protected region — a heading, list marker, link or similar — so the rewrite was discarded."
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

    /// Whether every word in `text` came from one of `sources`.
    ///
    /// The checking stage is given two passages and asked to write one of them,
    /// or a blend of the two. That means it cannot legitimately introduce a word
    /// that appears in neither — and an answer that does is not a check that
    /// went too far, it is a check that stopped reading its input. The failure
    /// this catches was verbatim: asked about one sentence, the model wrote back
    /// a sentence from the worked example in its own prompt.
    ///
    /// The cost is real and deliberate. A checking pass can no longer add a fix
    /// the editing pass missed, because that fix would be a new word. Choosing
    /// between what it was given is the job it was asked to do; finding new
    /// corrections is the job of the pass before it.
    static func isComposed(_ text: String, of sources: [String]) -> Bool {
        let allowed = sources.reduce(into: Set<String>()) { $0.formUnion(words(in: $1)) }
        return words(in: text).isSubset(of: allowed)
    }

    /// Whether `reviewed` is the proposal with some of its changes undone, and
    /// nothing else.
    ///
    /// The checking stage has exactly one legitimate move: take a change the
    /// editing pass made and put the original back. It cannot improve on the
    /// proposal, cannot make a different correction, and cannot decide half of
    /// a change is right — every position in its answer has to hold either what
    /// the original said there or what the proposal said there.
    ///
    /// Prose alone could not hold it to that. Asked to adjudicate, this model
    /// reverted a clean `teh → the` outright; told firmly not to, it started
    /// reverting *half* a correction, leaving "The reports are ready and was
    /// sent yesterday" — a sentence neither the author nor the editing pass
    /// ever wrote. A rule the model cannot break is the only version of this
    /// that has held.
    ///
    /// When the three texts do not tokenise to the same shape — clarity and
    /// full cleanup legitimately change how many words there are — there is no
    /// position to compare, so the only answer accepted is the proposal
    /// unchanged. The check keeps its veto and loses its pen.
    static func onlyReverts(
        _ reviewed: String,
        from proposal: String,
        towards original: String
    ) -> Bool {
        if reviewed == proposal { return true }

        let reviewedTokens = tokens(in: reviewed)
        let proposalTokens = tokens(in: proposal)
        let originalTokens = tokens(in: original)
        guard reviewedTokens.count == proposalTokens.count,
              proposalTokens.count == originalTokens.count else { return false }

        return zip(reviewedTokens, zip(originalTokens, proposalTokens))
            .allSatisfy { reviewed, pair in
                reviewed == pair.0 || reviewed == pair.1
            }
    }

    /// Alternating words and the runs of everything between them, so a
    /// comparison can be positional rather than set-based.
    private static func tokens(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var buildingWord: Bool?

        for character in text {
            let isWord = character.isLetter || character.isNumber
            if buildingWord == nil { buildingWord = isWord }
            if isWord == buildingWord {
                current.append(character)
            } else {
                result.append(current)
                current = String(character)
                buildingWord = isWord
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
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
