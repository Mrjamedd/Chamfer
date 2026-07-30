import Foundation

/// Real-looking messy note text, so the UI is designed against prose that
/// wraps, breaks and overflows the way actual notes do.
enum SampleNotes {
    static let vault = URL(fileURLWithPath: "/Users/you/Notes")

    static func url(_ name: String) -> URL {
        vault.appendingPathComponent(name)
    }

    /// Deliberately awkward: a title long enough to need truncation anywhere
    /// it is shown in a constrained row.
    static let longTitle =
        "Thoughts on the migration away from the old scheduling system and what we learned"

    static let ordinaryHunks: [(before: String, after: String, line: Int)] = [
        (
            "so basically the thing that kept braking was the retry logic, it woudl retry but not back off at all so you get a thundering herd",
            "The retry logic kept breaking: it retried without any backoff, producing a thundering herd.",
            12
        ),
        (
            "we shoudl probably write this down somewhere proper insted of in here",
            "We should write this down somewhere more permanent than this note.",
            28
        ),
        (
            "questions - who owns the queue now? - is the old dashboard still wired up - do we still need the nightly job",
            "Open questions:\n- Who owns the queue now?\n- Is the old dashboard still wired up?\n- Do we still need the nightly job?",
            41
        )
    ]

    static let timidHunk = (
        before: "notes on the parser fix",
        after: "Notes on the parser fix",
        line: 3
    )

    static let rules = [
        "heading.levels",
        "list.bullets",
        "whitespace.blankLines",
        "whitespace.trailing",
        "quotes.style",
        "dates.format",
        "links.syntax",
        "list.numbering"
    ]
}
