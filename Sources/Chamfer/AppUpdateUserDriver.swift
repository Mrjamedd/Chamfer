import AppKit
import ChamferUI
import Observation
import Sparkle
import SwiftUI

@MainActor
@Observable
final class AppUpdateUserDriver: NSObject, SPUUserDriver {
    private(set) var state: AppUpdatePresentationState = .idle
    private(set) var isPresented = false

    @ObservationIgnored private var machine = AppUpdateStateMachine()
    @ObservationIgnored private var resetsStateWhenClosed = true
    @ObservationIgnored private let presentation = AppUpdatePresentationController()
    @ObservationIgnored private let allowsAutomaticDownloads: Bool
    @ObservationIgnored private let automaticallyDownloadsByDefault: Bool

    @ObservationIgnored private var permissionReply: ((SUUpdatePermissionResponse) -> Void)?
    @ObservationIgnored private var checkCancellation: (() -> Void)?
    @ObservationIgnored private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var downloadCancellation: (() -> Void)?
    @ObservationIgnored private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var retryTermination: (() -> Void)?
    @ObservationIgnored private var acknowledgement: (() -> Void)?

    init(bundle: Bundle) {
        let allows = bundle.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates")
            as? NSNumber
        let downloads = bundle.object(forInfoDictionaryKey: "SUAutomaticallyUpdate")
            as? NSNumber
        allowsAutomaticDownloads = allows?.boolValue ?? true
        automaticallyDownloadsByDefault = downloads?.boolValue ?? false
        super.init()
    }

    func showStartupFailure(_ error: Error) {
        let cocoaError = error as NSError
        receive(
            .failed(
                AppUpdateMessage(
                    title: "Chamfer couldn’t start updates",
                    detail: messageDetail(for: cocoaError)
                )
            )
        )
    }

    // MARK: - Sparkle callbacks

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        permissionReply = reply
        receive(.permissionRequested)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkCancellation = cancellation
        receive(.userInitiatedCheckStarted)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state updateState: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        updateReply = reply
        receive(.updateFound(details(for: appcastItem, state: updateState)))
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        let type = downloadData.mimeType?.lowercased()
        let notes: AppUpdateReleaseNotes
        if type == "text/plain" {
            notes = .plain(
                String(data: downloadData.data, encoding: .utf8)
                    ?? String(decoding: downloadData.data, as: UTF8.self)
            )
        } else {
            notes = .html(
                downloadData.data,
                textEncodingName: downloadData.textEncodingName
            )
        }
        receive(.releaseNotesLoaded(notes), present: isPresented)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        receive(
            .releaseNotesLoaded(
                .plain(
                    "Chamfer couldn’t load these release notes. You can still install the update."
                )
            ),
            present: isPresented
        )
    }

    func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        self.acknowledgement = acknowledgement
        let cocoaError = error as NSError
        let reason = (cocoaError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?
            .intValue
        let isCurrentVersion = reason.map {
            $0 == SPUNoUpdateFoundReason.onLatestVersion.rawValue
                || $0 == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue
        } ?? false
        let message = AppUpdateMessage(
            title: isCurrentVersion ? "You’re up to date" : "No update is available",
            detail: messageDetail(for: cocoaError)
        )
        receive(.noUpdate(message, isCurrentVersion: isCurrentVersion))
    }

    func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        self.acknowledgement = acknowledgement
        let cocoaError = error as NSError
        receive(
            .failed(
                AppUpdateMessage(
                    title: "Chamfer couldn’t update",
                    detail: messageDetail(for: cocoaError)
                )
            )
        )
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadCancellation = cancellation
        receive(.downloadStarted)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        receive(.downloadExpectedLength(expectedContentLength))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receive(.downloadReceived(bytes: length))
    }

    func showDownloadDidStartExtractingUpdate() {
        downloadCancellation = nil
        receive(.extractionStarted)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        receive(.extractionProgress(progress))
    }

    func showReady(
        toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        readyReply = reply
        receive(.readyToInstall)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        receive(.installing(applicationTerminated: applicationTerminated))
        if !applicationTerminated {
            hide(performHaptic: false, resetState: false)
        }
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        receive(.installed(relaunched: relaunched), present: !relaunched)
        if relaunched {
            acknowledgement()
            hide(performHaptic: false)
        } else {
            self.acknowledgement = acknowledgement
        }
    }

    func dismissUpdateInstallation() {
        clearSparkleActions()
        if isPresented || presentation.isVisible {
            hide(performHaptic: false)
        } else {
            machine.receive(.dismissed)
            state = machine.state
        }
    }

    func showUpdateInFocus() {
        guard state != .idle else { return }
        presentation.present(driver: self, takingFocus: true)
        reveal()
    }

    // MARK: - User actions

    func allowAutomaticChecks() {
        Haptics.commit()
        let reply = permissionReply
        permissionReply = nil
        hide(performHaptic: false)
        reply?(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: true,
                automaticUpdateDownloading: allowsAutomaticDownloads
                    ? NSNumber(value: automaticallyDownloadsByDefault)
                    : nil,
                sendSystemProfile: false
            )
        )
    }

    func declineAutomaticChecks() {
        Haptics.commit()
        let reply = permissionReply
        permissionReply = nil
        hide(performHaptic: false)
        reply?(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: false,
                automaticUpdateDownloading: allowsAutomaticDownloads
                    ? NSNumber(value: false)
                    : nil,
                sendSystemProfile: false
            )
        )
    }

    func installAvailableUpdate() {
        guard case let .available(details) = state else { return }
        Haptics.commit()
        let reply = updateReply
        updateReply = nil
        if details.isInformationOnly {
            if let informationURL = details.informationURL {
                NSWorkspace.shared.open(informationURL)
            }
            hide(performHaptic: false)
            reply?(.dismiss)
        } else {
            reply?(.install)
        }
    }

    func skipAvailableUpdate() {
        Haptics.commit()
        let reply = updateReply
        updateReply = nil
        hide(performHaptic: false)
        reply?(.skip)
    }

    func installAndRelaunch() {
        Haptics.commit()
        let reply = readyReply
        readyReply = nil
        hide(performHaptic: false)
        reply?(.install)
    }

    func retryTerminating() {
        Haptics.commit()
        let retry = retryTermination
        retryTermination = nil
        retry?()
    }

    func dismissFromUser() {
        guard isPresented else { return }
        Haptics.commit()

        switch state {
        case .permission:
            let reply = permissionReply
            permissionReply = nil
            hide(performHaptic: false)
            reply?(
                SUUpdatePermissionResponse(
                    automaticUpdateChecks: false,
                    automaticUpdateDownloading: allowsAutomaticDownloads
                        ? NSNumber(value: false)
                        : nil,
                    sendSystemProfile: false
                )
            )

        case .checking:
            let cancellation = checkCancellation
            checkCancellation = nil
            hide(performHaptic: false)
            cancellation?()

        case .available:
            let reply = updateReply
            updateReply = nil
            hide(performHaptic: false)
            reply?(.dismiss)

        case .downloading:
            let cancellation = downloadCancellation
            downloadCancellation = nil
            hide(performHaptic: false)
            cancellation?()

        case .readyToInstall:
            let reply = readyReply
            readyReply = nil
            hide(performHaptic: false)
            reply?(.dismiss)

        case .upToDate, .error, .installed:
            let acknowledgement = acknowledgement
            self.acknowledgement = nil
            hide(performHaptic: false)
            acknowledgement?()

        case .extracting, .installing:
            // Sparkle exposes no cancellation once extraction has begun. Hide
            // the progress without lying that the update itself was stopped;
            // its next actionable callback will bring the panel back.
            hide(performHaptic: false, resetState: false)

        case .idle:
            hide(performHaptic: false)
        }
    }

    // MARK: - Presentation lifecycle

    func presentationDidClose() {
        guard !isPresented, resetsStateWhenClosed else { return }
        machine.receive(.dismissed)
        state = machine.state
    }

    private func receive(
        _ event: AppUpdateStateMachine.Event,
        present: Bool = true
    ) {
        machine.receive(event)
        state = machine.state
        guard present else { return }
        presentation.present(driver: self, takingFocus: false)
        reveal()
    }

    private func reveal() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            resetsStateWhenClosed = false
            isPresented = true
            presentation.resizeAndCenter()
        }
    }

    private func hide(performHaptic: Bool, resetState: Bool = true) {
        guard isPresented || presentation.isVisible else { return }
        if performHaptic { Haptics.commit() }
        resetsStateWhenClosed = resetState
        isPresented = false
        presentation.dismiss(driver: self)
    }

    private func clearSparkleActions() {
        permissionReply = nil
        checkCancellation = nil
        updateReply = nil
        downloadCancellation = nil
        readyReply = nil
        retryTermination = nil
        acknowledgement = nil
    }

    private func details(
        for item: SUAppcastItem,
        state: SPUUserUpdateState
    ) -> AppUpdateDetails {
        let releaseNotes: AppUpdateReleaseNotes
        if let description = item.itemDescription {
            if item.itemDescriptionFormat?.lowercased() == "plain-text" {
                releaseNotes = .plain(description)
            } else {
                releaseNotes = .html(Data(description.utf8))
            }
        } else {
            releaseNotes = .plain("Release notes are not available for this update.")
        }

        let stage: AppUpdateStage = switch state.stage {
        case .notDownloaded: .notDownloaded
        case .downloaded: .downloaded
        case .installing: .installing
        @unknown default: .notDownloaded
        }

        return AppUpdateDetails(
            version: item.displayVersionString,
            releaseNotes: releaseNotes,
            informationURL: item.infoURL,
            isInformationOnly: item.isInformationOnlyUpdate,
            isCritical: item.isCriticalUpdate,
            stage: stage
        )
    }

    private func messageDetail(for error: NSError) -> String {
        if let suggestion = error.localizedRecoverySuggestion, !suggestion.isEmpty {
            return suggestion
        }
        let description = error.localizedDescription
        return description.isEmpty
            ? "Try checking again in a little while."
            : description
    }
}

@MainActor
private final class AppUpdatePresentationController {
    private var panel: AppUpdatePanel?
    private weak var previousKeyWindow: NSWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var closeTask: Task<Void, Never>?

    var isVisible: Bool { panel?.isVisible == true }

    func present(driver: AppUpdateUserDriver, takingFocus: Bool) {
        closeTask?.cancel()
        closeTask = nil

        let panel = panel ?? makePanel(driver: driver)
        self.panel = panel
        installClickAwayMonitors(driver: driver)

        if takingFocus || NSApp.isActive {
            if NSApp.keyWindow !== panel {
                previousKeyWindow = NSApp.keyWindow
            }
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
            NSApp.requestUserAttention(.informationalRequest)
        }
        resizeAndCenter()
    }

    func resizeAndCenter() {
        guard let panel, let view = panel.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        panel.setContentSize(size)

        let parent = NSApp.windows.first {
            $0 !== panel && $0.isVisible && !($0 is NSPanel)
        }
        if let parent {
            let frame = panel.frame
            panel.setFrameOrigin(
                CGPoint(
                    x: parent.frame.midX - frame.width / 2,
                    y: parent.frame.midY - frame.height / 2
                )
            )
        } else {
            panel.center()
        }
    }

    func dismiss(driver: AppUpdateUserDriver) {
        guard let panel else {
            driver.presentationDidClose()
            return
        }
        removeClickAwayMonitors()
        closeTask?.cancel()
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? Chamfer.Motion.reducedDuration
            : Chamfer.Motion.sheetDepartureDuration
        closeTask = Task { @MainActor [weak self, weak driver] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            panel.orderOut(nil)
            self.panel = nil
            self.closeTask = nil
            if self.previousKeyWindow?.isVisible == true {
                self.previousKeyWindow?.makeKey()
            }
            self.previousKeyWindow = nil
            driver?.presentationDidClose()
        }
    }

    private func makePanel(driver: AppUpdateUserDriver) -> AppUpdatePanel {
        let content = AppUpdatePanelView(driver: driver)
            .preferredColorScheme(.light)
        let hosting = NSHostingController(rootView: content)
        let panel = AppUpdatePanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.escapeAction = { [weak driver] in driver?.dismissFromUser() }
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func installClickAwayMonitors(driver: AppUpdateUserDriver) {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self, weak driver] event in
            guard event.window !== self?.panel else { return event }
            Task { @MainActor in driver?.dismissFromUser() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak driver] _ in
            Task { @MainActor in driver?.dismissFromUser() }
        }
    }

    private func removeClickAwayMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

@MainActor
private final class AppUpdatePanel: NSPanel {
    var escapeAction: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        escapeAction?()
    }
}
