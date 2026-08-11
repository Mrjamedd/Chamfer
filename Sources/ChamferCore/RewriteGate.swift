import Foundation

/// The check every model result has to pass before it is allowed near a file.
///
/// A language model is not trusted to have respected the masking, the mode, or
/// the user's preservation settings — not because it usually fails, but because
/// the cost of the one time it does is a corrupted note. Everything here is a
/// cheap, deterministic check on two strings, and anything that fails is
/// discarded whole rather than partially applied.
public enum RewriteGate {
    /// How far the length may move before the result is treated as a different
    /// document rather than a corrected one.
    ///
    /// Wide, because clarity mode legitimately shortens and formatting mode
    /// legitimately lengthens. It is not tuned to catch small mistakes; it is
    /// there to catch a model that returned a summary, an apology, or a single
    /// sentence where a page went in.
    public static let minimumLengthRatio = 0.55
    public static let maximumLengthRatio = 1.8

    /// Below this, ratio checks stop meaning anything — one word becoming two
    /// is a 100% increase and entirely legitimate.
    public static let lengthCheckFloor = 120

    /// Runs every check, in the order that gives the most useful failure.
    ///
    /// - Parameters:
    ///   - original: the note as it was, unmasked.
    ///   - candidate: what came back, already unmasked.
    ///   - preserved: what the user asked to be left alone.
    public static func inspect(
        original: String,
        candidate: String,
        preserved: MarkdownStructure
    ) -> RewriteFailure? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .localModelFailed(detail: "The model returned nothing.")
        }

        if let failure = lengthFailure(original: original, candidate: candidate) {
            return failure
        }

        let violated = violations(
            original: original,
            candidate: candidate,
            preserved: preserved
        )
        guard violated.isEmpty else {
            return .preservationViolated(violated)
        }

        return nil
    }

    /// Which protected structures came back a different shape.
    ///
    /// Counted rather than compared exactly. A heading whose wording improved
    /// is still a heading, and the promise the user made settings about is
    /// structural — "do not remove my headings", not "do not touch these
    /// words". Counting catches the failure that matters (things vanishing or
    /// multiplying) without forbidding the edit they asked for.
    public static func violations(
        original: String,
        candidate: String,
        preserved: MarkdownStructure
    ) -> MarkdownStructure {
        var violated: MarkdownStructure = []

        for (structure, count) in [
            (MarkdownStructure.headings, countHeadings),
            (.lists, countListItems),
            (.taskCheckboxes, countTasks),
            (.codeBlocks, countCodeFences),
            (.links, countLinks),
            (.images, countImages),
            (.embeds, countEmbeds)
        ] as [(MarkdownStructure, (String) -> Int)] {
            guard preserved.contains(structure) else { continue }
            if count(original) != count(candidate) {
                violated.insert(structure)
            }
        }

        if preserved.contains(.frontMatter),
           frontMatter(of: original) != frontMatter(of: candidate) {
            violated.insert(.frontMatter)
        }

        return violated
    }

    private static func lengthFailure(
        original: String,
        candidate: String
    ) -> RewriteFailure? {
        guard original.count >= lengthCheckFloor else { return nil }
        let ratio = Double(candidate.count) / Double(original.count)
        guard ratio < minimumLengthRatio || ratio > maximumLengthRatio else {
            return nil
        }
        let direction = ratio < minimumLengthRatio ? "shorter" : "longer"
        return .localModelFailed(
            detail: "The rewrite came back dramatically \(direction) than the note, so it was discarded."
        )
    }

    // MARK: - Counting

    static func countHeadings(_ text: String) -> Int {
        count(in: text) { $0.hasPrefix("#") && $0.drop { $0 == "#" }.first == " " }
    }

    static func countListItems(_ text: String) -> Int {
        count(in: text) { line in
            guard let first = line.first else { return false }
            if ["-", "*", "+"].contains(String(first)) {
                return line.dropFirst().first == " "
            }
            let digits = line.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 3 else { return false }
            let rest = line.dropFirst(digits.count)
            guard let marker = rest.first, marker == "." || marker == ")" else {
                return false
            }
            return rest.dropFirst().first == " "
        }
    }

    static func countTasks(_ text: String) -> Int {
        count(in: text) { line in
            guard let first = line.first, ["-", "*", "+"].contains(String(first)) else {
                return false
            }
            let rest = line.dropFirst().drop { $0 == " " }
            guard rest.hasPrefix("[") else { return false }
            let inner = rest.dropFirst()
            guard let marker = inner.first, inner.dropFirst().first == "]" else {
                return false
            }
            return " xX/-".contains(marker)
        }
    }

    static func countCodeFences(_ text: String) -> Int {
        count(in: text) { $0.hasPrefix("```") || $0.hasPrefix("~~~") }
    }

    /// Links only — the leading-`!` lookbehind is what keeps an image from
    /// being counted here as well as in `countImages`, which would make every
    /// note containing one look as though a link had appeared from nowhere.
    static func countLinks(_ text: String) -> Int {
        occurrences(of: "(?<!!)\\[[^\\]\\n]*\\]\\([^)\\n]*\\)", in: text)
            + occurrences(of: "(?<!!)\\[\\[[^\\]\\n]*\\]\\]", in: text)
    }

    static func countImages(_ text: String) -> Int {
        occurrences(of: "!\\[[^\\]\\n]*\\]\\([^)\\n]*\\)", in: text)
    }

    static func countEmbeds(_ text: String) -> Int {
        occurrences(of: "!\\[\\[[^\\]\\n]*\\]\\]", in: text)
    }

    /// The front-matter block verbatim, or nil when the note has none.
    ///
    /// Compared exactly rather than counted: front matter is machine-read by
    /// whatever else touches these notes, and a model rephrasing a tag is a
    /// silent data change even though it looks like an improvement.
    static func frontMatter(of text: String) -> String? {
        for fence in ["---", "+++"] where text.hasPrefix(fence + "\n") {
            let afterOpening = text.index(text.startIndex, offsetBy: fence.count + 1)
            guard let closing = text.range(
                of: "\n" + fence,
                range: afterOpening..<text.endIndex
            ) else { continue }
            return String(text[text.startIndex..<closing.upperBound])
        }
        return nil
    }

    private static func count(
        in text: String,
        where predicate: (Substring) -> Bool
    ) -> Int {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(into: 0) { total, line in
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if predicate(trimmed) { total += 1 }
            }
    }

    private static func occurrences(of pattern: String, in text: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }
        return expression.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }
}
