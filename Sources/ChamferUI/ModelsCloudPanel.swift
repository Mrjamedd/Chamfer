import ChamferRewrite
import SwiftUI

/// Cloud's configuration, which is the only configuration on this page that
/// needs form fields: a provider and a key that has to be validated.
///
/// It is a panel over the page rather than a third column, because it is the
/// secondary path and giving it permanent room would be the old hierarchy back
/// again. It arrives out of the cloud strip and returns into it.
struct ModelsCloudPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var closeHovered = false

    @Binding var state: ModelsDashboardState
    @Binding var provider: CloudProvider?
    @Binding var credential: String
    let errorMessage: String?
    let isWorking: Bool
    let onClose: () -> Void
    let onConnect: () -> Void
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            intro
            fields
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cloud model settings")
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack {
            Text("CLOUD MODEL")
                .font(Chamfer.TypeScale.eyebrow)
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.68))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Chamfer.Palette.canvasDeep.opacity(0.68))
                    .clipShape(Circle())
                    // The smallest target in the panel, and one of only two
                    // ways out of it. Padding out and back in gives it a 44pt
                    // reach while leaving the header's layout untouched.
                    .padding(8)
                    .contentShape(Rectangle())
                    .padding(-8)
            }
            .buttonStyle(.plain)
            .chamferFocusableCircle()
            .chamferHoverRingCircle(closeHovered)
            .onHover { closeHovered = $0 }
            .accessibilityLabel("Close cloud model settings")
        }
        .padding(.bottom, 12)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                Text("Cloud Model")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .tracking(-0.65)
                    .foregroundStyle(Chamfer.Palette.pageText)
                Spacer(minLength: 0)
                ModelsStatusBadge(text: connectionLabel, tone: connectionTone)
            }

            Text(
                "A larger model than this Mac can hold, on your own provider "
                    + "account. Note contents leave this Mac while it runs — "
                    + "the local model remains Chamfer’s default."
            )
            .font(.system(size: 13, design: .serif))
            .foregroundStyle(Chamfer.Palette.pageTextSoft)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 14)
    }

    private var fields: some View {
        VStack(spacing: 0) {
            ModelsFieldRow(label: "Provider") {
                ChamferMenuPicker(
                    selection: provider,
                    options: [(nil, "Not configured")]
                        + CloudProvider.allCases.map {
                            (Optional($0), $0.displayName)
                        },
                    label: "Provider"
                ) { provider = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Chamfer.Control.compactFieldHeight)
            }

            ModelsFieldRow(label: "API key") {
                SecureField(
                    state.connection == .connected
                        ? "Stored securely in Keychain"
                        : "Paste provider key",
                    text: $credential
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, Chamfer.Space.snug + 2)
                .frame(height: Chamfer.Control.compactFieldHeight)
                .background(ModelsFieldBackground())
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
                .disabled(provider == nil)
                .onSubmit(submit)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text("Credentials stay in this Mac’s Keychain.")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.82))
                Spacer()
                Button(buttonTitle, action: submit)
                    .buttonStyle(ModelsPanelButtonStyle())
                    .disabled(buttonDisabled)
            }

            if let errorMessage {
                InlineNotice(
                    symbol: "exclamationmark.octagon.fill",
                    tone: .danger,
                    text: errorMessage
                )
            }
        }
        .padding(.top, 18)
    }

    private var surface: some View {
        ChamferCardSurface(
            tint: .models(.cloud),
            radius: Chamfer.Radius.card,
            presentation: .cloudPanel
        )
    }

    private var connectionLabel: String {
        switch state.connection {
        case .notConnected: "Not connected"
        case .connected: state.active == .cloud ? "Active" : "Connected"
        case .testing: "Connecting…"
        case .failed: "Unavailable"
        }
    }

    private var connectionTone: ModelsStatusBadge.Tone {
        switch state.connection {
        case .notConnected: .quiet
        case .connected: state.active == .cloud ? .active : .ready
        case .testing: .working
        case .failed: .danger
        }
    }

    private var buttonTitle: String {
        if state.connection == .testing || isWorking { return "Connecting…" }
        if state.connection == .connected {
            return state.active == .cloud ? "In Use" : "Use This Model"
        }
        return "Connect Provider"
    }

    private var buttonDisabled: Bool {
        provider == nil
            || state.connection == .testing
            || isWorking
            || (state.connection == .connected && state.active == .cloud)
    }

    private func submit() {
        guard !buttonDisabled else { return }
        if state.connection == .connected {
            onActivate()
        } else {
            onConnect()
        }
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
                .frame(width: 96, alignment: .leading)
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
        RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
            .fill(Chamfer.Palette.page)
            .overlay {
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                    .strokeBorder(
                        Chamfer.Palette.pageInsetStroke,
                        lineWidth: 1
                    )
            }
    }
}

private struct ModelsPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ModelsPanelButtonStyle.Configuration

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chamfer.Palette.paper)
                .padding(.horizontal, 14)
                .frame(height: 35)
                .background(Chamfer.Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
                .chamferFocusable(radius: 9)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.50)
                .animation(Chamfer.Motion.quick, value: configuration.isPressed)
                .animation(Chamfer.Motion.quick, value: isEnabled)
                .padding(Chamfer.Control.hitPadding(for: 35))
                .contentShape(Rectangle())
                .padding(-Chamfer.Control.hitPadding(for: 35))
        }
    }
}
