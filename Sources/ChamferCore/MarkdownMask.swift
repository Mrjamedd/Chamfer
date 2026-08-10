import Foundation

/// A note with its protected parts lifted out.
///
/// The model never sees a URL, a code fence, or a block of front matter. It
/// sees a placeholder where each one was, and the placeholder is put back
/// afterwards — byte for byte, from the original, so there is no path by which
/// a model's opinion about a link target can reach the file.
public struct MaskedText: Sendable, Equatable {
    /// What the model is given.
    public let masked: String
    /// Placeholder token to the exact original text it stands for.
    public let replacements: [String: String]

    public init(masked: String, replacements: [String: String]) {
        self.masked = masked
        self.replacements = replacements
    }

    /// Puts the originals back.
    ///
    /// Returns nil when a placeholder the mask created is missing from `text`,
    /// or appears more than once. That is the model having eaten or duplicated
    /// something it was not shown, and the only safe response is to discard the
    /// whole rewrite — a note with one link silently deleted is worse than a
    /// note that was not improved.
    public func unmask(_ text: String) -> String? {
        var result = text
        for (token, original) in replacements.sorted(by: { $0.key > $1.key }) {
            let parts = result.components(separatedBy: token)
            guard parts.count == 2 else { return nil }
            result = parts[0] + original + parts[1]
        }
        return result
    }

    /// Which placeholders `text` has lost or duplicated. Empty means intact.
    public func brokenTokens(in text: String) -> [String] {
        replacements.keys.filter {
            text.components(separatedBy: $0).count != 2
        }
        .sorted()
    }
}

/// Lifting the parts of a note a rewrite has no business editing.
///
/// What gets masked is not fixed: it follows the user's `MarkdownStructure`
/// preservation settings, because formatting mode exists precisely to reflow
/// headings and lists and would be a no-op if those were always protected.
/// What is *always* masked is the set of things that are addresses and payloads
/// rather than prose — a URL is not writing, and no rewrite mode improves one.
public enum MarkdownMask {
    /// Chosen to survive a language model unchanged. Braces are rare in prose,
    /// the token is plain ASCII, and it carries no Markdown meaning that a
    /// model might feel invited to tidy up.
    static func token(_ index: Int) -> String { "{{CHAMFER-\(index)}}" }

    /// Ranges of the note that must not be shown to the model, in order.
    private struct Region {
        let range: Range<String.Index>
        /// Regions inside another region are dropped: a link inside a code
        /// fence is already protected by the fence.
        let priority: Int
    }

    public static func apply(
        to text: String,
        preserving structure: MarkdownStructure
    ) -> MaskedText {
        var regions: [Region] = []

        if structure.contains(.frontMatter) {
            regions.append(contentsOf: frontMatterRegions(in: text))
        }
        if structure.contains(.codeBlocks) {
            regions.append(contentsOf: codeRegions(in: text))
        }
        if structure.contains(.embeds) {
            regions.append(contentsOf: matches(of: Patterns.embed, in: text, priority: 2))
        }
        if structure.contains(.images) {
            regions.append(contentsOf: matches(of: Patterns.image, in: text, priority: 2))
        }
        if structure.contains(.links) {
            regions.append(contentsOf: matches(of: Patterns.wikiLink, in: text, priority: 2))
            // Only the target is masked, so a typo in the visible link text is
            // still something a rewrite is allowed to fix.
            regions.append(contentsOf: matches(of: Patterns.linkTarget, in: text, priority: 3))
            regions.append(contentsOf: matches(of: Patterns.bareURL, in: text, priority: 3))
        }
        if structure.contains(.taskCheckboxes) {
            regions.append(contentsOf: matches(of: Patterns.taskMarker, in: text, priority: 3))
        }
        if structure.contains(.metadata) {
            regions.append(contentsOf: matches(of: Patterns.tag, in: text, priority: 3))
            regions.append(contentsOf: matches(of: Patterns.inlineField, in: text, priority: 3))
        }
        if structure.contains(.headings) {
            regions.append(contentsOf: matches(of: Patterns.headingMarker, in: text, priority: 3))
        }
        if structure.contains(.lists) {
            regions.append(contentsOf: matches(of: Patterns.listMarker, in: text, priority: 3))
        }

        return build(from: text, regions: regions)
    }

    // MARK: - Assembling

    private static func build(from text: String, regions: [Region]) -> MaskedText {
        let ordered = flatten(regions)
        guard !ordered.isEmpty else {
            return MaskedText(masked: text, replacements: [:])
        }

        var masked = ""
        var replacements: [String: String] = [:]
        var cursor = text.startIndex

        for (index, region) in ordered.enumerated() {
            masked += text[cursor..<region.range.lowerBound]
            let placeholder = token(index)
            masked += placeholder
            replacements[placeholder] = String(text[region.range])
            cursor = region.range.upperBound
        }
        masked += text[cursor...]

        return MaskedText(masked: masked, replacements: replacements)
    }

    /// Sorts regions and drops any that sit inside another.
    ///
    /// Overlap is the normal case rather than the exception — every link inside
    /// a code fence produces one — and two placeholders written over the same
    /// bytes would corrupt the note on the way back.
    private static func flatten(_ regions: [Region]) -> [Region] {
        let sorted = regions.sorted { left, right in
            if left.range.lowerBound != right.range.lowerBound {
                return left.range.lowerBound < right.range.lowerBound
            }
            // A longer region at the same start wins, so the fence beats the
            // link that begins with it.
            if left.range.upperBound != right.range.upperBound {
                return left.range.upperBound > right.range.upperBound
            }
            return left.priority < right.priority
        }

        var kept: [Region] = []
        for region in sorted {
            if let last = kept.last, region.range.lowerBound < last.range.upperBound {
                continue
            }
            kept.append(region)
        }
        return kept
    }

    // MARK: - Regions

    /// Front matter is only front matter when it opens the file. The same fence
    /// three paragraphs down is a horizontal rule.
    private static func frontMatterRegions(in text: String) -> [Region] {
        for fence in ["---", "+++"] where text.hasPrefix(fence + "\n") {
            let afterOpening = text.index(text.startIndex, offsetBy: fence.count + 1)
            guard let closing = text.range(
                of: "\n" + fence,
                range: afterOpening..<text.endIndex
            ) else { continue }
            return [Region(range: text.startIndex..<closing.upperBound, priority: 0)]
        }
        return []
    }

    /// Fenced blocks first, then inline spans. An indented code block is
    /// deliberately not detected: four spaces is also how people indent a
    /// wrapped list item, and masking those would freeze half the note.
    private static func codeRegions(in text: String) -> [Region] {
        var regions = matches(of: Patterns.fencedCode, in: text, priority: 1)
        regions.append(contentsOf: matches(of: Patterns.inlineCode, in: text, priority: 2))
        return regions
    }

    private static func matches(
        of pattern: Pattern,
        in text: String,
        priority: Int
    ) -> [Region] {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.expression
            .matches(in: text, options: [], range: full)
            .compactMap { match in
                guard match.numberOfRanges > pattern.group,
                      let range = Range(match.range(at: pattern.group), in: text)
                else { return nil }
                return Region(range: range, priority: priority)
            }
    }

    // MARK: - Patterns

    /// A pattern and which of its groups is the part to hide.
    ///
    /// The group is stated rather than inferred. It was briefly inferred — "use
    /// group 1 if the pattern has one" — and the fenced-code pattern needs a
    /// capture group for its own backreference, so that rule masked the three
    /// backticks and left the code between them in plain sight.
    private struct Pattern {
        let expression: NSRegularExpression
        let group: Int
    }

    private enum Patterns {
        /// The group exists only so the closing fence can be matched to the
        /// opening one; the region to hide is the whole block.
        static let fencedCode = make("(?ms)^[ \\t]*(`{3,}|~{3,}).*?^[ \\t]*\\1[ \\t]*$", group: 0)
        static let inlineCode = make("`[^`\\n]+`", group: 0)
        static let embed = make("!\\[\\[[^\\]\\n]*\\]\\]", group: 0)
        static let image = make("!\\[[^\\]\\n]*\\]\\([^)\\n]*\\)", group: 0)
        static let wikiLink = make("\\[\\[[^\\]\\n]*\\]\\]", group: 0)
        /// The target only: `[visible text](THIS PART)`.
        static let linkTarget = make("\\[[^\\]\\n]*\\]\\(([^)\\n]*)\\)", group: 1)
        static let bareURL = make(
            "(?i)\\b((?:https?|ftp|obsidian|file)://[^\\s<>\\)\\]]+)",
            group: 1
        )
        static let taskMarker = make("(?m)^([ \\t]*[-*+][ \\t]+\\[[ xX/-]\\][ \\t]+)", group: 1)
        /// The lookbehind bars `#` as well as word characters, so the second
        /// hash of `##Kickoff` is not read as a tag. It was, and masking it
        /// hid the heading from the rule whose whole job is to space it.
        static let tag = make("(?<![\\w&#])(#[A-Za-z][\\w/-]*)", group: 1)
        /// Dataview-style inline fields, and YAML-ish `key:: value` lines.
        static let inlineField = make("(?m)^([A-Za-z][\\w -]{0,40}::[ \\t]*)", group: 1)
        static let headingMarker = make("(?m)^([ \\t]*#{1,6}[ \\t]+)", group: 1)
        static let listMarker = make("(?m)^([ \\t]*(?:[-*+]|\\d{1,3}[.)])[ \\t]+)", group: 1)

        /// The patterns are constants written here and nowhere else, so a
        /// failure to compile one is a programming error rather than something
        /// to handle at a call site.
        private static func make(_ pattern: String, group: Int) -> Pattern {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                preconditionFailure("Malformed mask pattern: \(pattern)")
            }
            return Pattern(expression: expression, group: group)
        }
    }
}
