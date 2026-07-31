import ChamferCore
import ChamferFixtures
import ChamferUI
import SwiftUI

/// Every component, every state, on one scrolling page.
struct ComponentCatalog: View {
    @State private var barSelection = "notes"
    @State private var barIsSearching = false

    private let typical = Fixtures.state(for: .typical)
    private let unreachable = Fixtures.state(for: .folderUnreachable)
    private let huge = Fixtures.state(for: .hugeNote)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Chamfer.Space.section) {
                specimen("Palette") { palette }
                specimen("Hover lift — at rest and held open") { hoverPair }
                specimen("Bottom bar") { bar }
                specimen("Surfaces — paper and ink") { surfaces }
                specimen("Run state badges") {
                    HStack(spacing: Chamfer.Space.snug) {
                        RunStateBadge(.idle)
                        RunStateBadge(.sweeping(completed: 137, total: 412))
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
                specimen("Proposal card — hover it") {
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
                            ForEach(typical.recentlyCleaned) { CleanupRow($0) }
                        }
                    }
                }
                specimen("Empty state") {
                    Card(interactive: false) {
                        EmptyState(
                            symbol: "checkmark.seal",
                            title: "Nothing to review",
                            message: "Your notes are tidy. Chamfer will queue anything it wants to rewrite here."
                        )
                    }
                }
            }
            .padding(Chamfer.Space.section)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Chamfer.Palette.canvas)
    }

    /// The hover state pinned open next to a resting one. Hover is impossible
    /// to inspect properly while you are holding the mouse still on it, and
    /// impossible to screenshot at all.
    private var hoverPair: some View {
        HStack(spacing: Chamfer.Space.section) {
            ForEach([false, true], id: \.self) { glowing in
                VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
                    Text("Standup 30 Jul")
                        .font(Chamfer.TypeScale.title)
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                    Text("340 words · line 12 · 3 min ago")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                }
                .padding(Chamfer.Space.roomy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Chamfer.Palette.paper)
                .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
                        .strokeBorder(Chamfer.Palette.paperStroke, lineWidth: 1)
                )
                .chamferHoverLift(isActive: glowing)
            }
        }
        .padding(.vertical, Chamfer.Space.roomy)
    }

    private var bar: some View {
        VStack(spacing: Chamfer.Space.loose) {
            // Normally only visible while the pointer is in the gutter above
            // the page, so it is pinned open here to be inspectable.
            FloatingCloseButton {}
            barControl
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Chamfer.Space.regular)
    }

    private var barControl: some View {
        BottomBar(
            items: [
                .init(id: "notes", symbol: "doc.text", label: "Notes"),
                .init(id: "review", symbol: "checkmark.circle", label: "Review"),
                .init(id: "models", symbol: "cpu", label: "Models")
            ],
            selection: $barSelection,
            isSearching: $barIsSearching,
            searchableNotes: typical.searchableNotes
        )
    }

    /// The same components on both surfaces, since every one of them has to
    /// survive a card inverting under it.
    private var surfaces: some View {
        HStack(spacing: Chamfer.Space.regular) {
            ForEach(SurfaceMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                    HStack(spacing: Chamfer.Space.snug) {
                        Pill("Neutral")
                        Pill("Accent", symbol: "sparkles", tone: .accent)
                    }
                    HStack(spacing: Chamfer.Space.snug) {
                        Pill("Positive", symbol: "checkmark", tone: .positive)
                        Pill("Danger", symbol: "xmark", tone: .danger)
                    }
                    HStack(spacing: Chamfer.Space.snug) {
                        Button("Primary") {}.buttonStyle(ChamferButtonStyle(.primary))
                        Button("Secondary") {}.buttonStyle(ChamferButtonStyle(.secondary))
                        Button("Quiet") {}.buttonStyle(ChamferButtonStyle(.quiet))
                    }
                    if let hunk = typical.proposals.first?.hunks.first {
                        DiffHunkView(hunk)
                    }
                }
                .environment(\.chamferSurface, mode)
                .padding(Chamfer.Space.roomy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(mode.background)
                .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
                        .strokeBorder(mode.stroke, lineWidth: 1)
                )
            }
        }
    }

    private var palette: some View {
        let swatches: [(String, Color)] = [
            ("canvas", Chamfer.Palette.canvas),
            ("paper", Chamfer.Palette.paper),
            ("sunken", Chamfer.Palette.paperSunken),
            ("stroke", Chamfer.Palette.paperStroke),
            ("ink", Chamfer.Palette.ink),
            ("brass", Chamfer.Palette.brass),
            ("pink", Chamfer.Palette.pink),
            ("positive", Chamfer.Palette.positive),
            ("danger", Chamfer.Palette.danger)
        ]
        return HStack(spacing: Chamfer.Space.snug) {
            ForEach(swatches, id: \.0) { name, color in
                VStack(spacing: Chamfer.Space.tight) {
                    RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                        .fill(color)
                        .frame(width: 58, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                                .strokeBorder(Chamfer.Palette.paperStroke, lineWidth: 1)
                        )
                    Text(name)
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
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
