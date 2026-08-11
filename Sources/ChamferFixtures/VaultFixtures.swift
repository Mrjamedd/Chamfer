import ChamferCore
import Foundation

/// Vaults, history and settings for the pages the release scope added.
///
/// Deliberately hostile, in the same spirit as the rest of the fixtures: the
/// vaults disagree with the defaults and with each other, the history runs
/// past the 200 the standard view shows, and the failures are the ones that
/// are awkward to render rather than the ones that are easy.
public extension Fixtures {
    static let personalVaultID = UUID(uuidString: "1E7C6F9A-0000-4000-8000-000000000001")!
    static let workVaultID = UUID(uuidString: "1E7C6F9A-0000-4000-8000-000000000002")!
    static let archiveVaultID = UUID(uuidString: "1E7C6F9A-0000-4000-8000-000000000003")!

    /// One vault on the defaults, one that has taken over half of them, and
    /// one that is unreachable — the three rows the page has to get right.
    static func vaults() -> [Vault] {
        [
            Vault(
                id: personalVaultID,
                url: SampleNotes.vault,
                noteCount: 412,
                lastSweep: now.addingTimeInterval(-1_800)
            ),
            Vault(
                id: workVaultID,
                url: URL(filePath: "/Users/you/Notes/Work"),
                noteCount: 168,
                lastSweep: now.addingTimeInterval(-5_400),
                // The awkward case: a vault configured to apply automatically,
                // on a schedule, protecting more than most vaults do.
                configuration: VaultConfiguration(
                    mode: .grammar,
                    application: .automatic,
                    runTrigger: .schedule,
                    sweep: .everyHours(6),
                    preserved: MarkdownStructure.standard.union(.headings)
                ),
                folders: [
                    WatchedFolder(
                        url: URL(filePath: "/Users/you/Notes/Work/Meetings"),
                        noteCount: 64,
                        lastSweep: now.addingTimeInterval(-5_400)
                    ),
                    WatchedFolder(
                        url: URL(filePath: "/Users/you/Notes/Work/Drafts"),
                        noteCount: 22,
                        lastSweep: now.addingTimeInterval(-9_000)
                    )
                ],
                rules: [
                    VaultRule(kind: .exclude, path: "Work/Archive"),
                    VaultRule(kind: .exclude, path: "Work/Shared with legal")
                ]
            ),
            Vault(
                id: archiveVaultID,
                url: URL(filePath: "/Volumes/Backup/Notes Archive"),
                availability: .offline,
                noteCount: 3_180,
                lastSweep: now.addingTimeInterval(-86_400 * 6),
                configuration: VaultConfiguration(
                    mode: .spelling,
                    application: .review,
                    runTrigger: .inactivity,
                    inactivityDelay: 600,
                    preserved: .standard
                )
            )
        ]
    }

    /// More than the standard view shows, so the "show everything" control at
    /// the foot of the timeline has something to reveal.
    static func history(count: Int = 214) -> [HistoryEntry] {
        (0..<count).map { index in
            let minutesAgo = Double(index) * 37 + 5
            let summary = note(
                historyTitles[index % historyTitles.count],
                file: "\(historyTitles[index % historyTitles.count]).md",
                words: 120 + index * 3,
                minutesAgo: minutesAgo
            )

            return HistoryEntry(
                note: summary,
                path: summary.url,
                vaultID: index % 3 == 0 ? workVaultID : personalVaultID,
                occurredAt: now.addingTimeInterval(-60 * minutesAgo),
                mode: RewriteMode.allCases[index % RewriteMode.allCases.count],
                modelID: index % 5 == 0 ? "cloud.sonnet" : "local.ollama",
                previousText: "teh quick brown fox\n\nand a  second  line",
                appliedText: "The quick brown fox\n\nand a second line",
                application: index % 3 == 0 ? .automatic : .review,
                sourceWasOutdated: index % 17 == 0,
                retryCount: index % 19 == 0 ? 2 : 0,
                outcome: outcome(at: index)
            )
        }
    }

    private static func outcome(at index: Int) -> HistoryEntry.Outcome {
        switch index % 13 {
        case 4: .failed(.preservationViolated([.codeBlocks, .frontMatter]))
        case 7: .failed(.fileChangedDuringProcessing)
        case 11: .reverted(at: now.addingTimeInterval(-60 * Double(index) * 30))
        default: .applied
        }
    }

    private static let historyTitles = [
        "Standup 30 Jul",
        "Reading list",
        "Launch checklist",
        "Project compass",
        "Garden log",
        "Loose ideas",
        "Small wins",
        "Questions worth keeping"
    ]

    /// A queue with every awkward state in it at once: outdated, failed,
    /// regenerating, and one produced by the cloud model.
    static func awkwardProposals() -> [Proposal] {
        let stale = note("Launch checklist", file: "Launch checklist.md", words: 265, minutesAgo: 5)
        return [
            Proposal(
                note: stale,
                hunks: [Hunk(before: "ship it friday", after: "Ship it on Friday.", startLine: 12)],
                createdAt: now.addingTimeInterval(-3_600),
                // Generated an hour ago against text that is now five minutes
                // old: outdated, and the page must say so.
                sourceModifiedAt: now.addingTimeInterval(-3_600),
                mode: .fullCleanup,
                vaultID: personalVaultID
            ),
            Proposal(
                note: note("Garden log", file: "Garden log.md", words: 118, minutesAgo: 90),
                hunks: [Hunk(before: "planted teh beans", after: "Planted the beans.", startLine: 3)],
                createdAt: now.addingTimeInterval(-1_200),
                mode: .spelling,
                modelID: "cloud.sonnet",
                vaultID: workVaultID
            ),
            Proposal(
                note: note("Loose ideas", file: "Loose ideas.md", words: 128, minutesAgo: 300),
                hunks: [],
                createdAt: now.addingTimeInterval(-600),
                mode: .clarity,
                vaultID: workVaultID,
                retryCount: 1,
                state: .failed(.cloudRequestFailed(detail: "The request timed out after 30 seconds."))
            ),
            Proposal(
                note: note("Small wins", file: "Small wins.md", words: 73, minutesAgo: 700),
                hunks: [Hunk(before: "did alot", after: "Did a lot.", startLine: 2)],
                createdAt: now.addingTimeInterval(-300),
                mode: .grammar,
                vaultID: personalVaultID,
                state: .regenerating
            )
        ]
    }

    /// A dashboard with all of the above in it, for driving the new pages.
    static func vaultScenario() -> DashboardState {
        var state = state(for: .typical)
        state.vaults = vaults()
        state.history = history()
        state.proposals = awkwardProposals()
        // The stale proposal's note has moved on since it was generated, which
        // is what makes it outdated rather than merely old.
        state.recentNotes = [
            note("Launch checklist", file: "Launch checklist.md", words: 271, minutesAgo: 5)
        ] + state.recentNotes.filter { $0.title != "Launch checklist" }
        return state
    }
}
