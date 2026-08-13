import Foundation
import Testing

@testable import Chamfer

private let updateDetails = AppUpdateDetails(
    version: "2.4",
    releaseNotes: .plain("A calmer update flow."),
    informationURL: nil,
    isInformationOnly: false,
    isCritical: false,
    stage: .notDownloaded
)

@Test
func updateStateMovesFromPermissionThroughAnAvailableRelease() {
    var machine = AppUpdateStateMachine()

    machine.receive(.permissionRequested)
    #expect(machine.state == .permission)

    machine.receive(.userInitiatedCheckStarted)
    #expect(machine.state == .checking)

    machine.receive(.updateFound(updateDetails))
    #expect(machine.state == .available(updateDetails))

    let fetched = AppUpdateReleaseNotes.plain("Two useful changes.")
    machine.receive(.releaseNotesLoaded(fetched))

    var revised = updateDetails
    revised.releaseNotes = fetched
    #expect(machine.state == .available(revised))
}

@Test
func downloadProgressIsIndeterminateUntilSparkleReportsATotal() {
    var machine = AppUpdateStateMachine()
    machine.receive(.updateFound(updateDetails))
    machine.receive(.downloadStarted)

    #expect(
        machine.state == .downloading(
            updateDetails,
            AppUpdateProgress(completedBytes: 0, totalBytes: nil)
        )
    )

    machine.receive(.downloadReceived(bytes: 256))
    #expect(machine.progress?.fraction == nil)
    #expect(machine.progress?.completedBytes == 256)

    machine.receive(.downloadExpectedLength(1_024))
    #expect(machine.progress?.fraction == 0.25)

    machine.receive(.downloadReceived(bytes: 2_048))
    #expect(machine.progress?.fraction == 1)
    #expect(machine.progress?.completedBytes == 2_304)
}

@Test
func invalidTotalsAndOverflowCannotBreakDownloadProgress() {
    var machine = AppUpdateStateMachine()
    machine.receive(.downloadStarted)
    machine.receive(.downloadExpectedLength(0))
    machine.receive(.downloadReceived(bytes: UInt64.max))
    machine.receive(.downloadReceived(bytes: 20))

    #expect(machine.progress?.totalBytes == nil)
    #expect(machine.progress?.completedBytes == UInt64.max)
    #expect(machine.progress?.fraction == nil)
}

@Test
func extractionProgressClampsBadValuesAndReadyKeepsTheReleaseIdentity() {
    var machine = AppUpdateStateMachine()
    machine.receive(.updateFound(updateDetails))
    machine.receive(.extractionStarted)
    #expect(machine.state == .extracting(updateDetails, fraction: nil))

    machine.receive(.extractionProgress(-0.5))
    #expect(machine.state == .extracting(updateDetails, fraction: 0))

    machine.receive(.extractionProgress(1.5))
    #expect(machine.state == .extracting(updateDetails, fraction: 1))

    machine.receive(.extractionProgress(.nan))
    #expect(machine.state == .extracting(updateDetails, fraction: nil))

    machine.receive(.readyToInstall)
    #expect(machine.state == .readyToInstall(updateDetails))

    machine.receive(.installing(applicationTerminated: false))
    #expect(machine.state == .installing(updateDetails, applicationTerminated: false))
}

@Test
func terminalCallbacksProduceQuietOrActionableStatesAndDismissCleanly() {
    var machine = AppUpdateStateMachine()
    let current = AppUpdateMessage(
        title: "You’re up to date",
        detail: "Chamfer 2.3 is the newest version."
    )
    machine.receive(.noUpdate(current, isCurrentVersion: true))
    #expect(machine.state == .upToDate(current))

    let failure = AppUpdateMessage(
        title: "Chamfer couldn’t update",
        detail: "The download was interrupted."
    )
    machine.receive(.failed(failure))
    #expect(machine.state == .error(failure))

    machine.receive(.installed(relaunched: false))
    #expect(machine.state == .installed)

    machine.receive(.dismissed)
    #expect(machine.state == .idle)
    #expect(machine.progress == nil)
}

@Test
func outOfOrderProgressCallbacksDegradeToAnUnknownReleaseInsteadOfTrapping() {
    var machine = AppUpdateStateMachine()

    machine.receive(.downloadReceived(bytes: 80))
    #expect(machine.state == .downloading(.unknown, AppUpdateProgress(completedBytes: 80)))

    machine.receive(.readyToInstall)
    #expect(machine.state == .readyToInstall(.unknown))
}

@Test
func updaterConfigurationRequiresBothReleaseCredentials() {
    #expect(AppUpdateConfiguration(infoDictionary: [:]) == nil)
    #expect(AppUpdateConfiguration(infoDictionary: ["SUFeedURL": "feed"]) == nil)
    #expect(AppUpdateConfiguration(infoDictionary: ["SUPublicEDKey": "key"]) == nil)
    #expect(
        AppUpdateConfiguration(
            infoDictionary: ["SUFeedURL": "", "SUPublicEDKey": "key"]
        ) == nil
    )
    #expect(
        AppUpdateConfiguration(
            infoDictionary: ["SUFeedURL": "feed", "SUPublicEDKey": "key"]
        ) != nil
    )
}

@Test @MainActor
func sourceBuildWithoutAFeedDoesNotConstructAnUpdater() {
    let updates = AppUpdates(bundle: .main)

    #expect(!updates.isAvailable)
}

@Test
func releaseNotesImporterRecognizesHeadingsParagraphsAndLists() {
    let html = """
    <h2>What changed</h2>
    <p>Chamfer now keeps updates in its own visual language.</p>
    <ul><li>Warm paper surfaces</li><li>Honest progress</li></ul>
    """

    let notes = AppUpdateReleaseNotes.html(Data(html.utf8))

    #expect(notes.blocks.count == 4)
    #expect(notes.blocks[0] == .init(style: .heading, text: "What changed"))
    #expect(notes.blocks[1] == .init(
        style: .paragraph,
        text: "Chamfer now keeps updates in its own visual language."
    ))
    #expect(notes.blocks[2] == .init(style: .listItem, text: "Warm paper surfaces"))
    #expect(notes.blocks[3] == .init(style: .listItem, text: "Honest progress"))
}

@Test
func releaseNotesImporterNeverReturnsAnEmptyPanelForUnreadableInput() {
    let notes = AppUpdateReleaseNotes.html(Data([0xFF, 0xFE, 0x00]))

    #expect(!notes.blocks.isEmpty)
    #expect(!notes.plainText.isEmpty)
}
