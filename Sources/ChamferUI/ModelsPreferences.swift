import ChamferCore
import ChamferRewrite
import Foundation

enum ModelsPreferences {
    private static let activeKey = "models.activeBackend"
    private static let effortKey = "models.effort"
    private static let cloudProviderKey = "models.cloudProvider"
    /// Written by the version that let people pick their own local model.
    /// Read once, to be deleted.
    private static let legacyLocalModelKey = "models.selectedLocalModel"

    static func loadState(
        defaults: UserDefaults = .standard,
        device: DeviceProfile = .current()
    ) -> ModelsDashboardState {
        migrate(defaults: defaults)

        let active = defaults.string(forKey: activeKey)
            .flatMap(ModelsBackendID.init(rawValue:))
        let effort = defaults.string(forKey: effortKey)
            .flatMap(ModelEffort.init(rawValue:)) ?? .standard

        return ModelsDashboardState(
            active: active,
            effort: effort,
            device: device
        )
    }

    static func save(
        state: ModelsDashboardState,
        defaults: UserDefaults = .standard
    ) {
        if let active = state.active {
            defaults.set(active.rawValue, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
        defaults.set(state.effort.rawValue, forKey: effortKey)
    }

    static func saveEffort(_ effort: ModelEffort, defaults: UserDefaults = .standard) {
        defaults.set(effort.rawValue, forKey: effortKey)
    }

    static func loadCloudProvider(defaults: UserDefaults = .standard) -> CloudProvider? {
        defaults.string(forKey: cloudProviderKey)
            .flatMap(CloudProvider.init(rawValue:))
    }

    static func saveCloudProvider(
        _ provider: CloudProvider?,
        defaults: UserDefaults = .standard
    ) {
        if let provider {
            defaults.set(provider.rawValue, forKey: cloudProviderKey)
        } else {
            defaults.removeObject(forKey: cloudProviderKey)
        }
    }

    /// Brings preferences written by the three-backend version forward.
    ///
    /// The old raw values were the implementation's names rather than the
    /// product's: `mlx` was the downloadable local model and `ollama` was the
    /// cloud card. Both are renamed to what they always meant.
    ///
    /// `apple` becomes *nothing active* rather than being promoted to the local
    /// model. Someone whose active model has been removed from the product has
    /// not chosen its replacement, and a fresh install is deliberately inert
    /// until a model is activated — quietly activating a model that has not
    /// even been downloaded would break that promise on their behalf.
    ///
    /// The stored local-model name is deleted outright. Which model runs is now
    /// decided by the hardware, and leaving a stale name in preferences is how
    /// a restored settings file talks a Mac into downloading a second model.
    static func migrate(defaults: UserDefaults) {
        if let stored = defaults.string(forKey: activeKey),
           ModelsBackendID(rawValue: stored) == nil {
            switch stored {
            case "mlx": defaults.set(ModelsBackendID.local.rawValue, forKey: activeKey)
            case "ollama": defaults.set(ModelsBackendID.cloud.rawValue, forKey: activeKey)
            default: defaults.removeObject(forKey: activeKey)
            }
        }
        if defaults.object(forKey: legacyLocalModelKey) != nil {
            defaults.removeObject(forKey: legacyLocalModelKey)
        }
    }
}

/// What the Models page has chosen, for the parts of the app that have to act
/// on it rather than draw it.
///
/// A policy names a model in the abstract — `local.ollama`, `cloud.anthropic` —
/// and this is the seam that tells the rewrite pipeline which local model this
/// Mac actually runs and which provider has a key, without exposing the page's
/// whole state.
public enum ModelsSelection {
    /// The model this Mac runs. Derived from the hardware every time it is
    /// asked, so it cannot go stale against a machine, a migration, or a
    /// restored preferences file.
    public static func localModelID(device: DeviceProfile = .current()) -> String {
        LocalModelSelection.recommended(for: device).id
    }

    public static func cloudProvider(defaults: UserDefaults = .standard) -> CloudProvider? {
        ModelsPreferences.loadCloudProvider(defaults: defaults)
    }

    /// How hard the model is asked to work. Read by the rewrite pipeline at the
    /// moment a note is processed, so changing the mode takes effect on the
    /// next note rather than on the next launch.
    public static func effort(defaults: UserDefaults = .standard) -> ModelEffort {
        defaults.string(forKey: "models.effort")
            .flatMap(ModelEffort.init(rawValue:)) ?? .standard
    }

    /// The one model new rewrite work should use. Only an explicitly activated
    /// path produces an identifier; nothing activates itself.
    public static func activeModelID(defaults: UserDefaults = .standard) -> String? {
        ModelsPreferences.migrate(defaults: defaults)
        let active = defaults.string(forKey: "models.activeBackend")
            .flatMap(ModelsBackendID.init(rawValue:))
        switch active {
        case .local:
            return RewritePolicy.localModelIdentifier
        case .cloud:
            return ModelsPreferences.loadCloudProvider(defaults: defaults)
                .map { "cloud.\($0.rawValue)" }
        case nil:
            return nil
        }
    }
}
