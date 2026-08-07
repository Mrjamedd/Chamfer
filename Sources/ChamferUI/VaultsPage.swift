import ChamferCore
import SwiftUI

public struct VaultActions: Sendable {
    public var openVault: @MainActor (Vault) -> Void
    public var updatePolicy: @MainActor (UUID, PolicyOverride) -> Void
    public var updateFolderPolicy: @MainActor (UUID, UUID, PolicyOverride) -> Void
    public var removeVault: @MainActor (UUID) -> Void
    public var connectVault: @MainActor () -> Void

    public init(
        openVault: @escaping @MainActor (Vault) -> Void = { _ in },
        updatePolicy: @escaping @MainActor (UUID, PolicyOverride) -> Void = { _, _ in },
        updateFolderPolicy: @escaping @MainActor (UUID, UUID, PolicyOverride) -> Void = { _, _, _ in },
        removeVault: @escaping @MainActor (UUID) -> Void = { _ in },
        connectVault: @escaping @MainActor () -> Void = {}
    ) {
        self.openVault = openVault
        self.updatePolicy = updatePolicy
        self.updateFolderPolicy = updateFolderPolicy
        self.removeVault = removeVault
        self.connectVault = connectVault
    }
}

/// The connected note folders, and what each of them does differently.
///
/// This is the page where the scope is denser than the app's aesthetic wants,
/// so it is built on one rule: show difference, not state. A vault row carries
/// its name and whether it is reachable. Its settings are a sentence saying
/// what it does differently, and the full set is behind a disclosure. A vault
/// that simply follows the defaults says so in six words and takes one line.
struct VaultsPage: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let vaults: [Vault]
    let globalPolicy: RewritePolicy
    var actions = VaultActions()

    @State private var expanded: UUID?

    var body: some View {
        Group {
            if vaults.isEmpty {
                emptyState
            } else {
                PageScroll(title: "Vaults", accessory: connectButton) {
                    VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                        ForEach(vaults) { vault in
                            VaultRowView(
                                vault: vault,
                                globalPolicy: globalPolicy,
                                isExpanded: expanded == vault.id,
                                onToggle: { toggle(vault) },
                                onOpen: { actions.openVault(vault) },
                                onRemove: { actions.removeVault(vault.id) },
                                onChangePolicy: { actions.updatePolicy(vault.id, $0) },
                                onChangeFolderPolicy: {
                                    actions.updateFolderPolicy(vault.id, $0, $1)
                                }
                            )
                            if vault.id != vaults.last?.id {
                                PageRule()
                            }
                        }

                        Text("Anything not set here follows your defaults in Settings.")
                            .font(Chamfer.TypeScale.caption)
                            .foregroundStyle(Chamfer.Palette.pageTextSoft)
                            .padding(.top, Chamfer.Space.snug)
                    }
                }
            }
        }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion),
            value: expanded
        )
    }

    private var connectButton: AnyView? {
        AnyView(
            Button("Connect a vault") {
                Haptics.pop()
                actions.connectVault()
            }
            .buttonStyle(ChamferButtonStyle(.secondary))
        )
    }

    private var emptyState: some View {
        VStack(spacing: Chamfer.Space.loose) {
            PageMessage(
                title: "No vaults yet",
                detail: "Point Chamfer at a folder of Markdown or plain-text notes and it will watch everything inside it, including subfolders."
            )
            .frame(maxHeight: 200)

            Button("Connect a vault") {
                Haptics.pop()
                actions.connectVault()
            }
            .buttonStyle(ChamferButtonStyle(.primary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ vault: Vault) {
        Haptics.pop()
        expanded = expanded == vault.id ? nil : vault.id
    }
}

// MARK: - One vault

private struct VaultRowView: View {
    @Environment(\.chamferNow) private var now

    let vault: Vault
    let globalPolicy: RewritePolicy
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onChangePolicy: (PolicyOverride) -> Void
    let onChangeFolderPolicy: (UUID, PolicyOverride) -> Void

    @State private var isHovered = false

    private var resolved: ResolvedPolicy {
        vault.resolved(against: globalPolicy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            header
            status
            settingsSentence

            if isExpanded {
                VaultSettingsDetail(
                    vault: vault,
                    globalPolicy: globalPolicy,
                    onChangePolicy: onChangePolicy,
                    onChangeFolderPolicy: onChangeFolderPolicy
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            controls
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.snug) {
            Text(vault.name)
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Chamfer.Space.snug)

            if !vault.availability.isAvailable {
                Pill(vault.availability.title, symbol: vault.availability.symbol, tone: .danger)
            }
        }
    }

    /// Path, note count and last sweep — the facts, in one line.
    private var status: some View {
        Text(statusText)
            .font(Chamfer.TypeScale.caption)
            .foregroundStyle(Chamfer.Palette.pageTextSoft)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var statusText: String {
        var parts = [vault.displayPath, "\(vault.noteCount.formatted()) notes"]
        if let remedy = vault.availability.remedy {
            parts.append(remedy)
        } else if let sweep = vault.lastSweep {
            parts.append("swept \(RelativeTime.string(sweep, since: now))")
        } else {
            parts.append("not swept yet")
        }
        return parts.joined(separator: " · ")
    }

    /// The whole density strategy in one view: what this vault does
    /// differently, as a sentence, or an admission that it does nothing
    /// differently at all.
    @ViewBuilder
    private var settingsSentence: some View {
        let overridden = resolved.overriddenFields
        let policy = resolved.policy

        VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
            if overridden.isEmpty {
                Text("Follows your defaults: \(policy.mode.title.lowercased()), \(policy.application == .automatic ? "applied automatically" : "queued for review").")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
            } else {
                Text("Differs from your defaults: \(overridden.map(\.title).formattedList()).")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Automatic application is the one setting worth calling out
            // whatever level set it: it is the only one that writes to a note
            // without being asked again.
            if policy.application == .automatic {
                InlineFact(
                    symbol: "wand.and.stars",
                    text: "Rewrites here are applied automatically, set by \(resolved.source(of: .application).title). A snapshot is taken before each one."
                )
            }

            if vault.isNarrowed {
                InlineFact(
                    symbol: "line.3.horizontal.decrease",
                    text: "Only selected folders in this vault are processed."
                )
            } else if vault.excludedCount > 0 {
                InlineFact(
                    symbol: "minus.circle",
                    text: "\(vault.excludedCount) folder\(vault.excludedCount == 1 ? "" : "s") excluded."
                )
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Chamfer.Space.snug) {
            Button(isExpanded ? "Hide settings" : "Settings", action: onToggle)
                .buttonStyle(ChamferButtonStyle(.secondary))
            Button("Open a note", action: onOpen)
                .buttonStyle(ChamferButtonStyle(.quiet))
            Spacer(minLength: 0)
            Button("Disconnect", action: onRemove)
                .buttonStyle(ChamferButtonStyle(.quiet))
                .opacity(isHovered ? 1 : 0)
        }
    }
}

// MARK: - The full settings, behind the disclosure

/// Every setting for one vault, with each row saying where its value came
/// from and offering to hand it back.
private struct VaultSettingsDetail: View {
    let vault: Vault
    let globalPolicy: RewritePolicy
    let onChangePolicy: (PolicyOverride) -> Void
    let onChangeFolderPolicy: (UUID, PolicyOverride) -> Void

    private var resolved: ResolvedPolicy {
        vault.resolved(against: globalPolicy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.roomy) {
            PolicyEditor(
                resolved: resolved,
                override: vault.policy,
                inheritedFrom: "your defaults",
                onChange: onChangePolicy
            )

            if !vault.folders.isEmpty {
                VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                    PageSectionHeader(title: "Folders that differ", count: vault.folders.count)
                    ForEach(vault.folders) { folder in
                        FolderOverrideRow(
                            folder: folder,
                            resolved: vault.resolved(folder: folder, against: globalPolicy),
                            onChange: { onChangeFolderPolicy(folder.id, $0) }
                        )
                    }
                }
            }

            if !vault.rules.isEmpty {
                VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
                    PageSectionHeader(title: "Exclusions", count: vault.rules.count)
                    ForEach(vault.rules) { rule in
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
                        }
                    }
                }
            }
        }
        .padding(.vertical, Chamfer.Space.snug)
    }
}

private struct FolderOverrideRow: View {
    let folder: WatchedFolder
    let resolved: ResolvedPolicy
    let onChange: (PolicyOverride) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
            HStack(spacing: Chamfer.Space.snug) {
                Image(systemName: folder.isReachable ? "folder" : "folder.badge.questionmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                Text(folder.url.lastPathComponent)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(Chamfer.Palette.pageText)
                Spacer(minLength: 0)
                Button("Reset to vault") { onChange(.inherited) }
                    .buttonStyle(ChamferButtonStyle(.quiet))
                    .disabled(folder.policy.isInherited)
                    .opacity(folder.policy.isInherited ? 0.35 : 1)
            }
            Text(
                folder.policy.isInherited
                    ? "Follows this vault."
                    : "Overrides \(folder.policy.fields.map(\.title).formattedList())."
            )
            .font(Chamfer.TypeScale.caption)
            .foregroundStyle(Chamfer.Palette.pageTextSoft)
        }
    }
}

// MARK: - Shared pieces

/// A short line of fact with an icon, for the things worth stating outright
/// rather than leaving in a list.
struct InlineFact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
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
