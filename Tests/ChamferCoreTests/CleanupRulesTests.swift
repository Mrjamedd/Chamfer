import Foundation
import Testing

@testable import ChamferCore

// MARK: - Individual rules

@Test func trailingWhitespaceGoesExceptWhereItMeansSomething() {
    let rule = TrailingWhitespaceRule()

    #expect(rule.apply(to: "text   ") == "text")
    #expect(rule.apply(to: "text\t\t") == "text")
    // Exactly two trailing spaces is a Markdown hard line break. Stripping it
    // silently joins two lines the author meant to keep apart.
    #expect(rule.apply(to: "text  ") == "text  ")
    #expect(rule.apply(to: "one   \ntwo  \nthree") == "one\ntwo  \nthree")
}

@Test func headingsGetTheirMissingSpace() {
    let rule = HeadingSpacingRule()

    #expect(rule.apply(to: "##Details") == "## Details")
    #expect(rule.apply(to: "  ###Deeper") == "  ### Deeper")
    #expect(rule.apply(to: "# Already fine") == "# Already fine")
}

@Test func aTagIsNotAHeadingMissingASpace() {
    // `#meeting` is a tag. Putting a space in it would destroy it.
    #expect(HeadingSpacingRule().apply(to: "#meeting") == "#meeting")
}

@Test func bulletsAreNormalisedToOneCharacter() {
    let rule = ListMarkerRule()

    #expect(rule.apply(to: "* one\n+ two\n- three") == "- one\n- two\n- three")
    #expect(rule.apply(to: "  * nested") == "  - nested")
    // Ordered lists carry meaning in their numbers and are left alone.
    #expect(rule.apply(to: "1. one\n2. two") == "1. one\n2. two")
    // No space after the marker means it is not a bullet.
    #expect(rule.apply(to: "*emphasis*") == "*emphasis*")
}

@Test func runsOfBlankLinesCollapseToTwo() {
    let rule = BlankLineRule()

    #expect(rule.apply(to: "a\n\n\n\n\nb") == "a\n\n\nb")
    // Two is a legitimate visual break between sections and is left alone.
    #expect(rule.apply(to: "a\n\n\nb") == "a\n\n\nb")
    #expect(rule.apply(to: "a\n\nb") == "a\n\nb")
}

@Test func aNoteEndsWithExactlyOneNewline() {
    let rule = FinalNewlineRule()

    #expect(rule.apply(to: "text") == "text\n")
    #expect(rule.apply(to: "text\n\n\n\n") == "text\n")
    #expect(rule.apply(to: "text\n") == "text\n")
    #expect(rule.apply(to: "") == "")
}

// MARK: - The pass as a whole

@Test func aCleanNoteIsReportedAsUnchanged() {
    let note = "# Kickoff\n\n- One\n- Two\n"
    let result = CleanupRules.apply(to: note)

    #expect(result.text == note)
    #expect(!result.changedAnything)
    #expect(result.appliedRuleIDs.isEmpty)
}

@Test func aMessyNoteIsTidiedAndSaysWhichRulesFired() {
    let note = "##Kickoff   \n\n\n\n* one\n+ two"
    let result = CleanupRules.apply(to: note)

    #expect(result.text == "## Kickoff\n\n\n- one\n- two\n")
    #expect(result.changedAnything)
    #expect(result.appliedRuleIDs.contains("heading.spacing"))
    #expect(result.appliedRuleIDs.contains("list.marker"))
    #expect(result.appliedRuleIDs.contains("whitespace.trailing"))
}

@Test func rulesNeverReachInsideACodeFence() {
    let note = """
        Body.

        ```python
        items = [
            "*  not a bullet",


            "trailing space here   "
        ]
        ```
        """

    let result = CleanupRules.apply(to: note)

    // Everything inside the fence has to come back byte for byte. Tidying
    // indentation inside code changes what the code means.
    #expect(result.text.contains("\"*  not a bullet\""))
    #expect(result.text.contains("\"trailing space here   \""))
}

@Test func rulesNeverReachIntoFrontMatter() {
    let note = "---\ntags:   [a]\n\n\n\nauthor: x\n---\n\nBody."
    let result = CleanupRules.apply(to: note)

    #expect(result.text.hasPrefix("---\ntags:   [a]\n\n\n\nauthor: x\n---"))
}

@Test func aPassOverAnEmptyNoteDoesNothing() {
    let result = CleanupRules.apply(to: "")
    #expect(result.text.isEmpty)
    #expect(!result.changedAnything)
}

@Test func theRulePassIsIdempotent() {
    // Running twice must not keep changing the note, or the watcher and the
    // rule pass would chase each other forever.
    let note = "##Kickoff   \n\n\n\n* one\n+ two"
    let once = CleanupRules.apply(to: note)
    let twice = CleanupRules.apply(to: once.text)

    #expect(twice.text == once.text)
    #expect(!twice.changedAnything)
}
