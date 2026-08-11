import Foundation
import Testing

@testable import ChamferCore

// MARK: - Helpers

/// Long enough that the length checks apply. Below the floor they are switched
/// off, because one word becoming two is a 100% increase and entirely fine.
private let longNote = String(repeating: "This is a sentence in a note. ", count: 8)

// MARK: - Emptiness and length

@Test func anEmptyRewriteIsRefused() {
    #expect(
        RewriteGate.inspect(original: longNote, candidate: "   \n\n", preserved: [])
            != nil
    )
}

@Test func aRewriteThatCameBackAsASummaryIsRefused() {
    // The classic model failure: asked to correct a page, it returns a
    // sentence about the page.
    let failure = RewriteGate.inspect(
        original: longNote,
        candidate: "This note discusses several topics.",
        preserved: []
    )
    #expect(failure != nil)
}

@Test func aRewriteThatBalloonedIsRefused() {
    #expect(
        RewriteGate.inspect(
            original: longNote,
            candidate: longNote + longNote + longNote,
            preserved: []
        ) != nil
    )
}

@Test func aNormalCorrectionPassesTheLengthCheck() {
    #expect(
        RewriteGate.inspect(
            original: longNote,
            candidate: longNote.replacingOccurrences(of: "sentence", with: "line"),
            preserved: []
        ) == nil
    )
}

@Test func shortNotesSkipTheLengthCheckEntirely() {
    // "hi" becoming "Hello there, how are you?" is a legitimate clarity edit
    // and a 1000% increase.
    #expect(
        RewriteGate.inspect(
            original: "hi",
            candidate: "Hello there, how are you?",
            preserved: []
        ) == nil
    )
}

// MARK: - Preservation

@Test func aLostHeadingIsAPreservationViolation() {
    let original = "# Kickoff\n\nBody text here.\n\n## Details\n\nMore body text."
    let candidate = "# Kickoff\n\nBody text here.\n\nMore body text."

    #expect(
        RewriteGate.inspect(
            original: original,
            candidate: candidate,
            preserved: [.headings]
        ) == .preservationViolated([.headings])
    )
}

@Test func aRewordedHeadingIsNotAViolation() {
    // The promise is structural: "do not remove my headings", not "do not
    // touch these words". A heading whose wording improved is still a heading.
    let original = "# teh kickoff\n\nBody text here."
    let candidate = "# The kickoff\n\nBody text here."

    #expect(
        RewriteGate.inspect(
            original: original,
            candidate: candidate,
            preserved: [.headings]
        ) == nil
    )
}

@Test func headingsMayChangeFreelyWhenTheyAreNotProtected() {
    let original = "# One\n\nBody.\n\n# Two\n\nBody."
    let candidate = "Body.\n\nBody."

    #expect(
        RewriteGate.inspect(original: original, candidate: candidate, preserved: [])
            == nil
    )
}

@Test func aDroppedListItemIsAViolation() {
    let original = "- One\n- Two\n- Three"
    let candidate = "- One\n- Two"

    #expect(
        RewriteGate.inspect(
            original: original,
            candidate: candidate,
            preserved: [.lists]
        ) == .preservationViolated([.lists])
    )
}

@Test func aTickedCheckboxIsStillACheckbox() {
    #expect(
        RewriteGate.violations(
            original: "- [ ] Ship it",
            candidate: "- [x] Ship it",
            preserved: [.taskCheckboxes]
        ).isEmpty
    )
}

@Test func aRemovedCheckboxIsAViolation() {
    #expect(
        RewriteGate.violations(
            original: "- [ ] Ship it\n- [ ] Tell someone",
            candidate: "- [ ] Ship it",
            preserved: [.taskCheckboxes]
        ) == [.taskCheckboxes]
    )
}

@Test func anEditedFrontMatterBlockIsAViolationEvenWhenItLooksLikeAnImprovement() {
    let original = "---\ntags: [meeting, kickof]\n---\n\nBody."
    let candidate = "---\ntags: [meeting, kickoff]\n---\n\nBody."

    // Front matter is machine-read by whatever else touches these notes, so a
    // model fixing a typo in a tag is a silent data change.
    #expect(
        RewriteGate.violations(
            original: original,
            candidate: candidate,
            preserved: [.frontMatter]
        ) == [.frontMatter]
    )
}

@Test func severalViolationsAreReportedTogether() {
    let original = "# One\n\n- a\n- b\n\n[link](https://example.com)"
    let candidate = "Body only."

    let violated = RewriteGate.violations(
        original: original,
        candidate: candidate,
        preserved: [.headings, .lists, .links]
    )

    #expect(violated.contains(.headings))
    #expect(violated.contains(.lists))
    #expect(violated.contains(.links))
}

@Test func anUntouchedNotePassesEveryPreservationCheck() {
    let note = """
        ---
        tags: [meeting]
        ---

        # Kickoff

        - [ ] Follow up
        - One

        See [the brief](https://example.com) and ![shot](a.png) and ![[embed.md]].

        ```swift
        let x = 1
        ```
        """

    #expect(
        RewriteGate.inspect(original: note, candidate: note, preserved: .all) == nil
    )
}

// MARK: - Counting

@Test func headingCountingIgnoresTags() {
    #expect(RewriteGate.countHeadings("# Real heading") == 1)
    // A line that is only a tag is not a heading someone forgot to space.
    #expect(RewriteGate.countHeadings("#tag") == 0)
    #expect(RewriteGate.countHeadings("Body #tag inline") == 0)
}

@Test func listCountingHandlesBothKinds() {
    #expect(RewriteGate.countListItems("- one\n* two\n+ three") == 3)
    #expect(RewriteGate.countListItems("1. one\n2) two") == 2)
    // Not a list: no space after the marker.
    #expect(RewriteGate.countListItems("-notalist") == 0)
}

@Test func linkCountingSeparatesLinksFromImages() {
    let text = "[a](x) ![b](y) [[c]] ![[d]]"
    #expect(RewriteGate.countImages(text) == 1)
    #expect(RewriteGate.countEmbeds(text) == 1)
    // The image's `[b](y)` must not be counted again as a plain link.
    #expect(RewriteGate.countLinks(text) == 2)
}
