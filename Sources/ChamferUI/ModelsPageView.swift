import ChamferCore
import ChamferRewrite
import SwiftUI

/// A rewrite path and what it is doing right now. The Models page and the
/// bottom bar both read these, so what the bar says can never disagree with
/// what the page shows.
struct Backend: Identifiable {
    let backendID: ModelsBackendID
    let name: String
    let shortName: String
    let status: String

    var id: ModelsBackendID { backendID }

    static func all(state: ModelsDashboardState) -> [Backend] {
        [
            Backend(
                backendID: .local,
                name: state.recommendedModel.displayName + " "
                    + state.recommendedModel.parameterLabel,
                shortName: "Local Model",
                status: state.status(for: .local)
            ),
            Backend(
                backendID: .cloud,
                name: "Cloud Model",
                shortName: "Cloud Model",
                status: state.status(for: .cloud)
            )
        ]
    }
}

private enum ModelsCoordinateSpace {
    static let name = "models-page"
}

/// The Models dashboard.
///
/// One hierarchy, stated three times over: the model this Mac runs is the
/// largest surface on the page, its configuration sits beside it as part of the
/// same object rather than under a disclosure, and cloud is a hairline strip
/// underneath that is available without competing.
struct ModelsPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chamferModelsRuntimeProbe) private var runtimeProbeEnabled

    @Binding var state: ModelsDashboardState

    @LegacyState private var hoveredBackend: ModelsBackendID?
    @LegacyState private var cloudProvider = ModelsPreferences.loadCloudProvider()
    @LegacyState private var cloudCredential = ""
    @LegacyState private var runtime = ModelsRuntimeModel()
    @LegacyState private var cloudRowFrame = CGRect.zero
    /// Observed, not owned: provisioning starts at launch and outlives this
    /// page, which is created and destroyed as you navigate.
    private let provisioning = OllamaProvisioning.shared
    /// How far the cloud panel is out. Driven explicitly rather than by a
    /// `transition`, because a transition only resolves when the insertion
    /// happens inside an animated update — and a page that opens *already*
    /// showing the panel, as the design harness and state restoration both can,
    /// leaves it stuck at its inserted opacity of zero. Everything here reads
    /// one number instead.
    @LegacyState private var panelProgress: CGFloat = 0
    @FocusState private var cloudTriggerFocused: Bool

    private var timing: ModelsMotionTiming {
        ModelsMotionResponse.timing(reduceMotion: reduceMotion)
    }

    /// Arriving. A larger surface than a popover, so nearer the sheet end of
    /// the scale — but still critically damped: everything downstream reads
    /// these values directly and overshoot would be visible as a wobble.
    private var openAnimation: Animation {
        Chamfer.Motion.reduce(
            .spring(duration: timing.panelOpen, bounce: 0),
            when: reduceMotion
        )
    }

    /// Leaving. Deliberately shorter: showing you something can afford to be
    /// seen doing it, getting out of the way cannot.
    private var closeAnimation: Animation {
        Chamfer.Motion.reduce(
            .spring(duration: timing.panelClose, bounce: 0),
            when: reduceMotion
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let metrics = ModelsPageMetrics.metrics(for: size)
            let recession = ModelsPanelPresentation.recession(progress: panelProgress)

            ZStack(alignment: .topLeading) {
                Chamfer.Palette.canvas

                ModelsAmbientField(
                    active: state.active,
                    hovered: hoveredBackend,
                    recessed: recession.isRecessed,
                    size: size
                )

                pageContent(metrics: metrics, recession: recession)

            }
            // An overlay rather than a `zIndex`-ed sibling. The page below is a
            // scroll view, which composites its own layer, and a sibling sharing
            // that ZStack could end up beneath it however its z order was
            // declared. An overlay is above its content by construction.
            .overlay {
                if panelProgress > 0.001 {
                    ModelsCloudPanel(
                        state: $state,
                        provider: $cloudProvider,
                        credential: $cloudCredential,
                        errorMessage: runtime.errorMessage,
                        isWorking: runtime.isWorking,
                        onClose: closeCloudConfiguration,
                        onConnect: connectProvider,
                        onActivate: activateCloud
                    )
                    // Clamped low as well as high: a `GeometryReader`'s first
                    // pass proposes zero, and an unclamped `size.width - 56` is
                    // a negative frame at that moment.
                    .frame(width: max(300, min(470, size.width - 56)))
                    // Grows out of the row that opened it and shrinks back into
                    // it: the same path in both directions, so the panel always
                    // says where it came from.
                    .scaleEffect(
                        ModelsPanelPresentation.scale(progress: panelProgress),
                        anchor: panelAnchor(canvas: size)
                    )
                    .opacity(
                        Double(ModelsPanelPresentation.opacity(progress: panelProgress))
                    )
                    .position(
                        x: max(size.width / 2, 1),
                        y: max(size.height * 0.46, 190)
                    )
                    .allowsHitTesting(panelProgress > 0.5)
                }
            }
            .clipped()
            .coordinateSpace(name: ModelsCoordinateSpace.name)
        }
        .background(Chamfer.Palette.canvas)
        .onExitCommand(perform: closeCloudConfiguration)
        .task {
            // State can arrive with the panel already open — restored, or
            // seeded by the harness. Match it without animating something the
            // user did not do.
            if state.cloudConfigurationOpen { panelProgress = 1 }
            if case let .working(progress) = provisioning.state {
                state.runtimeInstall = ModelsDownloadState(
                    fraction: progress.fraction,
                    stage: progress.summary
                )
            }
            await refreshRuntime()
        }
        // Chamfer installs the runtime for you, so the card has to follow it.
        // When it lands, the local path is asked what it can see rather than
        // being told — presence is always a report about the disk.
        .onChange(of: provisioning.state) { _, provisioningState in
            withAnimation(Chamfer.Motion.quick) {
                switch provisioningState {
                case .idle:
                    state.runtimeInstall = nil
                case let .working(progress):
                    state.runtimeInstall = ModelsDownloadState(
                        fraction: progress.fraction,
                        stage: progress.summary
                    )
                case .ready, .failed:
                    state.runtimeInstall = nil
                }
            }
            if case .ready = provisioningState {
                Task { await refreshRuntime() }
            }
        }
        .onChange(of: cloudProvider) { _, provider in
            ModelsPreferences.saveCloudProvider(provider)
            runtime.refreshCredentialStatus(provider: provider)
            state.synchronizeConnection(connected: runtime.cloudConnected)
        }
    }

    /// The composition, laid out once and then either placed or scrolled.
    ///
    /// The two columns take no explicit height: an `HStack` is as tall as its
    /// tallest child, and both cards already stretch to fill it, so they match
    /// each other by construction. Pinning them to a number is what let the
    /// configuration column overflow its own frame.
    @ViewBuilder
    private func pageContent(
        metrics: ModelsPageMetrics,
        recession: ModelsPanelRecession
    ) -> some View {
        let body = VStack(alignment: .leading, spacing: 0) {
            ModelsPageHeader(compact: metrics.isCompact)
                .padding(.bottom, metrics.headerBottomPadding)

            HStack(alignment: .top, spacing: metrics.columnGap) {
                ModelsPrimaryCard(
                    state: state,
                    isHovered: hoveredBackend == .local,
                    isRecessed: recession.isRecessed,
                    // A runtime Chamfer could not install is the local path's
                    // failure as much as a model that would not download, and
                    // the card has one line to say either in. The runtime comes
                    // first: a provisioning failure means the pull never ran, so
                    // anything the model installer has to say about it is older
                    // news.
                    errorMessage: provisioning.state.failure ?? runtime.errorMessage,
                    compact: metrics.isCompact,
                    onPrimaryAction: performLocalAction,
                    onHoverChange: { hovering in
                        setHover(.local, hovering: hovering)
                    }
                )
                .frame(width: metrics.primaryWidth)

                ModelsConfigurationColumn(
                    effort: state.effort,
                    isRecessed: recession.isRecessed,
                    compact: metrics.isCompact,
                    onSelect: select
                )
                .frame(width: metrics.configurationWidth)
            }
            .frame(minHeight: metrics.minimumRowHeight)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, metrics.rowGap)

            ModelsCloudRow(
                state: state,
                provider: cloudProvider,
                isHovered: hoveredBackend == .cloud,
                isRecessed: recession.isRecessed,
                compact: metrics.isCompact,
                onOpen: openCloudConfiguration,
                focus: $cloudTriggerFocused,
                onHoverChange: { hovering in
                    setHover(.cloud, hovering: hovering)
                }
            )
            .frame(height: metrics.cloudHeight)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(ModelsCoordinateSpace.name))
            } action: { frame in
                cloudRowFrame = frame
            }

            ModelsLocalFootnote()
                .padding(.top, metrics.footnoteTopPadding)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        // Receding rather than blurring: the page has to stay readable behind
        // the panel so the thing being configured is still visible, and a blur
        // on a surface this size costs a frame. Continuous with the panel's own
        // progress, so the two are one movement rather than two that agree.
        .scaleEffect(recession.scale, anchor: .top)
        .opacity(recession.opacity)
        .allowsHitTesting(!recession.isRecessed)
        .disabled(recession.isRecessed)

        // Always scrollable, never scrolling unnecessarily. `basedOnSize` means
        // a composition that fits behaves exactly like a static page — no
        // indicator, no rubber-banding — and one that does not stays reachable
        // instead of being cropped. Which of the two it is cannot be predicted
        // from the window alone: a download in progress adds a progress track,
        // and an error adds a line of explanation.
        ScrollView(.vertical, showsIndicators: false) { body }
            .scrollBounceBehavior(.basedOnSize)
            // Pinned. Without it a focusable control further down the page —
            // the primary action — can pull the initial scroll position to
            // itself, and the page opens with its own title already scrolled
            // off the top.
            .defaultScrollAnchor(.top)
    }

    /// The scale anchor is the cloud row's own centre, expressed in the unit
    /// space of the canvas, so the panel is seen to come out of the strip that
    /// was pressed rather than out of the middle of the page.
    private func panelAnchor(canvas: CGSize) -> UnitPoint {
        guard canvas.width > 0, canvas.height > 0, cloudRowFrame.midX > 0 else {
            return UnitPoint(x: 0.5, y: 0.8)
        }
        return UnitPoint(
            x: min(max(cloudRowFrame.midX / canvas.width, 0), 1),
            y: min(max(cloudRowFrame.midY / canvas.height, 0), 1)
        )
    }

    // MARK: - Actions

    private func select(_ effort: ModelEffort) {
        guard effort != state.effort else { return }
        Haptics.pop()
        withAnimation(
            Chamfer.Motion.reduce(
                .spring(duration: timing.effortChange, bounce: 0),
                when: reduceMotion
            )
        ) {
            state.setEffort(effort)
        }
        ModelsPreferences.saveEffort(effort)
    }

    private func setHover(_ backend: ModelsBackendID, hovering: Bool) {
        // Deliberately slow: this drives the ambient background wash, not a
        // control's answer to the pointer, so it is allowed to drift.
        withAnimation(
            Chamfer.Motion.reduce(
                .easeInOut(duration: timing.ambient),
                when: reduceMotion
            )
        ) {
            if hovering {
                hoveredBackend = backend
            } else if hoveredBackend == backend {
                hoveredBackend = nil
            }
        }
    }

    private func openCloudConfiguration() {
        guard !state.cloudConfigurationOpen else { return }
        Haptics.pop()
        withAnimation(openAnimation) {
            state.openCloudConfiguration()
            panelProgress = 1
        }
    }

    private func closeCloudConfiguration() {
        guard state.cloudConfigurationOpen else { return }
        Haptics.commit()
        withAnimation(closeAnimation) {
            state.closeCloudConfiguration()
            panelProgress = 0
        }
        // The page is disabled while the panel is modal. These writes are
        // batched into the dismissal update, so the trigger becomes eligible
        // again at the same moment focus returns to it.
        cloudTriggerFocused = true
    }

    private func performLocalAction() {
        switch ModelsLocalPresentation.action(for: state) {
        case .preparingRuntime:
            // Chamfer is already setting itself up. Nothing for a press to do.
            break
        case .download:
            downloadModel()
        case .activate:
            activateLocal()
        case .downloading, .alreadyActive:
            break
        }
    }

    /// Gets the model, and whatever it needs underneath it.
    ///
    /// The button asks for one thing, so this does both: the runtime is
    /// arranged first — joining the provisioning that starts at launch rather
    /// than beginning a second — and the pull follows. Nobody is sent to a
    /// website for a dependency the app is perfectly able to install itself.
    ///
    /// Idempotent all the way down: the installer checks the disk before it
    /// fetches anything and joins an existing pull rather than starting a
    /// second one, so pressing this twice — or reopening the page mid-download
    /// — costs nothing.
    private func downloadModel() {
        let model = state.recommendedModel
        let device = state.device

        Haptics.pop()
        withAnimation(Chamfer.Motion.quick) {
            state.beginDownload()
        }

        Task {
            guard await provisioning.ensureReady() else {
                // The failure is read off the provisioning state by the card,
                // so there is nothing to carry back here.
                withAnimation(Chamfer.Motion.navigation) {
                    state.finishDownload(installed: false)
                }
                return
            }

            let outcome = await runtime.install(model, device: device) { progress in
                withAnimation(
                    Chamfer.Motion.reduce(
                        .spring(duration: timing.progress, bounce: 0),
                        when: reduceMotion
                    )
                ) {
                    state.updateDownload(
                        fraction: progress.fraction,
                        stage: progress.stage
                    )
                }
            }

            withAnimation(Chamfer.Motion.navigation) {
                state.finishDownload(installed: outcome.isInstalled)
            }
            if outcome.isInstalled { Haptics.commit() }
        }
    }

    private func activateLocal() {
        Haptics.commit()
        withAnimation(Chamfer.Motion.navigation) {
            state.activate(.local)
        }
        ModelsPreferences.save(state: state)
    }

    private func activateCloud() {
        Haptics.commit()
        withAnimation(closeAnimation) {
            state.activate(.cloud)
            panelProgress = 0
        }
        cloudTriggerFocused = true
        ModelsPreferences.save(state: state)
    }

    private func connectProvider() {
        guard let cloudProvider else { return }
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
            if connected { cloudCredential = "" }
        }
    }

    /// Deliberately unanimated.
    ///
    /// This lands a few milliseconds after the page mounts — the local probe
    /// fails fast when Ollama is not running — which is squarely inside the
    /// bottom bar's selection spring. The bar's destinations are derived from
    /// this same state, so wrapping the write in a shorter curve retargeted
    /// that spring mid-flight and the black selector stuttered. Data arriving
    /// in the background is not an event the interface should animate.
    private func refreshRuntime() async {
        guard runtimeProbeEnabled else { return }
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

// MARK: - Header

private struct ModelsPageHeader: View {
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                ModelsEyebrowMark()
                Text("CHAMFER  /  INTELLIGENCE")
                    .font(Chamfer.TypeScale.eyebrow)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.78))
            }
            .padding(.bottom, compact ? 5 : 8)

            Text("Models")
                .font(
                    .system(
                        size: compact ? 33 : 40,
                        weight: .regular,
                        design: .serif
                    )
                )
                .tracking(-1.3)
                .foregroundStyle(Chamfer.Palette.pageText)

            Text("Chamfer picks the model your Mac can run, and you decide how hard it works.")
                .font(.system(size: compact ? 13 : 15, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ModelsEyebrowMark: View {
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

private struct ModelsLocalFootnote: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Chamfer.Palette.pageTextSoft.opacity(0.34))
                .frame(width: 22, height: 1)
            Text("The local model never sends a note anywhere.")
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The primary card

private struct ModelsPrimaryCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: ModelsDashboardState
    let isHovered: Bool
    let isRecessed: Bool
    let errorMessage: String?
    let compact: Bool
    let onPrimaryAction: () -> Void
    let onHoverChange: (Bool) -> Void

    private var model: LocalModelDescriptor { state.recommendedModel }
    private var action: ModelsLocalAction {
        ModelsLocalPresentation.action(for: state)
    }

    private var presentation: ModelsSurfacePresentation {
        ModelsSurfaceResponse.presentation(
            for: .local,
            isActive: state.active == .local,
            isHovered: isHovered,
            isRecessed: isRecessed
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            title.padding(.top, compact ? Chamfer.Space.snug : 14)
            deviceStrip.padding(.top, compact ? Chamfer.Space.snug : 16)
            facts.padding(.top, compact ? Chamfer.Space.snug : 10)

            Spacer(minLength: compact ? Chamfer.Space.tight : 12)

            statusBlock
            actionRow.padding(.top, compact ? Chamfer.Space.snug : 14)
        }
        .padding(compact ? Chamfer.Space.roomy : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ChamferCardSurface(
                tint: .models(.local),
                radius: Chamfer.Radius.card,
                presentation: presentation
            )
        )
        .offset(y: presentation.lift)
        .animation(Chamfer.Motion.reduce(.spring(duration: 0.24, bounce: 0), when: reduceMotion), value: isHovered)
        .onHover(perform: onHoverChange)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Local model, \(model.displayName) \(model.parameterLabel)")
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text("RECOMMENDED FOR THIS MAC")
                .font(Chamfer.TypeScale.eyebrow)
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.78))
            Spacer(minLength: 8)
            ModelsStatusBadge(
                text: state.status(for: .local),
                tone: badgeTone
            )
        }
    }

    private var badgeTone: ModelsStatusBadge.Tone {
        if state.active == .local { return state.localReady ? .active : .danger }
        if state.runtimeInstall != nil, !state.localRuntimeAvailable { return .working }
        return switch state.installation {
        case .installed: .ready
        case .downloading: .working
        case .notInstalled: .quiet
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(model.displayName)
                    .font(
                        .system(
                            size: compact ? 29 : 34,
                            weight: .regular,
                            design: .serif
                        )
                    )
                    .tracking(-1)
                    .foregroundStyle(Chamfer.Palette.pageText)
                Text(model.parameterLabel)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
            }
            Text(model.characterisation)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(compact ? 1 : nil)
                .lineSpacing(1)
        }
    }

    /// Why this model, said in the machine's own numbers. The recommendation is
    /// not a choice the user gets to make, so it has to be a recommendation
    /// they can see the reasoning behind.
    private var deviceStrip: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(state.device.summary.uppercased())
                .font(Chamfer.TypeScale.micro)
                .kerning(0.55)
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.72))
            if !compact {
                Text(state.recommendationRationale)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? Chamfer.Space.snug : 11)
        // The interior deliberately tightens below the 22pt card edge, so each
        // nested layer reads as sitting inside the surface around it.
        .background(ModelsInsetSurface(radius: 12))
    }

    /// The three things somebody actually wants to know before agreeing to a
    /// multi-gigabyte download, in the space the card would otherwise leave
    /// empty above its action.
    private var facts: some View {
        HStack(spacing: 8) {
            ModelsFact(
                label: "DOWNLOAD",
                value: model.downloadSizeLabel,
                compact: compact
            )
            ModelsFact(
                label: "MEMORY",
                value: model.minimumMemoryGB == 0
                    ? "Any Mac"
                    : "\(model.minimumMemoryGB) GB+",
                compact: compact
            )
            ModelsFact(label: "NETWORK", value: "Once, then never", compact: compact)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let runtimeInstall = state.runtimeInstall, !state.localRuntimeAvailable {
                ModelsDownloadTrack(download: runtimeInstall)
            } else if state.installation == .downloading {
                ModelsDownloadTrack(download: state.download)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                ModelsStatusDot(tone: badgeTone)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(errorMessage ?? ModelsLocalPresentation.statusDetail(for: state))
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(
                        errorMessage == nil
                            ? Chamfer.Palette.pageTextSoft
                            : Chamfer.Palette.danger
                    )
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            switch action {
            case .alreadyActive:
                // Not a disabled button. There is nothing here to press, and
                // dimming a filled control to say so reads as something broken
                // rather than as something finished.
                ModelsStateMark(
                    text: "In use for rewrites",
                    symbol: "checkmark.circle.fill",
                    tint: Chamfer.Palette.positive,
                    fill: Chamfer.Palette.positiveSoft.opacity(0.78)
                )
            case .preparingRuntime:
                ModelsStateMark(
                    text: "Setting up Ollama…",
                    symbol: nil,
                    tint: Chamfer.Palette.brass,
                    fill: Chamfer.Palette.brassSoft.opacity(0.85),
                    showsSpinner: true
                )
            case .downloading:
                // Work in progress is not a control either. The track above
                // says how far along it is; this says what is happening.
                ModelsStateMark(
                    text: "Downloading…",
                    symbol: nil,
                    tint: Chamfer.Palette.brass,
                    fill: Chamfer.Palette.brassSoft.opacity(0.85),
                    showsSpinner: true
                )
            case .download, .activate:
                Button(action: onPrimaryAction) {
                    HStack(spacing: 6) {
                        Text(action.title(model: model))
                        Image(systemName: action.symbol)
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(ModelsPrimaryButtonStyle())
                .disabled(!ModelsLocalPresentation.isActionEnabled(for: state))
                .accessibilityLabel(
                    "\(action.title(model: model)), \(model.displayName) \(model.parameterLabel)"
                )
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Configuration column

/// A state where the primary action would otherwise be a dead control.
///
/// A filled button dimmed to 40% says "broken", not "finished" or "working".
/// This occupies the same place at the same height, so nothing shifts when the
/// card moves between acting and having acted.
private struct ModelsStateMark: View {
    let text: String
    var symbol: String?
    let tint: Color
    let fill: Color
    var showsSpinner = false

    var body: some View {
        HStack(spacing: 7) {
            if showsSpinner {
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.16))
                    ModelsIndeterminateSweep(
                        width: 16,
                        minimumSegmentWidth: 5,
                        tint: tint.opacity(0.78)
                    )
                }
                .frame(width: 16, height: 4)
                .clipShape(Capsule())
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 15)
        .frame(height: 38)
        .background { Capsule().fill(fill) }
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

private struct ModelsFact: View {
    let label: String
    let value: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Chamfer.TypeScale.micro)
                .kerning(0.5)
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
                // Three facts share a fixed card row. Scaling is the last
                // resort before clipping, not a return to an 8pt default.
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? Chamfer.Space.snug : 10)
        .padding(.vertical, compact ? Chamfer.Space.tight : 9)
        .background(ModelsInsetSurface(radius: 11))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct ModelsConfigurationColumn: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    @LegacyState private var hoveredEffort: ModelEffort?

    let effort: ModelEffort
    let isRecessed: Bool
    let compact: Bool
    let onSelect: (ModelEffort) -> Void

    private var presentation: ModelsSurfacePresentation {
        ModelsSurfaceResponse.presentation(
            for: .local,
            isActive: false,
            isHovered: false,
            isRecessed: isRecessed
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONFIGURATION")
                .font(Chamfer.TypeScale.eyebrow)
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.78))
                .padding(.bottom, compact ? Chamfer.Space.snug : 11)

            VStack(spacing: 2) {
                ForEach(ModelEffort.allCases) { candidate in
                    ModelsEffortRow(
                        effort: candidate,
                        presentation: ModelsEffortSelectorResponse.presentation(
                            for: candidate,
                            selected: effort,
                            hovered: hoveredEffort
                        ),
                        indicator: indicator,
                        action: { onSelect(candidate) },
                        onHoverChange: { hovering in
                            withAnimation(Chamfer.Motion.quick) {
                                if hovering {
                                    hoveredEffort = candidate
                                } else if hoveredEffort == candidate {
                                    hoveredEffort = nil
                                }
                            }
                        }
                    )
                }
            }
            .padding(4)
            .background(ModelsInsetSurface(radius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Model effort")

            PageRule()
                .opacity(0.8)
                .padding(.vertical, compact ? Chamfer.Space.snug : 12)

            if compact {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: Chamfer.Space.snug
                ) {
                    ForEach(effort.profile.readouts) { readout in
                        ModelsReadoutRow(readout: readout)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(effort.profile.readouts) { readout in
                        ModelsReadoutRow(readout: readout)
                    }
                }
            }

            Spacer(minLength: compact ? 0 : 10)

            if !compact {
                Text(effort.profile.mechanics)
                    .font(Chamfer.TypeScale.micro)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.72))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, compact ? Chamfer.Space.regular : 16)
        .padding(.vertical, compact ? Chamfer.Space.regular : 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ChamferCardSurface(
                tint: .models(.local),
                radius: Chamfer.Radius.card,
                presentation: presentation
            )
        )
    }
}

private struct ModelsEffortRow: View {
    let effort: ModelEffort
    let presentation: ModelsEffortRowPresentation
    let indicator: Namespace.ID
    let action: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(effort.title)
                        .font(.system(size: 13, weight: presentation.isSelected ? .semibold : .medium))
                        .foregroundStyle(
                            (presentation.isSelected
                                ? Chamfer.Palette.textOnInk
                                : Chamfer.Palette.pageText)
                                .opacity(presentation.titleOpacity)
                        )
                    Text(effort.tagline)
                        .font(Chamfer.TypeScale.micro)
                        .foregroundStyle(
                            (presentation.isSelected
                                ? Chamfer.Palette.textOnInkSoft
                                : Chamfer.Palette.pageTextSoft)
                                .opacity(presentation.detailOpacity)
                        )
                        .lineLimit(1)
                        // The selector column is fixed. Preserve the full
                        // tagline by yielding slightly before it can clip.
                        .minimumScaleFactor(0.90)
                }
                Spacer(minLength: 0)
                if presentation.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Chamfer.Palette.textOnInk)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if presentation.isSelected {
                    // One indicator that travels between rows rather than three
                    // that fade in and out, so the selection is seen to move.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Chamfer.Palette.ink)
                        .matchedGeometryEffect(id: "effort", in: indicator)
                }
            }
        }
        .buttonStyle(.plain)
        .chamferFocusable(radius: 10)
        .padding(Chamfer.Control.hitPadding(for: 38))
        .contentShape(Rectangle())
        .padding(-Chamfer.Control.hitPadding(for: 38))
        .onHover(perform: onHoverChange)
        .accessibilityLabel("\(effort.title). \(effort.tagline)")
        .accessibilityValue(presentation.isSelected ? "Selected" : "")
        .accessibilityHint(effort.summary)
        .accessibilityAddTraits(presentation.isSelected ? .isSelected : [])
    }
}

private struct ModelsReadoutRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let readout: ModelEffortReadout

    private var fill: Color {
        readout.axis.higherIsBetter
            ? Chamfer.Palette.ink.opacity(0.72)
            : Chamfer.Palette.brass.opacity(0.68)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(readout.axis.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                Spacer(minLength: 4)
                Text(readout.caption)
                    .font(Chamfer.TypeScale.micro)
                    .foregroundStyle(Chamfer.Palette.pageText.opacity(0.86))
                    .contentTransition(.opacity)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Chamfer.Palette.pageText.opacity(0.08))
                    Capsule()
                        .fill(fill)
                        .frame(width: max(3, proxy.size.width * readout.level))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(readout.axis.title): \(readout.caption)")
    }
}

// MARK: - Cloud

private struct ModelsCloudRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: ModelsDashboardState
    let provider: CloudProvider?
    let isHovered: Bool
    let isRecessed: Bool
    let compact: Bool
    let onOpen: () -> Void
    let focus: FocusState<Bool>.Binding
    let onHoverChange: (Bool) -> Void

    private var presentation: ModelsSurfacePresentation {
        ModelsSurfaceResponse.presentation(
            for: .cloud,
            isActive: state.active == .cloud,
            isHovered: isHovered,
            isRecessed: isRecessed
        )
    }

    private var actionTitle: String {
        state.connection == .connected ? "Manage Provider" : "Connect Provider"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("CLOUD  ·  OPTIONAL")
                        .font(Chamfer.TypeScale.eyebrow)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.72))
                    ModelsStatusBadge(
                        text: state.status(for: .cloud),
                        tone: state.active == .cloud
                            ? (state.connection == .connected ? .active : .danger)
                            : (state.connection == .connected ? .ready : .quiet)
                    )
                }
                Text("Cloud Model")
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .tracking(-0.5)
                    .foregroundStyle(Chamfer.Palette.pageText)
                if !compact {
                    Text(detail)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onOpen) {
                HStack(spacing: 5) {
                    Text(actionTitle)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .buttonStyle(ModelsQuietButtonStyle(focus: focus))
            .accessibilityHint("Opens cloud provider settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? Chamfer.Space.regular : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            ChamferCardSurface(
                tint: .models(.cloud),
                radius: Chamfer.Radius.large,
                presentation: presentation
            )
        )
        // Covered rather than removed. The page's whole argument is that the
        // local model is the product and cloud is the quieter alternative
        // beneath it; deleting the row would leave that argument with one side,
        // and shipping it live would offer something this build cannot do.
        .overlay {
            if !ModelsCloudAvailability.isAvailable {
                ModelsComingSoonScrim()
            }
        }
        .allowsHitTesting(ModelsCloudAvailability.isAvailable)
        .offset(y: presentation.lift)
        .animation(
            Chamfer.Motion.reduce(.spring(duration: 0.24, bounce: 0), when: reduceMotion),
            value: isHovered
        )
        .onHover { hovering in
            guard ModelsCloudAvailability.isAvailable else { return }
            onHoverChange(hovering)
        }
    }

    private var detail: String {
        if let provider, state.connection == .connected {
            return "\(provider.displayName) connected. Notes leave this Mac when it runs."
        }
        return "A larger model than this Mac can hold, billed by your provider."
    }
}

/// The cover over an unreleased path.
///
/// Deliberately close in colour to the page it sits on rather than a dark
/// scrim: this is not a modal blocking something, it is a card that has not
/// opened yet. The row beneath stays legible enough to read what is coming,
/// which is the only reason to leave it on the page at all.
private struct ModelsComingSoonScrim: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
            .fill(Chamfer.Palette.canvas.opacity(0.86))
            .overlay {
                RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
                    .strokeBorder(
                        Chamfer.Palette.pageTextSoft.opacity(0.20),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
            .overlay {
                VStack(spacing: 4) {
                    Text(ModelsCloudAvailability.comingSoonTitle)
                        .font(Chamfer.TypeScale.eyebrow)
                        .foregroundStyle(Chamfer.Palette.pageText.opacity(0.72))
                    Text(ModelsCloudAvailability.comingSoonDetail)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Cloud model, coming soon. \(ModelsCloudAvailability.comingSoonDetail)"
            )
    }
}

// MARK: - Shared surfaces

extension ChamferCardSurface.Tint {
    static func models(_ backend: ModelsBackendID) -> Self {
        let primary = ModelsBackendTintResponse.tint(for: backend)
        let secondary = ModelsBackendTintResponse.secondaryTint(for: backend)
        return Self(
            primary: Color(red: primary.red, green: primary.green, blue: primary.blue),
            secondary: Color(
                red: secondary.red,
                green: secondary.green,
                blue: secondary.blue
            )
        )
    }
}

struct ModelsStatusBadge: View {
    enum Tone {
        case active
        case ready
        case working
        case quiet
        case danger

        var color: Color {
            switch self {
            case .active, .ready: Chamfer.Palette.positive
            case .working: Chamfer.Palette.brass
            case .quiet: Chamfer.Palette.pageTextSoft
            case .danger: Chamfer.Palette.danger
            }
        }

        var showsFill: Bool {
            switch self {
            case .active: true
            case .ready, .working, .quiet, .danger: false
            }
        }
    }

    let text: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 5) {
            ModelsStatusDot(tone: tone)
            Text(text)
                .font(Chamfer.TypeScale.micro)
                .kerning(0.9)
                // Card headers cannot widen around a long state. Let the
                // 10pt floor yield slightly before the capsule can clip it.
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(
            tone == .quiet
                ? Chamfer.Palette.pageTextSoft.opacity(0.82)
                : tone.color
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if tone.showsFill {
                Capsule().fill(Chamfer.Palette.positiveSoft.opacity(0.72))
            } else {
                Capsule().fill(Chamfer.Palette.canvasDeep.opacity(0.55))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ModelsStatusDot: View {
    let tone: ModelsStatusBadge.Tone

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// The download's own progress, determinate when the runtime has told us a
/// total and honestly indeterminate when it has not.
private struct ModelsDownloadTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let download: ModelsDownloadState?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Chamfer.Palette.pageText.opacity(0.09))
                    if let fraction = download?.fraction {
                        Capsule()
                            .fill(Chamfer.Palette.ink.opacity(0.78))
                            .frame(width: max(4, proxy.size.width * fraction))
                    } else {
                        // No total yet. A bar pretending to know how far along
                        // it is would be a lie; a quiet sweep says "working".
                        ModelsIndeterminateSweep(width: proxy.size.width)
                    }
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())

            if let fraction = download?.fraction {
                Text("\(Int(fraction * 100))%")
                    .font(Chamfer.TypeScale.micro)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Download progress")
        .accessibilityValue(
            download?.fraction.map { "\(Int($0 * 100)) percent" } ?? "Starting"
        )
    }
}

private struct ModelsIndeterminateSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var advanced = false

    let width: CGFloat
    var minimumSegmentWidth: CGFloat = 24
    var tint = Chamfer.Palette.ink.opacity(0.55)

    private var segmentWidth: CGFloat {
        max(minimumSegmentWidth, width * 0.32)
    }

    private var travel: CGFloat {
        max(0, width - segmentWidth)
    }

    var body: some View {
        Capsule()
            .fill(tint)
            .frame(width: segmentWidth)
            .offset(x: reduceMotion ? travel / 2 : (advanced ? travel : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    Chamfer.Motion.reduce(
                        Chamfer.Motion.indeterminate
                            .repeatForever(autoreverses: true),
                        when: reduceMotion
                    )
                ) {
                    advanced = true
                }
            }
    }
}

// MARK: - Buttons

private struct ModelsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ModelsPrimaryButtonStyle.Configuration

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.paper)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(Chamfer.Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
                .chamferFocusable(radius: 11)
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1) : 0.42)
                .animation(Chamfer.Motion.quick, value: configuration.isPressed)
                .animation(Chamfer.Motion.quick, value: isEnabled)
                .padding(Chamfer.Control.hitPadding(for: 38))
                .contentShape(Rectangle())
                .padding(-Chamfer.Control.hitPadding(for: 38))
        }
    }
}

private struct ModelsQuietButtonStyle: ButtonStyle {
    let focus: FocusState<Bool>.Binding?

    init(focus: FocusState<Bool>.Binding? = nil) {
        self.focus = focus
    }

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, focus: focus)
    }

    private struct StyledLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        @LegacyState private var isHovered = false
        let configuration: ModelsQuietButtonStyle.Configuration
        let focus: FocusState<Bool>.Binding?

        @ViewBuilder
        var body: some View {
            if let focus {
                label.chamferFocusable(
                    radius: 10,
                    focused: focus,
                    equals: true
                )
            } else {
                label.chamferFocusable(radius: 10)
            }
        }

        private var label: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.pageText.opacity(isHovered ? 0.98 : 0.88))
                .padding(.horizontal, 14)
                .frame(height: Chamfer.Control.compactFieldHeight)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Chamfer.Palette.paper.opacity(isHovered ? 0.86 : 0.68))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Chamfer.Palette.barStroke.opacity(isHovered ? 0.9 : 0.7),
                            lineWidth: 1
                        )
                }
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1) : 0.45)
                .onHover { hovering in
                    withAnimation(Chamfer.Motion.interactive) { isHovered = hovering }
                }
                .animation(Chamfer.Motion.quick, value: configuration.isPressed)
                .padding(
                    Chamfer.Control.hitPadding(
                        for: Chamfer.Control.compactFieldHeight
                    )
                )
                .contentShape(Rectangle())
                .padding(
                    -Chamfer.Control.hitPadding(
                        for: Chamfer.Control.compactFieldHeight
                    )
                )
        }
    }
}

// MARK: - Ambient field

private struct ModelsAmbientField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let active: ModelsBackendID?
    let hovered: ModelsBackendID?
    let recessed: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            // Local owns the top two-thirds of the page in atmosphere as well
            // as in layout, which is the hierarchy stated before a word is read.
            ModelsBloom(
                color: Color(red: 0.72, green: 0.66, blue: 0.87),
                center: CGPoint(x: 0.06, y: 0.30),
                size: CGSize(width: 0.72, height: 0.62),
                inwardOffset: CGSize(width: 0.07, height: 0.03),
                intensity: 1.18,
                backend: .local,
                active: active,
                hovered: hovered,
                recessed: recessed,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.93, green: 0.66, blue: 0.43),
                center: CGPoint(x: 0.86, y: 0.10),
                size: CGSize(width: 0.60, height: 0.52),
                inwardOffset: CGSize(width: -0.05, height: 0.05),
                intensity: 1.14,
                backend: .local,
                active: active,
                hovered: hovered,
                recessed: recessed,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.96, green: 0.86, blue: 0.51),
                center: CGPoint(x: 0.40, y: 0.02),
                size: CGSize(width: 0.52, height: 0.42),
                inwardOffset: CGSize(width: 0.02, height: 0.05),
                intensity: 1.10,
                backend: .local,
                active: active,
                hovered: hovered,
                recessed: recessed,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.94, green: 0.67, blue: 0.78),
                center: CGPoint(x: 0.78, y: 0.97),
                size: CGSize(width: 0.62, height: 0.44),
                inwardOffset: CGSize(width: -0.04, height: -0.07),
                intensity: 1.12,
                backend: .cloud,
                active: active,
                hovered: hovered,
                recessed: recessed,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.94, green: 0.60, blue: 0.51),
                center: CGPoint(x: 0.22, y: 1.00),
                size: CGSize(width: 0.58, height: 0.40),
                inwardOffset: CGSize(width: 0.03, height: -0.07),
                intensity: 1.08,
                backend: .cloud,
                active: active,
                hovered: hovered,
                recessed: recessed,
                canvas: size
            )
        }
        .compositingGroup()
        .blendMode(.multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            Chamfer.Motion.reduce(.easeInOut(duration: 0.46), when: reduceMotion),
            value: hovered
        )
        .animation(
            Chamfer.Motion.reduce(.easeInOut(duration: 0.30), when: reduceMotion),
            value: recessed
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
    let active: ModelsBackendID?
    let hovered: ModelsBackendID?
    let recessed: Bool
    let canvas: CGSize

    private var presentation: ModelsBloomPresentation {
        ModelsBloomResponse.presentation(
            for: backend,
            active: active,
            hovered: hovered,
            recessed: recessed
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
