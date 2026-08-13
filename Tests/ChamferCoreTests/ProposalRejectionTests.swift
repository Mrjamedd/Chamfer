import Foundation
import Testing

@testable import ChamferCore

private func selectionProposal() -> Proposal {
    Proposal(
        note: NoteSummary(
            url: URL(filePath: "/Vault/Review.md"),
            title: "Review",
            wordCount: 8,
            modifiedAt: Date(timeIntervalSince1970: 100)
        ),
        hunks: [
            Hunk(before: "teh first", after: "the first", startLine: 2),
            Hunk(before: "teh second", after: "the second", startLine: 4),
            Hunk(before: "teh third", after: "the third", startLine: 6)
        ],
        baseText: "Intro\nteh first\nMiddle\nteh second\nLater\nteh third",
        proposedText: "Intro\nthe first\nMiddle\nthe second\nLater\nthe third",
        createdAt: Date(timeIntervalSince1970: 200)
    )
}

@Test func excludedHunksStayOfferedWhileKeptHunksAndCountFollowTheSelection() {
    var proposal = selectionProposal()
    let excluded = proposal.hunks[1]

    proposal.setHunkSelected(excluded.id, selected: false)

    #expect(proposal.hunks.count == 3)
    #expect(proposal.excludedHunkIDs == [excluded.id])
    #expect(proposal.keptHunks.map(\.id) == [proposal.hunks[0].id, proposal.hunks[2].id])
    #expect(proposal.changeCount == 2)

    proposal.setHunkSelected(excluded.id, selected: true)

    #expect(proposal.excludedHunkIDs.isEmpty)
    #expect(proposal.keptHunks == proposal.hunks)
    #expect(proposal.changeCount == 3)
}

@Test func proposalQueuesSavedBeforeChangeSelectionStillDecodeWithEveryHunkSelected() throws {
    let proposal = selectionProposal()
    let encoded = try JSONEncoder().encode(proposal)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "rejectedHunkIDs")
    let legacy = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(Proposal.self, from: legacy)

    #expect(decoded.excludedHunkIDs.isEmpty)
    #expect(decoded.keptHunks == proposal.hunks)
    #expect(decoded.changeCount == proposal.hunks.count)
}

@Test func excludedHunkStateSurvivesQueueEncoding() throws {
    var proposal = selectionProposal()
    proposal.setHunkSelected(proposal.hunks[0].id, selected: false)

    let decoded = try JSONDecoder().decode(
        Proposal.self,
        from: JSONEncoder().encode(proposal)
    )

    #expect(decoded == proposal)
    #expect(decoded.excludedHunkIDs == [proposal.hunks[0].id])
}
