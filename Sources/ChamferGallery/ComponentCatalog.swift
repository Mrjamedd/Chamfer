import ChamferCore
import ChamferFixtures
import ChamferUI
import SwiftUI

/// Every component, every state, on one scrolling page.
struct ComponentCatalog: View {
    private let typical = Fixtures.state(for: .typical)
    private let unreachable = Fixtures.state(for: .folderUnreachable)
    private let huge = Fixtures.state(for: .hugeNote)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Chamfer.Space.section) {
                specimen("Palette") { palette }
                specimen("Pills") {
                    HStack(spacing: Chamfer.Space.snug) {
                        Pill("Neutral")
                        Pill("Accent", symbol: "sparkles", tone: .accent)
                        Pill("Positive", symbol: "checkmark", tone: .positive)
                        Pill("Danger", symbol: "xmark", tone: .danger)
                    }
                }
                specimen("Buttons") {
                    HStack(spacing: Chamfer.Space.snug) {
                        Button("Primary") {}.buttonStyle(ChamferButtonStyle(.primary))
                        Button("Secondary") {}.buttonStyle(ChamferButtonStyle(.secondary))
                        Button("Quiet") {}.buttonStyle(ChamferButtonStyle(.quiet))
                    }
                }
                specimen("Run state badges") {
                    HStack(spacing: Chamfer.Space.snug) {
                        RunStateBadge(.idle)
                        RunStateBadge(.sweeping(completed: 137, total: 412))
                        RunStateBadge(.rewriting(noteTitle: "Standup"))
                        RunStateBadge(.paused)
                        RunStateBadge(.rewritingUnavailable(reason: ""))
                        RunStateBadge(.failed(message: ""))
                    }
                }
                specimen("Banners") {
                    VStack(spacing: Chamfer.Space.regular) {
                        RunStateBanner(.rewritingUnavailable(
                            reason: "Apple Intelligence is turned off in System Settings."
                        ))
                        RunStateBanner(.failed(
                            message: "Couldn't write to “Meeting notes.md” — the file is read-only."
                        ))
                    }
                }
                specimen("Diff hunk") {
                    if let hunk = typical.proposals.first?.hunks.first {
                        DiffHunkView(hunk)
                    }
                }
                specimen("Proposal card — one change") {
                    if let proposal = typical.proposals.last {
                        ProposalCard(proposal)
                    }
                }
                specimen("Proposal card — long title, many changes") {
                    if let proposal = huge.proposals.first {
                        ProposalCard(proposal)
                    }
                }
                specimen("Rows") {
                    Card(padding: Chamfer.Space.regular) {
                        VStack(spacing: Chamfer.Space.regular) {
                            ForEach(unreachable.folders) { FolderRow($0) }
                            Divider().overlay(Chamfer.Palette.stroke)
                            ForEach(typical.recentlyCleaned) { CleanupRow($0) }
                        }
                    }
                }
                specimen("Empty state") {
                    Card {
                        EmptyState(
                            symbol: "checkmark.seal",
                            title: "Nothing to review",
                            message: "Your notes are tidy. Chamfer will queue anything it wants to rewrite here."
                        )
                    }
                }
            }
            .padding(Chamfer.Space.loose)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Chamfer.Palette.canvas)
    }

    private var palette: some View {
        let swatches: [(String, Color)] = [
            ("canvas", Chamfer.Palette.canvas),
            ("surface", Chamfer.Palette.surface),
            ("sunken", Chamfer.Palette.sunken),
            ("stroke", Chamfer.Palette.stroke),
            ("text", Chamfer.Palette.textPrimary),
            ("text 2", Chamfer.Palette.textSecondary),
            ("accent", Chamfer.Palette.accent),
            ("positive", Chamfer.Palette.positive),
            ("danger", Chamfer.Palette.danger)
        ]
        return HStack(spacing: Chamfer.Space.snug) {
            ForEach(swatches, id: \.0) { name, color in
                VStack(spacing: Chamfer.Space.tight) {
                    RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                        .fill(color)
                        .frame(width: 56, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                                .strokeBorder(Chamfer.Palette.stroke, lineWidth: 1)
                        )
                    Text(name)
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textTertiary)
                }
            }
        }
    }

    private func specimen<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            SectionHeader(title)
            content()
        }
    }
}
