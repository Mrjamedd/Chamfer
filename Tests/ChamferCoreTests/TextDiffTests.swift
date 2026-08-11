import Foundation
import Testing

@testable import ChamferCore

// MARK: - Hunks

@Test func identicalTextProducesNoHunks() {
    #expect(TextDiff.hunks(from: "Same text.", to: "Same text.").isEmpty)
}

@Test func aSingleChangedLineIsOneHunkOnThatLine() {
    let before = "First line.\nteh second line.\nThird line."
    let after = "First line.\nThe second line.\nThird line."

    let hunks = TextDiff.hunks(from: before, to: after)

    #expect(hunks.count == 1)
    #expect(hunks[0].before == "teh second line.")
    #expect(hunks[0].after == "The second line.")
    // 1-indexed, as every editor numbers its gutter.
    #expect(hunks[0].startLine == 2)
}

@Test func consecutiveChangesBecomeOneHunkRatherThanSeveral() {
    let before = "Keep.\nteh one.\nteh two.\nteh three.\nKeep."
    let after = "Keep.\nThe one.\nThe two.\nThe three.\nKeep."

    let hunks = TextDiff.hunks(from: before, to: after)

    // A rewritten paragraph is one decision. Presenting it as three would make
    // the queue unreadable.
    #expect(hunks.count == 1)
    #expect(hunks[0].startLine == 2)
}

@Test func separatedChangesStayAsSeparateHunks() {
    let before = "teh one.\nKeep.\nKeep.\nKeep.\nteh five."
    let after = "The one.\nKeep.\nKeep.\nKeep.\nThe five."

    let hunks = TextDiff.hunks(from: before, to: after)

    #expect(hunks.count == 2)
    #expect(hunks[0].startLine == 1)
    #expect(hunks[1].startLine == 5)
}

@Test func aPureInsertionIsAHunkWithNothingRemoved() {
    let hunks = TextDiff.hunks(from: "One.\nThree.", to: "One.\nTwo.\nThree.")

    #expect(hunks.count == 1)
    #expect(hunks[0].before.isEmpty)
    #expect(hunks[0].after == "Two.")
}

@Test func aPureDeletionIsAHunkWithNothingAdded() {
    let hunks = TextDiff.hunks(from: "One.\nTwo.\nThree.", to: "One.\nThree.")

    #expect(hunks.count == 1)
    #expect(hunks[0].before == "Two.")
    #expect(hunks[0].after.isEmpty)
}

@Test func blankLinesCountAsContentBecauseTheyChangeMeaning() {
    // Losing a blank line joins two paragraphs into one, which is a real edit.
    let hunks = TextDiff.hunks(from: "One.\n\nTwo.", to: "One.\nTwo.")
    #expect(!hunks.isEmpty)
}

// MARK: - Applying

@Test func applyingAHunkPutsTheRewriteBackWhereItCameFrom() {
    let before = "First.\nteh second.\nThird."
    let after = "First.\nThe second.\nThird."
    let hunks = TextDiff.hunks(from: before, to: after)

    #expect(TextDiff.apply(hunks, to: before) == after)
}

@Test func applyingSeveralHunksSurvivesTheLineNumbersMoving() {
    let before = "teh one.\nKeep.\nteh three.\nKeep."
    let after = "The first line entirely.\nKeep.\nThe third.\nKeep."
    let hunks = TextDiff.hunks(from: before, to: after)

    #expect(hunks.count == 2)
    #expect(TextDiff.apply(hunks, to: before) == after)
}

@Test func applyingRefusesWhenTheTextHasMovedOnUnderneath() {
    let hunks = TextDiff.hunks(
        from: "First.\nteh second.\nThird.",
        to: "First.\nThe second.\nThird."
    )

    // The user edited the line the rewrite was built against. Applying blind
    // would silently overwrite what they just wrote.
    #expect(TextDiff.apply(hunks, to: "First.\nsomething else.\nThird.") == nil)
}

@Test func applyingIsPositionalRatherThanASearchAndReplace() {
    // The same line twice. Replacing "the first occurrence" would edit the
    // wrong one, and notes repeat lines constantly.
    let before = "- [ ] Task\nMiddle.\n- [ ] Task"
    let after = "- [ ] Task\nMiddle.\n- [x] Task"
    let hunks = TextDiff.hunks(from: before, to: after)

    #expect(TextDiff.apply(hunks, to: before) == after)
}

@Test func applyingNothingLeavesTheTextAlone() {
    #expect(TextDiff.apply([], to: "Untouched.") == "Untouched.")
}

// MARK: - Word segments

@Test func aOneWordFixMarksOnlyThatWord() {
    let (before, after) = TextDiff.segments(
        before: "The quick brown fox jumped over teh lazy dog.",
        after: "The quick brown fox jumped over the lazy dog."
    )

    #expect(before.filter { $0.kind == .removed }.map(\.text) == ["teh"])
    #expect(after.filter { $0.kind == .added }.map(\.text) == ["the"])
    // Everything else has to survive as unchanged, or the highlight stops
    // meaning "this is what moved".
    #expect(before.contains { $0.kind == .unchanged && $0.text.contains("quick") })
}

@Test func segmentsReassembleIntoTheOriginalStrings() {
    let original = "The quick brown fox jumped over teh lazy dog."
    let revised = "The quick brown fox leapt over the lazy dog."
    let (before, after) = TextDiff.segments(before: original, after: revised)

    #expect(before.map(\.text).joined() == original)
    #expect(after.map(\.text).joined() == revised)
}

@Test func aWhollyRewrittenLineIsNotMarkedWordByWord() {
    let (before, after) = TextDiff.segments(
        before: "Alpha beta gamma delta.",
        after: "Completely different words here entirely."
    )

    // Tinting ninety per cent of both lines is noise. One segment each.
    #expect(before.count == 1)
    #expect(after.count == 1)
    #expect(before.first?.kind == .removed)
    #expect(after.first?.kind == .added)
}

@Test func whitespaceIsATokenSoFormattingChangesAreVisible() {
    let (before, after) = TextDiff.segments(
        before: "One  two",
        after: "One two"
    )

    #expect(before.map(\.text).joined() == "One  two")
    #expect(after.map(\.text).joined() == "One two")
    #expect(before.contains { $0.kind == .removed })
}

@Test func tokenisingKeepsWordsAndGapsApart() {
    #expect(TextDiff.tokenise("a b") == ["a", " ", "b"])
    #expect(TextDiff.tokenise("hello") == ["hello"])
    #expect(TextDiff.tokenise("") == [])
    #expect(TextDiff.tokenise("a\n b").joined() == "a\n b")
}
