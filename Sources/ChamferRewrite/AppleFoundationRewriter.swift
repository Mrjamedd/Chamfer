import Foundation

#if canImport(FoundationModels)
import FoundationModels

public struct AppleFoundationRewriter: Rewriter {
    public init() {}

    public var isAvailable: Bool {
        get async { SystemLanguageModel.default.isAvailable }
    }

    public func rewrite(_ section: String) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw ModelAccessError.unavailable(
                "Apple Intelligence is not available on this Mac."
            )
        }
        let session = LanguageModelSession(instructions: """
            Improve the supplied note while preserving its meaning, Markdown, links, code, and factual claims. Return only the revised note text.
            """)
        let response = try await session.respond(to: section)
        let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw ModelAccessError.emptyResponse }
        return result
    }
}
#else
public struct AppleFoundationRewriter: Rewriter {
    public init() {}

    public var isAvailable: Bool { get async { false } }

    public func rewrite(_ section: String) async throws -> String {
        throw ModelAccessError.unavailable(
            "Apple Foundation Models are not present in this macOS SDK."
        )
    }
}
#endif
