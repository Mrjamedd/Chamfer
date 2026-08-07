import ChamferRewrite
import Foundation

enum ModelsPreferences {
    private static let activeKey = "models.activeBackend"
    private static let localModelKey = "models.selectedLocalModel"
    private static let cloudProviderKey = "models.cloudProvider"

    static func loadState(defaults: UserDefaults = .standard) -> ModelsLandscapeState {
        let active = defaults.string(forKey: activeKey)
            .flatMap(ModelsBackendID.init(rawValue:)) ?? .apple
        let localModel = defaults.string(forKey: localModelKey) ?? "qwen3.5:4b"
        return ModelsLandscapeState(
            active: active,
            selected: active,
            selectedLocalModelID: localModel
        )
    }

    static func save(state: ModelsLandscapeState, defaults: UserDefaults = .standard) {
        defaults.set(state.active.rawValue, forKey: activeKey)
        defaults.set(state.selectedLocalModelID, forKey: localModelKey)
    }

    static func loadCloudProvider(defaults: UserDefaults = .standard) -> CloudProvider {
        defaults.string(forKey: cloudProviderKey)
            .flatMap(CloudProvider.init(rawValue:)) ?? .openAI
    }

    static func saveCloudProvider(
        _ provider: CloudProvider,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(provider.rawValue, forKey: cloudProviderKey)
    }
}
