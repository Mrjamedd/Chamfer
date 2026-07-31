import ChamferCore
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

    var id: ModelsBackendID { backendID }

    static func all(
        runState: RunState,
        landscapeState: ModelsLandscapeState
    ) -> [Backend] {
        let appleAvailable: Bool
        if case .rewritingUnavailable = runState {
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
                detail: "Private, fast and built into macOS."
            ),
            Backend(
                backendID: .ollama,
                name: "Ollama",
                shortName: "Ollama",
                status: landscapeState.status(
                    for: .ollama,
                    appleAvailable: appleAvailable
                ),
                tone: tone(
                    for: .ollama,
                    appleAvailable: appleAvailable,
                    state: landscapeState
                ),
                detail: "Connect a larger local model running on your Mac."
            ),
            Backend(
                backendID: .mlx,
                name: "Bundled MLX",
                shortName: "Bundled MLX",
                status: landscapeState.status(
                    for: .mlx,
                    appleAvailable: appleAvailable
                ),
                tone: tone(
                    for: .mlx,
                    appleAvailable: appleAvailable,
                    state: landscapeState
                ),
                detail: "Download a model that works independently of Apple Intelligence."
            )
        ]
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

/// A calm, open landscape of the three local-model choices. DashboardView
/// keeps the existing page, bottom bar and floating close control around it;
/// this view owns only the expressive content layer inside that page.
struct ModelsPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let runState: RunState
    @Binding var state: ModelsLandscapeState

    @State private var serverAddress = "http://localhost:11434"
    @State private var ollamaModel = "Qwen3.5 9B"

    private var appleAvailable: Bool {
        if case .rewritingUnavailable = runState { return false }
        return true
    }

    private var backends: [Backend] {
        Backend.all(runState: runState, landscapeState: state)
    }

    private var landscapeAnimation: Animation {
        reduceMotion
            ? Chamfer.Motion.quick
            : .spring(duration: 0.46, bounce: 0.025)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                Chamfer.Palette.canvas

                ModelsAmbientField(selected: state.selected, size: size)

                ModelsPageHeader()
                    .padding(.top, 38)
                    .padding(.leading, 42)
                    .zIndex(4)

                ForEach(backends) { backend in
                    let placement = ModelsLandscapeLayout.placement(
                        for: backend.backendID,
                        state: state
                    )

                    ModelsZone(
                        backend: backend,
                        isActive: state.active == backend.backendID,
                        isSelected: state.selected == backend.backendID,
                        action: { select(backend.backendID) }
                    )
                    .position(
                        x: size.width * placement.x,
                        y: size.height * placement.y
                    )
                    .scaleEffect(placement.scale)
                    .opacity(placement.opacity)
                    .zIndex(state.selected == backend.backendID ? 3 : 2)
                    .animation(landscapeAnimation, value: placement)
                }

                if let expanded = state.expanded {
                    ModelsConfigurationSheet(
                        state: $state,
                        appleAvailable: appleAvailable,
                        serverAddress: $serverAddress,
                        ollamaModel: $ollamaModel,
                        onClose: closeConfiguration,
                        onActivate: activateSelected,
                        onTestConnection: testConnection,
                        onDownload: downloadBundledModel
                    )
                    .id(expanded)
                    .frame(width: min(470, size.width - 56))
                    .position(
                        x: size.width
                            * ModelsLandscapeLayout.sheetCenterX(for: expanded),
                        y: size.height * 0.66
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .offset(y: 18).combined(with: .opacity)
                    )
                    .zIndex(8)
                }

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
        }
        .background(Chamfer.Palette.canvas)
        .onExitCommand(perform: closeConfiguration)
    }

    private func select(_ backend: ModelsBackendID) {
        Haptics.pop()
        withAnimation(landscapeAnimation) {
            state.select(backend)
        }
    }

    private func closeConfiguration() {
        guard state.expanded != nil else { return }
        withAnimation(landscapeAnimation) {
            state.closeConfiguration()
        }
    }

    private func activateSelected() {
        Haptics.commit()
        withAnimation(landscapeAnimation) {
            state.activateSelected()
        }
    }

    private func testConnection() {
        withAnimation(Chamfer.Motion.quick) {
            state.beginConnectionTest()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(720))
            withAnimation(Chamfer.Motion.quick) {
                state.finishConnectionTest(connected: true)
            }
        }
    }

    private func downloadBundledModel() {
        if state.installation == .installed {
            activateSelected()
            return
        }

        withAnimation(Chamfer.Motion.quick) {
            state.beginDownload()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_350))
            withAnimation(landscapeAnimation) {
                state.finishDownload()
            }
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
    @State private var isHovered = false

    let backend: Backend
    let isActive: Bool
    let isSelected: Bool
    let action: () -> Void

    private var horizontalAlignment: HorizontalAlignment {
        switch backend.backendID {
        case .apple: .leading
        case .ollama: .trailing
        case .mlx: .center
        }
    }

    private var frameAlignment: Alignment {
        switch backend.backendID {
        case .apple: .leading
        case .ollama: .trailing
        case .mlx: .center
        }
    }

    private var title: String {
        backend.backendID == .apple
            ? "Apple Foundation\nModels"
            : backend.name
    }

    private var width: CGFloat {
        backend.backendID == .mlx ? 290 : 230
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: horizontalAlignment, spacing: 0) {
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
                                        : Chamfer.Palette.positiveSoft.opacity(0.78)
                                )
                        }
                    }
                    .padding(.bottom, 8)

                Text(title)
                    .font(
                        .system(
                            size: isActive ? 27 : 25,
                            weight: isActive ? .semibold : .regular,
                            design: .serif
                        )
                    )
                    .tracking(-0.75)
                    .multilineTextAlignment(textAlignment)
                    .foregroundStyle(
                        isActive
                            ? Chamfer.Palette.pageText
                            : Chamfer.Palette.pageText.opacity(0.88)
                    )
                    .lineSpacing(-3)
                    .padding(.bottom, 7)

                Text(backend.detail)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.88))
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                HStack(spacing: 6) {
                    Text("Configure")
                    Text("→")
                        .font(.system(size: 14))
                        .offset(x: isHovered ? 3 : 0)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.pageText.opacity(0.75))
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Chamfer.Palette.pageText.opacity(isHovered ? 0.55 : 0.24))
                        .frame(height: 1)
                }
            }
            .frame(width: width, alignment: frameAlignment)
            .contentShape(Rectangle())
            .background {
                Ellipse()
                    .fill(localGlow)
                    .frame(width: width + 70, height: 128)
                    .blur(radius: 30)
                    .opacity(isHovered || isSelected || isActive ? 0.48 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chamfer.Motion.interactive) {
                isHovered = hovering
            }
        }
        .animation(Chamfer.Motion.interactive, value: isHovered)
        .accessibilityLabel("\(backend.name), \(backend.status.lowercased())")
        .accessibilityHint("Opens model configuration")
    }

    private var statusForeground: Color {
        if backend.status == "UNAVAILABLE" { return Chamfer.Palette.danger }
        if isActive { return Chamfer.Palette.positive.opacity(0.86) }
        return Chamfer.Palette.pageTextSoft.opacity(0.72)
    }

    private var textAlignment: TextAlignment {
        switch backend.backendID {
        case .apple: .leading
        case .ollama: .trailing
        case .mlx: .center
        }
    }

    private var localGlow: Color {
        switch backend.backendID {
        case .apple: Color(red: 0.78, green: 0.89, blue: 0.72)
        case .ollama: Color(red: 0.94, green: 0.61, blue: 0.64)
        case .mlx: Color(red: 0.76, green: 0.67, blue: 0.88)
        }
    }
}

private struct ModelsAmbientField: View {
    let selected: ModelsBackendID
    let size: CGSize

    var body: some View {
        ZStack {
            ModelsBloom(
                color: Color(red: 0.74, green: 0.86, blue: 0.78),
                center: CGPoint(x: 0.05, y: 0.37),
                size: CGSize(width: 0.66, height: 0.54),
                inwardOffset: CGSize(width: 0.08, height: 0.03),
                focused: selected == .apple,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.96, green: 0.86, blue: 0.51),
                center: CGPoint(x: 0.35, y: 0.10),
                size: CGSize(width: 0.54, height: 0.46),
                inwardOffset: CGSize(width: 0.04, height: 0.05),
                focused: selected == .apple,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.94, green: 0.60, blue: 0.51),
                center: CGPoint(x: 0.95, y: 0.38),
                size: CGSize(width: 0.64, height: 0.54),
                inwardOffset: CGSize(width: -0.08, height: 0.03),
                focused: selected == .ollama,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.94, green: 0.67, blue: 0.78),
                center: CGPoint(x: 0.70, y: 0.09),
                size: CGSize(width: 0.52, height: 0.46),
                inwardOffset: CGSize(width: -0.04, height: 0.05),
                focused: selected == .ollama,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.72, green: 0.66, blue: 0.87),
                center: CGPoint(x: 0.34, y: 0.94),
                size: CGSize(width: 0.68, height: 0.54),
                inwardOffset: CGSize(width: 0.03, height: -0.08),
                focused: selected == .mlx,
                canvas: size
            )
            ModelsBloom(
                color: Color(red: 0.93, green: 0.66, blue: 0.43),
                center: CGPoint(x: 0.72, y: 0.91),
                size: CGSize(width: 0.62, height: 0.55),
                inwardOffset: CGSize(width: -0.03, height: -0.08),
                focused: selected == .mlx,
                canvas: size
            )
        }
        .compositingGroup()
        .blendMode(.multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.spring(duration: 0.62, bounce: 0.02), value: selected)
    }
}

private struct ModelsBloom: View {
    let color: Color
    let center: CGPoint
    let size: CGSize
    let inwardOffset: CGSize
    let focused: Bool
    let canvas: CGSize

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
                x: canvas.width * (center.x + (focused ? inwardOffset.width : 0)),
                y: canvas.height * (center.y + (focused ? inwardOffset.height : 0))
            )
            .scaleEffect(focused ? 1.10 : 1)
            .opacity(focused ? 0.62 : 0.43)
            .blur(radius: 48)
    }
}
