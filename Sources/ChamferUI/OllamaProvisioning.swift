import ChamferRewrite
import Foundation
import Observation

/// What the app is doing about the Ollama runtime, for the one surface that
/// shows it.
public enum OllamaProvisioningState: Equatable, Sendable {
    case idle
    case working(OllamaRuntimeProgress)
    case ready
    case failed(String)

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    public var progress: OllamaRuntimeProgress? {
        if case let .working(progress) = self { return progress }
        return nil
    }

    public var failure: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

/// Gets Ollama onto the Mac, once, without being asked.
///
/// Chamfer's whole intelligence path is a local model, and a local model needs
/// a runtime. Making that the user's errand — read a status line, follow a
/// link, find the right download, come back — is three minutes of homework
/// before the app does anything at all. So the app does it.
///
/// Process-scoped for the same reason `HomeGreetingClock` is: the Models page
/// is created and destroyed as you navigate, and provisioning outlives it. The
/// page observes this; it does not own it.
///
/// Run on every launch rather than behind a "first boot" flag. When Ollama is
/// already running this costs one request to localhost, and a first attempt
/// that failed — no network, full disk — gets another try next time instead of
/// being remembered as done.
@MainActor
@Observable
public final class OllamaProvisioning {
    public static let shared = OllamaProvisioning()

    public private(set) var state: OllamaProvisioningState = .idle

    @ObservationIgnored private let installer: OllamaRuntimeInstaller
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(installer: OllamaRuntimeInstaller = .shared) {
        self.installer = installer
    }

    /// Stops Chamfer's own server, if it started one. Called when the app
    /// quits — the runtime is a child process and should not outlive its parent.
    public func shutDown() async {
        await installer.shutDown()
    }

    /// Waits until a runtime is available, starting one if nothing is already
    /// on its way. Answers whether there is one.
    ///
    /// This is what lets the Models card offer a single button: asking for the
    /// model implies asking for whatever has to exist underneath it. A call
    /// made while the launch-time provisioning is still running joins it rather
    /// than starting a second, and a call made after a failure gets a fresh
    /// attempt — pressing the button again is the retry.
    @discardableResult
    public func ensureReady() async -> Bool {
        if state == .ready { return true }
        startIfNeeded()
        // Captured before awaiting: the task clears itself on the way out.
        if let running = task { await running.value }
        return state == .ready
    }

    /// Starts provisioning if it is not already running. Idempotent at this
    /// level as well as inside the installer, so calling it from more than one
    /// place is harmless.
    public func startIfNeeded() {
        guard task == nil, state != .ready else { return }

        task = Task { [installer] in
            let outcome = await installer.ensureAvailable { progress in
                Task { @MainActor [weak self] in
                    // A late report must not overwrite a finished state.
                    guard self?.state.isWorking != false else { return }
                    self?.state = .working(progress)
                }
            }

            await MainActor.run { [weak self] in
                if let baseURL = outcome.baseURL {
                    // Published before the state flips, so anything reacting to
                    // `.ready` already builds its client against the right
                    // server.
                    OllamaEndpoint.shared.current = baseURL
                    self?.state = .ready
                } else if case let .failed(message) = outcome {
                    self?.state = .failed(message)
                }
                self?.task = nil
            }
        }
    }
}
