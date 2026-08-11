import Foundation

/// One run of text inside a diff line, and whether it actually changed.
///
/// The reason this exists: in spelling and grammar modes most hunks differ by a
/// single word, and a whole-line tint makes a typo fix look like a paragraph
/// rewrite. Marking the runs lets the interface tint only what moved, so the
/// size of the highlight matches the size of the edit.
public struct DiffSegment: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case unchanged
        case removed
        case added
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// Turning two versions of a note into something a person can judge.
public enum TextDiff {
    // MARK: - Line diff

    /// Groups the differences between two texts into reviewable hunks.
    ///
    /// Contiguous changes become one hunk rather than one per line, because a
    /// rewritten paragraph is one decision and presenting it as six would make
    /// the queue unreadable.
    public static func hunks(from before: String, to after: String) -> [Hunk] {
        let beforeLines = lines(of: before)
        let afterLines = lines(of: after)

        guard beforeLines != afterLines else { return [] }

        let difference = afterLines.difference(from: beforeLines)
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removedOffsets.insert(offset)
            case let .insert(offset, _, _): insertedOffsets.insert(offset)
            }
        }

        var hunks: [Hunk] = []
        var beforeIndex = 0
        var afterIndex = 0
        var pendingBefore: [String] = []
        var pendingAfter: [String] = []
        var pendingStart: Int?

        func flush() {
            defer {
                pendingBefore.removeAll()
                pendingAfter.removeAll()
                pendingStart = nil
            }
            guard let start = pendingStart else { return }
            // Compared as arrays rather than as joined text. A deleted blank
            // line is `[""]` becoming `[]`, and both join to the empty string —
            // so a text comparison quietly threw away every rewrite whose only
            // change was closing up a gap between paragraphs.
            guard pendingBefore != pendingAfter else { return }
            hunks.append(
                Hunk(
                    before: pendingBefore.joined(separator: "\n"),
                    after: pendingAfter.joined(separator: "\n"),
                    // 1-indexed, as the type documents and as every editor
                    // numbers its gutter.
                    startLine: start + 1
                )
            )
        }

        while beforeIndex < beforeLines.count || afterIndex < afterLines.count {
            let isRemoved = beforeIndex < beforeLines.count
                && removedOffsets.contains(beforeIndex)
            let isInserted = afterIndex < afterLines.count
                && insertedOffsets.contains(afterIndex)

            if isRemoved || isInserted {
                if pendingStart == nil { pendingStart = beforeIndex }
                if isRemoved {
                    pendingBefore.append(beforeLines[beforeIndex])
                    beforeIndex += 1
                }
                if isInserted {
                    pendingAfter.append(afterLines[afterIndex])
                    afterIndex += 1
                }
                continue
            }

            flush()
            // Both sides are looking at the same line, so both advance. The
            // guards are for the tail, where one side has run out.
            if beforeIndex < beforeLines.count { beforeIndex += 1 }
            if afterIndex < afterLines.count { afterIndex += 1 }
        }
        flush()

        return hunks
    }

    /// Applies a set of hunks to the text they were made from.
    ///
    /// Positional rather than by search-and-replace. Replacing the first
    /// occurrence of a hunk's text is wrong whenever a note repeats a line —
    /// and notes repeat lines constantly: blank ones, `## Notes`, `- [ ]`.
    /// Returns nil when a hunk no longer matches what is at its line, which
    /// means the text has moved on and the rewrite must not be applied blind.
    public static func apply(_ hunks: [Hunk], to text: String) -> String? {
        guard !hunks.isEmpty else { return text }
        var result = lines(of: text)

        // Applied bottom-up so an earlier hunk's line numbers stay valid while
        // a later one is being spliced in.
        for hunk in hunks.sorted(by: { $0.startLine > $1.startLine }) {
            let start = hunk.startLine - 1
            guard start >= 0, start <= result.count else { return nil }

            let originalLines = hunk.before.isEmpty ? [] : lines(of: hunk.before)
            let replacementLines = hunk.after.isEmpty ? [] : lines(of: hunk.after)
            let end = start + originalLines.count
            guard end <= result.count else { return nil }
            guard Array(result[start..<end]) == originalLines else { return nil }

            result.replaceSubrange(start..<end, with: replacementLines)
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Word diff

    /// The two sides of a hunk, marked run by run.
    ///
    /// Returned as a pair rather than one merged sequence because the interface
    /// draws them as two lines — the removed one above the added one — and a
    /// single interleaved sequence would have to be split again to render.
    public static func segments(
        before: String,
        after: String
    ) -> (before: [DiffSegment], after: [DiffSegment]) {
        let beforeTokens = tokenise(before)
        let afterTokens = tokenise(after)

        let difference = afterTokens.difference(from: beforeTokens)

        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        var removedWords = 0
        var addedWords = 0
        for change in difference {
            switch change {
            case let .remove(offset, element, _):
                removedOffsets.insert(offset)
                if !isBlank(element) { removedWords += 1 }
            case let .insert(offset, element, _):
                insertedOffsets.insert(offset)
                if !isBlank(element) { addedWords += 1 }
            }
        }

        // A hunk where nothing lines up — a wholly rewritten paragraph — gets
        // no word marking at all. Tinting ninety per cent of both lines is
        // noise, and the whole point of this is that the highlight means
        // something.
        //
        // Measured against words rather than all tokens. The whitespace between
        // words almost always survives a rewrite, so counting it dragged every
        // ratio down towards a half and no rewrite ever looked wholesale.
        let beforeWords = beforeTokens.count { !isBlank($0) }
        let afterWords = afterTokens.count { !isBlank($0) }
        let removedShare = beforeWords == 0 ? 0 : Double(removedWords) / Double(beforeWords)
        let addedShare = afterWords == 0 ? 0 : Double(addedWords) / Double(afterWords)
        // Both sides have to be almost entirely new. One side alone is a large
        // insertion or deletion, and marking those is exactly what this is for.
        if min(removedShare, addedShare) >= 0.7 {
            return (
                [DiffSegment(text: before, kind: .removed)],
                [DiffSegment(text: after, kind: .added)]
            )
        }

        return (
            coalesce(beforeTokens, marked: removedOffsets, as: .removed),
            coalesce(afterTokens, marked: insertedOffsets, as: .added)
        )
    }

    /// Splits into words and the whitespace between them, keeping both.
    ///
    /// Whitespace is a token rather than a separator because formatting mode
    /// exists to change it, and a diff that could not see it would report those
    /// rewrites as changing nothing at all.
    static func tokenise(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWhitespace: Bool?

        for character in text {
            let isWhitespace = character.isWhitespace
            if currentIsWhitespace == nil || currentIsWhitespace == isWhitespace {
                current.append(character)
            } else {
                tokens.append(current)
                current = String(character)
            }
            currentIsWhitespace = isWhitespace
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Joins neighbouring tokens of the same kind, so a three-word change is
    /// one segment rather than five.
    private static func coalesce(
        _ tokens: [String],
        marked: Set<Int>,
        as kind: DiffSegment.Kind
    ) -> [DiffSegment] {
        var segments: [DiffSegment] = []
        var buffer = ""
        var bufferKind: DiffSegment.Kind?

        for (offset, token) in tokens.enumerated() {
            let tokenKind: DiffSegment.Kind = marked.contains(offset) ? kind : .unchanged
            if bufferKind == tokenKind {
                buffer += token
            } else {
                if let bufferKind, !buffer.isEmpty {
                    segments.append(DiffSegment(text: buffer, kind: bufferKind))
                }
                buffer = token
                bufferKind = tokenKind
            }
        }
        if let bufferKind, !buffer.isEmpty {
            segments.append(DiffSegment(text: buffer, kind: bufferKind))
        }
        return segments
    }

    // MARK: - Lines

    /// Splits on newlines keeping empty lines, which carry meaning in Markdown:
    /// a lost blank line joins two paragraphs into one.
    static func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// Whitespace, or nothing at all.
    private static func isBlank(_ token: String) -> Bool {
        token.allSatisfy(\.isWhitespace)
    }
}
