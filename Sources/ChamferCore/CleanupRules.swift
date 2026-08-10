import Foundation

/// The deterministic pass.
///
/// These run without asking, which is only defensible because every one of them
/// is reversible, offline, and incapable of changing what a note says. Anything
/// that requires judgement is a rewrite and goes through the review queue
/// instead. The dividing line is strict: if a rule could ever produce a result
/// a reasonable person would want to reject, it does not belong here.
public enum CleanupRules {
    /// Applied in this order. Order matters — collapsing blank lines before
    /// heading spacing has been fixed would undo the spacing the heading rule
    /// is about to add.
    public static let standard: [any CleanupRule] = [
        TrailingWhitespaceRule(),
        HeadingSpacingRule(),
        ListMarkerRule(),
        BlankLineRule(),
        FinalNewlineRule()
    ]

    /// Runs the rules over the parts of the note that are not protected.
    ///
    /// The masking is the same masking the model pass uses, and for the same
    /// reason: a rule that "tidied" the indentation inside a code fence would
    /// change what that code means.
    public static func apply(
        _ rules: [any CleanupRule] = standard,
        to text: String,
        preserving structure: MarkdownStructure = .standard
    ) -> CleanupResult {
        // Headings and lists are excluded from the mask here whatever the
        // user's settings say: these rules exist to normalise exactly those
        // markers, and masking them would make every rule a no-op.
        let masking = structure.subtracting([.headings, .lists])
        let masked = MarkdownMask.apply(to: text, preserving: masking)

        var working = masked.masked
        var applied: [String] = []

        for rule in rules {
            let result = rule.apply(to: working)
            if result != working {
                applied.append(rule.identifier)
                working = result
            }
        }

        guard let restored = masked.unmask(working) else {
            // A rule dropped a placeholder. That is a bug rather than a model
            // being unpredictable, so the safe answer is to change nothing.
            return CleanupResult(text: text, appliedRuleIDs: [])
        }

        return CleanupResult(
            text: restored,
            appliedRuleIDs: restored == text ? [] : applied
        )
    }
}

/// What one pass of the rules did.
public struct CleanupResult: Sendable, Equatable {
    public let text: String
    /// Identifiers of the rules that actually changed something, for the
    /// history entry. A rule that ran and found nothing to do is not news.
    public let appliedRuleIDs: [String]

    public init(text: String, appliedRuleIDs: [String]) {
        self.text = text
        self.appliedRuleIDs = appliedRuleIDs
    }

    public var changedAnything: Bool { !appliedRuleIDs.isEmpty }
}

// MARK: - Rules

/// Spaces and tabs at the end of a line.
///
/// With one exception: exactly two trailing spaces is a Markdown hard line
/// break, and stripping it silently joins two lines the user meant to keep
/// apart. It is the only trailing whitespace that means something.
public struct TrailingWhitespaceRule: CleanupRule {
    public let identifier = "whitespace.trailing"

    public init() {}

    public func apply(to text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = String(line.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
                let removed = line.count - trimmed.count
                // Preserved only when it is spaces, and only when it is a
                // deliberate two.
                if removed == 2, line.hasSuffix("  "), !line.hasSuffix("\t ") {
                    return trimmed + "  "
                }
                return trimmed
            }
            .joined(separator: "\n")
    }
}

/// `#Heading` becomes `# Heading`.
///
/// Only where the run of hashes is genuinely a heading marker: a line starting
/// `#tag` is a tag, and putting a space in it would destroy it.
public struct HeadingSpacingRule: CleanupRule {
    public let identifier = "heading.spacing"

    public init() {}

    public func apply(to text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { line -> String in
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                let rest = line.dropFirst(indent.count)
                let hashes = rest.prefix { $0 == "#" }
                guard !hashes.isEmpty, hashes.count <= 6 else { return line }

                let body = rest.dropFirst(hashes.count)
                guard let first = body.first else { return line }
                guard first != " " else { return line }
                // A word character straight after the hashes is a tag, not a
                // heading someone forgot to space.
                guard !(first.isLetter || first.isNumber) || hashes.count > 1 else {
                    return line
                }
                guard first.isLetter || first.isNumber else { return line }
                return indent + hashes + " " + body
            }
            .joined(separator: "\n")
    }
}

/// One bullet character throughout: `-`.
///
/// `*` and `+` are equally valid Markdown and mixing them in one document is
/// the sort of thing that happens by accident and never on purpose. Ordered
/// lists are left completely alone — their numbers carry meaning.
public struct ListMarkerRule: CleanupRule {
    public let identifier = "list.marker"

    public init() {}

    public func apply(to text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { line -> String in
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                let rest = line.dropFirst(indent.count)
                guard let marker = rest.first, marker == "*" || marker == "+" else {
                    return line
                }
                let body = rest.dropFirst()
                guard body.first == " " else { return line }
                // `* * *` is a horizontal rule, not a bullet.
                guard body.trimmingCharacters(in: .whitespaces) != "* *" else {
                    return line
                }
                return indent + "-" + body
            }
            .joined(separator: "\n")
    }
}

/// Three or more blank lines become two.
///
/// Two is left alone deliberately. One blank line separates paragraphs and two
/// is a legitimate visual break people use between sections; collapsing to a
/// single blank everywhere would be the rule imposing a taste rather than
/// fixing a mistake.
public struct BlankLineRule: CleanupRule {
    public let identifier = "blankLines.collapse"

    public init() {}

    public func apply(to text: String) -> String {
        var output: [String] = []
        var blankRun = 0

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun <= 2 { output.append(line) }
            } else {
                blankRun = 0
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }
}

/// A note ends with exactly one newline.
///
/// Files without a trailing newline confuse every tool that reads them a line
/// at a time, and files with six have accumulated them by accident.
public struct FinalNewlineRule: CleanupRule {
    public let identifier = "file.finalNewline"

    public init() {}

    public func apply(to text: String) -> String {
        guard !text.isEmpty else { return text }
        let trimmed = String(text.reversed().drop { $0 == "\n" }.reversed())
        guard !trimmed.isEmpty else { return text }
        return trimmed + "\n"
    }
}
