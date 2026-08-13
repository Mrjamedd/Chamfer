import ChamferCore
import SwiftUI

/// App-wide privacy, notification and vault-reset controls, in their own window.
///
/// Vault rewrite behaviour is intentionally absent: each connected vault owns
/// all of its choices and inherits nothing from here. Keeping these truly
/// global controls outside the main window leaves that window for notes and
/// what is happening to them.
/// Command-comma, native convention, styled in the app's own language so it
/// does not read as bolted on.
public struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var preferences: AppPreferences

    @LegacyState private var section: Section
    @LegacyState private var showingClearConfirmation = false
    @LegacyState private var clearStatus: String?

    /// Set when macOS refused to register the login item — most often because
    /// it needs approving in System Settings. A toggle that silently does
    /// nothing is worse than one that says why.
    private let launchAtLoginNote: String?
    private let vaultSettingsCount: Int
    private let clearAllVaultSettings: @MainActor () -> String?

    public init(
        preferences: Binding<AppPreferences>,
        section: Section = .privacy,
        launchAtLoginNote: String? = nil,
        vaultSettingsCount: Int = 0,
        clearAllVaultSettings: @escaping @MainActor () -> String? = { nil }
    ) {
        _preferences = preferences
        _section = State(initialValue: section)
        self.launchAtLoginNote = launchAtLoginNote
        self.vaultSettingsCount = vaultSettingsCount
        self.clearAllVaultSettings = clearAllVaultSettings
    }

    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case privacy
        case notifications
        case vaults

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .privacy: "Privacy"
            case .notifications: "Notifications"
            case .vaults: "Vaults"
            }
        }

        var symbol: String {
            switch self {
            case .privacy: "lock"
            case .notifications: "bell"
            case .vaults: "folder.badge.gearshape"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabs
            content
        }
        .frame(width: Chamfer.SettingsWindow.width)
        // The page surface, not the canvas it would float on. This window is
        // the sheet of paper rather than something laid on top of one, so
        // there is nothing here for a canvas to be behind — and every colour
        // the type uses is a `textOnPaper` already.
        .background(Chamfer.Palette.page)
        .chamferHidesTitleBar()
        .navigationTitle("Chamfer Settings")
        .confirmationDialog(
            "Clear all vault settings?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Vault Settings", role: .destructive) {
                Haptics.commit()
                clearStatus = clearAllVaultSettings()
                    ?? "Vault settings cleared. Your vaults remain connected."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This clears rewrite behavior, schedules, preservation choices, rules, and pending reviews for every vault. Connections, AI configuration, note files, snapshots, and history are preserved."
            )
        }
    }

    /// Sized to what is in it rather than to a number.
    ///
    /// This was a fixed height with a scroll view inside, which meant the short
    /// tabs ended in a field of empty paper and the long one scrolled — two
    /// different failures from the same decision. The window now grows and
    /// shrinks with its contents the way System Settings does, so every tab
    /// ends where its last row does.
    private var content: some View {
        Group {
            switch section {
            case .privacy: privacy
            case .notifications: notifications
            case .vaults: vaultSettings
            }
        }
        .padding(Chamfer.Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // Switching section is a change of subject, not a navigation: the
        // window does not move and neither should its contents. A cross-fade is
        // also what the reduced-motion curve already is, so the two branches
        // differ only in duration.
        .id(section)
        .transition(.opacity)
    }

    /// The header band: cream above the paper, closed off with the same
    /// hairline that divides anything from anything else in this app. Without
    /// the rule the strip read as the page's top padding happening to be a
    /// different colour.
    private var tabs: some View {
        HStack(spacing: Chamfer.Space.snug) {
            ForEach(Section.allCases) { candidate in
                SettingsTab(
                    section: candidate,
                    isSelected: candidate == section
                ) {
                    guard candidate != section else { return }
                    Haptics.pop()
                    withAnimation(
                        Chamfer.Motion.reduce(
                            Chamfer.Motion.interactive,
                            when: reduceMotion
                        )
                    ) {
                        section = candidate
                    }
                }
            }
            Spacer(minLength: 0)
        }
        // Inset by the capsule's own padding, so the first tab's *label* lands
        // on the same margin as the content below it rather than 12pt inside
        // it. The capsule bleeds past that line when selected, which is what a
        // selected row is supposed to do.
        .padding(.horizontal, Chamfer.Space.section - Chamfer.Space.regular)
        .padding(.bottom, Chamfer.Space.regular)
        // Clearance for the traffic lights, which now sit over this band
        // rather than in a white strip above it.
        .padding(.top, Chamfer.SettingsWindow.titleBarClearance)
        .background(Chamfer.Palette.canvasDeep)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Chamfer.Palette.paperStroke)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            ConfigurationGroup(
                title: "Where your notes are processed",
                caption: "Model selection lives on the Models page. This is the limit that sits over it.",
                symbol: "lock"
            ) {
                SettingRow(
                    title: "Keep everything on this device",
                    detail: "Cloud models are refused, whatever a vault or folder asks for."
                ) {
                    optionalChoice(
                        preferences.localProcessingOnly,
                        label: "Keep everything on this device"
                    ) { preferences.localProcessingOnly = $0 }
                }

                if preferences.localProcessingOnly == true {
                    InlineFact(
                        symbol: "lock",
                        text: "A vault set to the cloud model reports as failed rather than running there. The local model is unaffected — it never leaves this Mac in the first place."
                    )
                }
            }
        }
    }

    // MARK: Notifications

    private var notifications: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            ConfigurationGroup(
                title: "What Chamfer tells you about",
                caption: "Each of these is independent.",
                symbol: "bell"
            ) {
                ForEach(NotificationCategory.allCases) { category in
                    SettingRow(
                        title: category.title,
                        detail: category.detail
                    ) {
                        optionalChoice(
                            preferences.notificationChoice(for: category),
                            label: category.title
                        ) { choice in
                            guard let enabled = choice else {
                                preferences.clearNotificationChoice(category)
                                return
                            }
                            preferences.setNotification(category, enabled: enabled)
                        }
                    }
                }
            }

            ConfigurationGroup(
                title: "When Chamfer runs",
                caption: "Chamfer watches your notes for as long as it is running, and stops entirely when you quit it.",
                symbol: "power"
            ) {
                SettingRow(
                    title: "Open at login",
                    detail: "Start watching as soon as you log in, without opening the window."
                ) {
                    optionalChoice(preferences.launchAtLogin, label: "Open at login") {
                        preferences.launchAtLogin = $0
                    }
                }

                if let launchAtLoginNote {
                    InlineFact(symbol: "exclamationmark.triangle", text: launchAtLoginNote)
                }
            }
        }
    }

    // MARK: Vault reset

    private var vaultSettings: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            ConfigurationGroup(
                title: "Reset vault behavior",
                caption: "Keep every vault connected while removing the choices that control how Chamfer processes it.",
                symbol: "arrow.counterclockwise"
            ) {
                SettingRow(
                    title: "Clear all vault settings",
                    detail: vaultSettingsCount == 0
                        ? "No vault currently has processing settings."
                        : "Clears stored processing settings from \(vaultSettingsCount.formatted()) vault\(vaultSettingsCount == 1 ? "" : "s")."
                ) {
                    Button("Clear All Vault Settings", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .buttonStyle(ChamferButtonStyle(.quiet))
                    .disabled(vaultSettingsCount == 0)
                }

                InlineFact(
                    symbol: "checkmark.shield",
                    text: "Vault connections, model and provider settings, API keys, notes, snapshots, and history are never cleared by this action."
                )

                if let clearStatus {
                    let succeeded = clearStatus.hasPrefix("Vault settings cleared")
                    InlineFact(
                        symbol: succeeded
                            ? "checkmark.circle"
                            : "exclamationmark.triangle",
                        tint: succeeded
                            ? Chamfer.Palette.positive
                            : Chamfer.Palette.danger,
                        text: clearStatus
                    )
                }
            }
        }
    }

    private func optionalChoice(
        _ choice: Bool?,
        label: String,
        onChange: @escaping (Bool?) -> Void
    ) -> some View {
        ChamferMenuPicker(
            selection: choice.map { $0 ? "on" : "off" } ?? "",
            options: [
                ("", "Not configured"),
                ("on", "On"),
                ("off", "Off")
            ],
            label: label
        ) { selection in
            onChange(selection.isEmpty ? nil : selection == "on")
        }
    }
}

private struct SettingsTab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var isHovered = false

    let section: SettingsView.Section
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Chamfer.Space.tight + 2) {
                Image(systemName: section.symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(section.title)
                    .font(Chamfer.TypeScale.bodyStrong)
            }
            .foregroundStyle(
                isSelected ? Chamfer.Palette.textOnInk : Chamfer.Palette.textOnPaper
            )
            .padding(.horizontal, Chamfer.Space.regular)
            .frame(height: Chamfer.Control.compactFieldHeight)
            .background(isSelected ? Chamfer.Palette.ink : (isHovered ? Chamfer.Palette.hoverTint : .clear))
            .clipShape(Capsule())
            .chamferHoverRing(isHovered && !isSelected, radius: Chamfer.Radius.pill)
            .contentShape(Capsule())
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
        .buttonStyle(.plain)
        .chamferFocusable(radius: Chamfer.Radius.pill)
        .onHover { isHovered = $0 }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: isSelected
        )
        // Which tab is open is carried entirely by an ink capsule, which
        // VoiceOver cannot see. Said outright, along with the trait that makes
        // the rotor treat these three as a group of choices.
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
