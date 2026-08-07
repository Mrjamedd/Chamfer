import CoreGraphics

public enum ModelsBackendID: String, CaseIterable, Hashable, Sendable {
    case apple
    case ollama
    case mlx
}

public enum ModelsConnectionState: Equatable, Sendable {
    case notConnected
    case connected
    case testing
    case failed
}

public enum ModelsInstallationState: Equatable, Sendable {
    case notInstalled
    case downloading
    case installed
}

public struct ModelsLandscapeState: Equatable, Sendable {
    public var active: ModelsBackendID
    public var selected: ModelsBackendID
    public var expanded: ModelsBackendID?
    public var connection: ModelsConnectionState
    public var installation: ModelsInstallationState
    public var selectedLocalModelID: String
    public var installedLocalModelIDs: Set<String>
    public var localRuntimeAvailable: Bool

    public init(
        active: ModelsBackendID = .apple,
        selected: ModelsBackendID = .apple,
        expanded: ModelsBackendID? = nil,
        connection: ModelsConnectionState = .notConnected,
        installation: ModelsInstallationState = .notInstalled,
        selectedLocalModelID: String = "qwen3.5:4b",
        installedLocalModelIDs: Set<String> = [],
        localRuntimeAvailable: Bool = true
    ) {
        self.active = active
        self.selected = selected
        self.expanded = expanded
        self.connection = connection
        self.selectedLocalModelID = selectedLocalModelID
        self.installedLocalModelIDs = installedLocalModelIDs
        self.localRuntimeAvailable = localRuntimeAvailable
        self.installation = installedLocalModelIDs.contains(selectedLocalModelID)
            ? .installed
            : installation
    }

    public mutating func select(_ backend: ModelsBackendID) {
        selected = backend
        expanded = backend
    }

    public mutating func closeConfiguration() {
        selected = active
        expanded = nil
    }

    public mutating func activateSelected() {
        active = selected
        expanded = nil
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

    public mutating func beginDownload() {
        installation = .downloading
    }

    public mutating func finishDownload() {
        installedLocalModelIDs.insert(selectedLocalModelID)
        installation = .installed
    }

    public mutating func selectLocalModel(_ modelID: String) {
        selectedLocalModelID = modelID
        installation = installedLocalModelIDs.contains(modelID)
            ? .installed
            : .notInstalled
    }

    public mutating func synchronizeInstalledLocalModels(_ modelIDs: Set<String>) {
        installedLocalModelIDs = modelIDs
        installation = modelIDs.contains(selectedLocalModelID)
            ? .installed
            : .notInstalled
    }

    public func status(
        for backend: ModelsBackendID,
        appleAvailable: Bool
    ) -> String {
        if backend == active {
            if backend == .apple, !appleAvailable { return "UNAVAILABLE" }
            if backend == .ollama, connection != .connected { return "UNAVAILABLE" }
            if backend == .mlx,
               (!localRuntimeAvailable || installation != .installed) {
                return "UNAVAILABLE"
            }
            return "ACTIVE"
        }

        switch backend {
        case .apple:
            return appleAvailable ? "AVAILABLE" : "UNAVAILABLE"
        case .ollama:
            return connection == .connected ? "CONNECTED" : "NOT CONNECTED"
        case .mlx:
            if !localRuntimeAvailable { return "OLLAMA REQUIRED" }
            return installation == .installed ? "READY" : "NOT INSTALLED"
        }
    }
}

public struct ModelsTitlePresentation: Equatable, Sendable {
    public let size: CGFloat
    public let isBold: Bool
}

/// A single stable title size keeps the hierarchy from jumping when a backend
/// becomes active. Weight alone communicates the active model.
public enum ModelsTitleResponse {
    public static func presentation(isActive: Bool) -> ModelsTitlePresentation {
        ModelsTitlePresentation(size: 27, isBold: isActive)
    }

    public static func presentation(
        for backend: ModelsBackendID,
        active: ModelsBackendID
    ) -> ModelsTitlePresentation {
        presentation(isActive: backend == active)
    }
}

public enum ModelsZoneContentMode: Equatable, Sendable {
    case full
    case focusedSummary
    case titleOnly
}

public enum ModelsZoneStatusPlacement: Equatable, Sendable {
    case aboveTitle
    case besideAction
    case hidden
}

/// Keeps the open configuration sheet from competing with the landscape.
/// The selected model retains enough context to identify the sheet, while
/// the two peripheral models become quiet editorial landmarks.
public enum ModelsLandscapeContent {
    public static func mode(
        for backend: ModelsBackendID,
        state: ModelsLandscapeState
    ) -> ModelsZoneContentMode {
        guard let expanded = state.expanded else { return .full }
        return backend == expanded ? .focusedSummary : .titleOnly
    }

    public static func statusPlacement(
        for backend: ModelsBackendID,
        state: ModelsLandscapeState
    ) -> ModelsZoneStatusPlacement {
        switch mode(for: backend, state: state) {
        case .full:
            return backend == state.active ? .besideAction : .aboveTitle
        case .focusedSummary:
            return .aboveTitle
        case .titleOnly:
            return .hidden
        }
    }
}

public struct ModelsSheetSurfaceIntensity: Equatable, Sendable {
    public let washOpacity: Double
    public let primaryOpacity: Double
    public let secondaryOpacity: Double
    public let borderOpacity: Double
    public let shadowOpacity: Double

    public init(
        washOpacity: Double,
        primaryOpacity: Double,
        secondaryOpacity: Double,
        borderOpacity: Double,
        shadowOpacity: Double
    ) {
        self.washOpacity = washOpacity
        self.primaryOpacity = primaryOpacity
        self.secondaryOpacity = secondaryOpacity
        self.borderOpacity = borderOpacity
        self.shadowOpacity = shadowOpacity
    }
}

public struct ModelsMorphSurfacePresentation: Equatable, Sendable {
    public let paperOpacity: Double
    public let washOpacity: Double
    public let primaryOpacity: Double
    public let secondaryOpacity: Double
    /// The gradient's far stop.
    ///
    /// The sheet's tint falls away toward the bottom-right, but the button it
    /// grows from is filled flatly. While this was pinned at transparent, the
    /// pill's tint drained across its own width the instant the morph mounted,
    /// leaving near-white paper — the flash. Starting it level with
    /// `primaryOpacity` makes the surface begin as a flat fill and *become* a
    /// gradient. Worst on Apple, whose flat fill is the strongest and so had
    /// the most to lose.
    public let trailingOpacity: Double
    public let borderOpacity: Double
    public let shadowOpacity: Double
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat
}

public enum ModelsSheetSurfaceResponse {
    /// Apple carries more opacity than the other two, and that is not an
    /// inconsistency to be tidied away.
    ///
    /// Its green is the palest hue in the set — secondary luminance 0.81 against
    /// 0.70 and 0.67 — and the surface's paper layer climbs to 0.90 of a
    /// near-white cream as the sheet opens. The other two have tints saturated
    /// enough to break that up; Apple's do not, so at a shared strength its
    /// panel opens as a growing white rectangle. The extra opacity is what buys
    /// it the same visual weight.
    ///
    /// The flash was never this. It was that Apple's *pill* did not match its
    /// own sheet, so the fill had to travel — which `ModelsZoneActionResponse`
    /// now makes impossible by deriving the pill from these values.
    public static func intensity(
        for backend: ModelsBackendID?
    ) -> ModelsSheetSurfaceIntensity {
        if backend == .apple {
            return ModelsSheetSurfaceIntensity(
                washOpacity: 0.08,
                primaryOpacity: 0.32,
                secondaryOpacity: 0.17,
                borderOpacity: 0.25,
                shadowOpacity: 0.14
            )
        }

        return ModelsSheetSurfaceIntensity(
            washOpacity: 0.04,
            primaryOpacity: 0.23,
            secondaryOpacity: 0.12,
            borderOpacity: 0.20,
            shadowOpacity: 0.10
        )
    }

    /// - Parameter isHovered: what the button looked like at the instant it was
    ///   clicked. Assuming it unhovered made the surface start from a paler
    ///   fill than the one on screen, so the morph opened with a single frame
    ///   of the tint dropping out and the near-white paper showing through —
    ///   seen as a white flash on the button you had just pressed.
    public static func morphPresentation(
        for backend: ModelsBackendID,
        progress: CGFloat,
        isHovered: Bool = false
    ) -> ModelsMorphSurfacePresentation {
        let amount = ModelsConfigurationTimeline.shaped(progress)
        let action = ModelsZoneActionResponse.presentation(
            for: backend,
            isHovered: isHovered
        )
        let sheet = intensity(for: backend)

        func interpolate(_ start: Double, _ end: Double) -> Double {
            start + (end - start) * Double(amount)
        }

        // Every stop starts level with the button's flat fill, so at progress 0
        // the surface *is* the button rather than a gradient standing in for
        // it, and the sheet's falloff arrives as the morph opens.
        return ModelsMorphSurfacePresentation(
            paperOpacity: interpolate(action.paperOpacity, 0.90),
            washOpacity: interpolate(0, sheet.washOpacity),
            primaryOpacity: interpolate(
                action.fillOpacity,
                sheet.primaryOpacity
            ),
            secondaryOpacity: interpolate(
                action.fillOpacity,
                sheet.secondaryOpacity
            ),
            trailingOpacity: interpolate(action.fillOpacity, 0),
            borderOpacity: interpolate(
                action.borderOpacity,
                sheet.borderOpacity
            ),
            shadowOpacity: interpolate(
                action.shadowOpacity,
                sheet.shadowOpacity
            ),
            // The button's own shadow, not a fixed 4/2 — a hovered pill casts
            // radius 8 at y 4, so anything else pops the moment it hands over.
            shadowRadius: CGFloat(interpolate(isHovered ? 8 : 4, 24)),
            shadowY: CGFloat(interpolate(isHovered ? 4 : 2, 14))
        )
    }
}

public struct ModelsMotionTiming: Equatable, Sendable {
    public let peripheralDuration: Double
    public let focusDuration: Double
    public let morphOpenDuration: Double
    public let morphCloseDuration: Double
    public let contentRevealDelay: Double
    public let contentRevealDuration: Double
    public let contentHideDuration: Double
    public let bloomDuration: Double
    public let sheetRise: CGFloat

    public init(
        peripheralDuration: Double,
        focusDuration: Double,
        morphOpenDuration: Double,
        morphCloseDuration: Double,
        contentRevealDelay: Double,
        contentRevealDuration: Double,
        contentHideDuration: Double,
        bloomDuration: Double,
        sheetRise: CGFloat
    ) {
        self.peripheralDuration = peripheralDuration
        self.focusDuration = focusDuration
        self.morphOpenDuration = morphOpenDuration
        self.morphCloseDuration = morphCloseDuration
        self.contentRevealDelay = contentRevealDelay
        self.contentRevealDuration = contentRevealDuration
        self.contentHideDuration = contentHideDuration
        self.bloomDuration = bloomDuration
        self.sheetRise = sheetRise
    }
}

public enum ModelsMotionResponse {
    public static func timing(reduceMotion: Bool) -> ModelsMotionTiming {
        if reduceMotion {
            return ModelsMotionTiming(
                peripheralDuration: 0.08,
                focusDuration: 0.10,
                morphOpenDuration: 0.10,
                morphCloseDuration: 0.10,
                contentRevealDelay: 0,
                contentRevealDuration: 0.08,
                contentHideDuration: 0.06,
                bloomDuration: 0.10,
                sheetRise: 0
            )
        }

        let morphDuration = 0.20
        // Derived from the timeline rather than restated, so the durations
        // cannot drift away from the windows they are meant to describe.
        let revealDelay = morphDuration
            * Double(ModelsConfigurationTimeline.contentBegins)

        return ModelsMotionTiming(
            peripheralDuration: 0.16,
            focusDuration: 0.18,
            morphOpenDuration: morphDuration,
            // Shorter than opening: getting out of the way should not take as
            // long as arriving. The floor is 0.16 — `contentHideDuration` is
            // held at 0.08 and has to fit inside half of this.
            morphCloseDuration: 0.16,
            contentRevealDelay: revealDelay,
            contentRevealDuration: morphDuration - revealDelay,
            contentHideDuration: 0.08,
            bloomDuration: 0.20,
            sheetRise: 0
        )
    }
}

public struct ModelsZoneActionPresentation: Equatable, Sendable {
    public let fillOpacity: Double
    public let borderOpacity: Double
    public let paperOpacity: Double
    public let shadowOpacity: Double
    public let minimumHeight: CGFloat
    public let cornerRadius: CGFloat
}

public enum ModelsZoneActionResponse {
    public static func presentation(
        for backend: ModelsBackendID,
        isHovered: Bool
    ) -> ModelsZoneActionPresentation {
        // A hovered pill *is* its own sheet's tint, by construction rather than
        // by two constants that happened to agree. Apple's used to sit a hair
        // below the sheet it hands over to, so mounting the morph had to travel
        // the fill — and Apple's hue is too pale to disguise the paper climbing
        // underneath it while that happened. Derived here, that gap cannot
        // reopen the next time either value is tuned.
        let hoveredFill = ModelsSheetSurfaceResponse
            .intensity(for: backend)
            .primaryOpacity
        let restingFill = hoveredFill - 0.09
        let restingBorder = 0.34

        return ModelsZoneActionPresentation(
            fillOpacity: isHovered ? hoveredFill : restingFill,
            borderOpacity: isHovered ? 0.52 : restingBorder,
            paperOpacity: isHovered ? 0.78 : 0.68,
            shadowOpacity: isHovered ? 0.13 : 0.06,
            minimumHeight: 38,
            cornerRadius: 12
        )
    }
}

public struct ModelsZoneGlowPresentation: Equatable, Sendable {
    public let opacity: Double
    public let scale: CGFloat
}

/// The glow behind a model zone.
///
/// Its resting values used to be gated on whether the morph had mounted, so at
/// the instant of mounting — inside a transaction that deliberately disables
/// animations, while progress is still zero — a hovered zone's glow dropped
/// from 0.34 to 0.14 and shrank from 1.10 to 0.95 in one frame. A large blurred
/// ellipse changing that much instantly, directly behind the button being
/// pressed, is the flash.
///
/// Mounting must change nothing. Everything moves on `transitionProgress`.
public enum ModelsZoneGlowResponse {
    public static func presentation(
        isHovered: Bool,
        isActive: Bool,
        isMorphSource: Bool,
        transitionProgress: CGFloat
    ) -> ModelsZoneGlowPresentation {
        let restingOpacity: Double
        let restingScale: CGFloat
        if isHovered {
            restingOpacity = 0.34
            restingScale = 1.10
        } else if isActive {
            restingOpacity = 0.14
            restingScale = 0.95
        } else {
            restingOpacity = 0.05
            restingScale = 0.90
        }

        let focusedOpacity = isMorphSource ? 0.18 : (isActive ? 0.10 : 0.04)
        let focusedScale: CGFloat = isMorphSource ? 0.98 : 0.90
        let amount = min(max(transitionProgress, 0), 1)

        return ModelsZoneGlowPresentation(
            opacity: restingOpacity
                + (focusedOpacity - restingOpacity) * Double(amount),
            scale: restingScale + (focusedScale - restingScale) * amount
        )
    }
}

public enum ModelsConfigurationMorphPhase: Equatable, Sendable {
    case button
    case mounted
    case expanding
    case sheet
    case collapsing

    public var contentVisible: Bool {
        self == .expanding || self == .sheet
    }

    public mutating func beginOpening() {
        self = .mounted
    }

    public mutating func beginExpanding() {
        self = .expanding
    }

    public mutating func finishOpening() {
        self = .sheet
    }

    public mutating func beginClosing() {
        self = .collapsing
    }

    public mutating func finishClosing() {
        self = .button
    }
}

/// Keeps the morphing surface alive after the landscape has returned to its
/// resting state. This gives the departing sheet a real, already-mounted pill
/// to collapse into before the surface is removed from the hierarchy.
public struct ModelsConfigurationMorphState: Equatable, Sendable {
    public private(set) var phase: ModelsConfigurationMorphPhase
    public private(set) var backend: ModelsBackendID?

    public init(
        phase: ModelsConfigurationMorphPhase = .button,
        backend: ModelsBackendID? = nil
    ) {
        self.phase = phase
        self.backend = backend
    }

    public var contentVisible: Bool {
        phase.contentVisible
    }

    public var mountedBackend: ModelsBackendID? {
        phase == .button ? nil : backend
    }

    public mutating func beginOpening(_ backend: ModelsBackendID) {
        self.backend = backend
        phase.beginOpening()
    }

    public mutating func finishOpening() {
        phase.finishOpening()
    }

    public mutating func beginExpanding() {
        phase.beginExpanding()
    }

    public mutating func beginClosing() {
        phase.beginClosing()
    }

    public mutating func finishClosing() {
        phase.finishClosing()
        backend = nil
    }
}

/// Produces the one rect followed by the configuration surface. Keeping this
/// interpolation independent of either endpoint's live SwiftUI layout avoids
/// matched-geometry feedback while the surrounding landscape is also moving.
public enum ModelsConfigurationMorphGeometry {
    private static func clamped(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    public static func frame(
        from source: CGRect,
        to destination: CGRect,
        progress: CGFloat
    ) -> CGRect {
        let amount = clamped(progress)

        return CGRect(
            x: source.origin.x
                + (destination.origin.x - source.origin.x) * amount,
            y: source.origin.y
                + (destination.origin.y - source.origin.y) * amount,
            width: source.width
                + (destination.width - source.width) * amount,
            height: source.height
                + (destination.height - source.height) * amount
        )
    }

    public static func cornerRadius(progress: CGFloat) -> CGFloat {
        let amount = clamped(progress)
        return 12 + (27 - 12) * amount
    }
}

/// Keeps the pill label at a constant proposal size while its center follows
/// the expanding surface. This prevents text layout from being recalculated
/// on every animation frame.
/// How much to scale the stand-in label so it matches the button it replaces.
///
/// Zones are drawn inside `.scaleEffect(placement.scale)` — the active one sits
/// at 1.06, the others at 0.95 — and the action frame is measured *through*
/// that transform. The morph's pill label is a sibling positioned in the same
/// coordinate space, so it is not inside the transform: it was drawing 11pt
/// text into a box sized for 11.66pt text. The two then swapped sizes at the
/// handover, which is the label appearing to morph as the sheet returns.
///
/// The source frame's height over the button's unscaled height recovers the
/// zone's scale exactly, so this needs no knowledge of the placement itself.
public enum ModelsMorphLabelScale {
    public static func scale(
        sourceHeight: CGFloat,
        unscaledHeight: CGFloat
    ) -> CGFloat {
        guard unscaledHeight > 0, sourceHeight > 0 else { return 1 }
        return sourceHeight / unscaledHeight
    }
}

public enum ModelsMorphContentGeometry {
    public static func frame(
        from source: CGRect,
        to destination: CGRect,
        progress: CGFloat
    ) -> CGRect {
        let surface = ModelsConfigurationMorphGeometry.frame(
            from: source,
            to: destination,
            progress: progress
        )

        return CGRect(
            x: surface.midX - source.width / 2,
            y: surface.midY - source.height / 2,
            width: source.width,
            height: source.height
        )
    }
}

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

/// The action and its replacement surface deliberately share one tint source,
/// so mounting the morph cannot introduce a one-frame color discontinuity.
public enum ModelsBackendTintResponse {
    public static func actionTint(
        for backend: ModelsBackendID
    ) -> ModelsRGBTint {
        tint(for: backend)
    }

    public static func surfaceTint(
        for backend: ModelsBackendID
    ) -> ModelsRGBTint {
        tint(for: backend)
    }

    private static func tint(for backend: ModelsBackendID) -> ModelsRGBTint {
        switch backend {
        case .apple:
            ModelsRGBTint(red: 0.57, green: 0.82, blue: 0.63)
        case .mlx:
            ModelsRGBTint(red: 0.71, green: 0.63, blue: 0.86)
        case .ollama:
            ModelsRGBTint(red: 0.92, green: 0.61, blue: 0.75)
        }
    }
}

public struct ModelsConfigurationTimelinePresentation: Equatable, Sendable {
    public let sheetContentOpacity: Double
    public let pillLabelOpacity: Double
    public let peripheralProgress: CGFloat

    public init(
        sheetContentOpacity: Double,
        pillLabelOpacity: Double,
        peripheralProgress: CGFloat
    ) {
        self.sheetContentOpacity = sheetContentOpacity
        self.pillLabelOpacity = pillLabelOpacity
        self.peripheralProgress = peripheralProgress
    }
}

/// Every visual participating in the button-to-sheet morph reads from this
/// one normalized timeline. Reading the same function while progress moves
/// from one back to zero makes closing the literal inverse of opening.
public enum ModelsConfigurationTimeline {
    // The two text layers' windows, disjoint on purpose and with a gap between
    // them. Both set type at the same size in the same place, so any overlap
    // cross-dissolves one glyph run through another and the label appears to
    // mangle itself rather than to hand over.
    //
    // Named, and read by `ModelsMotionResponse.timing`, because the morph used
    // to be described in two unconnected places — these windows, and the
    // durations in `ModelsMotionTiming` — which agreed only by coincidence and
    // silently stopped agreeing the moment either moved.
    public static let pillFadeBegins: CGFloat = 0.04
    public static let pillRetired: CGFloat = 0.34
    public static let contentBegins: CGFloat = 0.40
    public static let contentSettled: CGFloat = 0.86

    /// The morph's one easing shape, shared with the surface's own ramp. That
    /// ramp used to be linear — the only unshaped thing in a morph that is
    /// smoothstepped everywhere else — which put the hardest onset on whichever
    /// value had the furthest to travel.
    public static func shaped(_ progress: CGFloat) -> CGFloat {
        smoothstep(clamped(progress))
    }

    public static func presentation(
        progress: CGFloat
    ) -> ModelsConfigurationTimelinePresentation {
        let amount = clamped(progress)

        return ModelsConfigurationTimelinePresentation(
            sheetContentOpacity: Double(windowedSmoothstep(
                amount,
                from: contentBegins,
                to: contentSettled
            )),
            pillLabelOpacity: Double(1 - windowedSmoothstep(
                amount,
                from: pillFadeBegins,
                to: pillRetired
            )),
            peripheralProgress: smoothstep(amount)
        )
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

    private static func windowedSmoothstep(
        _ value: CGFloat,
        from start: CGFloat,
        to end: CGFloat
    ) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        return smoothstep(clamped((value - start) / (end - start)))
    }
}

public struct ModelsZoneTimelinePresentation: Equatable, Sendable {
    public let titleOpacity: Double
    public let detailOpacity: Double
    public let actionOpacity: Double
    public let topStatusOpacity: Double
    public let besideStatusOpacity: Double
}

/// Opacity changes never add or remove model-zone subviews. The zone keeps one
/// stable layout while this presentation softens or restores its contents.
public enum ModelsZoneTimeline {
    public static func presentation(
        for backend: ModelsBackendID,
        active: ModelsBackendID,
        expanded: ModelsBackendID?,
        progress: CGFloat
    ) -> ModelsZoneTimelinePresentation {
        guard let expanded else {
            return ModelsZoneTimelinePresentation(
                titleOpacity: 1,
                detailOpacity: 1,
                actionOpacity: 1,
                topStatusOpacity: backend == active ? 0 : 1,
                besideStatusOpacity: backend == active ? 1 : 0
            )
        }

        let amount = min(max(progress, 0), 1)
        let selected = backend == expanded
        let isActive = backend == active

        return ModelsZoneTimelinePresentation(
            titleOpacity: selected ? 1 : Double(1 - 0.88 * amount),
            detailOpacity: selected ? 1 : Double(1 - amount),
            actionOpacity: Double(1 - amount),
            topStatusOpacity: isActive
                ? (selected ? Double(amount) : 0)
                : (selected ? 1 : Double(1 - amount)),
            besideStatusOpacity: isActive ? Double(1 - amount) : 0
        )
    }
}

/// The sheet endpoint is a fixed design value rather than a live measurement.
/// That prevents its target from moving while SwiftUI lays out appearing text.
public enum ModelsConfigurationLayout {
    public static func sheetFrame(
        for backend: ModelsBackendID,
        canvasSize: CGSize
    ) -> CGRect {
        let width = max(1, min(470, canvasSize.width - 56))
        let height: CGFloat = switch backend {
        case .apple: 318
        case .mlx: 330
        case .ollama: 360
        }
        let desiredCenterX = canvasSize.width
            * ModelsLandscapeLayout.sheetCenterX(for: backend)
        let centerX = min(
            max(desiredCenterX, width / 2),
            max(width / 2, canvasSize.width - width / 2)
        )
        let centerY = canvasSize.height * 0.66

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}

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

/// Converts selection and pointer state into a continuous ambient treatment.
/// Hover is deliberately stronger than selection so the active Apple model
/// still has somewhere visible to go when the pointer arrives.
public enum ModelsBloomResponse {
    public static func presentation(
        for backend: ModelsBackendID,
        active: ModelsBackendID,
        selected: ModelsBackendID,
        hovered: ModelsBackendID?
    ) -> ModelsBloomPresentation {
        if hovered == backend {
            return ModelsBloomPresentation(
                scale: backend == active ? 1.14 : 1.10,
                opacity: backend == active ? 0.57 : 0.45,
                inwardProgress: 1
            )
        }

        if active == backend {
            return ModelsBloomPresentation(
                scale: 1.045,
                opacity: 0.48,
                inwardProgress: 0.32
            )
        }

        if selected == backend {
            return ModelsBloomPresentation(
                scale: 1.02,
                opacity: 0.42,
                inwardProgress: 0.22
            )
        }

        return ModelsBloomPresentation(
            scale: 0.96,
            opacity: 0.34,
            inwardProgress: 0
        )
    }

    public static func transitionPresentation(
        for backend: ModelsBackendID,
        active: ModelsBackendID,
        selected: ModelsBackendID,
        hovered: ModelsBackendID?,
        progress: CGFloat
    ) -> ModelsBloomPresentation {
        let amount = min(max(progress, 0), 1)
        let start = presentation(
            for: backend,
            active: active,
            selected: active,
            hovered: hovered
        )
        let end = presentation(
            for: backend,
            active: active,
            selected: selected,
            hovered: nil
        )

        return ModelsBloomPresentation(
            scale: start.scale + (end.scale - start.scale) * amount,
            opacity: start.opacity
                + (end.opacity - start.opacity) * Double(amount),
            inwardProgress: start.inwardProgress
                + (end.inwardProgress - start.inwardProgress) * amount
        )
    }
}

public struct ModelsLandscapePlacement: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let opacity: Double
    public let scale: CGFloat

    public init(x: CGFloat, y: CGFloat, opacity: Double, scale: CGFloat) {
        self.x = x
        self.y = y
        self.opacity = opacity
        self.scale = scale
    }
}

public enum ModelsLandscapeLayout {
    public static func transitionPlacement(
        for backend: ModelsBackendID,
        active: ModelsBackendID,
        expanded: ModelsBackendID?,
        progress: CGFloat
    ) -> ModelsLandscapePlacement {
        let start = basePlacement(for: backend, active: active)
        guard let expanded else { return start }

        var targetState = ModelsLandscapeState(
            active: active,
            selected: expanded,
            expanded: expanded
        )
        targetState.expanded = expanded
        let end = placement(for: backend, state: targetState)
        let amount = min(max(progress, 0), 1)

        return ModelsLandscapePlacement(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount,
            opacity: start.opacity
                + (end.opacity - start.opacity) * Double(amount),
            scale: start.scale + (end.scale - start.scale) * amount
        )
    }

    public static func placement(
        for backend: ModelsBackendID,
        state: ModelsLandscapeState
    ) -> ModelsLandscapePlacement {
        let base = basePlacement(for: backend, active: state.active)
        guard let expanded = state.expanded else { return base }

        if backend == expanded {
            let focusedY: CGFloat = switch backend {
            case .apple: base.y - 0.005
            case .mlx: 0.35
            case .ollama: 0.35
            }

            return ModelsLandscapePlacement(
                x: base.x,
                y: focusedY,
                opacity: 1,
                scale: max(base.scale, 1.045)
            )
        }

        switch backend {
        case .apple:
            return ModelsLandscapePlacement(
                x: 0.14,
                y: 0.35,
                opacity: 0.12,
                scale: 0.90
            )
        case .mlx:
            return ModelsLandscapePlacement(
                x: 0.86,
                y: 0.36,
                opacity: 0.12,
                scale: 0.90
            )
        case .ollama:
            return ModelsLandscapePlacement(
                x: 0.50,
                y: 0.82,
                opacity: 0.10,
                scale: 0.90
            )
        }
    }

    public static func sheetCenterX(for backend: ModelsBackendID) -> CGFloat {
        switch backend {
        case .apple: 0.39
        case .mlx: 0.61
        case .ollama: 0.50
        }
    }

    private static func basePlacement(
        for backend: ModelsBackendID,
        active: ModelsBackendID
    ) -> ModelsLandscapePlacement {
        switch backend {
        case .apple:
            ModelsLandscapePlacement(
                x: 0.24,
                y: 0.355,
                opacity: 1,
                scale: active == .apple ? 1.06 : 1
            )
        case .mlx:
            ModelsLandscapePlacement(
                x: 0.76,
                y: 0.365,
                opacity: 1,
                scale: active == .mlx ? 1.035 : 0.95
            )
        case .ollama:
            ModelsLandscapePlacement(
                x: 0.50,
                y: 0.67,
                opacity: 1,
                scale: active == .ollama ? 1.035 : 0.95
            )
        }
    }
}
