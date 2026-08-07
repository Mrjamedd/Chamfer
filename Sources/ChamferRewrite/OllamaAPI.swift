import Foundation

public enum OllamaAPI {
    public static let baseURL = URL(string: "http://127.0.0.1:11434")!

    public static func healthRequest() -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api/version"))
        request.timeoutInterval = 2
        return request
    }

    public static func modelsRequest() -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api/tags"))
        request.timeoutInterval = 5
        return request
    }

    public static func pullRequest(model: String) throws -> URLRequest {
        var request = try jsonRequest(
            path: "api/pull",
            body: ["model": model, "stream": false]
        )
        request.timeoutInterval = 86_400
        return request
    }

    public static func chatRequest(model: String, text: String) throws -> URLRequest {
        try jsonRequest(
            path: "api/chat",
            body: [
                "model": model,
                "stream": false,
                "think": false,
                "messages": [
                    [
                        "role": "system",
                        "content": "Improve the note while preserving meaning and Markdown. Return only the revised note."
                    ],
                    ["role": "user", "content": text]
                ]
            ]
        )
    }

    public static func installedModelIDs(from data: Data) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let models = root["models"] as? [[String: Any]] else {
            throw ModelAccessError.invalidResponse
        }
        return Set(models.compactMap { model in
            (model["name"] as? String) ?? (model["model"] as? String)
        })
    }

    public static func chatText(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let message = root["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ModelAccessError.invalidResponse
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw ModelAccessError.emptyResponse }
        return result
    }

    private static func jsonRequest(
        path: String,
        body: [String: Any]
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

public struct OllamaClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func isAvailable() async -> Bool {
        guard let (_, response) = try? await session.data(
            for: OllamaAPI.healthRequest()
        ), let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    public func installedModelIDs() async throws -> Set<String> {
        let data = try await perform(OllamaAPI.modelsRequest())
        return try OllamaAPI.installedModelIDs(from: data)
    }

    public func pull(model: String) async throws {
        _ = try await perform(try OllamaAPI.pullRequest(model: model))
    }

    public func rewrite(model: String, text: String) async throws -> String {
        let request = try OllamaAPI.chatRequest(model: model, text: text)
        let data = try await perform(request)
        return try OllamaAPI.chatText(from: data)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelAccessError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelAccessError.rejected(
                status: http.statusCode,
                message: "Ollama could not complete the request."
            )
        }
        return data
    }
}

public struct OllamaRewriter: Rewriter {
    public let model: String
    private let client: OllamaClient

    public init(model: String, client: OllamaClient = OllamaClient()) {
        self.model = model
        self.client = client
    }

    public var isAvailable: Bool {
        get async {
            guard await client.isAvailable(),
                  let models = try? await client.installedModelIDs() else {
                return false
            }
            return models.contains(model)
        }
    }

    public func rewrite(_ section: String) async throws -> String {
        try await client.rewrite(model: model, text: section)
    }
}
