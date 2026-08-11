import ChamferCore
import Foundation

/// One request's worth of a note, with the whitespace that surrounds it.
///
/// `leading + text + trailing`, concatenated across every unit, reproduces the
/// input exactly. Only `text` is ever sent to a model, so the blank lines that
/// separate paragraphs cannot be lost by a backend that trims its response.
struct RewriteUnit: Sendable, Equatable {
    var leading: String
    let text: String
    var trailing: String
    var contextBefore: String?
    var contextAfter: String?
}

/// Decides how much of a note goes into one model request.
///
/// This used to split prose into individual **sentences** for spelling and
/// grammar, which existed for exactly one reason: the previous on-device
/// backend had a four-thousand-token context and could not be trusted to hold a
/// paragraph and a set of rules at the same time. It was expensive — a hundred
/// requests for a page of notes — and it actively hurt quality, because a
/// sentence handed over alone gives a model no way to see the agreement, tense
/// or referent that the sentence before it established.
///
/// A downloaded local model has room for whole sections. Units are now
/// paragraph groups sized by the effort profile, which is where Base, Balanced
/// and Max differ in how much context each edit is made with: Base fails small
/// and fast, Max reads a section at a time.
///
/// Paragraph boundaries are kept rather than abandoned entirely. They are what
/// make a discarded answer cost one paragraph instead of one note, and they
/// keep the response guard's length comparison meaningful.
enum RewriteUnitPlanner {
    static func units(
        in text: String,
        mode: RewriteMode,
        profile: ModelEffortProfile
    ) -> [RewriteUnit] {
        guard !text.isEmpty else { return [] }

        var units: [RewriteUnit]
        switch mode {
        case .formatting:
            // Formatting is about the relationship *between* blocks, so it has
            // always been given the whole section at once. Splitting it would
            // ask the model to space a paragraph against neighbours it cannot
            // see.
            units = makeUnit(from: text).map { [$0] } ?? []
        case .spelling, .grammar, .clarity, .fullCleanup:
            units = groupedUnits(
                in: text,
                budget: profile.unitTargetCharacters
            )
        }

        guard profile.includesNeighbourContext, units.count > 1 else {
            return units
        }
        attachContext(to: &units)
        return units
    }

    /// Blocks are merged until adding the next one would cross the budget. A
    /// single block longer than the budget is still one unit — splitting inside
    /// a paragraph is what produced the sentence-level behaviour this replaces,
    /// and a paragraph cut in half mid-clause is worse input than a long one.
    private static func groupedUnits(
        in text: String,
        budget: Int
    ) -> [RewriteUnit] {
        let blocks = MarkdownSectioner.sections(in: text, targetCharacterCount: 1)
        guard !blocks.isEmpty else { return makeUnit(from: text).map { [$0] } ?? [] }

        var result: [RewriteUnit] = []
        var pending = ""
        let limit = max(1, budget)

        for block in blocks {
            if pending.isEmpty {
                pending = block
                continue
            }
            if pending.count + block.count <= limit {
                pending += block
            } else {
                if let unit = makeUnit(from: pending) { result.append(unit) }
                pending = block
            }
        }

        if !pending.isEmpty, let unit = makeUnit(from: pending) {
            result.append(unit)
        }

        // Whitespace-only blocks produce no unit, so their bytes would be lost.
        // Reattaching them keeps the reassembly exact.
        return reattachDroppedWhitespace(original: text, units: result)
    }

    /// The neighbouring units' text, clipped. A whole neighbouring section as
    /// context would cost more of the window than the passage being edited and
    /// invite the model to start editing what it can see.
    private static func attachContext(to units: inout [RewriteUnit]) {
        let clip = 400
        let texts = units.map(\.text)
        for index in units.indices {
            if index > 0 {
                units[index].contextBefore = String(texts[index - 1].suffix(clip))
            }
            if index + 1 < texts.count {
                units[index].contextAfter = String(texts[index + 1].prefix(clip))
            }
        }
    }

    /// Reassembly has to be byte-exact, so anything the grouping dropped is put
    /// back on the nearest unit rather than quietly lost.
    private static func reattachDroppedWhitespace(
        original: String,
        units: [RewriteUnit]
    ) -> [RewriteUnit] {
        var result = units
        let rebuilt = result.map { $0.leading + $0.text + $0.trailing }.joined()
        guard rebuilt != original else { return result }

        guard !result.isEmpty else {
            return makeUnit(from: original).map { [$0] } ?? []
        }
        // The only way the two can differ is dropped whitespace, and it can
        // only have come from the end. Restoring the tail is enough.
        if original.hasPrefix(rebuilt) {
            result[result.index(before: result.endIndex)].trailing
                += String(original.dropFirst(rebuilt.count))
            return result
        }
        // Anything else means the grouping is not trustworthy for this input;
        // one whole unit is always exact.
        return makeUnit(from: original).map { [$0] } ?? []
    }

    private static func makeUnit(from segment: String) -> RewriteUnit? {
        let leadingEnd = segment.firstIndex { !$0.isWhitespace } ?? segment.endIndex
        let trailingStart = segment[..<segment.endIndex].lastIndex { !$0.isWhitespace }
            .map { segment.index(after: $0) } ?? leadingEnd
        let body = String(segment[leadingEnd..<trailingStart])
        guard !body.isEmpty else { return nil }
        return RewriteUnit(
            leading: String(segment[..<leadingEnd]),
            text: body,
            trailing: String(segment[trailingStart...]),
            contextBefore: nil,
            contextAfter: nil
        )
    }
}
