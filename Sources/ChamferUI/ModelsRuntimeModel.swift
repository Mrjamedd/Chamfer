import ChamferRewrite
import Foundation
import Observation

struct ModelsRuntimeSnapshot: Sendable {
    let appleAvailable: Bool
    let ollamaAvailable: Bool
    let installedLocalModelIDs: Set<String>
    let cloudConnected: Bool
}

@MainActor
@Observable
final class ModelsRuntimeModel {
    private(set) var appleAvailable = true
    private(set) var didRefreshApple = false
    private(set) var ollamaAvailable = false
    private(set) var cloudConnected = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let apple = AppleFoundationRewriter()
    @ObservationIgnored private let ollama = OllamaClient()
    @ObservationIgnored private let cloud = CloudAPIClient()
    @ObservationIgnored private let keyStore = APIKeyStore.shared

    func refresh(provider: CloudProvider) async -> ModelsRuntimeSnapshot {
        isWorking = true
        errorMessage = nil

        async let appleCheck = apple.isAvailable
        async let ollamaCheck = ollama.isAvailable()
        let availableApple = await appleCheck
        let availableOllama = await ollamaCheck
        let installed: Set<String>
        if availableOllama {
            installed = (try? await ollama.installedModelIDs()) ?? []
        } else {
            installed = []
        }
        let connected = ((try? keyStore.load(for: provider)) ?? nil) != nil

        appleAvailable = availableApple
        didRefreshApple = true
        ollamaAvailable = availableOllama
        cloudConnected = connected
        isWorking = false

        return ModelsRuntimeSnapshot(
            appleAvailable: availableApple,
            ollamaAvailable: availableOllama,
            installedLocalModelIDs: installed,
            cloudConnected: connected
        )
    }

    func refreshCredentialStatus(provider: CloudProvider) {
        cloudConnected = ((try? keyStore.load(for: provider)) ?? nil) != nil
        errorMessage = nil
    }

    func connect(provider: CloudProvider, enteredCredential: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let entered = enteredCredential.trimmingCharacters(in: .whitespacesAndNewlines)
            let credential = entered.isEmpty
                ? try keyStore.load(for: provider)
                : entered
            guard let credential, !credential.isEmpty else {
                throw ModelAccessError.unavailable("Enter an API key first.")
            }

            try await cloud.validate(provider: provider, apiKey: credential)
            if !entered.isEmpty {
                try keyStore.save(credential, for: provider)
            }
            cloudConnected = true
            return true
        } catch {
            cloudConnected = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    func download(modelID: String) async -> Set<String>? {
        guard ollamaAvailable else {
            errorMessage = "Install and launch Ollama before downloading a local model."
            return nil
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await ollama.pull(model: modelID)
            return try await ollama.installedModelIDs()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
