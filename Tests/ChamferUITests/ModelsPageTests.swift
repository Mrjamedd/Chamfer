import ChamferCore
import ChamferRewrite
import CoreGraphics
import Foundation
import Testing

@testable import ChamferUI

private func device(
    memoryGB: Int,
    appleSilicon: Bool = true,
    diskGB: Int? = 400
) -> DeviceProfile {
    DeviceProfile(
        physicalMemoryBytes: UInt64(memoryGB) * DeviceProfile.bytesPerGigabyte,
        performanceCoreCount: 8,
        totalCoreCount: 10,
        isAppleSilicon: appleSilicon,
        availableDiskBytes: diskGB.map {
            UInt64($0) * DeviceProfile.bytesPerGigabyte
        }
    )
}

private func state(
    memoryGB: Int = 24,
    diskGB: Int? = 400,
    runtimeAvailable: Bool = true
) -> ModelsDashboardState {
    ModelsDashboardState(
        localRuntimeAvailable: runtimeAvailable,
        device: device(memoryGB: memoryGB, diskGB: diskGB)
    )
}

// MARK: - There are two paths, and no way to pick a model

@Test func theProductHasExactlyTwoIntelligencePathsAndAppleIsNotOneOfThem() {
    #expect(ModelsBackendID.allCases == [.local, .cloud])
    #expect(ModelsBackendID(rawValue: "apple") == nil)
    #expect(ModelsBackendID(rawValue: "mlx") == nil)
}

/// The dashboard never stores a chosen model. It stores the machine, and the
/// model falls out of it — which is what makes "locked to the recommendation"
/// structural rather than a rule someone has to remember to enforce.
@Test func theModelIsDerivedFromTheMacRatherThanStored() {
    #expect(state(memoryGB: 8).recommendedModel.id == "qwen3.5:2b")
    #expect(state(memoryGB: 16).recommendedModel.id == "qwen3.5:4b")
    #expect(state(memoryGB: 64).recommendedModel.id == "gpt-oss:20b")

    let small = state(memoryGB: 8)
    #expect(
        small.recommendedModel
            == LocalModelSelection.recommended(for: small.device)
    )
}

@Test func theRecommendationExplainsItselfInTheMachinesOwnNumbers() {
    let mac = state(memoryGB: 24)

    #expect(mac.device.summary.contains("24 GB"))
    #expect(mac.recommendationRationale.contains("24 GB"))
    #expect(!mac.recommendationRationale.isEmpty)
}

// MARK: - Presence reflects the disk, not the interface

@Test func installationStateFollowsWhatTheRuntimeReportsIsOnDisk() {
    var dashboard = state(memoryGB: 24)
    #expect(dashboard.installation == .notInstalled)

    dashboard.synchronizeInstalledLocalModels(["qwen3.5:9b"])
    #expect(dashboard.installation == .installed)

    // Deleted outside Chamfer. The page has to notice.
    dashboard.synchronizeInstalledLocalModels([])
    #expect(dashboard.installation == .notInstalled)
}

/// Another model being present is not this model being present. This is the
/// check that stops a Mac that once ran a different tier reporting as ready.
@Test func anUnrelatedInstalledModelDoesNotCountAsThisMacsModel() {
    var dashboard = state(memoryGB: 24)

    dashboard.synchronizeInstalledLocalModels(["qwen3.5:2b", "llama3:8b"])

    #expect(dashboard.installation == .notInstalled)
}

@Test func presenceIsIndifferentToHowTheTagIsWritten() {
    var dashboard = ModelsDashboardState(device: device(memoryGB: 4))
    #expect(dashboard.recommendedModel.id == "qwen3.5:0.8b")

    dashboard.synchronizeInstalledLocalModels(["qwen3.5:0.8b"])
    #expect(dashboard.installation == .installed)
}

/// A poll landing mid-download must not flick the button back to "Download".
@Test func aPollDuringADownloadDoesNotUndoIt() {
    var dashboard = state(memoryGB: 24)
    dashboard.beginDownload()

    dashboard.synchronizeInstalledLocalModels([])

    #expect(dashboard.installation == .downloading)
}

@Test func aDownloadReportsItsProgressAndClearsWhenItLands() {
    var dashboard = state(memoryGB: 24)

    dashboard.beginDownload()
    #expect(dashboard.installation == .downloading)
    #expect(dashboard.download?.fraction == nil)

    dashboard.updateDownload(fraction: 0.4, stage: "downloading")
    #expect(dashboard.download?.fraction == 0.4)

    dashboard.finishDownload(installed: true)
    #expect(dashboard.installation == .installed)
    #expect(dashboard.download == nil)
}

@Test func aDownloadThatFailedLeavesTheModelUninstalled() {
    var dashboard = state(memoryGB: 24)
    dashboard.beginDownload()

    dashboard.finishDownload(installed: false)

    #expect(dashboard.installation == .notInstalled)
    #expect(dashboard.download == nil)
}

// MARK: - Activation

@Test func aFreshInstallActivatesNothingByItself() {
    let dashboard = state()

    #expect(dashboard.active == nil)
    #expect(dashboard.status(for: .local) == "NOT INSTALLED")
    #expect(dashboard.status(for: .cloud) == "NOT CONNECTED")
}

@Test func theLocalPathBecomesActiveOnlyWhenItIsExplicitlyActivated() {
    var dashboard = state()
    dashboard.synchronizeInstalledLocalModels(["qwen3.5:9b"])

    #expect(dashboard.status(for: .local) == "READY")
    #expect(dashboard.active == nil)

    dashboard.activate(.local)

    #expect(dashboard.active == .local)
    #expect(dashboard.status(for: .local) == "ACTIVE")
}

/// An active path that stopped working says so rather than continuing to claim
/// it is running.
@Test func anActivePathWhoseRuntimeDiedReportsAsUnavailable() {
    var dashboard = state()
    dashboard.synchronizeInstalledLocalModels(["qwen3.5:9b"])
    dashboard.activate(.local)

    dashboard.localRuntimeAvailable = false

    #expect(dashboard.status(for: .local) == "UNAVAILABLE")
    #expect(!dashboard.localReady)
}

@Test func cloudActivationClosesItsOwnConfiguration() {
    var dashboard = state()
    dashboard.openCloudConfiguration()
    dashboard.synchronizeConnection(connected: true)

    dashboard.activate(.cloud)

    #expect(dashboard.active == .cloud)
    #expect(!dashboard.cloudConfigurationOpen)
    #expect(dashboard.status(for: .cloud) == "ACTIVE")
}

@Test func connectionTestingMovesFromTestingToTheReportedResult() {
    var dashboard = state()

    dashboard.beginConnectionTest()
    #expect(dashboard.connection == .testing)

    dashboard.finishConnectionTest(connected: true)
    #expect(dashboard.connection == .connected)

    dashboard.finishConnectionTest(connected: false)
    #expect(dashboard.connection == .failed)
}

/// Chamfer installs the runtime itself, so the card must not spend that time
/// telling somebody to go and get a thing that is already arriving.
@Test func whileChamferIsFetchingOllamaTheCardSaysSoRatherThanAskingForIt() {
    var dashboard = state(runtimeAvailable: false)
    dashboard.runtimeInstall = ModelsDownloadState(
        fraction: 0.3,
        stage: "Downloading Ollama…"
    )

    #expect(dashboard.status(for: .local) == "SETTING UP")
    #expect(ModelsLocalPresentation.action(for: dashboard) == .preparingRuntime)
    #expect(!ModelsLocalPresentation.isActionEnabled(for: dashboard))
    #expect(
        ModelsLocalPresentation.statusDetail(for: dashboard) == "Downloading Ollama…"
    )
}

/// Once the runtime lands, the card goes back to being about the model.
@Test func theRuntimeInstallStopsSpeakingForTheCardOnceOllamaIsThere() {
    var dashboard = state(runtimeAvailable: true)
    dashboard.runtimeInstall = ModelsDownloadState(stage: "Starting Ollama…")

    #expect(dashboard.status(for: .local) == "NOT INSTALLED")
    #expect(ModelsLocalPresentation.action(for: dashboard) == .download)
    #expect(ModelsLocalPresentation.isActionEnabled(for: dashboard))
}

@Test func ollamaMissingIsSaidPlainlyRatherThanAsNotInstalled() {
    let dashboard = state(runtimeAvailable: false)

    #expect(dashboard.status(for: .local) == "OLLAMA REQUIRED")
    #expect(ModelsLocalPresentation.action(for: dashboard) == .installRuntime)
    #expect(
        ModelsLocalPresentation.statusDetail(for: dashboard).contains("Ollama")
    )
}

// MARK: - The one action on the primary card

@Test func thePrimaryActionFollowsTheStateRatherThanBeingAssembledAtTheCallSite() {
    var dashboard = state()
    #expect(ModelsLocalPresentation.action(for: dashboard) == .download)

    dashboard.beginDownload()
    #expect(ModelsLocalPresentation.action(for: dashboard) == .downloading)
    #expect(!ModelsLocalPresentation.isActionEnabled(for: dashboard))

    dashboard.finishDownload(installed: true)
    #expect(ModelsLocalPresentation.action(for: dashboard) == .activate)
    #expect(ModelsLocalPresentation.isActionEnabled(for: dashboard))

    dashboard.activate(.local)
    #expect(ModelsLocalPresentation.action(for: dashboard) == .alreadyActive)
    #expect(!ModelsLocalPresentation.isActionEnabled(for: dashboard))
}

@Test func aFullDiskDisablesTheDownloadAndSaysWhy() {
    let dashboard = state(memoryGB: 24, diskGB: 2)

    #expect(!dashboard.hasRoomForModel)
    #expect(!ModelsLocalPresentation.isActionEnabled(for: dashboard))
    #expect(
        ModelsLocalPresentation.statusDetail(for: dashboard)
            .contains("Not enough free space")
    )
}

// MARK: - Configuration modes

@Test func theConfigurationModeIsPartOfTheDashboardAndDefaultsToBalanced() {
    var dashboard = state()
    #expect(dashboard.effort == .balanced)

    dashboard.setEffort(.max)
    #expect(dashboard.effort == .max)
    #expect(dashboard.effort.profile.reviewPasses == 2)
}

@Test func theSelectorKeepsUnselectedModesLegible() {
    for candidate in ModelEffort.allCases {
        let selected = ModelsEffortSelectorResponse.presentation(
            for: candidate,
            selected: candidate,
            hovered: nil
        )
        #expect(selected.isSelected)
        #expect(selected.titleOpacity == 1)

        let unselected = ModelsEffortSelectorResponse.presentation(
            for: candidate,
            selected: candidate == .base ? .max : .base,
            hovered: nil
        )
        #expect(!unselected.isSelected)
        // Legible, not ghosted: this is a choice between three things.
        #expect(unselected.titleOpacity > 0.6)
    }
}

@Test func hoveringAModeBringsItForwardWithoutSelectingIt() {
    let resting = ModelsEffortSelectorResponse.presentation(
        for: .max,
        selected: .base,
        hovered: nil
    )
    let hovered = ModelsEffortSelectorResponse.presentation(
        for: .max,
        selected: .base,
        hovered: .max
    )

    #expect(hovered.titleOpacity > resting.titleOpacity)
    #expect(!hovered.isSelected)
}

// MARK: - Persistence

@Test func emptyPreferencesActivateNothing() throws {
    let suite = "ChamferUITests.Models.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let loaded = ModelsPreferences.loadState(
        defaults: defaults,
        device: device(memoryGB: 24)
    )

    #expect(loaded.active == nil)
    #expect(loaded.effort == .balanced)
    #expect(ModelsPreferences.loadCloudProvider(defaults: defaults) == nil)
    #expect(ModelsSelection.activeModelID(defaults: defaults) == nil)
}

@Test func anActivatedPathAndItsModeSurviveARoundTrip() throws {
    let suite = "ChamferUITests.Models.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    var dashboard = state()
    dashboard.activate(.local)
    dashboard.setEffort(.max)
    ModelsPreferences.save(state: dashboard, defaults: defaults)

    let reloaded = ModelsPreferences.loadState(
        defaults: defaults,
        device: device(memoryGB: 24)
    )
    #expect(reloaded.active == .local)
    #expect(reloaded.effort == .max)
    #expect(
        ModelsSelection.activeModelID(defaults: defaults)
            == RewritePolicy.localModelIdentifier
    )
    #expect(ModelsSelection.effort(defaults: defaults) == .max)

    dashboard.activate(.cloud)
    ModelsPreferences.save(state: dashboard, defaults: defaults)
    ModelsPreferences.saveCloudProvider(.anthropic, defaults: defaults)
    #expect(ModelsSelection.activeModelID(defaults: defaults) == "cloud.anthropic")
}

/// The mode has to reach the pipeline the moment it is changed, not on the next
/// launch, so it is written on its own rather than only with the whole state.
@Test func changingTheModeIsWrittenImmediately() throws {
    let suite = "ChamferUITests.Models.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    ModelsPreferences.saveEffort(.base, defaults: defaults)

    #expect(ModelsSelection.effort(defaults: defaults) == .base)
    #expect(
        ModelsPreferences.loadState(
            defaults: defaults,
            device: device(memoryGB: 24)
        ).effort == .base
    )
}

/// The stored local-model name is deleted rather than migrated. Which model
/// runs is the hardware's answer now, and a leftover name in preferences is
/// exactly how a restored settings file talks a Mac into a second download.
@Test func theStoredLocalModelNameIsRemovedOnMigration() throws {
    let suite = "ChamferUITests.Models.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set("mlx", forKey: "models.activeBackend")
    defaults.set("gpt-oss:20b", forKey: "models.selectedLocalModel")

    let migrated = ModelsPreferences.loadState(
        defaults: defaults,
        device: device(memoryGB: 8)
    )

    #expect(migrated.active == .local)
    #expect(defaults.string(forKey: "models.selectedLocalModel") == nil)
    // The hardware's answer, not the one that was written down.
    #expect(migrated.recommendedModel.id == "qwen3.5:2b")
}

@Test func theOldCloudBackendNameIsBroughtForward() throws {
    let suite = "ChamferUITests.Models.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set("ollama", forKey: "models.activeBackend")
    ModelsPreferences.saveCloudProvider(.openAI, defaults: defaults)

    #expect(
        ModelsPreferences.loadState(
            defaults: defaults,
            device: device(memoryGB: 24)
        ).active == .cloud
    )
    #expect(ModelsSelection.activeModelID(defaults: defaults) == "cloud.openAI")
}

/// Someone whose active model has been removed from the product has not chosen
/// its replacement. A fresh install is deliberately inert, and quietly
/// activating an undownloaded model on their behalf would break that.
@Test func aStoredAppleSelectionBecomesNothingRatherThanTheLocalModel() throws {
    let suite = "ChamferUITests.Models.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set("apple", forKey: "models.activeBackend")

    let migrated = ModelsPreferences.loadState(
        defaults: defaults,
        device: device(memoryGB: 24)
    )

    #expect(migrated.active == nil)
    #expect(ModelsSelection.activeModelID(defaults: defaults) == nil)
    #expect(defaults.string(forKey: "models.activeBackend") == nil)
}

@Test func theLocalModelIdentifierIsAbstractRatherThanAModelName() {
    #expect(RewritePolicy.localModelIdentifier == "local.ollama")
    #expect(ModelsSelection.localModelID(device: device(memoryGB: 16)) == "qwen3.5:4b")
    #expect(ModelsSelection.localModelID(device: device(memoryGB: 64)) == "gpt-oss:20b")
}

// MARK: - Hierarchy

/// The whole redesign is in these numbers. Local carries a filled, shadowed
/// surface; cloud carries a hairline. Hover moves within a path's band rather
/// than across the gap between them, so cloud can never out-shout local by
/// being pointed at.
@Test func theLocalCardOutweighsCloudInEveryState() {
    for localActive in [true, false] {
        let local = ModelsSurfaceResponse.presentation(
            for: .local,
            isActive: localActive,
            isHovered: false
        )
        let hoveredCloud = ModelsSurfaceResponse.presentation(
            for: .cloud,
            isActive: true,
            isHovered: true
        )

        #expect(local.paperOpacity > hoveredCloud.paperOpacity)
        #expect(local.shadowRadius > hoveredCloud.shadowRadius)
    }
}

@Test func hoveringStrengthensASurfaceWithoutMovingItFar() {
    for backend in ModelsBackendID.allCases {
        let resting = ModelsSurfaceResponse.presentation(
            for: backend,
            isActive: false,
            isHovered: false
        )
        let hovered = ModelsSurfaceResponse.presentation(
            for: backend,
            isActive: false,
            isHovered: true
        )

        #expect(hovered.borderOpacity > resting.borderOpacity)
        #expect(hovered.shadowOpacity > resting.shadowOpacity)
        #expect(hovered.lift < 0)
        #expect(hovered.lift > -6)
    }
}

@Test func activationIsVisibleWithoutTheCardChangingSize() {
    for backend in ModelsBackendID.allCases {
        let resting = ModelsSurfaceResponse.presentation(
            for: backend,
            isActive: false,
            isHovered: false
        )
        let active = ModelsSurfaceResponse.presentation(
            for: backend,
            isActive: true,
            isHovered: false
        )

        #expect(active.tintOpacity > resting.tintOpacity)
        #expect(active.borderOpacity > resting.borderOpacity)
        #expect(active.lift == resting.lift)
    }
}

/// Opening cloud's panel pushes the page behind it back rather than hiding it,
/// so the thing being configured stays visible.
@Test func openingTheCloudPanelRecessesEverythingBehindIt() {
    for backend in ModelsBackendID.allCases {
        let normal = ModelsSurfaceResponse.presentation(
            for: backend,
            isActive: true,
            isHovered: false
        )
        let recessed = ModelsSurfaceResponse.presentation(
            for: backend,
            isActive: true,
            isHovered: false,
            isRecessed: true
        )

        #expect(recessed.tintOpacity < normal.tintOpacity)
        #expect(recessed.shadowOpacity < normal.shadowOpacity)
    }
}

@Test func theLocalAmbientWashSitsAboveTheCloudOneAtRest() {
    let local = ModelsBloomResponse.presentation(
        for: .local,
        active: nil,
        hovered: nil
    )
    let cloud = ModelsBloomResponse.presentation(
        for: .cloud,
        active: nil,
        hovered: nil
    )

    #expect(local.opacity > cloud.opacity)
    #expect(local.scale > cloud.scale)
}

@Test func hoveringAlwaysAddsBloomExpansionAndIntensity() {
    for backend in ModelsBackendID.allCases {
        let resting = ModelsBloomResponse.presentation(
            for: backend,
            active: nil,
            hovered: nil
        )
        let hovered = ModelsBloomResponse.presentation(
            for: backend,
            active: nil,
            hovered: backend
        )

        #expect(hovered.scale > resting.scale)
        #expect(hovered.opacity > resting.opacity)
        #expect(hovered.inwardProgress > resting.inwardProgress)
    }
}

// MARK: - Motion

@Test func leavingIsQuickerThanArrivingAndReducedMotionShortensBoth() {
    let full = ModelsMotionResponse.timing(reduceMotion: false)
    let reduced = ModelsMotionResponse.timing(reduceMotion: true)

    #expect(full.panelClose < full.panelOpen)
    #expect(reduced.panelOpen < full.panelOpen)
    #expect(reduced.panelClose <= full.panelClose)
    #expect(reduced.ambient < full.ambient)
}

// MARK: - Layout

@Test func theLocalColumnIsTheLargestThingOnThePageAtEverySupportedSize() {
    for height in [Chamfer.Window.minimumHeight, 720, Chamfer.Window.designedHeight] {
        let size = CGSize(width: Chamfer.Window.width - 64, height: height - 150)
        let metrics = ModelsPageMetrics.metrics(for: size)

        #expect(metrics.primaryWidth > metrics.configurationWidth)
        // Just under two-thirds. Any closer to half and the two columns read as
        // a pair of equals, which is the hierarchy this page exists to undo.
        #expect(metrics.primaryWidth > (metrics.primaryWidth + metrics.configurationWidth) * 0.58)
        #expect(metrics.minimumRowHeight > metrics.cloudHeight)

        let used = metrics.horizontalPadding * 2
            + metrics.primaryWidth
            + metrics.columnGap
            + metrics.configurationWidth
        #expect(abs(used - size.width) < 0.5)
    }
}

@Test func aShortWindowTightensRatherThanKeepingItsMargins() {
    let short = ModelsPageMetrics.metrics(for: CGSize(width: 716, height: 430))
    let tall = ModelsPageMetrics.metrics(for: CGSize(width: 716, height: 700))

    #expect(short.isCompact)
    #expect(!tall.isCompact)
    #expect(short.minimumRowHeight < tall.minimumRowHeight)
    #expect(short.topPadding < tall.topPadding)
    #expect(short.horizontalPadding < tall.horizontalPadding)
    #expect(short.cloudHeight <= tall.cloudHeight)
}

/// The cloud panel's arrival is one number, and leaving is its exact inverse.
@Test func theCloudPanelArrivesAndLeavesAlongTheSamePath() {
    #expect(ModelsPanelPresentation.opacity(progress: 0) == 0)
    #expect(ModelsPanelPresentation.opacity(progress: 1) == 1)
    #expect(ModelsPanelPresentation.scale(progress: 0) == 0.90)
    #expect(ModelsPanelPresentation.scale(progress: 1) == 1)

    // Monotonic, so a reversal in flight retraces rather than jumping.
    let samples = stride(from: 0.0, through: 1.0, by: 0.1).map {
        ModelsPanelPresentation.scale(progress: CGFloat($0))
    }
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
}

@Test func openingTheCloudPanelPushesThePageBackWithoutHidingIt() {
    let closed = ModelsPanelPresentation.recession(progress: 0)
    let open = ModelsPanelPresentation.recession(progress: 1)

    #expect(closed.scale == 1)
    #expect(closed.opacity == 1)
    #expect(!closed.isRecessed)

    #expect(open.scale < 1)
    #expect(open.isRecessed)
    // Still readable behind the panel: the thing being configured has to stay
    // visible while it is configured.
    #expect(open.opacity > 0.4)
}

// MARK: - The bottom bar reads the same state

@Test func theBottomBarNamesTheSameTwoPathsWithTheSameStatuses() throws {
    var dashboard = state(memoryGB: 24)
    dashboard.synchronizeInstalledLocalModels(["qwen3.5:9b"])
    dashboard.activate(.local)

    let entries = Backend.all(state: dashboard)

    #expect(entries.map(\.backendID) == [.local, .cloud])
    let local = try #require(entries.first { $0.id == .local })
    #expect(local.name == "Qwen3.5 9B")
    #expect(local.shortName == "Local Model")
    #expect(local.status == "ACTIVE")

    let cloud = try #require(entries.first { $0.id == .cloud })
    #expect(cloud.shortName == "Cloud Model")
    #expect(cloud.status == "NOT CONNECTED")
}
