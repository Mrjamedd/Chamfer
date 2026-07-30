import Foundation
import Testing

@testable import ChamferRewrite

/// A `Rewriter` that does nothing, proving the protocol can be satisfied
/// without a model. The review-queue suites use a fake like this so they never
/// need Apple Intelligence to run.
private struct EchoRewriter: Rewriter {
    var isAvailable: Bool { get async { true } }
    func rewrite(_ section: String) async throws -> String { section }
}

@Test func fakeRewriterSatisfiesTheProtocol() async throws {
    let rewriter = EchoRewriter()
    #expect(await rewriter.isAvailable)
    #expect(try await rewriter.rewrite("unchanged") == "unchanged")
}
