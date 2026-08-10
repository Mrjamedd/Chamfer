import ChamferCore
import SwiftUI

// MARK: - Controls

/// A menu that reads as a line of the page rather than as a system popup.
struct ChamferMenuPicker<Value: Hashable>: View {
    @LegacyState private var isHovered = false

    let selection: Value
    let options: [(value: Value, title: String)]
    /// What this menu is choosing. VoiceOver announced only the current value —
    /// "Full cleanup, pop up button" — with no hint of what it applied to.
    var label: String?
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
            .padding(.horizontal, Chamfer.Space.snug + 2)
            .padding(.vertical, Chamfer.Space.tight + 2)
            // A resting control rather than a word with a chevron after it.
            // On the inset surface these sit on, the lighter page colour is
            // what makes them read as something you can press.
            .background(
                isHovered ? Chamfer.Palette.paper : Chamfer.Palette.page
            )
            .clipShape(
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                    .strokeBorder(Chamfer.Palette.pageInsetStroke, lineWidth: 1)
            )
            .chamferHoverRing(isHovered, radius: Chamfer.Radius.small)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .accessibilityLabel(label ?? "Choose")
        .accessibilityValue(currentTitle)
    }
}

/// A switch in the app's own vocabulary: the knob slides, nothing recolours
/// beyond the track, and it settles on a spring like everything else.
struct ChamferToggle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isOn: Bool
    /// What is being switched. Without it VoiceOver reads "selected, button"
    /// and the user has to guess which of six rows they are on.
    var label: String?
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
        .accessibilityLabel(label ?? "Toggle")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityHint(isOn ? "Double tap to turn off" : "Double tap to turn on")
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

    @LegacyState private var isHovered = false

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

// MARK: - The vault's configuration

/// A quiet editorial heading inside the configuration.
///
/// Small tracked capitals and a hairline, which is the app's existing vocabulary
/// for dividing a page. Deliberately not a box: boxed groups are what a system
/// settings pane looks like, and five of them stacked in a card would read as a
/// form pasted into somebody else's app.
private struct ConfigurationGroup<Content: View>: View {
    let title: String
    /// One line saying what the group is for, so the rows beneath it do not
    /// each have to explain themselves. This is what stops the panel being a
    /// long flat column of description.
    let caption: String
    /// A thin monochrome mark, small enough to be read as punctuation on the
    /// heading rather than as an icon in its own right.
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                HStack(spacing: Chamfer.Space.tight + 2) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                        .frame(width: 12)
                    Text(title.uppercased())
                        .font(Chamfer.TypeScale.captionStrong)
                        .kerning(0.8)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                }
                Text(caption)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    // Aligned under the title rather than the icon, so the
                    // heading reads as one object with a mark in front of it.
                    .padding(.leading, 12 + Chamfer.Space.tight + 2)
            }

            content
        }
        .padding(.horizontal, Chamfer.Space.regular)
        .padding(.vertical, Chamfer.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A region set into the page rather than a card laid on it. One shade,
        // no border heavier than a hairline, and the same corner the rest of
        // the app uses — enough to gather what is on it and no more.
        .background(Chamfer.Palette.pageInset)
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
                .strokeBorder(Chamfer.Palette.pageInsetStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// How one vault is rewritten.
///
/// Grouped rather than listed. Every row edits a real value — there is no
/// inherited state, no "from your defaults" and no Reset, because the hierarchy
/// those expressed no longer exists.
struct PolicyEditor: View {
    let policy: VaultConfiguration
    let onChange: (VaultConfiguration) -> Void

    @LegacyState private var showingPreservation = false

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            ConfigurationGroup(
                title: "The rewrite",
                caption: "What Chamfer is allowed to change in a note here.",
                symbol: "pencil.line"
            ) {
                SettingRow(
                    title: PolicyField.mode.title,
                    detail: policy.mode?.summary ?? "Not configured."
                ) {
                    ChamferMenuPicker(
                        selection: policy.mode,
                        options: [(nil, "Not configured")]
                            + RewriteMode.allCases.map { (Optional($0), $0.title) },
                        label: PolicyField.mode.title
                    ) { mode in
                        change { $0.mode = mode }
                    }
                }
            }

            ConfigurationGroup(
                title: "What happens to it",
                caption: "Whether a finished rewrite waits for you or goes straight into the note.",
                symbol: "tray.and.arrow.down"
            ) {
                SettingRow(title: PolicyField.application.title) {
                    ChamferMenuPicker(
                        selection: policy.application,
                        options: [(nil, "Not configured")]
                            + RewriteApplication.allCases.map { (Optional($0), $0.title) },
                        label: PolicyField.application.title
                    ) { application in
                        change { $0.application = application }
                    }
                }

                if policy.application == .automatic {
                    InlineFact(
                        symbol: "wand.and.stars",
                        tint: Chamfer.Palette.attention,
                        text: "Notes in this vault are rewritten without being shown to you first. A snapshot is taken before each one, and anything applied can be undone from Review."
                    )
                }
            }

            ConfigurationGroup(
                title: "When it runs",
                caption: "Choose one trigger. Inactivity and scheduled sweeps are alternatives, so Chamfer will never run both for this vault.",
                symbol: "clock"
            ) {
                SettingRow(
                    title: "Run trigger",
                    detail: policy.runTrigger?.detail ?? "First choose what starts a rewrite."
                ) {
                    ChamferMenuPicker(
                        selection: policy.runTrigger,
                        options: [(nil, "Not configured")]
                            + VaultRunTrigger.allCases.map { (Optional($0), $0.title) },
                        label: "Run trigger"
                    ) { trigger in
                        change {
                            $0.runTrigger = trigger
                            switch trigger {
                            case .inactivity:
                                $0.sweep = nil
                            case .schedule:
                                $0.inactivityDelay = nil
                            case nil:
                                $0.inactivityDelay = nil
                                $0.sweep = nil
                            }
                        }
                    }
                }

                switch policy.runTrigger {
                case .inactivity:
                    SettingRow(title: "Quiet for") {
                        ChamferMenuPicker(
                            selection: policy.inactivityDelay,
                            options: [(nil, "Not configured")]
                                + PolicyEditorChoices.delays.map { (Optional($0.value), $0.title) },
                            label: PolicyField.inactivityDelay.title
                        ) { delay in
                            change { $0.inactivityDelay = delay }
                        }
                    }

                case .schedule:
                    SettingRow(title: PolicyField.sweep.title) {
                        ChamferMenuPicker(
                            selection: policy.sweep,
                            options: [(nil, "Not configured")]
                                + SweepSchedule.choices
                                    .filter { $0 != .never }
                                    .map { (Optional($0), $0.title) },
                            label: PolicyField.sweep.title
                        ) { sweep in
                            change { $0.sweep = sweep }
                        }
                    }

                case nil:
                    EmptyView()
                }
            }

            ConfigurationGroup(
                title: "What it leaves alone",
                caption: "Structures a rewrite may not disturb. If one would be broken, the rewrite is discarded and the note is untouched.",
                symbol: "shield"
            ) {
                PreservationSection(
                    preserved: policy.preserved,
                    isExpanded: $showingPreservation,
                    onChange: { structure in change { $0.preserved = structure } }
                )
            }
        }
    }

    private func change(_ edit: (inout VaultConfiguration) -> Void) {
        var next = policy
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

    let preserved: MarkdownStructure?
    var isOverridden: Bool = false
    var inheritedFrom: String?
    @Binding var isExpanded: Bool
    let onChange: (MarkdownStructure) -> Void
    var onReset: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            // The reveal is this slot growing under the row, not the block
            // arriving from somewhere else. The clip therefore has to be on the
            // slot, which stays put: a `.clipped()` applied to the block itself
            // travelled with the `.move` it was meant to be cutting, so it cut
            // nothing and the nine rows drew straight down over the control
            // that opened them.
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    structures
                        // The gap the row's spacing used to provide, moved
                        // inside the slot so a collapsed section is exactly as
                        // tall as it was before there was a slot at all.
                        .padding(.top, Chamfer.Space.regular)
                        .transition(.opacity)
                }
            }
            .clipped()
        }
    }

    /// The nine switches and the sentence under them.
    private var structures: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            HStack(spacing: Chamfer.Space.snug) {
                Button("Protect non-prose") {
                    onChange(.standard)
                }
                .buttonStyle(ChamferButtonStyle(.secondary))
                Button("Allow all changes") {
                    onChange([])
                }
                .buttonStyle(ChamferButtonStyle(.quiet))
            }

            ForEach(MarkdownStructure.ordered, id: \.structure.rawValue) { item in
                HStack(spacing: Chamfer.Space.regular) {
                    Text(item.title)
                        .font(Chamfer.TypeScale.body)
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                    Spacer(minLength: 0)
                    ChamferToggle(
                        isOn: preserved?.contains(item.structure) == true,
                        label: "Preserve \(item.title)"
                    ) { isOn in
                        var next = preserved ?? []
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
    }

    private var summary: String {
        guard let preserved else { return "Not configured." }
        let count = MarkdownStructure.ordered.filter { preserved.contains($0.structure) }.count
        switch count {
        case 0: return "Nothing is protected. Rewrites may restructure anything."
        case MarkdownStructure.ordered.count: return "Everything is protected."
        default: return "Protecting \(count) of \(MarkdownStructure.ordered.count): \(preserved.titles.map { $0.lowercased() }.joined(separator: ", "))."
        }
    }
}
