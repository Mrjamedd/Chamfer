import SwiftUI

struct ModelsConfigurationSheet: View {
    @State private var closeHovered = false

    @Binding var state: ModelsLandscapeState
    let appleAvailable: Bool
    @Binding var serverAddress: String
    @Binding var ollamaModel: String
    let onClose: () -> Void
    let onActivate: () -> Void
    let onTestConnection: () -> Void
    let onDownload: () -> Void

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
                }
                .buttonStyle(.plain)
                .chamferHoverRingCircle(closeHovered)
                .onHover { closeHovered = $0 }
                .accessibilityLabel("Close model configuration")
            }
            .padding(.bottom, 14)

            if let expanded = state.expanded {
                Group {
                    switch expanded {
                    case .apple:
                        applePanel
                    case .ollama:
                        ollamaPanel
                    case .mlx:
                        mlxPanel
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(Chamfer.Palette.paper.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(
                            Chamfer.Palette.paperStroke.opacity(0.76),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color(red: 0.31, green: 0.21, blue: 0.10).opacity(0.12),
                    radius: 28,
                    y: 18
                )
                .shadow(
                    color: Color(red: 0.31, green: 0.21, blue: 0.10).opacity(0.07),
                    radius: 8,
                    y: 4
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

    private var ollamaPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelsSheetHeading(index: "02 — LOCAL SERVER", title: "Ollama") {
                ModelsSheetBadge(
                    text: connectionLabel,
                    color: connectionColor,
                    showsDot: true
                )
            }

            ModelsFieldRow(label: "Server address") {
                TextField("Server address", text: $serverAddress)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(ModelsFieldBackground())
            }
            .padding(.top, 16)

            ModelsFieldRow(label: "Model") {
                Picker("Model", selection: $ollamaModel) {
                    Text("Qwen3.5 9B").tag("Qwen3.5 9B")
                    Text("Llama 3.2 3B").tag("Llama 3.2 3B")
                    Text("Mistral Small 3.1").tag("Mistral Small 3.1")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .background(ModelsFieldBackground())
            }

            HStack(spacing: 10) {
                Button(
                    state.connection == .testing ? "Testing…" : "Test Connection",
                    action: onTestConnection
                )
                .buttonStyle(ModelsSheetButtonStyle(.quiet))
                .disabled(state.connection == .testing)

                Spacer()

                Button("Use This Model", action: onActivate)
                    .buttonStyle(ModelsSheetButtonStyle(.primary))
            }
            .padding(.top, 18)
        }
    }

    private var mlxPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelsSheetHeading(index: "03 — BUNDLED RUNTIME", title: "Bundled MLX") {
                ModelsSheetBadge(text: "2.1 GB", color: nil, showsDot: false)
            }

            HStack(spacing: 14) {
                ModelsPackageSymbol()
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECOMMENDED MODEL")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.70))
                    Text("Qwen3.5 4B · MLX")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Chamfer.Palette.pageText)
                    Text("Balanced for quick cleanup and longer notes")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .background(ModelsInsetSurface(radius: 14))
            .padding(.top, 16)

            VStack(spacing: 9) {
                HStack {
                    Text("INSTALLATION")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.70))
                    Spacer()
                    Text(installationLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Chamfer.Palette.pageText)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Chamfer.Palette.paperStroke.opacity(0.60))
                        Capsule()
                            .fill(progressFill)
                            .frame(width: proxy.size.width * installationProgress)
                    }
                }
                .frame(height: 2)
                .animation(Chamfer.Motion.navigation, value: state.installation)
            }
            .padding(13)
            .background(ModelsInsetSurface(radius: 13))
            .padding(.top, 10)

            HStack {
                Spacer()
                Button(downloadButtonTitle, action: onDownload)
                    .buttonStyle(ModelsSheetButtonStyle(.primary))
                    .disabled(state.installation == .downloading)
            }
            .padding(.top, 18)
        }
    }

    private var connectionLabel: String {
        switch state.connection {
        case .connected: "Connected"
        case .testing: "Testing…"
        case .failed: "Unavailable"
        }
    }

    private var connectionColor: Color {
        switch state.connection {
        case .connected: Chamfer.Palette.positive
        case .testing: Chamfer.Palette.brass
        case .failed: Chamfer.Palette.danger
        }
    }

    private var installationLabel: String {
        switch state.installation {
        case .notInstalled: "2.1 GB download"
        case .downloading: "Downloading securely…"
        case .installed: "Ready on this Mac"
        }
    }

    private var installationProgress: CGFloat {
        switch state.installation {
        case .notInstalled: 0
        case .downloading: 0.78
        case .installed: 1
        }
    }

    private var progressFill: LinearGradient {
        LinearGradient(
            colors: state.installation == .installed
                ? [Chamfer.Palette.positive, Chamfer.Palette.positive]
                : [
                    Color(red: 0.67, green: 0.57, blue: 0.82),
                    Color(red: 0.85, green: 0.55, blue: 0.40)
                ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var downloadButtonTitle: String {
        switch state.installation {
        case .notInstalled: "Download Model"
        case .downloading: "Downloading…"
        case .installed: "Use This Model"
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
