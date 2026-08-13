import ChamferCore
import SwiftUI

public struct VaultActions: Sendable {
    /// A note the user picked out of a vault, rather than one Chamfer chose
    /// for them. The previous shape took a `Vault` and left the view to guess
    /// which of its notes was meant.
    public var openNote: @MainActor (NoteSummary) -> Void
    /// The vault's whole configuration. Setting one for the first time is
    /// what takes a vault from watched-only to actually being worked on.
    public var updateConfiguration: @MainActor (UUID, VaultConfiguration) -> Void
    public var removeVault: @MainActor (UUID) -> Void
    /// Returns a local explanation when macOS refused lasting folder access.
    public var connectVault: @MainActor () -> String?
    public var reconnectVault: @MainActor (UUID) -> String?
    /// Raises the app target's native note picker and returns vault-relative
    /// paths. The UI target remains independent of AppKit.
    public var chooseExcludedNotes: @MainActor (Vault) -> [String]
    /// Exclusions and include-only rules, replaced wholesale.
    ///
    /// The whole set rather than add and remove verbs, because the two kinds
    /// interact — adding an include-only changes what every exclusion means —
    /// and a page that could only append would make that hard to reason about.
    public var updateRules: @MainActor (UUID, [VaultRule]) -> Void

    public init(
        openNote: @escaping @MainActor (NoteSummary) -> Void = { _ in },
        updateConfiguration: @escaping @MainActor (UUID, VaultConfiguration) -> Void = { _, _ in },
        removeVault: @escaping @MainActor (UUID) -> Void = { _ in },
        connectVault: @escaping @MainActor () -> String? = { nil },
        reconnectVault: @escaping @MainActor (UUID) -> String? = { _ in nil },
        chooseExcludedNotes: @escaping @MainActor (Vault) -> [String] = { _ in [] },
        updateRules: @escaping @MainActor (UUID, [VaultRule]) -> Void = { _, _ in }
    ) {
        self.openNote = openNote
        self.updateConfiguration = updateConfiguration
        self.removeVault = removeVault
        self.connectVault = connectVault
        self.reconnectVault = reconnectVault
        self.chooseExcludedNotes = chooseExcludedNotes
        self.updateRules = updateRules
    }
}

/// The connected note folders, and what each of them does differently.
///
/// This is the page where the scope is denser than the app's aesthetic wants,
/// so it is built on one rule: show difference, not state. A vault row carries
/// its name and whether it is reachable. Its settings are a sentence saying
/// what it does differently, and the full set is behind a disclosure. A vault
/// that is incomplete says exactly which choices are still missing.
struct VaultsPage: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let vaults: [Vault]
    /// Every note Chamfer has indexed. Filtered per vault when the picker
    /// opens, so the page does not have to hold a copy per row.
    var notes: [NoteSummary] = []
    var activeModelConfigured = false
    var actions = VaultActions()
    var onOpenModels: () -> Void = {}

    @LegacyState private var expanded: UUID?
    @LegacyState private var picking: Vault?
    @LegacyState private var connectionNotice: String?
    @FocusState private var notePickerTrigger: UUID?

    /// Opening a vault's settings is the card unfolding, not a page changing.
    ///
    /// Slightly longer and slightly springier than the app's navigation curve:
    /// there is real height arriving, and it should look like it has weight
    /// rather than appearing instantly. Restrained enough not to overshoot into
    /// something bouncy — the settle is the only thing you should notice.
    static let disclosure = Animation.spring(duration: 0.34, bounce: 0.08)

    var body: some View {
        Group {
            if vaults.isEmpty {
                emptyState
            } else {
                PageScroll(title: "Vaults", accessory: connectButton) {
                    VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                        if let connectionNotice {
                            InlineNotice(
                                symbol: "exclamationmark.triangle",
                                tone: .danger,
                                text: connectionNotice
                            )
                        }

                        ForEach(vaults) { vault in
                            VaultRowView(
                                vault: vault,
                                activeModelConfigured: activeModelConfigured,
                                isExpanded: expanded == vault.id,
                                onToggle: { toggle(vault) },
                                onOpen: { presentNotes(in: vault) },
                                openNoteFocus: $notePickerTrigger,
                                onRemove: { actions.removeVault(vault.id) },
                                onReconnect: { reconnect(vault.id) },
                                onConfigure: { actions.updateConfiguration(vault.id, $0) },
                                onChooseExcludedNotes: { actions.chooseExcludedNotes(vault) },
                                onOpenModels: onOpenModels,
                                onChangeRules: { actions.updateRules(vault.id, $0) }
                            )
                        }

                        Text("Each vault is set up on its own. Chamfer never changes a note in a vault you haven't configured.")
                            .font(Chamfer.TypeScale.caption)
                            .foregroundStyle(Chamfer.Palette.pageTextSoft)
                            .padding(.top, Chamfer.Space.snug)
                    }
                }
            }
        }
        .disabled(picking != nil)
        .overlay {
            if let vault = picking {
                VaultNotesSheet(
                    vaultName: vault.name,
                    notes: notes(in: vault),
                    onOpen: openNote,
                    onDismiss: { dismissNotes(restoringFocusTo: vault.id) }
                )
            }
        }
    }

    /// This vault's notes, by containment rather than by any stored vault id —
    /// a note knows where it lives, and that survives the vault being renamed
    /// underneath it.
    private func notes(in vault: Vault) -> [NoteSummary] {
        notes.filter {
            NoteEligibility.relativePath(of: $0.url, under: vault.url) != nil
        }
    }

    private var connectButton: AnyView? {
        AnyView(
            Button("Connect a vault") {
                Haptics.pop()
                connect()
            }
            .buttonStyle(ChamferButtonStyle(.secondary))
        )
    }

    private var emptyState: some View {
        VStack(spacing: Chamfer.Space.loose) {
            if let connectionNotice {
                InlineNotice(
                    symbol: "exclamationmark.triangle",
                    tone: .danger,
                    text: connectionNotice
                )
                .frame(maxWidth: Chamfer.Page.measure)
            }
            PageMessage(
                title: "No vaults yet",
                detail: "Point Chamfer at a folder of Markdown or plain-text notes and it will watch everything inside it, including subfolders.",
                actionTitle: "Connect a vault",
                action: connect
            )
        }
        .padding(Chamfer.Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connect() {
        connectionNotice = actions.connectVault()
    }

    private func reconnect(_ vaultID: UUID) {
        connectionNotice = actions.reconnectVault(vaultID)
    }

    private func toggle(_ vault: Vault) {
        Haptics.pop()
        expanded = expanded == vault.id ? nil : vault.id
    }

    private func presentNotes(in vault: Vault) {
        Haptics.pop()
        withAnimation(sheetArrivalAnimation) {
            picking = vault
        }
    }

    private func openNote(_ note: NoteSummary) {
        Haptics.commit()
        withAnimation(sheetDepartureAnimation) {
            picking = nil
        }
        actions.openNote(note)
    }

    private func dismissNotes(restoringFocusTo vaultID: UUID) {
        Haptics.commit()
        withAnimation(sheetDepartureAnimation) {
            picking = nil
        }
        notePickerTrigger = vaultID
    }

    private var sheetArrivalAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.sheetArrival, when: reduceMotion)
    }

    private var sheetDepartureAnimation: Animation {
        Chamfer.Motion.reduce(Chamfer.Motion.sheetDeparture, when: reduceMotion)
    }
}

// MARK: - One vault

private struct VaultRowView: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.chamferScanProgress) private var progress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let vault: Vault
    let activeModelConfigured: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let openNoteFocus: FocusState<UUID?>.Binding
    let onRemove: () -> Void
    let onReconnect: () -> Void
    let onConfigure: (VaultConfiguration) -> Void
    let onChooseExcludedNotes: () -> [String]
    let onOpenModels: () -> Void
    let onChangeRules: ([VaultRule]) -> Void

    @LegacyState private var isHovered = false


    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            // Everything the disclosure grows inside, clipped as one group.
            //
            // The clip needs something that stays put while the row's height
            // changes, which is what this group is — but it has to stop short
            // of `controls`. Every button down there wears its hover state as a
            // shadow drawn *outside* its own bounds, and `controls` sits on the
            // row's bottom edge, so a row-wide clip sliced those shadows flat
            // as they faded in. Same for the amber glow on an unconfigured
            // vault's button.
            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                header
                status
                unavailableNotice

                // What a vault does differently only means anything while it is
                // doing something. An unreachable one leads with the remedy.
                if isReachable {
                    settingsSentence
                }

                if isExpanded {
                    VaultSettingsDetail(
                        vault: vault,
                        activeModelConfigured: activeModelConfigured,
                        onConfigure: onConfigure,
                        onChooseExcludedNotes: onChooseExcludedNotes,
                        onOpenModels: onOpenModels,
                        onChangeRules: onChangeRules
                    )
                    // Unfolds from the top edge of its own slot rather than
                    // sliding in from above: it grows out of the row it belongs
                    // to, and the controls below are pushed down by it rather
                    // than jumped past. The `.move` it used to have drew the
                    // whole block over the row above for the length of the
                    // curve, which is what made opening read as a jump.
                    .transition(settingsTransition)
                }
            }
            // Keeps the unfolding block inside the row while it is still
            // smaller than its final size.
            .clipped()

            controls
        }
        // On the row, because the row's height is what changes. While this sat
        // on the page's outer Group it animated a container whose own size was
        // fixed, so the disclosure appeared fully formed and everything below
        // it snapped down.
        .animation(
            Chamfer.Motion.reduce(VaultsPage.disclosure, when: reduceMotion),
            value: isExpanded
        )
        .padding(Chamfer.Space.roomy)
        // The fill and stroke draw their own rounded bounds rather than
        // clipping the whole row. The controls deliberately sit outside the
        // disclosure clip above, and a second row-wide clip would flatten the
        // hover shadows and setup glow that extend beyond their labels.
        .background {
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
                .fill(Chamfer.Palette.pageInset)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
                .strokeBorder(Chamfer.Palette.pageInsetStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .opacity(isReachable ? 1 : 0.82)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // Availability is carried by a dimmed name and a coloured pill, neither
        // of which VoiceOver can see. Said outright here, first, because it is
        // the fact that decides whether anything else on the row matters.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isReachable
                ? "\(vault.name). \(statusText)"
                : "\(vault.name). \(vault.availability.title). \(vault.availability.remedy ?? "")"
        )
    }

    private var isReachable: Bool { vault.availability.isAvailable }

    private var settingsTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.97, anchor: .top)
                .combined(with: .opacity),
            removal: .opacity
        )
    }

    /// Attention belongs on the action only while there is an action to take.
    private var needsSetup: Bool { !vault.isConfigured && isReachable }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.snug) {
            Text(vault.name)
                .font(Chamfer.TypeScale.pageHeading)
                // A vault Chamfer cannot reach is not watching anything, and
                // the name is where that reads first. Dimmed rather than
                // recoloured: it is unavailable, not broken.
                .foregroundStyle(
                    isReachable
                        ? Chamfer.Palette.pageText
                        : Chamfer.Palette.pageTextSoft
                )
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Chamfer.Space.snug)

            if !isReachable {
                Pill(vault.availability.title, symbol: vault.availability.symbol, tone: .danger)
            }
        }
    }

    /// Path, note count and last sweep — the facts, in one line.
    ///
    /// The remedy deliberately does not live here. It used to be appended to
    /// the end of this single truncating line, where it was never read.
    private var status: some View {
        Text(statusText)
            .font(Chamfer.TypeScale.caption)
            .foregroundStyle(Chamfer.Palette.pageTextSoft)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var statusText: String {
        var parts = [vault.displayPath]

        if let progress, progress.vaultID == vault.id, !progress.isFinished {
            // A four-thousand-note vault takes several seconds to walk, and
            // "not swept yet" for the whole of it reads as nothing happening.
            parts.append(
                "sweeping \(progress.completed.formatted()) of \(progress.total.formatted())"
            )
            return parts.joined(separator: " · ")
        }

        parts.append("\(vault.noteCount.formatted()) notes")
        if isReachable {
            if let sweep = vault.lastSweep {
                parts.append("swept \(RelativeTime.string(sweep, since: now))")
            } else {
                parts.append("not swept yet")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// The one line that says what to do about it, on its own where it can be
    /// read, with the verb that matches the problem.
    @ViewBuilder
    private var unavailableNotice: some View {
        if let remedy = vault.availability.remedy {
            VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
                InlineFact(symbol: vault.availability.symbol, text: remedy)

                // Offline fixes itself when the disk comes back, so it gets no
                // button — one that did nothing would be worse than none.
                if vault.availability != .offline {
                    Button(reconnectTitle) {
                        Haptics.pop()
                        onReconnect()
                    }
                    .buttonStyle(ChamferButtonStyle(.secondary))
                }
            }
        }
    }

    private var reconnectTitle: String {
        switch vault.availability {
        case .permissionDenied: "Grant access…"
        case .missing: "Find this folder…"
        case .offline, .available: "Reconnect…"
        }
    }

    /// What this vault will do, or the fact that nobody has said yet.
    ///
    /// No longer a comparison against defaults, because there are none. A vault
    /// either states its own settings or states that it is waiting for them,
    /// and the second is the more important sentence: it is the reason nothing
    /// is happening.
    @ViewBuilder
    private var settingsSentence: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
            if let policy = vault.configuration, policy.isComplete {
                Text(configuredSummary(policy))
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .fixedSize(horizontal: false, vertical: true)

                // The one setting that writes to a note without being asked
                // again, so it is said out loud wherever it is on.
                if policy.application == .automatic {
                    InlineFact(
                        symbol: "wand.and.stars",
                        text: "Rewrites here are written to your notes without review. A snapshot is taken before each one."
                    )
                }
            } else if let policy = vault.configuration {
                Text("Partially configured. Still needed: \(policy.missingFields.map(\.title).joined(separator: ", ")). Chamfer will not process this vault yet.")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not set up yet. Chamfer is watching this vault but will not change anything in it until you say how.")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if vault.isNarrowed {
                InlineFact(
                    symbol: "line.3.horizontal.decrease",
                    text: "Only selected folders in this vault are processed."
                )
            } else if vault.excludedCount > 0 {
                InlineFact(
                    symbol: "minus.circle",
                    text: "\(vault.excludedCount) note or folder path\(vault.excludedCount == 1 ? "" : "s") excluded."
                )
            }
        }
    }

    private func configuredSummary(_ policy: VaultConfiguration) -> String {
        let outcome = policy.application == .automatic
            ? "applied automatically"
            : "queued for review"
        let timing: String
        switch policy.runTrigger {
        case .inactivity:
            let minutes = Int(((policy.inactivityDelay ?? 0) / 60).rounded())
            timing = "Runs after \(minutes) minute\(minutes == 1 ? "" : "s") of inactivity; no schedule is active."
        case .schedule:
            timing = "Runs \((policy.sweep?.title ?? "on the selected schedule").lowercased()); inactivity does not trigger it."
        case nil:
            timing = "Run timing is not configured."
        }
        return "\(policy.mode?.title ?? "Not configured"), \(outcome). \(timing)"
    }

    private var controls: some View {
        HStack(spacing: Chamfer.Space.snug) {
            // The attention lives on the control that resolves it. Beside the
            // vault's name it was a bullet next to a title — it marked the row
            // without saying what to do about it. Here it is unmistakably
            // pointing at the button, and it leaves the moment the vault is
            // configured.
            //
            // The chevron turns rather than the label simply changing, so the
            // control carries the state of the thing it opens. It is the one
            // piece of the row that stays put across the transition, which is
            // what makes the unfolding read as coming from here.
            Button(action: onToggle) {
                HStack(spacing: Chamfer.Space.tight + 2) {
                    if needsSetup {
                        AttentionDot(.inline)
                    }
                    Text(
                        isExpanded
                            ? "Hide settings"
                            : (vault.isConfigured ? "Settings" : "Enable rewriting…")
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? -180 : 0))
                }
            }
            .buttonStyle(ChamferButtonStyle(.secondary))
            .overlay {
                // A warm outline rather than a fill. The brass a primary button
                // uses sits within a few degrees of the amber, so a filled
                // button would have swallowed the very signal it was carrying.
                if needsSetup {
                    RoundedRectangle(
                        cornerRadius: Chamfer.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(Chamfer.Palette.attentionRing, lineWidth: 1)
                    .allowsHitTesting(false)
                }
            }
            .background {
                if needsSetup {
                    RoundedRectangle(
                        cornerRadius: Chamfer.Radius.small,
                        style: .continuous
                    )
                    .fill(Chamfer.Palette.attentionSoft)
                    // Barely there, and only enough to lift the control off the
                    // page. Not a glow.
                    .shadow(color: Chamfer.Palette.attention.opacity(0.16), radius: 7, y: 2)
                }
            }
            .animation(
                Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
                value: needsSetup
            )
            Button("Open a note…", action: onOpen)
                .buttonStyle(ChamferButtonStyle(.quiet))
                .focused(openNoteFocus, equals: vault.id)
            Spacer(minLength: 0)
            Button("Disconnect", action: onRemove)
                .buttonStyle(ChamferButtonStyle(.quiet, tone: .danger))
                .opacity(isHovered ? 1 : 0)
        }
    }
}

// MARK: - The full settings, behind the disclosure

enum VaultSetupPresentation {
    enum NextStep: Equatable {
        case vaultSettings
        case model
        case enabled
    }

    static func nextStep(
        configuration: VaultConfiguration?,
        activeModel: Bool
    ) -> NextStep {
        guard configuration?.isComplete == true else { return .vaultSettings }
        return activeModel ? .enabled : .model
    }
}

/// Every setting for one vault, with each row saying where its value came
/// from and offering to hand it back.
private struct VaultSettingsDetail: View {
    let vault: Vault
    let activeModelConfigured: Bool
    let onConfigure: (VaultConfiguration) -> Void
    let onChooseExcludedNotes: () -> [String]
    let onOpenModels: () -> Void
    let onChangeRules: ([VaultRule]) -> Void

    /// A vault being set up for the first time needs values in the controls
    /// before it has any. Partial choices are persisted immediately, but the
    /// processor remains inert until the configuration and model are complete.
    @LegacyState private var draft: VaultConfiguration

    init(
        vault: Vault,
        activeModelConfigured: Bool,
        onConfigure: @escaping (VaultConfiguration) -> Void,
        onChooseExcludedNotes: @escaping () -> [String],
        onOpenModels: @escaping () -> Void,
        onChangeRules: @escaping ([VaultRule]) -> Void
    ) {
        self.vault = vault
        self.activeModelConfigured = activeModelConfigured
        self.onConfigure = onConfigure
        self.onChooseExcludedNotes = onChooseExcludedNotes
        self.onOpenModels = onOpenModels
        self.onChangeRules = onChangeRules
        _draft = State(initialValue: vault.configuration ?? VaultConfiguration())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            if !vault.isConfigured { opening }

            PolicyEditor(policy: draft) { next in
                draft = next
                // Partial intent is real user state and survives a relaunch,
                // but `Vault.isConfigured` remains false until it is complete.
                onConfigure(next)
            }

            VaultRulesEditor(
                vault: vault,
                onChooseExcludedNotes: onChooseExcludedNotes,
                onChange: onChangeRules
            )
                .padding(.horizontal, Chamfer.Space.regular)
                .padding(.vertical, Chamfer.Space.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Chamfer.Palette.pageInset)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: Chamfer.Radius.medium,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: Chamfer.Radius.medium,
                        style: .continuous
                    )
                    .strokeBorder(Chamfer.Palette.pageInsetStroke, lineWidth: 1)
                )

            setupStatus
        }
        .padding(.top, Chamfer.Space.snug)
        .padding(.bottom, Chamfer.Space.snug)
    }

    /// The line that opens the panel when nothing has been decided yet.
    ///
    /// Set in the page's serif rather than as another caption, because it is
    /// the sentence that explains why this panel is open at all — and because
    /// a panel that begins with an icon and small grey text begins like a
    /// warning, which this is not.
    private var opening: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
            Text("Decide how this vault is treated")
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
            Text("Nothing in it is read by a model or written to until you finish here.")
                .font(Chamfer.TypeScale.pageSubtitle)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A truthful end state for setup. Vault choices are saved as they are made,
    /// so there is no redundant button that merely writes the same values twice.
    private var setupStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.roomy) {
            Text(setupExplanation)
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Chamfer.Space.snug)

            if VaultSetupPresentation.nextStep(
                configuration: draft,
                activeModel: activeModelConfigured
            ) == .model {
                Button("Choose a model…") {
                    Haptics.pop()
                    onOpenModels()
                }
                .buttonStyle(ChamferButtonStyle(.primary))
                .fixedSize()
            }
        }
        .padding(.horizontal, Chamfer.Space.regular)
        .padding(.vertical, Chamfer.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A footer rather than one more row: the same inset shape as the groups
        // above, warmed a shade and closed with a rule, so it reads as the end
        // of the decision rather than as another thing to configure.
        .background(Chamfer.Palette.attentionSoft)
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Chamfer.Palette.attentionRing)
                .frame(height: 1)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
        )
        .padding(.top, Chamfer.Space.tight)
    }

    private var setupExplanation: String {
        switch VaultSetupPresentation.nextStep(
            configuration: draft,
            activeModel: activeModelConfigured
        ) {
        case .vaultSettings:
            let fields = draft.missingFields.map(\.title).formattedList()
            return "Finish choosing \(fields). Each choice is saved immediately."
        case .model:
            return "Vault settings are complete. Choose and activate a model to begin rewriting."
        case .enabled:
            return "Rewriting is enabled for \(vault.noteCount.formatted()) note\(vault.noteCount == 1 ? "" : "s"). Changes to these settings save immediately."
        }
    }
}

// MARK: - Exclusions

/// Which individual notes or folders are off limits, and which folders are the
/// only ones in use.
///
/// Exact notes come from a native picker. Folder scope uses the folders the
/// scanner actually found, so no path is ever hand-typed.
private struct VaultRulesEditor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let vault: Vault
    let onChooseExcludedNotes: () -> [String]
    let onChange: ([VaultRule]) -> Void

    @LegacyState private var isAdding = false

    /// Subfolders with notes in them that no rule already mentions.
    private var candidates: [String] {
        let taken = Set(vault.rules.map(\.path))
        return vault.folders
            .compactMap { NoteEligibility.relativePath(of: $0.url, under: vault.url) }
            .filter { !taken.contains($0) }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            SectionHeader(
                vault.isNarrowed ? "Folders in use" : "Exclusions",
                count: vault.rules.isEmpty ? nil : vault.rules.count,
                surface: .page
            )

            if vault.rules.isEmpty {
                Text("Every supported note in this vault is eligible. Exclude individual notes with Finder, or narrow processing to a folder.")
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
            } else {
                ForEach(vault.rules) { rule in
                    RuleRow(rule: rule) { remove(rule) }
                }
            }

            HStack(spacing: Chamfer.Space.snug) {
                Button("Choose notes to exclude…") {
                    Haptics.pop()
                    let paths = onChooseExcludedNotes()
                    guard !paths.isEmpty else { return }
                    onChange(VaultRuleSet.addingExclusions(paths: paths, to: vault.rules))
                }
                .buttonStyle(ChamferButtonStyle(.secondary))

                if !candidates.isEmpty, !isAdding {
                    Button("Add a folder rule…") {
                        Haptics.pop()
                        withAnimation(
                            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion)
                        ) {
                            isAdding = true
                        }
                    }
                    .buttonStyle(ChamferButtonStyle(.quiet))
                }
            }

            if isAdding, !candidates.isEmpty {
                adder.transition(adderTransition)
            }
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: vault.rules.count
        )
    }

    private var adderTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    /// Pick a folder, then say what to do with it.
    private var adder: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
            ForEach(candidates.prefix(8), id: \.self) { path in
                HStack(spacing: Chamfer.Space.snug) {
                    Text(path)
                        .font(Chamfer.TypeScale.body)
                        .foregroundStyle(Chamfer.Palette.pageText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Chamfer.Space.snug)
                    Button("Exclude") { add(.exclude, path: path) }
                        .buttonStyle(ChamferButtonStyle(.secondary))
                    Button("Only this") { add(.includeOnly, path: path) }
                        .buttonStyle(ChamferButtonStyle(.quiet))
                }
            }

            if candidates.count > 8 {
                Text("\(candidates.count - 8) more folders not shown.")
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
            }

            Button("Done") {
                Haptics.commit()
                withAnimation(
                    Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion)
                ) {
                    isAdding = false
                }
            }
            .buttonStyle(ChamferButtonStyle(.quiet))
        }
        .padding(Chamfer.Space.regular)
        .background(Chamfer.Palette.paperSunken)
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
        )
    }

    private func add(_ kind: VaultRule.Kind, path: String) {
        Haptics.commit()
        onChange(vault.rules + [VaultRule(kind: kind, path: path)])
    }

    private func remove(_ rule: VaultRule) {
        Haptics.commit()
        onChange(vault.rules.filter { $0.id != rule.id })
    }
}

private struct RuleRow: View {
    @LegacyState private var isHovered = false

    let rule: VaultRule
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Chamfer.Space.snug) {
            Image(systemName: rule.kind == .exclude ? "minus.circle" : "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
            Text(rule.path)
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(rule.kind == .exclude ? "Never processed" : "Only this")
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
            Button("Remove", action: onRemove)
                .buttonStyle(ChamferButtonStyle(.quiet))
                .opacity(isHovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Shared pieces

/// A short line of fact with an icon, for the things worth stating outright
/// rather than leaving in a list.
struct InlineFact: View {
    let symbol: String
    /// Amber on the one or two facts worth marking, so the accent appears
    /// somewhere other than the setup button and the panel does not read as
    /// having exactly one designed element on it.
    var tint: Color = Chamfer.Palette.pageTextSoft
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .frame(width: 13)
                .padding(.top, 2)
            Text(text)
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

extension Array where Element == String {
    /// "mode", "mode and schedule", "mode, schedule and model".
    func formattedList() -> String {
        switch count {
        case 0: ""
        case 1: self[0].lowercased()
        default:
            dropLast().map { $0.lowercased() }.joined(separator: ", ")
                + " and " + self[count - 1].lowercased()
        }
    }
}
