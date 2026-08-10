import ChamferCore
import Foundation

public enum RewriteBackendConfiguration: Equatable, Sendable {
    case local(modelID: String)
    case cloud(provider: CloudProvider)
}

/// Creates the same real backend the Models dashboard is showing. Cloud secrets
/// are resolved from Keychain at the last responsible moment and are never
/// copied into preferences.
public enum RewriterFactory {
    /// The identifier a policy stores for "the model on this Mac". Defined in
    /// `ChamferCore` because vault policies are written there; restated here so
    /// callers resolving a backend do not have to reach past this type.
    public static let localModelIdentifier = RewritePolicy.localModelIdentifier

    /// Turns a policy's model identifier into something that can actually run.
    ///
    /// A policy says `local.ollama` or `cloud.anthropic`; it does not say which
    /// local model this Mac was given or which provider has a key in the
    /// Keychain. Those arrive here as parameters, so the same policy resolves
    /// correctly on a Mac with different hardware.
    ///
    /// Returns nil for an identifier this build does not recognise, which the
    /// caller reports rather than guessing at — silently resolving an unknown
    /// model to the cloud is precisely what the scope forbids.
    public static func configuration(
        for modelID: String,
        localModelID: String?,
        cloudProvider: CloudProvider?
    ) -> RewriteBackendConfiguration? {
        if modelID.hasPrefix("local.") {
            let suffix = String(modelID.dropFirst("local.".count))
            // `local.ollama` means "the model this Mac was given"; anything
            // more specific names it outright, which only legacy state does.
            if suffix == "ollama" {
                guard let localModelID, !localModelID.isEmpty else { return nil }
                return .local(modelID: localModelID)
            }
            guard !suffix.isEmpty else { return nil }
            // A stored model name is honoured only while it is still the one
            // this Mac runs. Otherwise the device's own recommendation wins, so
            // restoring old state cannot resurrect a model nobody chose.
            if let localModelID, !localModelID.isEmpty,
               !LocalModelIdentity.contains(suffix, in: [localModelID]) {
                return .local(modelID: localModelID)
            }
            return .local(modelID: suffix)
        }

        if modelID.hasPrefix("cloud.") {
            let suffix = String(modelID.dropFirst("cloud.".count))
            guard let provider = CloudProvider(rawValue: suffix) ?? cloudProvider else {
                return nil
            }
            return .cloud(provider: provider)
        }

        return nil
    }

    public static func make(
        configuration: RewriteBackendConfiguration,
        keyStore: APIKeyStore = .shared
    ) throws -> any Rewriter {
        switch configuration {
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
