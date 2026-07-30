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

    /// A cleaned note, long enough that the page has to handle real reading
    /// length rather than two decorative paragraphs.
    static let migrationBody = """
    # Thoughts on the scheduling migration

    We finally moved off the old scheduling system last week, and it went \
    better than any of us expected. Writing this down while it is still fresh, \
    mostly so the next person who has to do something like this has something \
    to read that isn't a postmortem.

    The short version: the migration itself took an afternoon. Everything \
    around the migration took five weeks.

    ## What actually broke

    The retry logic kept breaking: it retried without any backoff, producing a \
    thundering herd every time a downstream service so much as flinched. We \
    knew about this. We had known about it for a year. It never made it above \
    the line on any planning document because it only hurt during incidents, \
    and during incidents nobody is writing tickets.

    Fixing it turned out to be nine lines. That ratio — a year of ambient pain \
    against nine lines — is the thing I keep turning over.

    ## What went well

    Running both systems side by side for a fortnight was the single best \
    decision. It cost us some duplicated work and a slightly confusing \
    dashboard, and in exchange we got to be wrong in private.

    We also wrote the rollback before the migration, which felt like \
    superstition at the time and like basic hygiene afterwards.

    ## Open questions

    Who owns the queue now? Is the old dashboard still wired up to anything? \
    Do we still need the nightly job, or was that only there to paper over the \
    retry problem we have now fixed?

    None of these are urgent. All of them will be embarrassing in six months \
    if nobody writes the answers down.
    """

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
