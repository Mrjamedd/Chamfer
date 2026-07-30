import ChamferCore
import Foundation

/// The states the dashboard has to survive.
///
/// These are the design brief. A layout that only looks good under `.typical`
/// is not finished — most of the work is in `.empty`, `.flooded` and the
/// degraded states.
public enum Scenario: String, CaseIterable, Sendable, Identifiable {
    case firstRun
    case empty
    case typical
    case flooded
    case hugeNote
    case codeHeavy
    case sweeping
    case rewriteUnavailable
    case folderUnreachable
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .firstRun: "First run"
        case .empty: "Nothing to do"
        case .typical: "Typical"
        case .flooded: "Flooded (200)"
        case .hugeNote: "One huge note"
        case .codeHeavy: "Code-heavy note"
        case .sweeping: "Sweeping"
        case .rewriteUnavailable: "Rewrites off"
        case .folderUnreachable: "Folder gone"
        case .failed: "Failed"
        }
    }

    public var note: String {
        switch self {
        case .firstRun: "No folders added yet. The only screen a new user sees."
        case .empty: "Folders watched, queue clear. The resting state — most common by far."
        case .typical: "Three pending rewrites and a few rule-pass writes today."
        case .flooded: "200 pending after a first sweep of an old vault. Does the list survive?"
        case .hugeNote: "A 12,400-word note with 40 hunks in one proposal."
        case .codeHeavy: "Mostly code fences, so masking leaves almost nothing to rewrite."
        case .sweeping: "Initial sweep in progress with determinate progress."
        case .rewriteUnavailable: "Apple Intelligence off. Rules still run; half the UI is meaningless."
        case .folderUnreachable: "External disk unplugged, bookmark dead."
        case .failed: "Something broke and the user has to be told."
        }
    }
}

public enum Fixtures {
    /// Fixed so the gallery renders identically on every launch — a moving
    /// clock makes visual comparison between runs impossible.
    public static let now = Date(timeIntervalSince1970: 1_785_000_000)

    public static func state(for scenario: Scenario) -> DashboardState {
        switch scenario {
        case .firstRun:
            DashboardState(runState: .idle, folders: [], proposals: [], recentlyCleaned: [])

        case .empty:
            DashboardState(
                runState: .idle,
                folders: [vaultFolder(noteCount: 412)],
                proposals: [],
                recentlyCleaned: []
            )

        case .typical:
            DashboardState(
                runState: .idle,
                folders: [vaultFolder(noteCount: 412), archiveFolder()],
                proposals: typicalProposals(),
                recentlyCleaned: recentCleanups()
            )

        case .flooded:
            DashboardState(
                runState: .idle,
                folders: [vaultFolder(noteCount: 2_284)],
                proposals: (0..<200).map { floodProposal(index: $0) },
                recentlyCleaned: recentCleanups()
            )

        case .hugeNote:
            DashboardState(
                runState: .idle,
                folders: [vaultFolder(noteCount: 412)],
                proposals: [hugeProposal()],
                recentlyCleaned: []
            )

        case .codeHeavy:
            DashboardState(
                runState: .idle,
                folders: [vaultFolder(noteCount: 412)],
                proposals: [codeHeavyProposal()],
                recentlyCleaned: []
            )

        case .sweeping:
            DashboardState(
                runState: .sweeping(completed: 137, total: 412),
                folders: [vaultFolder(noteCount: 412, lastSweep: nil)],
                proposals: Array(typicalProposals().prefix(1)),
                recentlyCleaned: Array(recentCleanups().prefix(2))
            )

        case .rewriteUnavailable:
            DashboardState(
                runState: .rewritingUnavailable(
                    reason: "Apple Intelligence is turned off in System Settings."
                ),
                folders: [vaultFolder(noteCount: 412)],
                proposals: [],
                recentlyCleaned: recentCleanups()
            )

        case .folderUnreachable:
            DashboardState(
                runState: .idle,
                folders: [
                    vaultFolder(noteCount: 412),
                    WatchedFolder(
                        url: URL(fileURLWithPath: "/Volumes/Archive/Old Notes"),
                        noteCount: 1_902,
                        isReachable: false,
                        lastSweep: now.addingTimeInterval(-86_400 * 6)
                    )
                ],
                proposals: Array(typicalProposals().prefix(2)),
                recentlyCleaned: []
            )

        case .failed:
            DashboardState(
                runState: .failed(
                    message: "Couldn't write to “Meeting notes.md” — the file is read-only."
                ),
                folders: [vaultFolder(noteCount: 412)],
                proposals: Array(typicalProposals().prefix(1)),
                recentlyCleaned: recentCleanups()
            )
        }
    }

    // MARK: - Pieces

    static func vaultFolder(noteCount: Int, lastSweep: Date? = Fixtures.now.addingTimeInterval(-1_800)) -> WatchedFolder {
        WatchedFolder(url: SampleNotes.vault, noteCount: noteCount, lastSweep: lastSweep)
    }

    static func archiveFolder() -> WatchedFolder {
        WatchedFolder(
            url: URL(fileURLWithPath: "/Users/you/Notes/Archive"),
            noteCount: 88,
            lastSweep: now.addingTimeInterval(-86_400 * 2)
        )
    }

    static func note(_ title: String, file: String, words: Int, minutesAgo: Double) -> NoteSummary {
        NoteSummary(
            url: SampleNotes.url(file),
            title: title,
            wordCount: words,
            modifiedAt: now.addingTimeInterval(-60 * minutesAgo)
        )
    }

    static func typicalProposals() -> [Proposal] {
        let hunks = SampleNotes.ordinaryHunks.map {
            Hunk(before: $0.before, after: $0.after, startLine: $0.line)
        }
        return [
            Proposal(
                note: note("Standup 30 Jul", file: "Standup 30 Jul.md", words: 340, minutesAgo: 4),
                hunks: Array(hunks.prefix(2)),
                createdAt: now.addingTimeInterval(-180)
            ),
            Proposal(
                note: note(SampleNotes.longTitle, file: "Scheduling migration.md", words: 1_820, minutesAgo: 52),
                hunks: hunks,
                createdAt: now.addingTimeInterval(-2_400)
            ),
            Proposal(
                note: note("Reading list", file: "Reading list.md", words: 96, minutesAgo: 190),
                hunks: [hunks[2]],
                createdAt: now.addingTimeInterval(-9_000)
            )
        ]
    }

    static func floodProposal(index: Int) -> Proposal {
        let hunks = SampleNotes.ordinaryHunks.map {
            Hunk(before: $0.before, after: $0.after, startLine: $0.line)
        }
        return Proposal(
            note: note(
                "Daily note \(2_026_000 + index)",
                file: "daily/\(index).md",
                words: 120 + index * 3,
                minutesAgo: Double(index) * 7
            ),
            hunks: Array(hunks.prefix(index % 3 + 1)),
            createdAt: now.addingTimeInterval(-Double(index) * 60)
        )
    }

    static func hugeProposal() -> Proposal {
        let hunks = (0..<40).map { index in
            Hunk(
                before: SampleNotes.ordinaryHunks[index % 3].before,
                after: SampleNotes.ordinaryHunks[index % 3].after,
                startLine: 12 + index * 27
            )
        }
        return Proposal(
            note: note("Research dump", file: "Research dump.md", words: 12_400, minutesAgo: 15),
            hunks: hunks,
            createdAt: now.addingTimeInterval(-900)
        )
    }

    static func codeHeavyProposal() -> Proposal {
        Proposal(
            note: note("Parser fix", file: "Parser fix.md", words: 2_100, minutesAgo: 8),
            hunks: [
                Hunk(
                    before: SampleNotes.timidHunk.before,
                    after: SampleNotes.timidHunk.after,
                    startLine: SampleNotes.timidHunk.line
                )
            ],
            createdAt: now.addingTimeInterval(-480)
        )
    }

    static func recentCleanups() -> [CleanupRecord] {
        [
            CleanupRecord(
                note: note("Standup 30 Jul", file: "Standup 30 Jul.md", words: 340, minutesAgo: 4),
                rules: ["whitespace.trailing", "list.bullets"],
                appliedAt: now.addingTimeInterval(-240)
            ),
            CleanupRecord(
                note: note("Groceries", file: "Groceries.md", words: 42, minutesAgo: 66),
                rules: ["list.bullets"],
                appliedAt: now.addingTimeInterval(-3_960)
            ),
            CleanupRecord(
                note: note(SampleNotes.longTitle, file: "Scheduling migration.md", words: 1_820, minutesAgo: 52),
                rules: ["heading.levels", "whitespace.blankLines", "quotes.style", "dates.format"],
                appliedAt: now.addingTimeInterval(-3_120)
            )
        ]
    }
}
