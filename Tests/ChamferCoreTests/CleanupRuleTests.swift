import Foundation
import Testing

@testable import ChamferCore

/// Scaffold-level checks only. The real suites are golden-file tests over the
/// rule set, added rule by rule as each one is implemented.
private struct TrimTrailingSpaces: CleanupRule {
    let identifier = "whitespace.trailing"

    func apply(to text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.reversed().drop(while: { $0 == " " }).reversed() }
            .map(String.init)
            .joined(separator: "\n")
    }
}

@Test func ruleRemovesTrailingSpaces() {
    let rule = TrimTrailingSpaces()
    #expect(rule.apply(to: "a note   \nsecond line  ") == "a note\nsecond line")
}

@Test func ruleLeavesCleanTextUnchanged() {
    let rule = TrimTrailingSpaces()
    let clean = "# Heading\n\nA tidy paragraph."
    #expect(rule.apply(to: clean) == clean)
}

@Test func documentsCompareByURLAndText() {
    let url = URL(fileURLWithPath: "/tmp/note.md")
    #expect(NoteDocument(url: url, text: "x") == NoteDocument(url: url, text: "x"))
    #expect(NoteDocument(url: url, text: "x") != NoteDocument(url: url, text: "y"))
}
