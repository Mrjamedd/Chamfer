import Foundation

/// How a model tag is written down.
///
/// Ollama accepts `qwen3.5:4b` and reports it as `qwen3.5:4b`, but a tagless
/// name means `:latest` on the way in and comes back spelled out on the way
/// out. Comparing the two forms directly is how an installed model is missed
/// and pulled a second time, so every presence check goes through here.
public enum LocalModelIdentity {
    public static func normalized(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        // A digest-pinned reference (`model@sha256:…`) names one exact blob and
        // is already unambiguous.
        if trimmed.contains("@") { return trimmed }
        return trimmed.contains(":") ? trimmed : trimmed + ":latest"
    }

    public static func normalized(_ identifiers: some Sequence<String>) -> Set<String> {
        Set(identifiers.map(normalized).filter { !$0.isEmpty })
    }

    /// Whether `installed` — as reported by the runtime — already contains
    /// `identifier`. The only presence test in the app.
    public static func contains(
        _ identifier: String,
        in installed: some Sequence<String>
    ) -> Bool {
        normalized(installed).contains(normalized(identifier))
    }
}

/// Where an install attempt ended up.
public enum LocalModelInstallOutcome: Sendable, Equatable {
    /// The model was already on disk. Nothing was downloaded.
    case alreadyPresent
    /// The model was downloaded during this call and verified afterwards.
    case downloaded
    /// Reported rather than thrown, so a failed install leaves the interface
    /// with something to say instead of an unhandled error.
    case failed(String)

    public var isInstalled: Bool {
        switch self {
        case .alreadyPresent, .downloaded: true
        case .failed: false
        }
    }
}

/// How far a download has got.
public struct LocalModelDownloadProgress: Sendable, Equatable {
    /// 0…1, or nil while the runtime is still resolving the manifest and has
    /// no total to divide by.
    public let fraction: Double?
    public let completedBytes: UInt64
    public let totalBytes: UInt64?
    /// The runtime's own word for what it is doing — "pulling manifest",
    /// "verifying sha256 digest". Shown verbatim rather than paraphrased.
    public let stage: String

    public init(
        fraction: Double?,
        completedBytes: UInt64,
        totalBytes: UInt64?,
        stage: String
    ) {
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.stage = stage
    }
}

/// Installs the recommended model, at most once.
///
/// Idempotency is the whole point of this type, and it is enforced at three
/// depths rather than one:
///
/// 1. **Presence.** Every call asks the runtime what is on disk before it asks
///    it to download anything. Persisted interface state is never trusted for
///    this — a model deleted outside Chamfer, or a preferences file restored
///    onto a different Mac, has to read as absent.
/// 2. **Coalescing.** A second call for a model already being pulled joins the
///    first rather than starting a parallel download of the same blob. A setup
///    flow and a launch check firing together is the ordinary case, not an edge.
/// 3. **Verification.** A pull is only believed if the model is present
///    afterwards. An interrupted download leaves no manifest, so it reads as
///    absent and can be retried without leaving a half-written model registered
///    as installed.
public actor LocalModelInstaller {
    public static let shared = LocalModelInstaller()

    private let client: OllamaClient
    private var inFlight: [String: Task<LocalModelInstallOutcome, Never>] = [:]

    public init(client: OllamaClient = OllamaClient()) {
        self.client = client
    }

    /// What is on disk right now, normalized.
    public func installedModelIDs() async -> Set<String> {
        guard await client.isAvailable(),
              let installed = try? await client.installedModelIDs() else {
            return []
        }
        return LocalModelIdentity.normalized(installed)
    }

    public func isInstalled(_ modelID: String) async -> Bool {
        LocalModelIdentity.contains(modelID, in: await installedModelIDs())
    }

    /// Downloads `model` only if it is not already here.
    ///
    /// `progress` is called on the installer's executor as the runtime reports
    /// it, and never at all when the model was already present — there is no
    /// download to show progress for, and a progress bar that completes
    /// instantly is a worse answer than no progress bar.
    public func ensureInstalled(
        _ model: LocalModelDescriptor,
        device: DeviceProfile,
        progress: (@Sendable (LocalModelDownloadProgress) -> Void)? = nil
    ) async -> LocalModelInstallOutcome {
        let key = LocalModelIdentity.normalized(model.id)

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<LocalModelInstallOutcome, Never> { [client] in
            guard await client.isAvailable() else {
                return .failed("Ollama isn’t running. Start it and try again.")
            }

            // 1. Presence, before anything is downloaded.
            if let installed = try? await client.installedModelIDs(),
               LocalModelIdentity.contains(model.id, in: installed) {
                return .alreadyPresent
            }

            guard LocalModelSelection.hasRoom(for: model, on: device) else {
                let needed = model.downloadSizeLabel
                return .failed(
                    "Not enough free space for the \(needed) download."
                )
            }

            // 2. Download.
            do {
                try await client.pull(model: model.id, onProgress: progress)
            } catch {
                return .failed(error.localizedDescription)
            }

            // 3. Verification. A pull that reported success but left nothing on
            // disk is a failed install, not an installed model.
            guard let after = try? await client.installedModelIDs(),
                  LocalModelIdentity.contains(model.id, in: after) else {
                return .failed(
                    "The download finished but \(model.id) isn’t registered with Ollama. Try again."
                )
            }
            return .downloaded
        }

        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil
        return outcome
    }
}
