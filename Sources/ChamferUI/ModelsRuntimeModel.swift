import ChamferRewrite
import Foundation
import Observation

struct ModelsRuntimeSnapshot: Sendable {
    let ollamaAvailable: Bool
    /// Everything Ollama reports on disk, normalized. The dashboard decides
    /// what that means for *its* model rather than being told.
    let installedLocalModelIDs: Set<String>
    let cloudConnected: Bool
}

/// The dashboard's window onto what is really installed and connected.
///
/// Nothing here is remembered between launches. Every answer is asked of the
/// runtime, which is what makes the page's installation state a report about
/// the disk rather than a memory of what the interface last did.
@MainActor
@Observable
final class ModelsRuntimeModel {
    private(set) var ollamaAvailable = false
    private(set) var cloudConnected = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let ollama = OllamaClient()
    @ObservationIgnored private let cloud = CloudAPIClient()
    @ObservationIgnored private let keyStore = APIKeyStore.shared
    @ObservationIgnored private let installer: LocalModelInstaller

    init(installer: LocalModelInstaller = .shared) {
        self.installer = installer
    }

    func refresh(provider: CloudProvider?) async -> ModelsRuntimeSnapshot {
        isWorking = true
        errorMessage = nil

        let availableOllama = await ollama.isAvailable()
        let installed = availableOllama ? await installer.installedModelIDs() : []
        let connected: Bool
        if let provider {
            connected = ((try? keyStore.load(for: provider)) ?? nil) != nil
        } else {
            connected = false
        }

        ollamaAvailable = availableOllama
        cloudConnected = connected
        isWorking = false

        return ModelsRuntimeSnapshot(
            ollamaAvailable: availableOllama,
            installedLocalModelIDs: installed,
            cloudConnected: connected
        )
    }

    func refreshCredentialStatus(provider: CloudProvider?) {
        if let provider {
            cloudConnected = ((try? keyStore.load(for: provider)) ?? nil) != nil
        } else {
            cloudConnected = false
        }
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

    /// Installs the device's model if it is not already here.
    ///
    /// The idempotency lives in `LocalModelInstaller`, not in this view model:
    /// a second call while a download is running joins the first, and a model
    /// already on disk returns without a byte being fetched. That is why the
    /// page can call this on activation as well as on the button, and why a
    /// setup flow re-entered twice cannot leave two copies behind.
    func install(
        _ model: LocalModelDescriptor,
        device: DeviceProfile,
        onProgress: @escaping @MainActor (LocalModelDownloadProgress) -> Void
    ) async -> LocalModelInstallOutcome {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let outcome = await installer.ensureInstalled(
            model,
            device: device,
            progress: { progress in
                Task { @MainActor in onProgress(progress) }
            }
        )

        if case let .failed(message) = outcome {
            errorMessage = message
        }
        return outcome
    }

    func installedModelIDs() async -> Set<String> {
        await installer.installedModelIDs()
    }
}
