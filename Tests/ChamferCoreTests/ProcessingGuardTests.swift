import Foundation
import Testing
@testable import ChamferCore

/// The scope's hardest privacy promise: note contents must never reach a cloud
/// model when the user expected local processing. These are the rules that
/// keep it.

private func policy(modelID: String) -> RewritePolicy {
    RewritePolicy(
        mode: .fullCleanup,
        application: .review,
        inactivityDelay: 600,
        sweep: .never,
        preserved: .standard,
        modelID: modelID
    )
}

@Test func localOnlyRefusesACloudModelRatherThanRunningIt() {
    let policy = policy(modelID: "cloud.sonnet")
    let preferences = AppPreferences(localProcessingOnly: true)

    #expect(ProcessingGuard.permittedModel(for: policy, preferences: preferences) == nil)
}

@Test func localOnlyLeavesTheOnDeviceModelAlone() {
    let policy = policy(modelID: RewritePolicy.localModelIdentifier)
    let preferences = AppPreferences(localProcessingOnly: true)

    #expect(
        ProcessingGuard.permittedModel(for: policy, preferences: preferences)
            == RewritePolicy.localModelIdentifier
    )
}

/// There is no second model to reach for. A blocked cloud policy reports as
/// unusable rather than quietly running somewhere the user did not choose.
@Test func localOnlyRefusesCloudWithNothingSubstitutedForIt() {
    let preferences = AppPreferences(localProcessingOnly: true)
    let cloudVault = policy(modelID: "cloud.sonnet")

    #expect(
        ProcessingGuard.permittedModel(for: cloudVault, preferences: preferences) == nil
    )
}

@Test func withoutTheLocalOnlySwitchTheChosenModelIsUsedAsIs() {
    let policy = policy(modelID: "cloud.sonnet")

    #expect(
        ProcessingGuard.permittedModel(for: policy, preferences: .unconfigured)
            == "cloud.sonnet"
    )
}

@Test func onlyCloudIdentifiersAreTreatedAsLeavingTheDevice() {
    #expect(ProcessingGuard.isCloud("cloud.sonnet"))
    #expect(!ProcessingGuard.isCloud(RewritePolicy.localModelIdentifier))
    #expect(!ProcessingGuard.isCloud("local.qwen3.5:4b"))
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

@Test func aFreshInstallHasNoImplicitGlobalPreferenceChoices() {
    let preferences = AppPreferences.unconfigured

    #expect(preferences.launchAtLogin == nil)
    #expect(preferences.localProcessingOnly == nil)
    #expect(NotificationCategory.allCases.allSatisfy {
        preferences.notificationChoice(for: $0) == nil
    })
    #expect(NotificationCategory.allCases.allSatisfy {
        !preferences.notifies(about: $0)
    })
}

@Test func deliberatelyTurningANotificationOffDiffersFromNeverChoosing() {
    var preferences = AppPreferences.unconfigured
    #expect(preferences.notificationChoice(for: .rewriteFailed) == nil)

    preferences.setNotification(.rewriteFailed, enabled: false)

    #expect(preferences.notificationChoice(for: .rewriteFailed) == false)
    #expect(!preferences.notifies(about: .rewriteFailed))
}
