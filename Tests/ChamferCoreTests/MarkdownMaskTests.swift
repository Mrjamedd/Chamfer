import Foundation
import Testing

@testable import ChamferCore

// MARK: - Round trips

@Test func maskingAndUnmaskingAnUntouchedNoteReturnsItExactly() {
    let note = """
        ---
        tags: [meeting]
        ---

        # Kickoff

        See [the brief](https://example.com/brief) and `run --now`.

        ```swift
        let x = 1
        ```

        - [ ] Follow up
        """

    let masked = MarkdownMask.apply(to: note, preserving: .standard)
    #expect(masked.unmask(masked.masked) == note)
}

@Test func aModelThatChangesOnlyProseStillRoundTrips() {
    let note = "Check [teh brief](https://example.com/a) later."
    let masked = MarkdownMask.apply(to: note, preserving: .standard)

    // The link text is visible to the model and fair game; the target is not.
    let edited = masked.masked.replacingOccurrences(of: "teh", with: "the")

    #expect(masked.unmask(edited) == "Check [the brief](https://example.com/a) later.")
}

// MARK: - What is hidden

@Test func linkTargetsAreHiddenButLinkTextIsNot() {
    let masked = MarkdownMask.apply(
        to: "Read [teh brief](https://example.com/secret) now.",
        preserving: .standard
    )

    #expect(!masked.masked.contains("https://example.com/secret"))
    #expect(masked.masked.contains("teh brief"))
}

@Test func codeFencesAndTheirContentsAreHiddenWhole() {
    let note = """
        Before.

        ```python
        teh = "not a typo to fix"
        ```

        After.
        """
    let masked = MarkdownMask.apply(to: note, preserving: .standard)

    #expect(!masked.masked.contains("not a typo to fix"))
    #expect(masked.masked.contains("Before."))
    #expect(masked.masked.contains("After."))
}

@Test func frontMatterIsHiddenOnlyWhenItOpensTheNote() {
    let opening = MarkdownMask.apply(
        to: "---\ntags: [a]\n---\n\nBody.",
        preserving: .standard
    )
    #expect(!opening.masked.contains("tags: [a]"))

    // The same fence mid-note is a horizontal rule and must stay visible.
    let rule = MarkdownMask.apply(
        to: "Body.\n\n---\n\nMore body.",
        preserving: .standard
    )
    #expect(rule.masked.contains("---"))
}

@Test func wikiLinksAndEmbedsAreHiddenWhole() {
    let masked = MarkdownMask.apply(
        to: "See [[Project Brief]] and ![[diagram.png]].",
        preserving: .standard
    )

    #expect(!masked.masked.contains("Project Brief"))
    #expect(!masked.masked.contains("diagram.png"))
}

@Test func tagsSurviveAsAddressesRatherThanWords() {
    let masked = MarkdownMask.apply(to: "Filed under #meeting today.", preserving: .standard)
    #expect(!masked.masked.contains("#meeting"))
    #expect(masked.masked.contains("today"))
}

@Test func taskCheckboxesKeepTheirMarkers() {
    let masked = MarkdownMask.apply(
        to: "- [x] Ship it\n- [ ] Tell someone",
        preserving: .standard
    )
    #expect(!masked.masked.contains("[x]"))
    #expect(masked.masked.contains("Ship it"))
}

// MARK: - What the settings control

@Test func headingsAndListsAreVisibleUnderTheStandardSettings() {
    // Formatting mode exists to reflow these, so protecting them by default
    // would make one of the five modes a no-op.
    let masked = MarkdownMask.apply(
        to: "# Kickoff\n\n- One\n- Two",
        preserving: .standard
    )
    #expect(masked.masked.contains("# Kickoff"))
    #expect(masked.masked.contains("- One"))
}

@Test func headingMarkersAreHiddenWhenTheUserProtectsThem() {
    let masked = MarkdownMask.apply(
        to: "# Kickoff\n\nBody.",
        preserving: [.headings]
    )
    #expect(!masked.masked.contains("# "))
    #expect(masked.masked.contains("Kickoff"))
}

@Test func protectingNothingMasksNothing() {
    let note = "See [the brief](https://example.com) and `code`."
    let masked = MarkdownMask.apply(to: note, preserving: [])
    #expect(masked.masked == note)
    #expect(masked.replacements.isEmpty)
}

// MARK: - Overlap

@Test func aLinkInsideACodeFenceIsMaskedOnceRatherThanTwice() {
    let note = """
        ```
        [a](https://example.com)
        ```
        """
    let masked = MarkdownMask.apply(to: note, preserving: .standard)

    // Two placeholders written over the same bytes would corrupt the note on
    // the way back. One region, one token.
    #expect(masked.replacements.count == 1)
    #expect(masked.unmask(masked.masked) == note)
}

// MARK: - Damage

@Test func aDroppedPlaceholderRefusesToUnmask() {
    let masked = MarkdownMask.apply(
        to: "See [the brief](https://example.com).",
        preserving: .standard
    )
    let mangled = masked.masked.replacingOccurrences(
        of: MarkdownMask.token(0),
        with: ""
    )

    #expect(masked.unmask(mangled) == nil)
    #expect(masked.brokenTokens(in: mangled) == [MarkdownMask.token(0)])
}

@Test func aDuplicatedPlaceholderRefusesToUnmask() {
    let masked = MarkdownMask.apply(
        to: "See [the brief](https://example.com).",
        preserving: .standard
    )
    let doubled = masked.masked + masked.masked

    #expect(masked.unmask(doubled) == nil)
    #expect(!masked.brokenTokens(in: doubled).isEmpty)
}

@Test func anIntactRewriteReportsNoBrokenTokens() {
    let masked = MarkdownMask.apply(
        to: "See [the brief](https://example.com).",
        preserving: .standard
    )
    #expect(masked.brokenTokens(in: masked.masked).isEmpty)
}
