import ChamferCore
import SwiftUI

// MARK: - Controls

/// A menu that reads as a line of the page rather than as a system popup.
struct ChamferMenuPicker<Value: Hashable>: View {
    @State private var isHovered = false

    let selection: Value
    let options: [(value: Value, title: String)]
    let onSelect: (Value) -> Void

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? "—"
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.title) {
                    Haptics.commit()
                    onSelect(option.value)
                }
            }
        } label: {
            HStack(spacing: Chamfer.Space.tight) {
                Text(currentTitle)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
            }
            .padding(.horizontal, Chamfer.Space.snug)
            .padding(.vertical, Chamfer.Space.tight + 1)
            .background(isHovered ? Chamfer.Palette.paperSunken : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous))
            .chamferHoverRing(isHovered, radius: Chamfer.Radius.small)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
    }
}

/// A switch in the app's own vocabulary: the knob slides, nothing recolours
/// beyond the track, and it settles on a spring like everything else.
struct ChamferToggle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            Haptics.commit()
            onChange(!isOn)
        } label: {
            Capsule()
                .fill(isOn ? Chamfer.Palette.ink : Chamfer.Palette.paperSunken)
                .frame(width: 30, height: 18)
                .overlay(
                    Circle()
                        .fill(Chamfer.Palette.paper)
                        .padding(2)
                        .frame(width: 18, height: 18)
                        .offset(x: isOn ? 6 : -6)
                )
                .overlay(
                    Capsule().strokeBorder(Chamfer.Palette.paperStroke, lineWidth: isOn ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: isOn
        )
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Rows

/// One setting: what it is, what it is set to, and — when this level did not
/// choose it — where the value came from and how to take it over.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    /// Nil at the root, where nothing is inherited.
    var inheritedFrom: String?
    var isOverridden: Bool = false
    var onReset: (() -> Void)?
    @ViewBuilder let control: Control

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.regular) {
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(title)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                if let detail {
                    Text(detail)
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let inheritedFrom, !isOverridden {
                    Text("From \(inheritedFrom).")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                }
            }

            Spacer(minLength: Chamfer.Space.regular)

            if isOverridden, let onReset {
                Button("Reset") {
                    Haptics.commit()
                    onReset()
                }
                .buttonStyle(ChamferButtonStyle(.quiet))
                .opacity(isHovered ? 1 : 0)
            }

            control
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Scoped editor

/// The configuration editor, scoped to a vault or a folder.
///
/// The same rows appear in Settings for the global defaults — that is the
/// point. One editor used at three scopes is why the hierarchy does not need
/// three pages to express it.
struct PolicyEditor: View {
    let resolved: ResolvedPolicy
    let override: PolicyOverride
    /// What this level falls back to, named for the user: "your defaults",
    /// "this vault".
    let inheritedFrom: String
    let onChange: (PolicyOverride) -> Void

    @State private var showingPreservation = false

    private var policy: RewritePolicy { resolved.policy }

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            SettingRow(
                title: PolicyField.mode.title,
                detail: policy.mode.summary,
                inheritedFrom: inheritedFrom,
                isOverridden: override.mode != nil,
                onReset: { change { $0.mode = nil } }
            ) {
                ChamferMenuPicker(
                    selection: policy.mode,
                    options: RewriteMode.allCases.map { ($0, $0.title) }
                ) { mode in
                    change { $0.mode = mode }
                }
            }

            SettingRow(
                title: PolicyField.application.title,
                detail: policy.application.detail,
                inheritedFrom: inheritedFrom,
                isOverridden: override.application != nil,
                onReset: { change { $0.application = nil } }
            ) {
                ChamferMenuPicker(
                    selection: policy.application,
                    options: RewriteApplication.allCases.map { ($0, $0.title) }
                ) { application in
                    change { $0.application = application }
                }
            }

            SettingRow(
                title: PolicyField.inactivityDelay.title,
                detail: "How long a note must sit unchanged before Chamfer works on it.",
                inheritedFrom: inheritedFrom,
                isOverridden: override.inactivityDelay != nil,
                onReset: { change { $0.inactivityDelay = nil } }
            ) {
                ChamferMenuPicker(
                    selection: policy.inactivityDelay,
                    options: PolicyEditorChoices.delays
                ) { delay in
                    change { $0.inactivityDelay = delay }
                }
            }

            SettingRow(
                title: PolicyField.sweep.title,
                detail: "A sweep catches notes that never go quiet.",
                inheritedFrom: inheritedFrom,
                isOverridden: override.sweep != nil,
                onReset: { change { $0.sweep = nil } }
            ) {
                ChamferMenuPicker(
                    selection: policy.sweep,
                    options: SweepSchedule.choices.map { ($0, $0.title) }
                ) { sweep in
                    change { $0.sweep = sweep }
                }
            }

            PreservationSection(
                preserved: policy.preserved,
                isOverridden: override.preserved != nil,
                inheritedFrom: inheritedFrom,
                isExpanded: $showingPreservation,
                onChange: { structure in change { $0.preserved = structure } },
                onReset: { change { $0.preserved = nil } }
            )
        }
    }

    private func change(_ edit: (inout PolicyOverride) -> Void) {
        var next = override
        edit(&next)
        onChange(next)
    }
}

enum PolicyEditorChoices {
    static let delays: [(value: TimeInterval, title: String)] = [
        (60, "1 minute"),
        (300, "5 minutes"),
        (600, "10 minutes"),
        (1_800, "30 minutes"),
        (3_600, "1 hour")
    ]
}

// MARK: - Preservation

/// The nine Markdown structures, kept behind a disclosure.
///
/// Collapsed it is one line saying how much is protected; opened it is the
/// full list. Nine switches permanently on the page would be the single
/// biggest thing crowding it, and most people will never change them.
struct PreservationSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let preserved: MarkdownStructure
    var isOverridden: Bool = false
    var inheritedFrom: String?
    @Binding var isExpanded: Bool
    let onChange: (MarkdownStructure) -> Void
    var onReset: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            SettingRow(
                title: PolicyField.preserved.title,
                detail: summary,
                inheritedFrom: inheritedFrom,
                isOverridden: isOverridden,
                onReset: onReset
            ) {
                Button(isExpanded ? "Hide" : "Change") {
                    Haptics.pop()
                    withAnimation(
                        Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion)
                    ) {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(ChamferButtonStyle(.secondary))
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
                    ForEach(MarkdownStructure.ordered, id: \.structure.rawValue) { item in
                        HStack(spacing: Chamfer.Space.regular) {
                            Text(item.title)
                                .font(Chamfer.TypeScale.body)
                                .foregroundStyle(Chamfer.Palette.textOnPaper)
                            Spacer(minLength: 0)
                            ChamferToggle(isOn: preserved.contains(item.structure)) { isOn in
                                var next = preserved
                                if isOn {
                                    next.insert(item.structure)
                                } else {
                                    next.remove(item.structure)
                                }
                                onChange(next)
                            }
                        }
                    }

                    Text("If a rewrite would break one of these, Chamfer discards it and leaves the note alone.")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Chamfer.Space.tight)
                }
                .padding(.leading, Chamfer.Space.regular)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var summary: String {
        let count = MarkdownStructure.ordered.filter { preserved.contains($0.structure) }.count
        switch count {
        case 0: return "Nothing is protected. Rewrites may restructure anything."
        case MarkdownStructure.ordered.count: return "Everything is protected."
        default: return "Protecting \(count) of \(MarkdownStructure.ordered.count): \(preserved.titles.map { $0.lowercased() }.joined(separator: ", "))."
        }
    }
}
