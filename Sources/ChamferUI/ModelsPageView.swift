import AppKit
import ChamferCore
import ChamferRewrite
import SwiftUI

/// A rewrite backend and whether it can run right now. The Models landscape
/// and bottom bar both read these descriptors, so activation never disagrees
/// between the page and its navigation chrome.
struct Backend: Identifiable {
    let backendID: ModelsBackendID
    let name: String
    let shortName: String
    let status: String
    let tone: Pill.Tone
    let detail: String
    let actionTitle: String
    let actionSymbol: String

    var id: ModelsBackendID { backendID }

    static func all(
        runState: RunState,
        landscapeState: ModelsLandscapeState,
        appleAvailableOverride: Bool? = nil
    ) -> [Backend] {
        let appleAvailable: Bool
        if let appleAvailableOverride {
            appleAvailable = appleAvailableOverride
        } else if case .rewritingUnavailable = runState {
            appleAvailable = false
        } else {
            appleAvailable = true
        }

        return [
            Backend(
                backendID: .apple,
                name: "Apple Foundation Models",
                shortName: "Foundation Models",
                status: landscapeState.status(
                    for: .apple,
                    appleAvailable: appleAvailable
                ),
                tone: tone(
                    for: .apple,
                    appleAvailable: appleAvailable,
                    state: landscapeState
                ),
                detail: "Private, fast and built into macOS.",
                actionTitle: "Manage settings",
                actionSymbol: "arrow.right"
            ),
            Backend(
                backendID: .mlx,
                name: "Local Model",
                shortName: "Local Model",
                status: landscapeState.status(
                    for: .mlx,
                    appleAvailable: appleAvailable
                ),
                tone: tone(
                    for: .mlx,
                    appleAvailable: appleAvailable,
                    state: landscapeState
                ),
                detail: "Download a private model that runs entirely on your Mac.",
                actionTitle: localActionTitle(
                    for: landscapeState.installation,
                    runtimeAvailable: landscapeState.localRuntimeAvailable
                ),
                actionSymbol: "arrow.down"
            ),
            Backend(
                backendID: .ollama,
                name: "Cloud Model",
                shortName: "Cloud Model",
                status: landscapeState.status(
                    for: .ollama,
                    appleAvailable: appleAvailable
                ),
                tone: tone(
                    for: .ollama,
                    appleAvailable: appleAvailable,
                    state: landscapeState
                ),
                detail: "Connect a supported cloud provider for access to larger models.",
                actionTitle: landscapeState.connection == .connected
                    ? "Manage provider"
                    : "Connect provider",
                actionSymbol: "arrow.up.right"
            )
        ]
    }

    private static func localActionTitle(
        for installation: ModelsInstallationState,
        runtimeAvailable: Bool
    ) -> String {
        guard runtimeAvailable else { return "Install Ollama" }
        return switch installation {
        case .notInstalled: "Download model"
        case .downloading: "Downloading…"
        case .installed: "Manage model"
        }
    }

    private static func tone(
        for backend: ModelsBackendID,
        appleAvailable: Bool,
        state: ModelsLandscapeState
    ) -> Pill.Tone {
        if backend == .apple, !appleAvailable { return .danger }
        return backend == state.active ? .positive : .neutral
    }
}

private enum ModelsLandscapeCoordinateSpace {
    static let name = "models-landscape"
}

struct ModelsExplicitConfigurationMorph: ViewModifier {
    let sourceFrame: CGRect
    let destinationFrame: CGRect
    let progress: CGFloat

    func body(content: Content) -> some View {
        content.visualEffect { effect, _ in
            let frame = ModelsConfigurationMorphGeometry.frame(
                from: sourceFrame,
                to: destinationFrame,
                progress: progress
            )
            let scaleX = destinationFrame.width > 0
                ? frame.width / destinationFrame.width
                : 1
            let scaleY = destinationFrame.height > 0
                ? frame.height / destinationFrame.height
                : 1

            return effect
                .scaleEffect(
                    x: scaleX,
                    y: scaleY,
                    anchor: .center
                )
                .offset(
                    x: frame.midX - destinationFrame.midX,
                    y: frame.midY - destinationFrame.midY
                )
        }
    }
}

/// A calm, open landscape of the three local-model choices. DashboardView
/// keeps the existing page, bottom bar and floating close control around it;
/// this view owns only the expressive content layer inside that page.
struct ModelsPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let runState: RunState
    @Binding var state: ModelsLandscapeState

    @State private var hoveredBackend: ModelsBackendID?
    @State private var cloudProvider = ModelsPreferences.loadCloudProvider()
    @State private var cloudCredential = ""
    @State private var runtime = ModelsRuntimeModel()
    @State private var configurationMorph = ModelsConfigurationMorphState()
    @State private var configurationMorphProgress: CGFloat = 0
    @State private var configurationMorphSourceFrame = CGRect.zero
    /// Captured before `hoveredBackend` is cleared, because the surface has to
    /// open from the button's hovered appearance rather than its resting one.
    @State private var configurationMorphStartedHovered = false
    @State private var actionFrames: [ModelsBackendID: CGRect] = [:]

    private var appleAvailable: Bool {
        if runtime.didRefreshApple { return runtime.appleAvailable }
        if case .rewritingUnavailable = runState { return false }
        return true
    }

    private var backends: [Backend] {
        Backend.all(
            runState: runState,
            landscapeState: state,
            appleAvailableOverride: appleAvailable
        )
    }

    private var motionTiming: ModelsMotionTiming {
        ModelsMotionResponse.timing(reduceMotion: reduceMotion)
    }

    /// The morph is the largest single transition in the app, which makes it
    /// the one that most needs to be interruptible: clicking away while a card
    /// is still expanding should redirect the motion rather than restart it
    /// from a standstill. A spring does that; the fixed-duration ease this
    /// replaces could not. Critically damped on purpose — every geometry helper
    /// downstream reads `progress` directly, so overshoot would be visible.
    private var configurationOpenAnimation: Animation {
        Chamfer.Motion.reduce(
            .spring(duration: motionTiming.morphOpenDuration, bounce: 0),
            when: reduceMotion
        )
    }

    /// Closing is quicker than opening. Opening is showing you something and
    /// can afford to be seen doing it; closing is getting out of the way, and
    /// anything longer than the gesture that asked for it feels like a wait.
    /// `morphCloseDuration` has always existed for this and was never read.
    private var configurationCloseAnimation: Animation {
        Chamfer.Motion.reduce(
            .spring(duration: motionTiming.morphCloseDuration, bounce: 0),
            when: reduceMotion
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let expanded = configurationMorph.mountedBackend
            let morphBackendID = expanded ?? state.selected
            let morphSourceFrame = expanded == nil
                ? actionFrames[morphBackendID]
                    ?? fallbackActionFrame(
                        for: morphBackendID,
                        canvasSize: size
                    )
                : configurationMorphSourceFrame
            let destinationFrame = ModelsConfigurationLayout.sheetFrame(
                for: morphBackendID,
                canvasSize: size
            )
            let timeline = ModelsConfigurationTimeline.presentation(
                progress: configurationMorphProgress
            )
            let surfaceFrame = ModelsConfigurationMorphGeometry.frame(
                from: morphSourceFrame,
                to: destinationFrame,
                progress: configurationMorphProgress
            )
            let morphContentFrame = ModelsMorphContentGeometry.frame(
                from: morphSourceFrame,
                to: destinationFrame,
                progress: configurationMorphProgress
            )
            let morphBackend = backends.first {
                $0.backendID == morphBackendID
            } ?? backends[0]

            ZStack(alignment: .topLeading) {
                Chamfer.Palette.canvas

                ModelsAmbientField(
                    active: state.active,
                    selected: morphBackendID,
                    hovered: hoveredBackend,
                    transitionProgress: timeline.peripheralProgress,
                    size: size
                )

                ModelsPageHeader()
                    .padding(.top, 38)
                    .padding(.leading, 42)
                    .zIndex(4)

                ForEach(backends) { backend in
                    let placement = ModelsLandscapeLayout.transitionPlacement(
                        for: backend.backendID,
                        active: state.active,
                        expanded: expanded,
                        progress: timeline.peripheralProgress
                    )
                    let zoneTimeline = ModelsZoneTimeline.presentation(
                        for: backend.backendID,
                        active: state.active,
                        expanded: expanded,
                        progress: timeline.peripheralProgress
                    )

                    ModelsZone(
                        backend: backend,
                        isActive: state.active == backend.backendID,
                        isSelected: state.selected == backend.backendID,
                        presentation: zoneTimeline,
                        transitionProgress: timeline.peripheralProgress,
                        morphIsMounted: expanded != nil,
                        isMorphSource: expanded == backend.backendID,
                        action: { select(backend.backendID, canvasSize: size) },
                        onActionFrameChange: { frame in
                            guard frame.width > 0, frame.height > 0 else { return }
                            actionFrames[backend.backendID] = frame
                        },
                        onHoverChange: { hovering in
                            setHover(backend.backendID, hovering: hovering)
                        }
                    )
                    .position(
                        x: size.width * placement.x,
                        y: size.height * placement.y
                    )
                    .scaleEffect(placement.scale)
                    .opacity(placement.opacity)
                    .zIndex(morphBackendID == backend.backendID ? 3 : 2)
                }

                ModelsConfigurationSurface(
                    backend: morphBackendID,
                    progress: configurationMorphProgress,
                    cornerRadius: ModelsConfigurationMorphGeometry
                        .cornerRadius(progress: configurationMorphProgress),
                    startedHovered: configurationMorphStartedHovered
                )
                .frame(
                    width: max(surfaceFrame.width, 1),
                    height: max(surfaceFrame.height, 1)
                )
                .position(x: surfaceFrame.midX, y: surfaceFrame.midY)
                .opacity(expanded == nil ? 0 : 1)
                .allowsHitTesting(false)
                .zIndex(8)

                ModelsConfigurationSheet(
                    state: $state,
                    backend: morphBackendID,
                    morphSourceFrame: morphSourceFrame,
                    morphDestinationFrame: destinationFrame,
                    morphProgress: configurationMorphProgress,
                    contentProgress: CGFloat(timeline.sheetContentOpacity),
                    contentInteractive: configurationMorph.phase == .sheet,
                    appleAvailable: appleAvailable,
                    localRuntimeAvailable: runtime.ollamaAvailable,
                    physicalMemory: ProcessInfo.processInfo.physicalMemory,
                    cloudProvider: $cloudProvider,
                    cloudCredential: $cloudCredential,
                    errorMessage: runtime.errorMessage,
                    isWorking: runtime.isWorking,
                    onSelectLocalModel: selectLocalModel,
                    onClose: closeConfiguration,
                    onActivate: activateSelected,
                    onConnectProvider: connectProvider,
                    onDownload: downloadSelectedModel,
                    onInstallLocalRuntime: installLocalRuntime
                )
                .frame(
                    width: destinationFrame.width,
                    height: destinationFrame.height,
                    alignment: .topLeading
                )
                .position(x: destinationFrame.midX, y: destinationFrame.midY)
                .opacity(expanded == nil ? 0 : 1)
                .zIndex(9)

                ModelsMorphPillLabel(backend: morphBackend)
                    // The zone this stands in for is scaled; this label is not
                    // inside that transform, so it has to carry the same scale
                    // or its text changes size at the handover.
                    .scaleEffect(
                        ModelsMorphLabelScale.scale(
                            sourceHeight: morphSourceFrame.height,
                            unscaledHeight: ModelsZoneActionResponse
                                .presentation(for: morphBackendID, isHovered: true)
                                .minimumHeight
                        )
                    )
                    .frame(
                        width: max(morphContentFrame.width, 1),
                        height: max(morphContentFrame.height, 1)
                    )
                    .position(
                        x: morphContentFrame.midX,
                        y: morphContentFrame.midY
                    )
                    .opacity(
                        expanded == nil
                            ? 0
                            : timeline.pillLabelOpacity
                    )
                    .allowsHitTesting(false)
                    .zIndex(10)

                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Chamfer.Palette.pageTextSoft.opacity(0.34))
                        .frame(width: 22, height: 1)
                    Text("Everything stays local.")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
                }
                .position(x: size.width - 112, y: size.height - 28)
                .zIndex(1)
            }
            .clipped()
            .coordinateSpace(name: ModelsLandscapeCoordinateSpace.name)
        }
        .background(Chamfer.Palette.canvas)
        .onExitCommand(perform: closeConfiguration)
        .task {
            await refreshModelRuntime()
        }
        .onChange(of: cloudProvider) { _, provider in
            ModelsPreferences.saveCloudProvider(provider)
            runtime.refreshCredentialStatus(provider: provider)
            state.synchronizeConnection(connected: runtime.cloudConnected)
        }
    }

    private func select(_ backend: ModelsBackendID, canvasSize: CGSize) {
        guard configurationMorph.mountedBackend == nil else { return }
        Haptics.pop()

        let wasHovered = hoveredBackend == backend

        var setup = Transaction()
        setup.disablesAnimations = true
        withTransaction(setup) {
            configurationMorphSourceFrame = actionFrames[backend]
                ?? fallbackActionFrame(for: backend, canvasSize: canvasSize)
            configurationMorphProgress = 0
            configurationMorphStartedHovered = wasHovered
            configurationMorph.beginOpening(backend)
            state.select(backend)
            hoveredBackend = nil
        }

        withAnimation(
            configurationOpenAnimation,
            completionCriteria: .logicallyComplete
        ) {
            configurationMorph.beginExpanding()
            configurationMorphProgress = 1
        } completion: {
            guard configurationMorph.mountedBackend == backend,
                  configurationMorph.phase == .expanding else { return }
            configurationMorph.finishOpening()
        }
    }

    private func fallbackActionFrame(
        for backend: ModelsBackendID,
        canvasSize: CGSize
    ) -> CGRect {
        var restingState = state
        restingState.expanded = nil
        let placement = ModelsLandscapeLayout.placement(
            for: backend,
            state: restingState
        )
        let width: CGFloat = 124
        let height: CGFloat = 38

        return CGRect(
            x: canvasSize.width * placement.x - width / 2,
            y: canvasSize.height * placement.y - height / 2,
            width: width,
            height: height
        )
    }

    private func setHover(_ backend: ModelsBackendID, hovering: Bool) {
        // Deliberately slow: this drives the ambient background wash, not a
        // control's answer to the pointer, so it is allowed to drift.
        let hoverAnimation = Chamfer.Motion.reduce(
            .easeInOut(duration: 0.46),
            when: reduceMotion
        )

        withAnimation(hoverAnimation) {
            if hovering {
                hoveredBackend = backend
            } else if hoveredBackend == backend {
                hoveredBackend = nil
            }
        }
    }

    /// Dismissal is punctuated like every other one in the app. Fired here
    /// rather than inside `collapseConfiguration` so that activating a model —
    /// which commits with its own pulse — cannot land two in a row.
    private func closeConfiguration() {
        guard configurationMorph.mountedBackend != nil else { return }
        Haptics.commit()
        collapseConfiguration(activatingSelection: false)
    }

    private func activateSelected() {
        Haptics.commit()
        collapseConfiguration(activatingSelection: true)
    }

    private func collapseConfiguration(activatingSelection: Bool) {
        guard let collapsingBackend = configurationMorph.mountedBackend,
              configurationMorph.phase != .collapsing else { return }

        var setup = Transaction()
        setup.disablesAnimations = true
        withTransaction(setup) {
            configurationMorph.beginClosing()
        }

        withAnimation(
            configurationCloseAnimation,
            completionCriteria: .logicallyComplete
        ) {
            configurationMorphProgress = 0
        } completion: {
            guard configurationMorph.phase == .collapsing,
                  configurationMorph.mountedBackend == collapsingBackend else {
                return
            }

            var teardown = Transaction()
            teardown.disablesAnimations = true
            withTransaction(teardown) {
                if activatingSelection {
                    state.activateSelected()
                    ModelsPreferences.save(state: state)
                } else {
                    state.closeConfiguration()
                }
                configurationMorph.finishClosing()
                configurationMorphProgress = 0
            }
        }
    }

    private func connectProvider() {
        withAnimation(Chamfer.Motion.quick) {
            state.beginConnectionTest()
        }
        Task {
            let connected = await runtime.connect(
                provider: cloudProvider,
                enteredCredential: cloudCredential
            )
            withAnimation(Chamfer.Motion.quick) {
                state.finishConnectionTest(connected: connected)
            }
            if connected {
                cloudCredential = ""
            }
        }
    }

    private func downloadSelectedModel() {
        guard runtime.ollamaAvailable else {
            installLocalRuntime()
            return
        }
        guard selectedLocalAssessment.fit != .unusable else { return }
        if state.installation == .installed {
            activateSelected()
            return
        }

        withAnimation(Chamfer.Motion.quick) {
            state.beginDownload()
        }
        Task {
            if let installed = await runtime.download(
                modelID: state.selectedLocalModelID
            ) {
                withAnimation(Chamfer.Motion.navigation) {
                    state.synchronizeInstalledLocalModels(installed)
                }
            } else {
                withAnimation(Chamfer.Motion.quick) {
                    state.synchronizeInstalledLocalModels(
                        state.installedLocalModelIDs
                    )
                }
            }
        }
    }

    private var selectedLocalAssessment: LocalModelAssessment {
        guard let model = LocalModelCatalog.standard.first(where: {
            $0.id == state.selectedLocalModelID
        }) else {
            return LocalModelAssessment(
                fit: .unusable,
                explanation: "Unknown model"
            )
        }
        return LocalModelCatalog.assessment(
            for: model,
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
    }

    private func selectLocalModel(_ modelID: String) {
        withAnimation(Chamfer.Motion.quick) {
            state.selectLocalModel(modelID)
        }
        ModelsPreferences.save(state: state)
    }

    private func installLocalRuntime() {
        guard let url = URL(string: "https://ollama.com/download") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Deliberately unanimated.
    ///
    /// This lands a few milliseconds after the page mounts — the local probe
    /// fails fast when Ollama is not running — which is squarely inside the
    /// bottom bar's selection spring. The bar's destinations are derived from
    /// this same state, so wrapping the write in a shorter curve retargeted
    /// that spring mid-flight and the black selector stuttered. Data arriving
    /// in the background is not an event the interface should animate.
    private func refreshModelRuntime() async {
        let snapshot = await runtime.refresh(provider: cloudProvider)

        var arrival = Transaction()
        arrival.disablesAnimations = true
        withTransaction(arrival) {
            state.localRuntimeAvailable = snapshot.ollamaAvailable
            state.synchronizeInstalledLocalModels(snapshot.installedLocalModelIDs)
            state.synchronizeConnection(connected: snapshot.cloudConnected)
        }
    }
}

private struct ModelsPageHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                ModelsEyebrowMark()
                Text("CHAMFER  /  INTELLIGENCE")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.78))
            }
            .padding(.bottom, 8)

            Text("Models")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .tracking(-1.3)
                .foregroundStyle(Chamfer.Palette.pageText)

            Text("Choose how Chamfer understands and cleans your notes.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
        }
    }
}

private struct ModelsEyebrowMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Chamfer.Palette.pageText.opacity(0.55), lineWidth: 0.8)
                .frame(width: 10, height: 10)
                .offset(x: -3.5)
            Circle()
                .stroke(Chamfer.Palette.pageText.opacity(0.55), lineWidth: 0.8)
                .frame(width: 10, height: 10)
                .offset(x: 3.5)
        }
        .frame(width: 17, height: 11)
        .accessibilityHidden(true)
    }
}

private struct ModelsZone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private static func glowCurve(reduceMotion: Bool) -> Animation {
        Chamfer.Motion.reduce(.easeInOut(duration: 0.42), when: reduceMotion)
    }

    let backend: Backend
    let isActive: Bool
    let isSelected: Bool
    let presentation: ModelsZoneTimelinePresentation
    let transitionProgress: CGFloat
    let morphIsMounted: Bool
    let isMorphSource: Bool
    let action: () -> Void
    let onActionFrameChange: (CGRect) -> Void
    let onHoverChange: (Bool) -> Void

    private var horizontalAlignment: HorizontalAlignment {
        switch backend.backendID {
        case .apple: .leading
        case .mlx: .trailing
        case .ollama: .center
        }
    }

    private var frameAlignment: Alignment {
        switch backend.backendID {
        case .apple: .topLeading
        case .mlx: .topTrailing
        case .ollama: .top
        }
    }

    private var title: String {
        backend.backendID == .apple
            ? "Apple Foundation\nModels"
            : backend.name
    }

    private var width: CGFloat {
        switch backend.backendID {
        case .apple: 245
        case .mlx: 250
        case .ollama: 310
        }
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 0) {
            statusLabel
                .opacity(presentation.topStatusOpacity)
                .frame(height: 24, alignment: .bottom)
                .padding(.bottom, 8)

            modelTitle(bottomPadding: 8)
                .opacity(presentation.titleOpacity)

            modelDetail(bottomPadding: 12)
                .opacity(presentation.detailOpacity)

            HStack(spacing: 9) {
                if isActive {
                    statusLabel
                        .opacity(presentation.besideStatusOpacity)
                }

                ModelsZoneActionButton(
                    backend: backend,
                    retainsHover: isMorphSource && morphIsMounted,
                    action: action,
                    onFrameChange: onActionFrameChange
                )
                .opacity(
                    isMorphSource && morphIsMounted
                        ? 0
                        : presentation.actionOpacity
                )
                .allowsHitTesting(!morphIsMounted)
            }
        }
        .frame(width: width, height: 190, alignment: frameAlignment)
        .contentShape(Rectangle())
        .background {
            Ellipse()
                .fill(localGlow)
                .frame(width: width + 96, height: 150)
                .scaleEffect(glowPresentation.scale)
                .blur(radius: 34)
                .opacity(glowPresentation.opacity)
        }
        // The glow behind a zone scales and blurs, so it is motion and has to
        // answer the setting — the ambient field it sits inside already does.
        .onHover { hovering in
            withAnimation(Self.glowCurve(reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
            onHoverChange(hovering)
        }
        .animation(Self.glowCurve(reduceMotion: reduceMotion), value: isHovered)
    }

    private func modelTitle(bottomPadding: CGFloat) -> some View {
        let titlePresentation = ModelsTitleResponse.presentation(
            isActive: isActive
        )
        return Text(title)
            .font(
                .system(
                    size: titlePresentation.size,
                    weight: titlePresentation.isBold ? .semibold : .regular,
                    design: .serif
                )
            )
            .tracking(-0.82)
            .multilineTextAlignment(textAlignment)
            .foregroundStyle(
                isActive
                    ? Chamfer.Palette.pageText
                    : Chamfer.Palette.pageText.opacity(0.86)
            )
            .lineSpacing(-3)
            .padding(.bottom, bottomPadding)
    }

    private func modelDetail(bottomPadding: CGFloat) -> some View {
        Text(backend.detail)
            .font(.system(size: 13, design: .serif))
            .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.88))
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, bottomPadding)
    }

    private var statusLabel: some View {
        Text(backend.status)
            .font(.system(size: 9, weight: .bold))
            .kerning(1.05)
            .foregroundStyle(statusForeground)
            .padding(.horizontal, isActive ? 8 : 0)
            .padding(.vertical, isActive ? 5 : 0)
            .background {
                if isActive {
                    Capsule()
                        .fill(
                            backend.status == "UNAVAILABLE"
                                ? Chamfer.Palette.dangerSoft.opacity(0.78)
                                : Chamfer.Palette.positiveSoft.opacity(0.72)
                        )
                }
            }
    }

    private var statusForeground: Color {
        if backend.status == "UNAVAILABLE" { return Chamfer.Palette.danger }
        if isActive { return Chamfer.Palette.positive.opacity(0.86) }
        return Chamfer.Palette.pageTextSoft.opacity(0.72)
    }

    private var textAlignment: TextAlignment {
        switch backend.backendID {
        case .apple: .leading
        case .mlx: .trailing
        case .ollama: .center
        }
    }

    private var localGlow: Color {
        switch backend.backendID {
        case .apple: Color(red: 0.78, green: 0.89, blue: 0.72)
        case .mlx: Color(red: 0.76, green: 0.67, blue: 0.88)
        case .ollama: Color(red: 0.94, green: 0.61, blue: 0.64)
        }
    }

    private var glowPresentation: ModelsZoneGlowPresentation {
        ModelsZoneGlowResponse.presentation(
            isHovered: isHovered,
            isActive: isActive,
            isMorphSource: isMorphSource,
            transitionProgress: transitionProgress
        )
    }
}

private struct ModelsMorphPillLabel: View {
    let backend: Backend

    var body: some View {
        HStack(spacing: 5) {
            Text(backend.actionTitle)
            Image(systemName: backend.actionSymbol)
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 11, weight: .semibold))
        // 0.96, matching the *hovered* button this stands in for. At 0.90 the
        // label dimmed the frame it took over, and brightened again the frame
        // it handed back — read as the text glitching on the way out and in.
        .foregroundStyle(Chamfer.Palette.pageText.opacity(0.96))
        .lineLimit(1)
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ModelsZoneActionButton: View {
    @State private var isHovered = false

    let backend: Backend
    /// True while the morph has taken this button's place.
    ///
    /// Hiding the button also disables its hit testing, which makes SwiftUI
    /// report the pointer as having left — so the button quietly animated
    /// itself back to resting while it was invisible. The surface then handed
    /// back to a button that no longer looked like what it had handed over
    /// from, and the pointer's return animated it forwards again: a pop and a
    /// settle, right as the sheet finished closing.
    let retainsHover: Bool
    let action: () -> Void
    let onFrameChange: (CGRect) -> Void

    private var showsHover: Bool { retainsHover || isHovered }

    private var presentation: ModelsZoneActionPresentation {
        ModelsZoneActionResponse.presentation(
            for: backend.backendID,
            isHovered: showsHover
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(backend.actionTitle)
                    // The label needs 91pt and `minWidth: 116` leaves it 88
                    // after padding, so it silently wrapped onto two lines —
                    // while the stand-in label the morph swaps in is
                    // `lineLimit(1)`. The handover flipped between a one-line
                    // and a two-line layout, which is the text appearing to
                    // change size as the sheet opens and returns. Sizing to the
                    // content lets the pill be as wide as its own words.
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: backend.actionSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .offset(iconOffset)
            }
        }
        .buttonStyle(
            ModelsZonePillActionStyle(
                tint: tint,
                isHovered: showsHover,
                presentation: presentation
            )
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(ModelsLandscapeCoordinateSpace.name))
        } action: { frame in
            onFrameChange(frame)
        }
        .onHover { hovering in
            // Ignored while the morph owns the button: the "exit" that arrives
            // here is hit testing being switched off, not the pointer leaving.
            guard !retainsHover else { return }
            withAnimation(Chamfer.Motion.interactive) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("\(backend.actionTitle), \(backend.name)")
        .accessibilityHint("Opens \(backend.name.lowercased()) settings")
    }

    private var iconOffset: CGSize {
        guard showsHover else { return .zero }
        // One distance, travelled in the direction the arrow points. Apple's
        // used to be 1.5 where the others were 2, so the same gesture read as a
        // slightly smaller nudge on one pill than on its neighbours.
        return switch backend.backendID {
        case .apple: CGSize(width: 2, height: 0)
        case .mlx: CGSize(width: 0, height: 2)
        case .ollama: CGSize(width: 2, height: 0)
        }
    }

    private var tint: Color {
        let tint = ModelsBackendTintResponse.actionTint(
            for: backend.backendID
        )
        return Color(red: tint.red, green: tint.green, blue: tint.blue)
    }
}

private struct ModelsZonePillActionStyle: ButtonStyle {
    let tint: Color
    let isHovered: Bool
    let presentation: ModelsZoneActionPresentation

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                Chamfer.Palette.pageText.opacity(isHovered ? 0.96 : 0.88)
            )
            .padding(.horizontal, 14)
            // No minimum width. While there was one, a short label was padded
            // out to reach it and a long one was not, so the gap between the
            // words and the pill's edge differed from pill to pill — and the
            // longest label had no room at all and wrapped. Sizing to content
            // gives every pill the same 14pt on both sides; they differ in
            // width instead, which is the honest difference between them.
            .frame(
                minHeight: presentation.minimumHeight,
                alignment: .center
            )
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(
                    cornerRadius: presentation.cornerRadius,
                    style: .continuous
                )
                .fill(Chamfer.Palette.paper.opacity(presentation.paperOpacity))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: presentation.cornerRadius,
                        style: .continuous
                    )
                    .fill(tint.opacity(presentation.fillOpacity))
                }
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: presentation.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    tint.opacity(presentation.borderOpacity),
                    lineWidth: 1
                )
            }
            .shadow(
                color: tint.opacity(presentation.shadowOpacity),
                radius: isHovered ? 8 : 4,
                y: isHovered ? 4 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(Chamfer.Motion.interactive, value: isHovered)
            .animation(Chamfer.Motion.quick, value: configuration.isPressed)
    }
}

private struct ModelsAmbientField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let active: ModelsBackendID
    let selected: ModelsBackendID
    let hovered: ModelsBackendID?
    let transitionProgress: CGFloat
    let size: CGSize

    var body: some View {
        ZStack {
            ModelsBloom(
                color: Color(red: 0.74, green: 0.86, blue: 0.78),
                center: CGPoint(x: 0.05, y: 0.37),
                size: CGSize(width: 0.66, height: 0.54),
                inwardOffset: CGSize(width: 0.08, height: 0.03),
                intensity: 1.15,
                backend: .apple,
                active: active,
                selected: selected,
                hovered: hovered,
                transitionProgress: transitionProgress,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.96, green: 0.86, blue: 0.51),
                center: CGPoint(x: 0.35, y: 0.10),
                size: CGSize(width: 0.54, height: 0.46),
                inwardOffset: CGSize(width: 0.04, height: 0.05),
                intensity: 1.22,
                backend: .apple,
                active: active,
                selected: selected,
                hovered: hovered,
                transitionProgress: transitionProgress,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.72, green: 0.66, blue: 0.87),
                center: CGPoint(x: 0.95, y: 0.38),
                size: CGSize(width: 0.64, height: 0.54),
                inwardOffset: CGSize(width: -0.08, height: 0.03),
                intensity: 1.15,
                backend: .mlx,
                active: active,
                selected: selected,
                hovered: hovered,
                transitionProgress: transitionProgress,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.93, green: 0.66, blue: 0.43),
                center: CGPoint(x: 0.70, y: 0.09),
                size: CGSize(width: 0.52, height: 0.46),
                inwardOffset: CGSize(width: -0.04, height: 0.05),
                intensity: 1.18,
                backend: .mlx,
                active: active,
                selected: selected,
                hovered: hovered,
                transitionProgress: transitionProgress,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.94, green: 0.60, blue: 0.51),
                center: CGPoint(x: 0.34, y: 0.94),
                size: CGSize(width: 0.68, height: 0.54),
                inwardOffset: CGSize(width: 0.03, height: -0.08),
                intensity: 1.15,
                backend: .ollama,
                active: active,
                selected: selected,
                hovered: hovered,
                transitionProgress: transitionProgress,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.94, green: 0.67, blue: 0.78),
                center: CGPoint(x: 0.72, y: 0.91),
                size: CGSize(width: 0.62, height: 0.55),
                inwardOffset: CGSize(width: -0.03, height: -0.08),
                intensity: 1.20,
                backend: .ollama,
                active: active,
                selected: selected,
                hovered: hovered,
                transitionProgress: transitionProgress,
                canvas: size
            )
        }
        .compositingGroup()
        .blendMode(.multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            Chamfer.Motion.reduce(
                .easeInOut(duration: 0.46),
                when: reduceMotion
            ),
            value: hovered
        )
    }
}

private struct ModelsBloom: View {
    let color: Color
    let center: CGPoint
    let size: CGSize
    let inwardOffset: CGSize
    let intensity: Double
    let backend: ModelsBackendID
    let active: ModelsBackendID
    let selected: ModelsBackendID
    let hovered: ModelsBackendID?
    let transitionProgress: CGFloat
    let canvas: CGSize

    private var presentation: ModelsBloomPresentation {
        ModelsBloomResponse.transitionPresentation(
            for: backend,
            active: active,
            selected: selected,
            hovered: hovered,
            progress: transitionProgress
        )
    }

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0.62), location: 0.38),
                        .init(color: color.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 230
                )
            )
            .frame(
                width: canvas.width * size.width,
                height: canvas.height * size.height
            )
            .position(
                x: canvas.width
                    * (center.x + inwardOffset.width * presentation.inwardProgress),
                y: canvas.height
                    * (center.y + inwardOffset.height * presentation.inwardProgress)
            )
            .scaleEffect(presentation.scale)
            .opacity(min(0.82, presentation.opacity * intensity))
            .blur(radius: 52)
    }
}
