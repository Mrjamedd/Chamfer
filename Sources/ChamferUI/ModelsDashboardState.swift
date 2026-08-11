import ChamferCore
import ChamferRewrite
import CoreGraphics

/// The two intelligence paths, in the order the dashboard ranks them.
///
/// There is no third case and no Apple case. The downloaded local model is the
/// product's intelligence; cloud is the paid alternative for people who want a
/// larger model than their Mac can hold.
public enum ModelsBackendID: String, CaseIterable, Hashable, Sendable {
    case local
    case cloud
}

/// Whether the cloud path is something this build can actually do.
///
/// One constant, read by the row that draws it and by the state that opens its
/// configuration, so "coming soon" cannot be a label on a panel that still
/// works. Flip it when cloud ships; nothing else needs to change.
public enum ModelsCloudAvailability {
    public static let isAvailable = false

    public static let comingSoonTitle = "COMING SOON"
    public static let comingSoonDetail = "Cloud models aren't part of this build yet. Everything Chamfer does today runs on your Mac."
}

public enum ModelsConnectionState: Equatable, Sendable {
    case notConnected
    case connected
    case testing
    case failed
}

/// What is actually on disk.
///
/// Never persisted. It is refreshed from the runtime every time the page
/// appears, because a model deleted outside Chamfer — or a preferences file
/// carried to another Mac — must read as absent rather than as installed.
public enum ModelsInstallationState: Equatable, Sendable {
    case notInstalled
    case downloading
    case installed
}

/// How far the download has got, as the interface needs it.
public struct ModelsDownloadState: Equatable, Sendable {
    /// 0…1, or nil while the runtime is resolving a manifest and has no total.
    public var fraction: Double?
    /// The runtime's own word for the current step.
    public var stage: String

    public init(fraction: Double? = nil, stage: String = "Starting…") {
        self.fraction = fraction
        self.stage = stage
    }
}

/// Everything the Models dashboard draws, and the only place the rest of the
/// app asks what the model situation is.
///
/// The device's recommended model is *derived*, never stored: `device` goes in,
/// exactly one model comes out. There is no selected-model field because there
/// is no selection to make.
public struct ModelsDashboardState: Equatable, Sendable {
    /// The explicitly activated path. Nil until the user activates one — a
    /// fresh install stays inert, which is a promise the app makes.
    public var active: ModelsBackendID?
    /// Only cloud has configuration to expand into.
    public var cloudConfigurationOpen: Bool
    public var connection: ModelsConnectionState
    public var installation: ModelsInstallationState
    public var download: ModelsDownloadState?
    public var localRuntimeAvailable: Bool
    /// Set while Chamfer is installing the Ollama runtime itself. Distinct from
    /// `download`, which is the *model* — the card has to be able to say which
    /// of the two multi-hundred-megabyte things it is fetching.
    public var runtimeInstall: ModelsDownloadState?
    public var effort: ModelEffort
    public var device: DeviceProfile

    public init(
        active: ModelsBackendID? = nil,
        cloudConfigurationOpen: Bool = false,
        connection: ModelsConnectionState = .notConnected,
        installation: ModelsInstallationState = .notInstalled,
        download: ModelsDownloadState? = nil,
        localRuntimeAvailable: Bool = false,
        runtimeInstall: ModelsDownloadState? = nil,
        effort: ModelEffort = .standard,
        device: DeviceProfile = .current()
    ) {
        self.active = active
        self.cloudConfigurationOpen = cloudConfigurationOpen
        self.connection = connection
        self.installation = installation
        self.download = download
        self.localRuntimeAvailable = localRuntimeAvailable
        self.runtimeInstall = runtimeInstall
        self.effort = effort
        self.device = device
    }

    // MARK: - The device's model

    /// The one local model this Mac runs. Derived, deterministic, and not a
    /// choice anyone is offered.
    public var recommendedModel: LocalModelDescriptor {
        LocalModelSelection.recommended(for: device)
    }

    public var recommendationRationale: String {
        LocalModelSelection.rationale(for: device, model: recommendedModel)
    }

    public var hasRoomForModel: Bool {
        LocalModelSelection.hasRoom(for: recommendedModel, on: device)
    }

    /// Whether the local path can run right now.
    public var localReady: Bool {
        localRuntimeAvailable && installation == .installed
    }

    // MARK: - Transitions

    /// Reconciles the interface with what the runtime reports is on disk.
    ///
    /// Takes the whole installed set rather than a boolean so the caller cannot
    /// answer the question itself with a stale identifier — presence is decided
    /// here, once, against the model this device actually runs.
    public mutating func synchronizeInstalledLocalModels(_ modelIDs: Set<String>) {
        let present = LocalModelIdentity.contains(recommendedModel.id, in: modelIDs)
        // A download in flight is not overwritten by a poll that has not seen
        // it land yet; that would flicker the button back to "Download".
        if installation == .downloading, !present { return }
        installation = present ? .installed : .notInstalled
        if present { download = nil }
    }

    public mutating func beginDownload() {
        installation = .downloading
        download = ModelsDownloadState()
    }

    public mutating func updateDownload(fraction: Double?, stage: String) {
        guard installation == .downloading else { return }
        download = ModelsDownloadState(fraction: fraction, stage: stage)
    }

    public mutating func finishDownload(installed: Bool) {
        installation = installed ? .installed : .notInstalled
        download = nil
    }

    public mutating func beginConnectionTest() {
        connection = .testing
    }

    public mutating func finishConnectionTest(connected: Bool) {
        connection = connected ? .connected : .failed
    }

    public mutating func synchronizeConnection(connected: Bool) {
        connection = connected ? .connected : .notConnected
    }

    public mutating func setEffort(_ effort: ModelEffort) {
        self.effort = effort
    }

    /// Refused while cloud is unreleased, so the panel cannot be reached by a
    /// keyboard shortcut, restored state, or a caller that has not heard.
    public mutating func openCloudConfiguration() {
        guard ModelsCloudAvailability.isAvailable else { return }
        cloudConfigurationOpen = true
    }

    public mutating func closeCloudConfiguration() {
        cloudConfigurationOpen = false
    }

    /// Activation is explicit and is the only thing that changes `active`.
    public mutating func activate(_ backend: ModelsBackendID) {
        active = backend
        if backend == .cloud { cloudConfigurationOpen = false }
    }

    // MARK: - Status

    /// The small capitalised word above each card.
    public func status(for backend: ModelsBackendID) -> String {
        switch backend {
        case .local:
            if backend == active {
                return localReady ? "ACTIVE" : "UNAVAILABLE"
            }
            // Gated on the runtime actually being absent, the same way the
            // action and the status line are. A provisioning report that
            // arrives a moment after Ollama starts answering must not take the
            // card backwards.
            if runtimeInstall != nil, !localRuntimeAvailable { return "SETTING UP" }
            // A missing runtime is not a state this card reports. Chamfer
            // installs it, so "the runtime is not here yet" and "the model is
            // not here yet" are the same sentence to the person reading it, and
            // one download answers both.
            return switch installation {
            case .installed: "READY"
            case .downloading: "DOWNLOADING"
            case .notInstalled: "NOT INSTALLED"
            }
        case .cloud:
            if backend == active {
                return connection == .connected ? "ACTIVE" : "UNAVAILABLE"
            }
            return connection == .connected ? "CONNECTED" : "NOT CONNECTED"
        }
    }
}

// MARK: - Local card presentation

/// The one action the primary card offers, resolved from state rather than
/// assembled at the call site. Title, symbol and whether it does anything all
/// come from the same switch, so the button cannot say "Download" while the
/// action activates.
///
/// There is no case for fetching Ollama. The runtime is Chamfer's errand — the
/// app downloads, verifies and runs its own copy — so the only thing this card
/// ever asks anybody for is the model.
public enum ModelsLocalAction: Equatable, Sendable {
    /// Chamfer is setting the runtime up and does not yet know whether the
    /// model is on disk. Nothing to press until it does.
    case preparingRuntime
    case download
    case downloading
    case activate
    case alreadyActive

    /// The button's words. The download names the model rather than saying
    /// "model", because a control that starts a multi-gigabyte download should
    /// say what arrives.
    public func title(model: LocalModelDescriptor) -> String {
        switch self {
        case .preparingRuntime: "Setting Up…"
        case .download: "Download \(model.displayName)"
        case .downloading: "Downloading…"
        case .activate: "Use This Model"
        case .alreadyActive: "In Use"
        }
    }

    public var symbol: String {
        switch self {
        case .preparingRuntime: "arrow.down"
        case .download: "arrow.down"
        case .downloading: "arrow.down"
        case .activate: "checkmark"
        case .alreadyActive: "checkmark"
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .download, .activate: true
        case .preparingRuntime, .downloading, .alreadyActive: false
        }
    }
}

public enum ModelsLocalPresentation {
    public static func action(for state: ModelsDashboardState) -> ModelsLocalAction {
        // Chamfer is fetching the runtime and cannot yet ask it what is on
        // disk, so a model already installed would read as missing. Waiting the
        // moment out is better than offering a download that is not needed.
        if state.runtimeInstall != nil, !state.localRuntimeAvailable {
            return .preparingRuntime
        }
        // No runtime and none on its way — a first run before provisioning
        // started, or one that failed — still offers the model. Pressing it
        // arranges the runtime first; that is not the user's problem to solve.
        switch state.installation {
        case .downloading: return .downloading
        case .notInstalled: return .download
        case .installed: return state.active == .local ? .alreadyActive : .activate
        }
    }

    /// The line beside the status dot: one sentence, always saying the most
    /// useful true thing rather than repeating the button.
    public static func statusDetail(for state: ModelsDashboardState) -> String {
        if let runtimeInstall = state.runtimeInstall, !state.localRuntimeAvailable {
            return runtimeInstall.stage
        }
        if !state.hasRoomForModel, state.installation != .installed {
            return "Not enough free space for the \(state.recommendedModel.downloadSizeLabel) download."
        }
        switch state.installation {
        case .downloading:
            return state.download?.stage.capitalizedFirst
                ?? "Downloading from Ollama…"
        case .notInstalled:
            return "\(state.recommendedModel.downloadSizeLabel) download, once. Nothing leaves this Mac."
        case .installed:
            return state.active == .local
                ? "Running on this Mac. Notes never leave it."
                : "Downloaded and ready. Activate it to start rewriting."
        }
    }

    /// Whether the primary action can actually be pressed.
    public static func isActionEnabled(for state: ModelsDashboardState) -> Bool {
        let action = action(for: state)
        guard action.isEnabled else { return false }
        if action == .download, !state.hasRoomForModel { return false }
        return true
    }
}

// MARK: - Tint

public struct ModelsRGBTint: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// One tint source per path, shared by the card, its glow and its controls, so
/// a surface handing over to another cannot introduce a colour discontinuity.
///
/// The violet that used to mark the downloadable model is now the page's
/// primary colour; cloud keeps the rose it always had, one step quieter.
public enum ModelsBackendTintResponse {
    public static func tint(for backend: ModelsBackendID) -> ModelsRGBTint {
        switch backend {
        case .local: ModelsRGBTint(red: 0.71, green: 0.63, blue: 0.86)
        case .cloud: ModelsRGBTint(red: 0.92, green: 0.61, blue: 0.75)
        }
    }

    /// The far stop of a card's gradient.
    public static func secondaryTint(for backend: ModelsBackendID) -> ModelsRGBTint {
        switch backend {
        case .local: ModelsRGBTint(red: 0.93, green: 0.66, blue: 0.43)
        case .cloud: ModelsRGBTint(red: 0.93, green: 0.57, blue: 0.48)
        }
    }
}

// MARK: - Hierarchy

/// How strongly a card is drawn.
///
/// The whole redesign is in these numbers: the local path carries a filled,
/// tinted, shadowed surface, and cloud carries a hairline on the page. Hover
/// and activation move within a path's band rather than across the gap between
/// them, so cloud can never out-shout local by being pointed at.
public struct ModelsSurfacePresentation: Equatable, Sendable {
    public let paperOpacity: Double
    public let tintOpacity: Double
    public let secondaryTintOpacity: Double
    public let borderOpacity: Double
    public let shadowOpacity: Double
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat
    public let lift: CGFloat

    public init(
        paperOpacity: Double,
        tintOpacity: Double,
        secondaryTintOpacity: Double,
        borderOpacity: Double,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowY: CGFloat,
        lift: CGFloat
    ) {
        self.paperOpacity = paperOpacity
        self.tintOpacity = tintOpacity
        self.secondaryTintOpacity = secondaryTintOpacity
        self.borderOpacity = borderOpacity
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
        self.lift = lift
    }
}

public enum ModelsSurfaceResponse {
    public static func presentation(
        for backend: ModelsBackendID,
        isActive: Bool,
        isHovered: Bool,
        isRecessed: Bool = false
    ) -> ModelsSurfacePresentation {
        var presentation = switch backend {
        case .local:
            ModelsSurfacePresentation(
                paperOpacity: 0.94,
                tintOpacity: isActive ? 0.30 : 0.24,
                secondaryTintOpacity: isActive ? 0.17 : 0.13,
                borderOpacity: isActive ? 0.42 : 0.30,
                shadowOpacity: isActive ? 0.17 : 0.13,
                shadowRadius: 26,
                shadowY: 14,
                lift: 0
            )
        case .cloud:
            ModelsSurfacePresentation(
                paperOpacity: 0.55,
                tintOpacity: isActive ? 0.15 : 0.07,
                secondaryTintOpacity: isActive ? 0.09 : 0.04,
                borderOpacity: isActive ? 0.34 : 0.22,
                shadowOpacity: isActive ? 0.08 : 0.04,
                shadowRadius: 12,
                shadowY: 6,
                lift: 0
            )
        }

        if isHovered {
            presentation = ModelsSurfacePresentation(
                paperOpacity: min(1, presentation.paperOpacity + 0.04),
                tintOpacity: presentation.tintOpacity + 0.06,
                secondaryTintOpacity: presentation.secondaryTintOpacity + 0.04,
                borderOpacity: presentation.borderOpacity + 0.12,
                shadowOpacity: presentation.shadowOpacity + 0.05,
                shadowRadius: presentation.shadowRadius + 6,
                shadowY: presentation.shadowY + 2,
                // A card the size of the local one only needs a hair of travel
                // to read as answering the pointer. More would make the page
                // feel loose.
                lift: -2
            )
        }

        if isRecessed {
            presentation = ModelsSurfacePresentation(
                paperOpacity: presentation.paperOpacity * 0.9,
                tintOpacity: presentation.tintOpacity * 0.5,
                secondaryTintOpacity: presentation.secondaryTintOpacity * 0.5,
                borderOpacity: presentation.borderOpacity * 0.5,
                shadowOpacity: presentation.shadowOpacity * 0.4,
                shadowRadius: presentation.shadowRadius,
                shadowY: presentation.shadowY,
                lift: 0
            )
        }

        return presentation
    }
}

// MARK: - Cloud panel

/// What the page behind the cloud panel looks like at a given moment.
public struct ModelsPanelRecession: Equatable, Sendable {
    public let scale: CGFloat
    public let opacity: Double
    /// Past halfway the page is no longer the thing being interacted with.
    public let isRecessed: Bool

    public init(scale: CGFloat, opacity: Double, isRecessed: Bool) {
        self.scale = scale
        self.opacity = opacity
        self.isRecessed = isRecessed
    }
}

/// The cloud panel's arrival, as one number the page and the panel both read.
///
/// Explicit rather than a SwiftUI `transition`: a transition only resolves when
/// its insertion happens inside an animated update, so a page that mounts with
/// the panel already open — restored state, or the design harness — leaves it
/// stuck at its inserted opacity of zero. A progress value has no such
/// dependence on how it came to be set, and it makes the departure the literal
/// inverse of the arrival.
public enum ModelsPanelPresentation {
    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    /// Smoothstepped, matching every other shaped value in the app.
    private static func shaped(_ value: CGFloat) -> CGFloat {
        let amount = clamped(value)
        return amount * amount * (3 - 2 * amount)
    }

    /// Grows from 90% — enough to read as arriving, not so much that it lurches.
    public static func scale(progress: CGFloat) -> CGFloat {
        0.90 + 0.10 * shaped(progress)
    }

    /// Ahead of the scale, so the panel is legible before it has finished
    /// settling rather than fading in after it has stopped.
    public static func opacity(progress: CGFloat) -> CGFloat {
        clamped(shaped(progress) * 1.35)
    }

    public static func recession(progress: CGFloat) -> ModelsPanelRecession {
        let amount = shaped(progress)
        return ModelsPanelRecession(
            scale: 1 - 0.015 * amount,
            opacity: 1 - 0.45 * Double(amount),
            isRecessed: progress > 0.5
        )
    }
}

// MARK: - Effort selector

public struct ModelsEffortRowPresentation: Equatable, Sendable {
    public let titleOpacity: Double
    public let detailOpacity: Double
    public let isSelected: Bool

    public init(titleOpacity: Double, detailOpacity: Double, isSelected: Bool) {
        self.titleOpacity = titleOpacity
        self.detailOpacity = detailOpacity
        self.isSelected = isSelected
    }
}

public enum ModelsEffortSelectorResponse {
    /// The unselected rows stay legible rather than fading to decoration: this
    /// is a choice between three things, and two of them being hard to read
    /// would make it look like one option with two ghosts.
    public static func presentation(
        for effort: ModelEffort,
        selected: ModelEffort,
        hovered: ModelEffort?
    ) -> ModelsEffortRowPresentation {
        if effort == selected {
            return ModelsEffortRowPresentation(
                titleOpacity: 1,
                detailOpacity: 1,
                isSelected: true
            )
        }
        let hovering = hovered == effort
        return ModelsEffortRowPresentation(
            titleOpacity: hovering ? 0.92 : 0.74,
            detailOpacity: hovering ? 0.72 : 0.52,
            isSelected: false
        )
    }
}

// MARK: - Motion

public struct ModelsMotionTiming: Equatable, Sendable {
    /// Cloud configuration arriving. Larger surface, slightly longer.
    public let panelOpen: Double
    /// Leaving is quicker than arriving: getting out of the way should not take
    /// as long as showing up.
    public let panelClose: Double
    /// The effort indicator sliding between rows.
    public let effortChange: Double
    /// Download progress catching up to a new report.
    public let progress: Double
    /// The ambient wash answering the pointer. Deliberately slow — it is
    /// atmosphere, not a control's reply.
    public let ambient: Double

    public init(
        panelOpen: Double,
        panelClose: Double,
        effortChange: Double,
        progress: Double,
        ambient: Double
    ) {
        self.panelOpen = panelOpen
        self.panelClose = panelClose
        self.effortChange = effortChange
        self.progress = progress
        self.ambient = ambient
    }
}

public enum ModelsMotionResponse {
    public static func timing(reduceMotion: Bool) -> ModelsMotionTiming {
        reduceMotion
            ? ModelsMotionTiming(
                panelOpen: 0.12,
                panelClose: 0.12,
                effortChange: 0.12,
                progress: 0.12,
                ambient: 0.12
            )
            : ModelsMotionTiming(
                panelOpen: 0.35,
                panelClose: 0.25,
                effortChange: 0.28,
                progress: 0.30,
                ambient: 0.46
            )
    }
}

// MARK: - Ambient field

public struct ModelsBloomPresentation: Equatable, Sendable {
    public let scale: CGFloat
    public let opacity: Double
    public let inwardProgress: CGFloat

    public init(scale: CGFloat, opacity: Double, inwardProgress: CGFloat) {
        self.scale = scale
        self.opacity = opacity
        self.inwardProgress = inwardProgress
    }
}

/// Converts activation and pointer state into the page's ambient wash.
///
/// The local blooms sit above the cloud ones at rest, which is the hierarchy
/// stated in atmosphere before a single word is read.
public enum ModelsBloomResponse {
    public static func presentation(
        for backend: ModelsBackendID,
        active: ModelsBackendID?,
        hovered: ModelsBackendID?,
        recessed: Bool = false
    ) -> ModelsBloomPresentation {
        var presentation: ModelsBloomPresentation
        if hovered == backend {
            presentation = ModelsBloomPresentation(
                scale: backend == active ? 1.14 : 1.10,
                opacity: backend == .local ? 0.60 : 0.46,
                inwardProgress: 1
            )
        } else if active == backend {
            presentation = ModelsBloomPresentation(
                scale: 1.05,
                opacity: backend == .local ? 0.54 : 0.40,
                inwardProgress: 0.32
            )
        } else {
            presentation = ModelsBloomPresentation(
                scale: backend == .local ? 1.0 : 0.94,
                opacity: backend == .local ? 0.44 : 0.30,
                inwardProgress: backend == .local ? 0.14 : 0
            )
        }

        if recessed {
            presentation = ModelsBloomPresentation(
                scale: presentation.scale * 0.97,
                opacity: presentation.opacity * 0.55,
                inwardProgress: presentation.inwardProgress
            )
        }
        return presentation
    }
}

// MARK: - Layout

/// The page's proportions, derived from the space it is given.
///
/// Chamfer's window is a fixed 780 wide and between 640 and 860 tall, so this
/// is a small, closed set of situations rather than an open responsive problem.
/// The columns keep their ratio and the card heights absorb the difference.
public struct ModelsPageMetrics: Equatable, Sendable {
    public let horizontalPadding: CGFloat
    public let topPadding: CGFloat
    public let columnGap: CGFloat
    public let rowGap: CGFloat
    public let primaryWidth: CGFloat
    public let configurationWidth: CGFloat
    /// A floor, not a fixed size. The two columns take the height of whichever
    /// has more to say and match each other; this only stops the row collapsing
    /// to something shorter than the composition wants.
    public let minimumRowHeight: CGFloat
    public let cloudHeight: CGFloat
    public let isCompact: Bool

    /// Below this the composition tightens: smaller title, tighter margins.
    static let compactHeightThreshold: CGFloat = 560

    /// What the row wants before anything is squeezed. Set by the configuration
    /// column, which is the taller of the two by construction — three modes,
    /// four readouts and a line of mechanics.
    static let naturalRowHeight: CGFloat = 336

    public static func metrics(for size: CGSize) -> ModelsPageMetrics {
        let isCompact = size.height < compactHeightThreshold
        let horizontal: CGFloat = isCompact ? 28 : 34
        let gap: CGFloat = 18
        let available = max(320, size.width - horizontal * 2)
        // The primary card takes just under two-thirds. Anything closer to half
        // and the two columns read as a pair of equals, which is the hierarchy
        // this page exists to undo.
        let configuration = min(244, max(196, (available - gap) * 0.355))
        let primary = available - gap - configuration

        let topPadding: CGFloat = isCompact ? 26 : 34
        let cloud: CGFloat = isCompact ? 88 : 96
        let rowHeight = isCompact ? naturalRowHeight - 20 : naturalRowHeight

        return ModelsPageMetrics(
            horizontalPadding: horizontal,
            topPadding: topPadding,
            columnGap: gap,
            rowGap: gap,
            primaryWidth: primary,
            configurationWidth: configuration,
            minimumRowHeight: rowHeight,
            cloudHeight: cloud,
            isCompact: isCompact
        )
    }
}

extension String {
    /// Ollama's stage strings arrive lowercase ("pulling manifest"). Only the
    /// first letter is raised; the rest is the runtime's own wording.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
