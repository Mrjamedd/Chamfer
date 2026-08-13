import ChamferCore
import Foundation
import Testing

@testable import ChamferUI

private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

private func proposal(
    automaticReviewReason: RewriteReviewRecommendation? = nil,
    state: ProposalState = .pending
) -> Proposal {
    Proposal(
        note: NoteSummary(
            url: URL(filePath: "/Vault/Review.md"),
            title: "Review",
            wordCount: 2,
            modifiedAt: timestamp
        ),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: timestamp,
        automaticReviewReason: automaticReviewReason,
        state: state
    )
}

@Test func intentionalReviewProposalUsesNeutralCardTint() throws {
    let configuration = VaultConfiguration(
        mode: .spelling,
        application: .review,
        runTrigger: .inactivity,
        inactivityDelay: 300,
        preserved: .standard
    )
    let policy = try #require(configuration.resolve(modelID: "test"))
    let decision = RewriteApplicationDecision.decide(
        requested: policy.application,
        recommendation: .broaderThanExpectedForMode
    )
    let automaticReason: RewriteReviewRecommendation?
    switch decision {
    case let .queueForReview(reason):
        automaticReason = reason
    case .applyAutomatically:
        Issue.record("A Review vault must always queue its rewrite")
        return
    }

    let queued = proposal(automaticReviewReason: automaticReason)

    #expect(queued.automaticReviewReason == nil)
    #expect(PendingRewriteCardTone.resolve(for: queued, isOutdated: false) == .neutral)
}

@Test func pendingRewriteCardTonesKeepAllFourStatesDistinct() {
    let ordinary = proposal()
    let held = proposal(automaticReviewReason: .broaderThanExpectedForMode)
    let failed = proposal(
        automaticReviewReason: .broaderThanExpectedForMode,
        state: .failed(.vaultUnavailable)
    )

    #expect(PendingRewriteCardTone.resolve(for: ordinary, isOutdated: false) == .neutral)
    #expect(PendingRewriteCardTone.resolve(for: held, isOutdated: false) == .heldForReview)
    #expect(PendingRewriteCardTone.resolve(for: ordinary, isOutdated: true) == .outdated)
    #expect(PendingRewriteCardTone.resolve(for: held, isOutdated: true) == .outdated)
    #expect(PendingRewriteCardTone.resolve(for: failed, isOutdated: true) == .failed)
}
