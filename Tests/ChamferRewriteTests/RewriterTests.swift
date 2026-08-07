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

@Test func openAIUsesTheResponsesAPIAndAggregatesOutputText() throws {
    let request = try CloudAPIRequestFactory.rewriteRequest(
        provider: .openAI,
        apiKey: "openai-secret",
        text: "Tighten this note."
    )

    #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-secret")

    let body = try #require(request.httpBody)
    let json = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    #expect(json["model"] as? String == "gpt-5.6-luna")

    let response = Data(#"{"output":[{"content":[{"type":"output_text","text":"First"}]},{"content":[{"type":"refusal","refusal":"no"},{"type":"output_text","text":" second"}]}]}"#.utf8)
    #expect(try CloudAPIResponseParser.text(provider: .openAI, data: response) == "First second")
}

@Test func anthropicUsesMessagesHeadersAndExtractsTextBlocks() throws {
    let request = try CloudAPIRequestFactory.rewriteRequest(
        provider: .anthropic,
        apiKey: "anthropic-secret",
        text: "Clean this up."
    )

    #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-secret")
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

    let response = Data(#"{"content":[{"type":"text","text":"Clean result"}]}"#.utf8)
    #expect(try CloudAPIResponseParser.text(provider: .anthropic, data: response) == "Clean result")
}

@Test func googleUsesGenerateContentAndExtractsCandidateParts() throws {
    let request = try CloudAPIRequestFactory.rewriteRequest(
        provider: .google,
        apiKey: "google-secret",
        text: "Rewrite."
    )

    #expect(
        request.url?.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent"
    )
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "google-secret")

    let response = Data(#"{"candidates":[{"content":{"parts":[{"text":"Google result"}]}}]}"#.utf8)
    #expect(try CloudAPIResponseParser.text(provider: .google, data: response) == "Google result")
}

@Test func ollamaRequestsAreLocalAndNeverCarryCredentials() throws {
    let pull = try OllamaAPI.pullRequest(model: "qwen3.5:4b")
    let chat = try OllamaAPI.chatRequest(
        model: "qwen3.5:4b",
        text: "Improve this."
    )

    #expect(pull.url?.absoluteString == "http://127.0.0.1:11434/api/pull")
    #expect(chat.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
    #expect(pull.allHTTPHeaderFields?["Authorization"] == nil)
    #expect(chat.allHTTPHeaderFields?["Authorization"] == nil)

    let body = try #require(chat.httpBody)
    let json = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    #expect(json["model"] as? String == "qwen3.5:4b")
    #expect(json["stream"] as? Bool == false)
    #expect(json["think"] as? Bool == false)

    let response = Data(#"{"message":{"role":"assistant","content":"Local result"}}"#.utf8)
    #expect(try OllamaAPI.chatText(from: response) == "Local result")
}

@Test func providerValidationUsesReadOnlyCatalogEndpoints() throws {
    let openAI = try CloudAPIRequestFactory.validationRequest(
        provider: .openAI,
        apiKey: "key"
    )
    let anthropic = try CloudAPIRequestFactory.validationRequest(
        provider: .anthropic,
        apiKey: "key"
    )
    let google = try CloudAPIRequestFactory.validationRequest(
        provider: .google,
        apiKey: "key"
    )

    #expect(openAI.httpMethod == "GET")
    #expect(openAI.url?.absoluteString == "https://api.openai.com/v1/models")
    #expect(anthropic.httpMethod == "GET")
    #expect(anthropic.url?.absoluteString == "https://api.anthropic.com/v1/models")
    #expect(google.httpMethod == "GET")
    #expect(google.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")
}

@Test func rewriterFactoryCreatesTheSelectedOnDeviceBackend() throws {
    let apple = try RewriterFactory.make(configuration: .apple)
    let local = try RewriterFactory.make(
        configuration: .local(modelID: "qwen3.5:4b")
    )

    #expect(apple is AppleFoundationRewriter)
    #expect(local is OllamaRewriter)
}
