import Foundation
import Testing
@testable import ChamferCore

/// The scope's hardest privacy promise: note contents must never reach a cloud
/// model when the user expected local processing. These are the rules that
/// keep it.

@Test func localOnlyRefusesACloudModelRatherThanRunningIt() {
    let policy = RewritePolicy(modelID: "cloud.sonnet")
    let preferences = AppPreferences(localProcessingOnly: true)

    #expect(ProcessingGuard.permittedModel(for: policy, preferences: preferences) == nil)
}

@Test func localOnlyLeavesOnDeviceModelsAlone() {
    let policy = RewritePolicy(modelID: "apple.foundation")
    let preferences = AppPreferences(localProcessingOnly: true)

    #expect(
        ProcessingGuard.permittedModel(for: policy, preferences: preferences)
            == "apple.foundation"
    )
}

/// A local fallback is a legitimate way out; a cloud one is not, and must not
/// be reached for just because it is configured.
@Test func localOnlyWillUseALocalFallbackButNeverACloudOne() {
    let preferences = AppPreferences(localProcessingOnly: true)

    let localFallback = RewritePolicy(
        modelID: "cloud.sonnet",
        fallbackModelID: "local.ollama"
    )
    #expect(
        ProcessingGuard.permittedModel(for: localFallback, preferences: preferences)
            == "local.ollama"
    )

    let cloudFallback = RewritePolicy(
        modelID: "cloud.sonnet",
        fallbackModelID: "cloud.haiku"
    )
    #expect(
        ProcessingGuard.permittedModel(for: cloudFallback, preferences: preferences) == nil
    )
}

@Test func withoutTheLocalOnlySwitchTheChosenModelIsUsedAsIs() {
    let policy = RewritePolicy(modelID: "cloud.sonnet")

    #expect(
        ProcessingGuard.permittedModel(for: policy, preferences: .standard)
            == "cloud.sonnet"
    )
}

@Test func fallingBackFromLocalToCloudIsRecognisedAsLeavingTheDevice() {
    #expect(ProcessingGuard.fallbackLeavesDevice(from: "apple.foundation", to: "cloud.sonnet"))
    #expect(!ProcessingGuard.fallbackLeavesDevice(from: "apple.foundation", to: "local.ollama"))
    #expect(!ProcessingGuard.fallbackLeavesDevice(from: "cloud.sonnet", to: "cloud.haiku"))
}

// MARK: - Notifications

@Test func everyNotificationCategoryCanBeSwitchedIndependently() {
    var preferences = AppPreferences(notifications: [])

    for category in NotificationCategory.allCases {
        preferences.setNotification(category, enabled: true)
        #expect(preferences.notifies(about: category))
    }
    #expect(preferences.notifications.count == NotificationCategory.allCases.count)

    preferences.setNotification(.rewriteFailed, enabled: false)
    #expect(!preferences.notifies(about: .rewriteFailed))
    #expect(preferences.notifies(about: .rewriteReady))
}

/// A notification for every queued rewrite trains the user to dismiss all of
/// them, including the ones that matter.
@Test func aFreshInstallOnlyNotifiesAboutThingsThatHappenedOrBroke() {
    #expect(AppPreferences.standard.notifies(about: .automaticApplied))
    #expect(AppPreferences.standard.notifies(about: .rewriteFailed))
    #expect(AppPreferences.standard.notifies(about: .folderUnavailable))
    #expect(!AppPreferences.standard.notifies(about: .rewriteReady))
    #expect(!AppPreferences.standard.notifies(about: .periodicSummary))
}
