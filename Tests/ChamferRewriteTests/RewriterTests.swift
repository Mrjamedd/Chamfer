import ChamferCore
import Foundation
import Testing

@testable import ChamferRewrite

/// A `Rewriter` that does nothing, proving the protocol can be satisfied
/// without a model. The review-queue suites use a fake like this so they never
/// need a downloaded model or a network to run.
private struct EchoRewriter: Rewriter {
    var isAvailable: Bool { get async { true } }
    func rewrite(_ section: String, instructions: String) async throws -> String {
        section
    }
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
        text: "Tighten this note.",
        maximumResponseTokens: 73
    )

    #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-secret")

    let body = try #require(request.httpBody)
    let json = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    #expect(json["model"] as? String == "gpt-5.6-luna")
    #expect(json["max_output_tokens"] as? Int == 73)

    let response = Data(#"{"output":[{"content":[{"type":"output_text","text":"First"}]},{"content":[{"type":"refusal","refusal":"no"},{"type":"output_text","text":" second"}]}]}"#.utf8)
    #expect(try CloudAPIResponseParser.text(provider: .openAI, data: response) == "First second")
}

@Test func anthropicUsesMessagesHeadersAndExtractsTextBlocks() throws {
    let request = try CloudAPIRequestFactory.rewriteRequest(
        provider: .anthropic,
        apiKey: "anthropic-secret",
        text: "Clean this up.",
        maximumResponseTokens: 74
    )

    #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-secret")
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let body = try #require(request.httpBody)
    let json = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    #expect(json["max_tokens"] as? Int == 74)

    let response = Data(#"{"content":[{"type":"text","text":"Clean result"}]}"#.utf8)
    #expect(try CloudAPIResponseParser.text(provider: .anthropic, data: response) == "Clean result")
}

@Test func googleUsesGenerateContentAndExtractsCandidateParts() throws {
    let request = try CloudAPIRequestFactory.rewriteRequest(
        provider: .google,
        apiKey: "google-secret",
        text: "Rewrite.",
        maximumResponseTokens: 75
    )

    #expect(
        request.url?.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"
    )
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "google-secret")
    let body = try #require(request.httpBody)
    let json = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    let generation = try #require(json["generationConfig"] as? [String: Any])
    #expect(generation["temperature"] as? Int == 0)
    #expect(generation["maxOutputTokens"] as? Int == 75)

    let response = Data(#"{"candidates":[{"content":{"parts":[{"text":"Google result"}]}}]}"#.utf8)
    #expect(try CloudAPIResponseParser.text(provider: .google, data: response) == "Google result")
}

@Test func ollamaRequestsAreLocalAndNeverCarryCredentials() throws {
    let pull = try OllamaAPI.pullRequest(model: "qwen3.5:4b")
    let chat = try OllamaAPI.chatRequest(
        model: "qwen3.5:4b",
        text: "Improve this.",
        maximumResponseTokens: 76,
        profile: ModelEffort.balanced.profile
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
    let options = try #require(json["options"] as? [String: Any])
    #expect(options["temperature"] as? Int == 0)
    #expect(options["num_predict"] as? Int == 76)
    // Sent explicitly. Ollama's own default is small enough to truncate a long
    // section's prompt, which loses the instructions at the top of it.
    #expect(options["num_ctx"] as? Int == ModelEffort.balanced.profile.contextTokens)

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

@Test func rewriterFactoryCreatesTheDownloadedLocalBackend() throws {
    let local = try RewriterFactory.make(
        configuration: .local(modelID: "qwen3.5:4b")
    )

    #expect(local is OllamaRewriter)
}

/// A vault stores `local.ollama` rather than a model name, and it resolves to
/// whatever this Mac was given. That indirection is what stops a policy written
/// on one machine downloading a second model on another.
@Test func theLocalIdentifierResolvesToThisMacsOwnModel() {
    let configuration = RewriterFactory.configuration(
        for: RewriterFactory.localModelIdentifier,
        localModelID: "qwen3.5:9b",
        cloudProvider: nil
    )

    #expect(configuration == .local(modelID: "qwen3.5:9b"))
}

/// Legacy state that named a specific model is honoured only while it is still
/// the model this Mac runs; otherwise the device's own answer wins.
@Test func aStaleStoredModelNameDoesNotOverrideTheDevicesModel() {
    #expect(
        RewriterFactory.configuration(
            for: "local.qwen3.5:0.8b",
            localModelID: "qwen3.5:9b",
            cloudProvider: nil
        ) == .local(modelID: "qwen3.5:9b")
    )
    #expect(
        RewriterFactory.configuration(
            for: "local.qwen3.5:9b",
            localModelID: "qwen3.5:9b",
            cloudProvider: nil
        ) == .local(modelID: "qwen3.5:9b")
    )
}

/// Apple's backend is gone. Nothing may resolve its identifier to a running
/// model, and in particular it must not silently become the cloud.
@Test func theRetiredAppleIdentifierResolvesToNothing() {
    #expect(
        RewriterFactory.configuration(
            for: "apple.foundation",
            localModelID: "qwen3.5:9b",
            cloudProvider: .anthropic
        ) == nil
    )
}
