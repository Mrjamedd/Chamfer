import ChamferRewrite
import SwiftUI

struct ModelsConfigurationSheet: View {
    @State private var closeHovered = false

    @Binding var state: ModelsLandscapeState
    let backend: ModelsBackendID
    let morphSourceFrame: CGRect
    let morphDestinationFrame: CGRect
    let morphProgress: CGFloat
    let contentProgress: CGFloat
    let contentInteractive: Bool
    let appleAvailable: Bool
    let localRuntimeAvailable: Bool
    let physicalMemory: UInt64
    @Binding var cloudProvider: CloudProvider
    @Binding var cloudCredential: String
    let errorMessage: String?
    let isWorking: Bool
    let onSelectLocalModel: (String) -> Void
    let onClose: () -> Void
    let onActivate: () -> Void
    let onConnectProvider: () -> Void
    let onDownload: () -> Void
    let onInstallLocalRuntime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MODEL SETTINGS")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.25)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Chamfer.Palette.canvasDeep.opacity(0.68))
                        .clipShape(Circle())
                        // The smallest target in the app, and one of only two
                        // ways out of this sheet. Padding out and back in gives
                        // it a 44pt reach while leaving the header's layout
                        // untouched, so the dot stays where it was.
                        .padding(8)
                        .contentShape(Rectangle())
                        .padding(-8)
                }
                .buttonStyle(.plain)
                .chamferHoverRingCircle(closeHovered)
                .onHover { closeHovered = $0 }
                .accessibilityLabel("Close model configuration")
            }
            .padding(.bottom, 14)

            Group {
                switch backend {
                case .apple:
                    applePanel
                case .ollama:
                    cloudPanel
                case .mlx:
                    localPanel
                }
            }
            .transition(.opacity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .opacity(Double(contentProgress))
        .allowsHitTesting(contentInteractive)
        .mask {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .modifier(
                    ModelsExplicitConfigurationMorph(
                        sourceFrame: morphSourceFrame,
                        destinationFrame: morphDestinationFrame,
                        progress: morphProgress
                    )
                )
        }
    }

    private var applePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelsSheetHeading(index: "01 — ON-DEVICE", title: "Apple Foundation Models") {
                ModelsSheetBadge(
                    text: appleAvailable ? "Ready" : "Unavailable",
                    color: appleAvailable
                        ? Chamfer.Palette.positive
                        : Chamfer.Palette.danger,
                    showsDot: true
                )
            }

            Text(
                "Chamfer uses the model already built into macOS. "
                    + "Note contents stay on this Mac."
            )
            .font(.system(size: 14, design: .serif))
            .foregroundStyle(Chamfer.Palette.pageTextSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
            .padding(.bottom, 18)

            HStack(spacing: 10) {
                ModelsFact(
                    label: "AVAILABILITY",
                    value: appleAvailable ? "Ready on this Mac" : "Not available"
                )
                ModelsFact(label: "NETWORK ACCESS", value: "Never required")
            }

            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(
                            appleAvailable
                                ? Chamfer.Palette.positive
                                : Chamfer.Palette.danger
                        )
                        .frame(width: 6, height: 6)
                    Text(
                        appleAvailable
                            ? "Apple Intelligence enabled"
                            : "Apple Intelligence unavailable"
                    )
                        .font(.system(size: 10))
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                }
                Spacer()
                Button("Use This Model", action: onActivate)
                    .buttonStyle(ModelsSheetButtonStyle(.primary))
                    .disabled(!appleAvailable)
            }
            .padding(.top, 18)
        }
    }

    private var cloudPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelsSheetHeading(index: "03 — SUPPORTED PROVIDER", title: "Cloud Model") {
                ModelsSheetBadge(
                    text: connectionLabel,
                    color: connectionColor,
                    showsDot: true
                )
            }

            Text(
                "Connect a supported provider for larger models while keeping "
                    + "Chamfer's local workflow unchanged."
            )
            .font(.system(size: 14, design: .serif))
            .foregroundStyle(Chamfer.Palette.pageTextSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ModelsFieldRow(label: "Provider") {
                Picker("Provider", selection: $cloudProvider) {
                    ForEach(CloudProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .background(ModelsFieldBackground())
            }

            ModelsFieldRow(label: "API key") {
                SecureField(
                    state.connection == .connected
                        ? "Stored securely in Keychain"
                        : "Paste provider key",
                    text: $cloudCredential
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(ModelsFieldBackground())
            }

            HStack(spacing: 10) {
                Text("Credentials remain on this Mac.")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.82))

                Spacer()

                Button(cloudButtonTitle, action: cloudButtonAction)
                    .buttonStyle(ModelsSheetButtonStyle(.primary))
                    .disabled(state.connection == .testing || isWorking)
            }
            .padding(.top, 18)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(Chamfer.Palette.danger)
                    .lineLimit(2)
                    .padding(.top, 7)
            }
        }
    }

    private var localPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelsSheetHeading(index: "02 — ON-DEVICE DOWNLOAD", title: "Local Model") {
                ModelsSheetBadge(
                    text: selectedLocalModel.downloadSize,
                    color: nil,
                    showsDot: false
                )
            }

            LocalModelPicker(
                models: LocalModelCatalog.standard,
                selectedID: state.selectedLocalModelID,
                physicalMemory: physicalMemory,
                onSelect: onSelectLocalModel
            )
            .frame(height: 64)
            .background(ModelsInsetSurface(radius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 12)

            VStack(spacing: 7) {
                HStack {
                    Text("INSTALLATION")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.70))
                    Spacer()
                    Text(installationLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(installationColor)
                }

                HStack(spacing: 6) {
                    if state.installation == .downloading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Circle()
                            .fill(installationColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(selectedLocalAssessment.explanation)
                        .font(.system(size: 9, design: .serif))
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(11)
            .background(ModelsInsetSurface(radius: 13))
            .padding(.top, 8)

            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(Chamfer.Palette.danger)
                        .lineLimit(2)
                }
                Spacer()
                Button(localButtonTitle, action: localButtonAction)
                    .buttonStyle(ModelsSheetButtonStyle(.primary))
                    .disabled(localButtonDisabled)
            }
            .padding(.top, 12)
        }
    }

    private var selectedLocalModel: LocalModelDescriptor {
        LocalModelCatalog.standard.first {
            $0.id == state.selectedLocalModelID
        } ?? LocalModelCatalog.standard[0]
    }

    private var selectedLocalAssessment: LocalModelAssessment {
        LocalModelCatalog.assessment(
            for: selectedLocalModel,
            physicalMemory: physicalMemory
        )
    }

    private var connectionLabel: String {
        switch state.connection {
        case .notConnected: "Not connected"
        case .connected: "Connected"
        case .testing: "Connecting…"
        case .failed: "Unavailable"
        }
    }

    private var connectionColor: Color {
        switch state.connection {
        case .notConnected: Chamfer.Palette.pageTextSoft
        case .connected: Chamfer.Palette.positive
        case .testing: Chamfer.Palette.brass
        case .failed: Chamfer.Palette.danger
        }
    }

    private var installationLabel: String {
        if !localRuntimeAvailable { return "Ollama is not running" }
        if selectedLocalAssessment.fit == .unusable {
            return "Not usable on this Mac"
        }
        return switch state.installation {
        case .notInstalled: "\(selectedLocalModel.downloadSize) download"
        case .downloading: "Downloading from Ollama…"
        case .installed: "Ready on this Mac"
        }
    }

    private var installationColor: Color {
        if !localRuntimeAvailable || selectedLocalAssessment.fit == .unusable {
            return Chamfer.Palette.danger
        }
        return state.installation == .installed
            ? Chamfer.Palette.positive
            : Chamfer.Palette.brass
    }

    private var cloudButtonTitle: String {
        if state.connection == .testing || isWorking { return "Connecting…" }
        return state.connection == .connected ? "Use This Model" : "Connect Provider"
    }

    private func cloudButtonAction() {
        if state.connection == .connected {
            onActivate()
        } else {
            onConnectProvider()
        }
    }

    private var localButtonTitle: String {
        if !localRuntimeAvailable { return "Get Ollama" }
        if selectedLocalAssessment.fit == .unusable { return "Not Supported" }
        return switch state.installation {
        case .notInstalled: "Download Model"
        case .downloading: "Downloading…"
        case .installed: "Use This Model"
        }
    }

    private var localButtonDisabled: Bool {
        isWorking
            || state.installation == .downloading
            || (localRuntimeAvailable && selectedLocalAssessment.fit == .unusable)
    }

    private func localButtonAction() {
        if localRuntimeAvailable {
            onDownload()
        } else {
            onInstallLocalRuntime()
        }
    }
}

private struct LocalModelPicker: View {
    let models: [LocalModelDescriptor]
    let selectedID: String
    let physicalMemory: UInt64
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(models) { model in
                        let assessment = LocalModelCatalog.assessment(
                            for: model,
                            physicalMemory: physicalMemory
                        )
                        Button {
                            onSelect(model.id)
                        } label: {
                            modelRow(model, assessment: assessment)
                        }
                        .buttonStyle(.plain)
                        .frame(height: 64)
                        .id(model.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .onAppear {
                proxy.scrollTo(selectedID, anchor: .center)
            }
            .onChange(of: selectedID) { _, nextID in
                withAnimation(Chamfer.Motion.quick) {
                    proxy.scrollTo(nextID, anchor: .center)
                }
            }
        }
        .accessibilityLabel("Local model picker")
        .accessibilityHint("Scroll, then choose a model")
    }

    private func modelRow(
        _ model: LocalModelDescriptor,
        assessment: LocalModelAssessment
    ) -> some View {
        HStack(spacing: 11) {
            ModelsPackageSymbol()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(assessment.fit.label)
                        .font(.system(size: 8, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(fitColor(assessment.fit))
                    Text(model.downloadSize)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
                }
                Text(model.displayName)
                    .font(.system(size: 12, weight: selectedID == model.id ? .semibold : .regular))
                    .foregroundStyle(Chamfer.Palette.pageText)
                Text(model.comparison.label)
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: selectedID == model.id ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(
                    selectedID == model.id
                        ? fitColor(assessment.fit)
                        : Chamfer.Palette.pageTextSoft.opacity(0.35)
                )
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private func fitColor(_ fit: LocalModelFit) -> Color {
        switch fit {
        case .recommended: Chamfer.Palette.positive
        case .usable: Chamfer.Palette.brass
        case .unusable: Chamfer.Palette.danger
        }
    }
}

struct ModelsConfigurationSurface: View {
    let backend: ModelsBackendID
    let progress: CGFloat
    let cornerRadius: CGFloat
    /// Whether the pointer was on the button this grew out of. Carried so the
    /// surface's first frame matches the button's last one.
    let startedHovered: Bool

    var body: some View {
        let tints = surfaceTints
        let presentation = ModelsSheetSurfaceResponse.morphPresentation(
            for: backend,
            progress: progress,
            isHovered: startedHovered
        )

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Chamfer.Palette.paper.opacity(presentation.paperOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tints.primary.opacity(presentation.washOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tints.primary.opacity(presentation.primaryOpacity),
                                tints.secondary.opacity(presentation.secondaryOpacity),
                                tints.primary.opacity(presentation.trailingOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        tints.primary.opacity(presentation.borderOpacity),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: tints.primary.opacity(presentation.shadowOpacity),
                radius: presentation.shadowRadius,
                y: presentation.shadowY
            )
            .shadow(
                color: Color(red: 0.31, green: 0.21, blue: 0.10)
                    .opacity(0.07 * Double(progress)),
                radius: 8,
                y: 4
            )
    }

    private var surfaceTints: (primary: Color, secondary: Color) {
        let tint = ModelsBackendTintResponse.surfaceTint(for: backend)
        let primary = Color(
            red: tint.red,
            green: tint.green,
            blue: tint.blue
        )

        return switch backend {
        case .apple:
            (
                primary,
                Color(red: 0.82, green: 0.87, blue: 0.50)
            )
        case .mlx:
            (
                primary,
                Color(red: 0.92, green: 0.64, blue: 0.43)
            )
        case .ollama:
            (
                primary,
                Color(red: 0.93, green: 0.57, blue: 0.48)
            )
        }
    }
}

private struct ModelsSheetHeading<Accessory: View>: View {
    let index: String
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(index)
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.55)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
                Text(title)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .tracking(-0.65)
                    .foregroundStyle(Chamfer.Palette.pageText)
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

private struct ModelsSheetBadge: View {
    let text: String
    let color: Color?
    let showsDot: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsDot, let color {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.18), radius: 0, x: 0, y: 0)
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Chamfer.Palette.pageTextSoft)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Chamfer.Palette.canvasDeep.opacity(0.62))
        .clipShape(Capsule())
        .padding(.top, 2)
    }
}

private struct ModelsFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.55)
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.pageText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ModelsInsetSurface(radius: 12))
    }
}

private struct ModelsFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .frame(width: 104, alignment: .leading)
            content
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Chamfer.Palette.paperStroke.opacity(0.75))
                .frame(height: 1)
        }
    }
}

private struct ModelsFieldBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Chamfer.Palette.page.opacity(0.76))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        Chamfer.Palette.barStroke.opacity(0.72),
                        lineWidth: 1
                    )
            }
    }
}

private struct ModelsInsetSurface: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Chamfer.Palette.canvas.opacity(0.50))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Chamfer.Palette.paperStroke.opacity(0.72),
                        lineWidth: 1
                    )
            }
    }
}

private struct ModelsPackageSymbol: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.66, blue: 0.87).opacity(0.68),
                            Color(red: 0.93, green: 0.66, blue: 0.43).opacity(0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ForEach([30.0, 60.0, 90.0], id: \.self) { angle in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Chamfer.Palette.pageText.opacity(0.46), lineWidth: 0.8)
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(angle))
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }
}

private struct ModelsSheetButtonStyle: ButtonStyle {
    enum Emphasis: Equatable {
        case primary
        case quiet
    }

    let emphasis: Emphasis

    init(_ emphasis: Emphasis) {
        self.emphasis = emphasis
    }

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, emphasis: emphasis)
    }

    private struct StyledLabel: View {
        @Environment(\.isEnabled) private var isEnabled

        let configuration: ModelsSheetButtonStyle.Configuration
        let emphasis: Emphasis

        var body: some View {
            configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                emphasis == .primary
                    ? Chamfer.Palette.paper
                    : Chamfer.Palette.pageText
            )
            .padding(.horizontal, 14)
            .frame(height: 35)
            .background(
                emphasis == .primary
                    ? Chamfer.Palette.ink
                    : Chamfer.Palette.canvasDeep.opacity(0.72)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if emphasis == .quiet {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            Chamfer.Palette.barStroke.opacity(0.62),
                            lineWidth: 1
                        )
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.50)
            .animation(Chamfer.Motion.quick, value: configuration.isPressed)
            .animation(Chamfer.Motion.quick, value: isEnabled)
        }
    }
}
