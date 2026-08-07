import Foundation

public enum RewriteBackendConfiguration: Equatable, Sendable {
    case apple
    case local(modelID: String)
    case cloud(provider: CloudProvider)
}

/// Creates the same real backend selected on the Models screen. Cloud secrets
/// are resolved from Keychain at the last responsible moment and are never
/// copied into preferences.
public enum RewriterFactory {
    public static func make(
        configuration: RewriteBackendConfiguration,
        keyStore: APIKeyStore = .shared
    ) throws -> any Rewriter {
        switch configuration {
        case .apple:
            return AppleFoundationRewriter()
        case let .local(modelID):
            return OllamaRewriter(model: modelID)
        case let .cloud(provider):
            guard let apiKey = try keyStore.load(for: provider), !apiKey.isEmpty else {
                throw ModelAccessError.unavailable(
                    "Connect \(provider.displayName) in Models before using it."
                )
            }
            return CloudRewriter(provider: provider, apiKey: apiKey)
        }
    }
}
