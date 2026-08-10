import Foundation

public enum CloudProvider: String, CaseIterable, Codable, Sendable {
    case openAI
    case anthropic
    case google

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-5.6-luna"
        case .anthropic: "claude-haiku-4-5"
        case .google: "gemini-3.6-flash"
        }
    }

    public init?(displayName: String) {
        switch displayName {
        case "OpenAI": self = .openAI
        case "Anthropic": self = .anthropic
        case "Google": self = .google
        default: return nil
        }
    }
}

public enum ModelAccessError: LocalizedError, Sendable {
    case invalidRequest
    case invalidResponse
    case emptyResponse
    case unavailable(String)
    case rejected(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Chamfer could not create the model request."
        case .invalidResponse:
            "The model returned an unreadable response."
        case .emptyResponse:
            "The model returned no text."
        case let .unavailable(reason):
            reason
        case let .rejected(status, message):
            message.isEmpty
                ? "The provider rejected the request (HTTP \(status))."
                : "The provider rejected the request (HTTP \(status)): \(message)"
        }
    }
}

public enum CloudAPIRequestFactory {
    public static func validationRequest(
        provider: CloudProvider,
        apiKey: String
    ) throws -> URLRequest {
        let urlString = switch provider {
        case .openAI:
            "https://api.openai.com/v1/models"
        case .anthropic:
            "https://api.anthropic.com/v1/models"
        case .google:
            "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1"
        }
        guard let url = URL(string: urlString) else {
            throw ModelAccessError.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        applyAuthentication(provider: provider, apiKey: apiKey, to: &request)
        return request
    }

    public static func rewriteRequest(
        provider: CloudProvider,
        apiKey: String,
        text: String,
        instructions: String = RewriteInstructions.standard,
        maximumResponseTokens: Int? = nil
    ) throws -> URLRequest {
        let rewriteInstruction = instructions
        let urlString = switch provider {
        case .openAI:
            "https://api.openai.com/v1/responses"
        case .anthropic:
            "https://api.anthropic.com/v1/messages"
        case .google:
            "https://generativelanguage.googleapis.com/v1beta/models/\(provider.defaultModel):generateContent"
        }
        guard let url = URL(string: urlString) else {
            throw ModelAccessError.invalidRequest
        }

        let body: [String: Any] = switch provider {
        case .openAI:
            [
                "model": provider.defaultModel,
                "instructions": rewriteInstruction,
                "input": text,
                "max_output_tokens": maximumResponseTokens ?? 4_096
            ]
        case .anthropic:
            [
                "model": provider.defaultModel,
                "max_tokens": maximumResponseTokens ?? 4_096,
                "system": rewriteInstruction,
                "messages": [["role": "user", "content": text]]
            ]
        case .google:
            [
                "systemInstruction": [
                    "parts": [["text": rewriteInstruction]]
                ],
                "contents": [[
                    "role": "user",
                    "parts": [["text": text]]
                ]],
                "generationConfig": [
                    "temperature": 0,
                    "maxOutputTokens": maximumResponseTokens ?? 4_096
                ]
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthentication(provider: provider, apiKey: apiKey, to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func applyAuthentication(
        provider: CloudProvider,
        apiKey: String,
        to request: inout URLRequest
    ) {
        switch provider {
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
    }
}

public enum CloudAPIResponseParser {
    public static func text(
        provider: CloudProvider,
        data: Data
    ) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw ModelAccessError.invalidResponse
        }

        let fragments: [String] = switch provider {
        case .openAI:
            (root["output"] as? [[String: Any]] ?? []).flatMap { output in
                (output["content"] as? [[String: Any]] ?? []).compactMap { item in
                    guard item["type"] as? String == "output_text" else { return nil }
                    return item["text"] as? String
                }
            }
        case .anthropic:
            (root["content"] as? [[String: Any]] ?? []).compactMap { item in
                guard item["type"] as? String == "text" else { return nil }
                return item["text"] as? String
            }
        case .google:
            (root["candidates"] as? [[String: Any]] ?? []).flatMap { candidate in
                let content = candidate["content"] as? [String: Any]
                return (content?["parts"] as? [[String: Any]] ?? []).compactMap {
                    $0["text"] as? String
                }
            }
        }

        let result = fragments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw ModelAccessError.emptyResponse }
        return result
    }
}

public struct CloudAPIClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func validate(provider: CloudProvider, apiKey: String) async throws {
        let request = try CloudAPIRequestFactory.validationRequest(
            provider: provider,
            apiKey: apiKey
        )
        _ = try await perform(request)
    }

    public func rewrite(
        provider: CloudProvider,
        apiKey: String,
        text: String,
        instructions: String = RewriteInstructions.standard,
        maximumResponseTokens: Int? = nil
    ) async throws -> String {
        let request = try CloudAPIRequestFactory.rewriteRequest(
            provider: provider,
            apiKey: apiKey,
            text: text,
            instructions: instructions,
            maximumResponseTokens: maximumResponseTokens
        )
        let data = try await perform(request)
        return try CloudAPIResponseParser.text(provider: provider, data: data)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelAccessError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelAccessError.rejected(
                status: http.statusCode,
                message: Self.errorMessage(from: data)
            )
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        if let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return root["message"] as? String ?? ""
    }
}

public struct CloudRewriter: Rewriter {
    public let provider: CloudProvider
    private let apiKey: String
    private let client: CloudAPIClient

    public init(
        provider: CloudProvider,
        apiKey: String,
        client: CloudAPIClient = CloudAPIClient()
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.client = client
    }

    public var isAvailable: Bool {
        get async {
            (try? await client.validate(provider: provider, apiKey: apiKey)) != nil
        }
    }

    public func rewrite(_ section: String, instructions: String) async throws -> String {
        try await rewrite(RewriteRequest(text: section), instructions: instructions)
    }

    public func rewrite(
        _ request: RewriteRequest,
        instructions: String
    ) async throws -> String {
        try await client.rewrite(
            provider: provider,
            apiKey: apiKey,
            text: request.prompt,
            instructions: instructions,
            maximumResponseTokens: request.maximumResponseTokens
        )
    }
}
