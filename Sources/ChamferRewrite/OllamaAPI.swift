import ChamferCore
import Foundation

public enum OllamaAPI {
    /// Where a runtime somebody installed themselves listens.
    ///
    /// Checked first: if there is already an Ollama on this Mac, Chamfer uses
    /// it rather than running a second copy of the same server.
    public static let sharedBaseURL = URL(string: "http://127.0.0.1:11434")!

    /// Where Chamfer's own runtime listens.
    ///
    /// Deliberately not 11434. Chamfer's copy is a private helper, and binding
    /// the well-known port would fight whatever the user runs themselves —
    /// and would leave *their* Ollama unable to start while Chamfer was open.
    public static let privateBaseURL = URL(string: "http://127.0.0.1:11913")!

    public static func healthRequest(baseURL: URL = sharedBaseURL) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api/version"))
        request.timeoutInterval = 2
        return request
    }

    public static func modelsRequest(baseURL: URL = sharedBaseURL) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api/tags"))
        request.timeoutInterval = 5
        return request
    }

    /// Streamed, so the download has something to report while it runs. A
    /// multi-gigabyte pull behind a single blocking request gives the interface
    /// nothing to draw for several minutes, which reads as a hang.
    public static func pullRequest(
        model: String,
        baseURL: URL = sharedBaseURL
    ) throws -> URLRequest {
        var request = try jsonRequest(
            baseURL: baseURL,
            path: "api/pull",
            body: ["model": model, "stream": true]
        )
        request.timeoutInterval = 86_400
        return request
    }

    public static func chatRequest(
        model: String,
        text: String,
        instructions: String = RewriteInstructions.standard,
        maximumResponseTokens: Int? = nil,
        profile: ModelEffortProfile = ModelEffort.standard.profile,
        baseURL: URL = sharedBaseURL
    ) throws -> URLRequest {
        try jsonRequest(
            baseURL: baseURL,
            path: "api/chat",
            body: [
                "model": model,
                "stream": false,
                // Hybrid-reasoning models think before answering when asked to.
                // Only Max asks: below it the deliberation costs more time than
                // the edit it is deciding on, and the mode has promised speed.
                "think": profile.allowsDeliberation,
                // Held in memory between the requests of one note. Without it
                // the weights are unloaded and reloaded between paragraphs,
                // which dominates the time a rewrite takes.
                "keep_alive": "10m",
                "options": [
                    // Temperature pinned low: this is an editing task with a
                    // right answer, and a model feeling creative about
                    // someone's notes is the failure mode the whole review
                    // queue exists to catch.
                    "temperature": 0,
                    // Sent explicitly. Ollama's own default context is small
                    // enough to truncate a long section's prompt silently, and
                    // a truncated prompt loses the instructions at the top of
                    // it — which reads as the model ignoring its mode rather
                    // than as a configuration problem.
                    "num_ctx": profile.contextTokens,
                    "num_predict": maximumResponseTokens
                        ?? profile.responseTokenCeiling
                ],
                "messages": [
                    ["role": "system", "content": instructions],
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
        return LocalModelIdentity.normalized(
            models.compactMap { model in
                (model["name"] as? String) ?? (model["model"] as? String)
            }
        )
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

    /// One line of a streamed pull.
    ///
    /// Returns nil for a line that carries no progress — a blank keep-alive, or
    /// a status the runtime emits before it knows the size of anything. Throws
    /// only for a line that reports a real failure, so the caller can stop.
    public static func pullProgress(
        from line: String
    ) throws -> LocalModelDownloadProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else { return nil }

        if let error = root["error"] as? String, !error.isEmpty {
            throw ModelAccessError.rejected(status: 500, message: error)
        }

        let stage = (root["status"] as? String) ?? "downloading"
        let completed = (root["completed"] as? NSNumber)?.uint64Value ?? 0
        let total = (root["total"] as? NSNumber)?.uint64Value

        let fraction: Double? = if let total, total > 0 {
            min(1, Double(completed) / Double(total))
        } else {
            nil
        }

        return LocalModelDownloadProgress(
            fraction: fraction,
            completedBytes: completed,
            totalBytes: total,
            stage: stage
        )
    }

    private static func jsonRequest(
        baseURL: URL = sharedBaseURL,
        path: String,
        body: [String: Any]
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

/// The server the app is actually using, resolved once at launch.
///
/// Chamfer speaks to whichever runtime provisioning settled on — the user's own
/// on the well-known port, or Chamfer's private child process. Everything
/// downstream (the model installer, the rewriter, the dashboard's probe) builds
/// its client from here rather than being handed the URL, so there is one place
/// that knows and no chance of half the app talking to the wrong server.
public final class OllamaEndpoint: @unchecked Sendable {
    public static let shared = OllamaEndpoint()

    private let lock = NSLock()
    private var storage = OllamaAPI.sharedBaseURL

    public var current: URL {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

public struct OllamaClient: Sendable {
    private let session: URLSession
    /// Which server this client speaks to — the user's own, or the private one
    /// Chamfer runs for itself.
    public let baseURL: URL

    /// A nil `baseURL` means "wherever the app resolved to", read at the moment
    /// the client is made rather than baked in at launch.
    public init(
        session: URLSession = .shared,
        baseURL: URL? = nil
    ) {
        self.session = session
        self.baseURL = baseURL ?? OllamaEndpoint.shared.current
    }

    /// The same client pointed somewhere else.
    public func addressing(_ baseURL: URL) -> OllamaClient {
        OllamaClient(session: session, baseURL: baseURL)
    }

    public func isAvailable() async -> Bool {
        guard let (_, response) = try? await session.data(
            for: OllamaAPI.healthRequest(baseURL: baseURL)
        ), let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    public func installedModelIDs() async throws -> Set<String> {
        let data = try await perform(OllamaAPI.modelsRequest(baseURL: baseURL))
        return try OllamaAPI.installedModelIDs(from: data)
    }

    /// Runs to completion or throws. Never reports success for a pull that was
    /// cut short — `LocalModelInstaller` re-checks presence afterwards anyway,
    /// so a partial download stays absent rather than becoming a registered
    /// model with nothing behind it.
    public func pull(
        model: String,
        onProgress: (@Sendable (LocalModelDownloadProgress) -> Void)? = nil
    ) async throws {
        let request = try OllamaAPI.pullRequest(model: model, baseURL: baseURL)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelAccessError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelAccessError.rejected(
                status: http.statusCode,
                message: "Ollama refused to download \(model)."
            )
        }

        for try await line in bytes.lines {
            if let progress = try OllamaAPI.pullProgress(from: line) {
                onProgress?(progress)
            }
        }
    }

    public func rewrite(
        model: String,
        text: String,
        instructions: String = RewriteInstructions.standard,
        maximumResponseTokens: Int? = nil,
        profile: ModelEffortProfile = ModelEffort.standard.profile
    ) async throws -> String {
        let request = try OllamaAPI.chatRequest(
            model: model,
            text: text,
            instructions: instructions,
            maximumResponseTokens: maximumResponseTokens,
            profile: profile,
            baseURL: baseURL
        )
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
            return LocalModelIdentity.contains(model, in: models)
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
            model: model,
            text: request.prompt,
            instructions: instructions,
            maximumResponseTokens: request.maximumResponseTokens,
            profile: request.effort.profile
        )
    }
}
