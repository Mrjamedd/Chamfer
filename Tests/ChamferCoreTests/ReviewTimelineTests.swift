import Foundation
import Testing
@testable import ChamferCore

// MARK: - Helpers

private let clock = Date(timeIntervalSince1970: 1_800_000_000)

private func note(
    _ title: String,
    modified: Date = clock
) -> NoteSummary {
    NoteSummary(
        url: URL(filePath: "/Vault/\(title).md"),
        title: title,
        wordCount: 120,
        modifiedAt: modified
    )
}

private func proposal(
    _ title: String,
    vault: UUID? = nil,
    created: Date = clock,
    sourceModified: Date? = nil,
    state: ProposalState = .pending
) -> Proposal {
    Proposal(
        note: note(title, modified: sourceModified ?? created),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: created,
        sourceModifiedAt: sourceModified ?? created,
        vaultID: vault,
        state: state
    )
}

private func entry(_ title: String, at date: Date) -> HistoryEntry {
    HistoryEntry(
        note: note(title),
        path: URL(filePath: "/Vault/\(title).md"),
        occurredAt: date,
        mode: .fullCleanup,
        modelID: "local.ollama",
        previousText: "before",
        appliedText: "after",
        application: .automatic
    )
}

// MARK: - Grouping

@Test func pendingRewritesAreGroupedByVault() {
    let alpha = UUID()
    let beta = UUID()

    let timeline = ReviewTimelineBuilder.build(
        proposals: [
            proposal("One", vault: alpha),
            proposal("Two", vault: beta),
            proposal("Three", vault: alpha)
        ],
        history: [],
        vaultNames: [alpha: "Alpha", beta: "Beta"]
    )

    #expect(timeline.pending.count == 2)
    #expect(timeline.pending.map(\.vaultName) == ["Alpha", "Beta"])
    #expect(timeline.pending[0].proposals.count == 2)
    #expect(timeline.pendingCount == 3)
}

@Test func newestPendingRewriteComesFirstWithinItsVault() {
    let vault = UUID()
    let timeline = ReviewTimelineBuilder.build(
        proposals: [
            proposal("Older", vault: vault, created: clock.addingTimeInterval(-600)),
            proposal("Newer", vault: vault, created: clock)
        ],
        history: [],
        vaultNames: [vault: "Alpha"]
    )

    #expect(timeline.pending[0].proposals.map(\.note.title) == ["Newer", "Older"])
}

/// Filing a rewrite untidily is better than dropping it: a pending change the
/// user cannot see is the one thing the queue must never do.
@Test func rewritesWithNoVaultStillAppearLast() {
    let vault = UUID()
    let timeline = ReviewTimelineBuilder.build(
        proposals: [proposal("Loose"), proposal("Filed", vault: vault)],
        history: [],
        vaultNames: [vault: "Alpha"]
    )

    #expect(timeline.pending.count == 2)
    #expect(timeline.pending.last?.vaultName == "Unfiled")
    #expect(timeline.pendingCount == 2)
}

@Test func judgedRewritesLeaveThePendingSection() {
    let timeline = ReviewTimelineBuilder.build(
        proposals: [
            proposal("Accepted", state: .accepted),
            proposal("Rejected", state: .rejected),
            proposal("Waiting"),
            proposal("Broken", state: .failed(.vaultUnavailable)),
            proposal("Working", state: .regenerating)
        ],
        history: [],
        vaultNames: [:]
    )

    // Failed and regenerating rewrites are still the user's business — they
    // carry a retry — so only accepted and rejected leave.
    #expect(timeline.pendingCount == 3)
}

// MARK: - The past

@Test func historyFollowsPendingNewestFirst() {
    let timeline = ReviewTimelineBuilder.build(
        proposals: [],
        history: [
            entry("Old", at: clock.addingTimeInterval(-7_200)),
            entry("Recent", at: clock),
            entry("Middle", at: clock.addingTimeInterval(-3_600))
        ],
        vaultNames: [:]
    )

    #expect(timeline.past.map(\.note.title) == ["Recent", "Middle", "Old"])
}

@Test func theStandardViewStopsAtTwoHundredAndSaysHowManyMoreThereAre() {
    let history = (0..<250).map {
        entry("Note \($0)", at: clock.addingTimeInterval(-Double($0) * 60))
    }

    let timeline = ReviewTimelineBuilder.build(
        proposals: [],
        history: history,
        vaultNames: [:]
    )

    #expect(timeline.past.count == 200)
    #expect(timeline.storedCount == 250)
    #expect(timeline.hasMoreStored)
    #expect(timeline.hiddenCount == 50)
}

/// The control at the foot of the scroll is the only way into the full
/// history, so it must not appear when it would reveal nothing.
@Test func theShowEverythingControlHidesWhenNothingIsHidden() {
    let history = (0..<12).map {
        entry("Note \($0)", at: clock.addingTimeInterval(-Double($0) * 60))
    }
    let timeline = ReviewTimelineBuilder.build(
        proposals: [],
        history: history,
        vaultNames: [:]
    )

    #expect(!timeline.hasMoreStored)
    #expect(timeline.hiddenCount == 0)
}

@Test func askingForEverythingReturnsEverything() {
    let history = (0..<250).map {
        entry("Note \($0)", at: clock.addingTimeInterval(-Double($0) * 60))
    }
    let timeline = ReviewTimelineBuilder.build(
        proposals: [],
        history: history,
        vaultNames: [:],
        limit: .max
    )

    #expect(timeline.past.count == 250)
    #expect(!timeline.hasMoreStored)
}

// MARK: - Outdated sources

@Test func aRewriteGoesOutdatedWhenTheNoteChangesUnderIt() {
    let generated = proposal("Draft", created: clock, sourceModified: clock)

    #expect(!generated.isOutdated(currentModification: clock))
    #expect(!generated.isOutdated(currentModification: clock.addingTimeInterval(-60)))
    #expect(generated.isOutdated(currentModification: clock.addingTimeInterval(60)))
}

/// A note we have not seen change is not outdated. Guessing "probably" here
/// would put a warning on every rewrite in the queue.
@Test func aNoteWithNoKnownModificationIsNotTreatedAsOutdated() {
    #expect(!proposal("Draft").isOutdated(currentModification: nil))
}

@Test func dashboardStateResolvesOutdatednessFromTheNotesItHasSeen() {
    let stale = proposal("Draft", created: clock, sourceModified: clock)
    var state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [stale],
        recentlyCleaned: []
    )

    #expect(!state.isOutdated(stale))

    state.recentNotes = [note("Draft", modified: clock.addingTimeInterval(300))]
    #expect(state.isOutdated(stale))
}

// MARK: - Selection

@Test func bulkActionsTouchOnlyWhatWasSelected() {
    let first = proposal("One")
    let second = proposal("Two")
    let third = proposal("Three")

    var selection = ReviewSelection()
    selection.toggle(first.id)
    selection.toggle(third.id)

    let resolved = selection.resolve(in: [first, second, third])
    #expect(resolved.map(\.note.title) == ["One", "Three"])
}

@Test func selectingSomethingTwiceDeselectsIt() {
    let target = proposal("One")
    var selection = ReviewSelection()

    selection.toggle(target.id)
    #expect(selection.contains(target.id))

    selection.toggle(target.id)
    #expect(!selection.contains(target.id))
    #expect(selection.isEmpty)
}

/// A tick left behind by a rewrite that has since been accepted must not
/// quietly widen the next bulk action.
@Test func selectionDropsRewritesThatAreNoLongerPending() {
    var accepted = proposal("One")
    let waiting = proposal("Two")

    var selection = ReviewSelection()
    selection.toggle(accepted.id)
    selection.toggle(waiting.id)
    accepted.state = .accepted

    #expect(selection.resolve(in: [accepted, waiting]).map(\.note.title) == ["Two"])

    selection.prune(against: [accepted, waiting])
    #expect(selection.count == 1)
}
