import ChamferCore
import SwiftUI

/// The global defaults, in their own window.
///
/// Everything here is what a vault inherits when it has no opinion of its own,
/// which is why it is not a page in the main window: the main window is for
/// notes and what is happening to them, and a settings page competing with
/// them for the same single-page slot is what would make the app feel full.
/// Command-comma, native convention, styled in the app's own language so it
/// does not read as bolted on.
public struct SettingsView: View {
    @Binding var policy: RewritePolicy
    @Binding var preferences: AppPreferences

    @State private var section = Section.rewriting
    @State private var showingPreservation = false

    public init(policy: Binding<RewritePolicy>, preferences: Binding<AppPreferences>) {
        _policy = policy
        _preferences = preferences
    }

    enum Section: String, CaseIterable, Identifiable {
        case rewriting
        case privacy
        case notifications

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rewriting: "Rewriting"
            case .privacy: "Privacy"
            case .notifications: "Notifications"
            }
        }

        var symbol: String {
            switch self {
            case .rewriting: "wand.and.stars"
            case .privacy: "lock"
            case .notifications: "bell"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabs
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch section {
                    case .rewriting: rewriting
                    case .privacy: privacy
                    case .notifications: notifications
                    }
                }
                .padding(Chamfer.Space.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(
            width: Chamfer.SettingsWindow.width,
            height: Chamfer.SettingsWindow.height
        )
        .background(Chamfer.Palette.canvas)
    }

    private var tabs: some View {
        HStack(spacing: Chamfer.Space.snug) {
            ForEach(Section.allCases) { candidate in
                SettingsTab(
                    section: candidate,
                    isSelected: candidate == section
                ) {
                    Haptics.pop()
                    section = candidate
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Chamfer.Space.section)
        .padding(.vertical, Chamfer.Space.regular)
        .background(Chamfer.Palette.canvasDeep)
    }

    // MARK: Rewriting

    private var rewriting: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            SettingsHeading(
                title: "Defaults",
                detail: "Every vault starts from these. A vault or folder can depart from any of them without affecting the rest."
            )

            SettingRow(
                title: PolicyField.mode.title,
                detail: policy.mode.summary
            ) {
                ChamferMenuPicker(
                    selection: policy.mode,
                    options: RewriteMode.allCases.map { ($0, $0.title) }
                ) { policy.mode = $0 }
            }

            SettingRow(
                title: PolicyField.application.title,
                detail: policy.application.detail
            ) {
                ChamferMenuPicker(
                    selection: policy.application,
                    options: RewriteApplication.allCases.map { ($0, $0.title) }
                ) { policy.application = $0 }
            }

            if policy.application == .automatic {
                InlineFact(
                    symbol: "exclamationmark.triangle",
                    text: "This applies rewrites to every vault that hasn't chosen otherwise. A snapshot is taken before each one, and anything applied can be undone from Review."
                )
            }

            SettingRow(
                title: PolicyField.inactivityDelay.title,
                detail: "How long a note must sit unchanged before Chamfer works on it."
            ) {
                ChamferMenuPicker(
                    selection: policy.inactivityDelay,
                    options: PolicyEditorChoices.delays
                ) { policy.inactivityDelay = $0 }
            }

            SettingRow(
                title: PolicyField.sweep.title,
                detail: "A sweep catches notes that never go quiet."
            ) {
                ChamferMenuPicker(
                    selection: policy.sweep,
                    options: SweepSchedule.choices.map { ($0, $0.title) }
                ) { policy.sweep = $0 }
            }

            PreservationSection(
                preserved: policy.preserved,
                isExpanded: $showingPreservation,
                onChange: { policy.preserved = $0 }
            )
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            SettingsHeading(
                title: "Where your notes are processed",
                detail: "Model selection lives on the Models page. This is the limit that sits over it."
            )

            SettingRow(
                title: "Keep everything on this device",
                detail: "Cloud models are refused, whatever a vault or folder asks for."
            ) {
                ChamferToggle(isOn: preferences.localProcessingOnly) {
                    preferences.localProcessingOnly = $0
                }
            }

            SettingRow(
                title: PolicyField.fallbackModel.title,
                detail: fallbackDetail
            ) {
                ChamferMenuPicker(
                    selection: policy.fallbackModelID ?? "",
                    options: [
                        ("", "None"),
                        ("apple.foundation", "Apple on-device"),
                        ("local.ollama", "Local model"),
                        ("cloud.sonnet", "Cloud model")
                    ]
                ) { policy.fallbackModelID = $0.isEmpty ? nil : $0 }
            }

            if let fallback = policy.fallbackModelID,
               ProcessingGuard.isCloud(fallback),
               !preferences.localProcessingOnly {
                InlineFact(
                    symbol: "cloud",
                    text: "This fallback sends note contents off the device when it runs. It is always recorded in the rewrite's details and in history."
                )
            }

            if preferences.localProcessingOnly,
               let fallback = policy.fallbackModelID,
               ProcessingGuard.isCloud(fallback) {
                InlineFact(
                    symbol: "lock",
                    text: "This fallback is switched off while everything is kept on-device. Rewrites that need it will report as failed rather than run in the cloud."
                )
            }
        }
    }

    private var fallbackDetail: String {
        policy.fallbackModelID == nil
            ? "Nothing is tried when the selected model fails. Rewrites report the failure and wait."
            : "Tried only when the selected model is unavailable or fails."
    }

    // MARK: Notifications

    private var notifications: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            SettingsHeading(
                title: "What Chamfer tells you about",
                detail: "Each of these is independent."
            )

            ForEach(NotificationCategory.allCases) { category in
                SettingRow(
                    title: category.title,
                    detail: category.detail
                ) {
                    ChamferToggle(isOn: preferences.notifies(about: category)) { enabled in
                        preferences.setNotification(category, enabled: enabled)
                    }
                }
            }

            Divider().overlay(Chamfer.Palette.paperStroke)

            SettingRow(
                title: "Open at login",
                detail: "Chamfer watches your notes whenever it is running, and stops entirely when you quit it."
            ) {
                ChamferToggle(isOn: preferences.launchAtLogin) {
                    preferences.launchAtLogin = $0
                }
            }
        }
    }
}

// MARK: - Parts

private struct SettingsHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
            Text(title)
                .font(Chamfer.TypeScale.display)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
            Text(detail)
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, Chamfer.Space.snug)
    }
}

private struct SettingsTab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

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
            .padding(.vertical, Chamfer.Space.snug - 1)
            .background(isSelected ? Chamfer.Palette.ink : (isHovered ? Chamfer.Palette.hoverTint : .clear))
            .clipShape(Capsule())
            .chamferHoverRing(isHovered && !isSelected, radius: Chamfer.Radius.pill)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: isSelected
        )
    }
}
