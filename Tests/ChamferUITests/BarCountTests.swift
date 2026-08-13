import ChamferCore
import Foundation
import Testing

@testable import ChamferUI

// MARK: - Helpers

private let clock = Date(timeIntervalSince1970: 1_800_000_000)

private func proposal(_ title: String, state: ProposalState = .pending) -> Proposal {
    Proposal(
        note: NoteSummary(
            url: URL(filePath: "/Vault/\(title).md"),
            title: title,
            wordCount: 100,
            modifiedAt: clock
        ),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: clock,
        state: state
    )
}

private func state(_ proposals: [Proposal]) -> DashboardState {
    DashboardState(
        runState: .idle,
        folders: [],
        proposals: proposals,
        recentlyCleaned: []
    )
}

private func reviewItem(_ proposals: [Proposal]) -> BottomBar.Item? {
    DashboardBottomBarItems
        .make(for: state(proposals))
        .first { $0.id == DashboardView.Tab.review }
}

// MARK: - The count

@Test func theReviewItemCarriesHowManyRewritesAreWaiting() {
    let item = reviewItem([proposal("One"), proposal("Two"), proposal("Three")])
    #expect(item?.count == 3)
    #expect(item?.visibleCount == 3)
}

@Test func anEmptyQueueDrawsNoCountAtAll() {
    let item = reviewItem([])
    // Zero and nil are different facts, and only one of them would be a bug to
    // change — but neither draws anything.
    #expect(item?.count == 0)
    #expect(item?.visibleCount == nil)
}

@Test func onlyRewritesStillAwaitingJudgementAreCounted() {
    let item = reviewItem([
        proposal("Waiting"),
        proposal("Accepted", state: .accepted),
        proposal("Rejected", state: .rejected)
    ])

    // A count that included judged rewrites would keep asking for attention
    // that has already been given.
    #expect(item?.count == 1)
}

@Test func failedAndRegeneratingRewritesCountEverywhereTheyRemainActionable() {
    let item = reviewItem([
        proposal("Waiting"),
        proposal("Regenerating", state: .regenerating),
        proposal("Failed", state: .failed(.vaultUnavailable)),
        proposal("Accepted", state: .accepted),
        proposal("Rejected", state: .rejected)
    ])

    #expect(item?.count == 3)
    #expect(item?.entries.count == 3)
}

@Test func reviewEntryCountsOnlyChangesStillKeptForAcceptance() {
    let hunks = [
        Hunk(before: "teh first", after: "the first", startLine: 1),
        Hunk(before: "teh second", after: "the second", startLine: 3)
    ]
    var partial = Proposal(
        note: NoteSummary(
            url: URL(filePath: "/Vault/Partial.md"),
            title: "Partial",
            wordCount: 4,
            modifiedAt: clock
        ),
        hunks: hunks,
        createdAt: clock
    )
    partial.setHunkSelected(hunks[1].id, selected: false)

    #expect(reviewItem([partial])?.entries.first?.detail == "1 change")
}

@Test func theOtherDestinationsDoNotCountAnything() {
    let items = DashboardBottomBarItems.make(for: state([proposal("One")]))

    for item in items where item.id != DashboardView.Tab.review {
        // Nil rather than zero: these destinations are not places things
        // accumulate, and a zero would imply they could be.
        #expect(item.count == nil)
        #expect(item.visibleCount == nil)
    }
}

@Test func theBarStillCarriesExactlyThreeDestinations() {
    // The count rides on an existing item. It is not a fourth thing.
    #expect(DashboardBottomBarItems.make(for: state([proposal("One")])).count == 3)
}
