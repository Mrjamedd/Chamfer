import ChamferCore
import SwiftUI

/// The whole window: one page floating on beige, a bar sitting under it, and a
/// close control that only appears when you reach for it.
public struct DashboardView: View {
    @State private var tab: String
    @State private var pointerAtTop = false

    private let state: DashboardState
    private let onClose: () -> Void

    private static let topGutter: CGFloat = 52

    public init(state: DashboardState, tab: String = Tab.notes, onClose: @escaping () -> Void = {}) {
        self.state = state
        self.onClose = onClose
        _tab = State(initialValue: tab)
    }

    public enum Tab {
        public static let notes = "notes"
        public static let review = "review"
        public static let models = "models"
    }

    private var items: [BottomBar.Item] {
        [
            .init(id: Tab.notes, symbol: "doc.text", label: "Notes"),
            .init(id: Tab.review, symbol: "checkmark.circle", label: "Review"),
            .init(id: Tab.models, symbol: "cpu", label: "Models")
        ]
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Chamfer.Palette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: Self.topGutter)
                page
                BottomBar(items: items, selection: $tab)
                    .padding(.top, Chamfer.Space.loose)
                    .padding(.bottom, Chamfer.Space.loose)
            }
            .padding(.horizontal, Chamfer.Space.section)

            // The close control lives in the gutter above the page and is
            // revealed by moving towards it, so nothing sits over the note
            // while you are reading.
            closeZone
        }
    }

    private var page: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Chamfer.Palette.page)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .chamferFloat()
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case Tab.review:
            ReviewPage(proposals: state.pendingProposals)
        case Tab.models:
            ModelsPage(runState: state.runState)
        default:
            if let note = state.openNote {
                NotePageView(note)
            } else {
                PageMessage(
                    title: "No note open",
                    detail: "Pick a note from your vault and it will appear here."
                )
            }
        }
    }

    private var closeZone: some View {
        ZStack {
            if pointerAtTop {
                FloatingCloseButton(action: onClose)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.topGutter)
        .contentShape(Rectangle())
        .onHover { pointerAtTop = $0 }
        .animation(Chamfer.Motion.quick, value: pointerAtTop)
    }
}

// MARK: - Page contents

private struct PageMessage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Chamfer.Space.snug) {
            Text(title)
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
            Text(detail)
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReviewPage: View {
    let proposals: [Proposal]

    var body: some View {
        if proposals.isEmpty {
            PageMessage(
                title: "Nothing to review",
                detail: "Rewrites waiting on your judgement will appear here."
            )
        } else {
            PageScroll(title: "Pending review") {
                ForEach(proposals) { proposal in
                    VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                        Text(proposal.note.title)
                            .font(Chamfer.TypeScale.pageHeading)
                            .foregroundStyle(Chamfer.Palette.pageText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let first = proposal.hunks.first {
                            DiffHunkView(first)
                        }
                        HStack(spacing: Chamfer.Space.snug) {
                            Button("Accept") {}.buttonStyle(ChamferButtonStyle(.primary))
                            Button("Reject") {}.buttonStyle(ChamferButtonStyle(.secondary))
                        }
                    }
                    .padding(.bottom, Chamfer.Space.section)
                }
            }
        }
    }
}

/// Which local model does the rewriting, and whether it can right now.
private struct ModelsPage: View {
    let runState: RunState

    var body: some View {
        PageScroll(title: "Models") {
            ForEach(backends, id: \.name) { backend in
                VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
                    HStack(spacing: Chamfer.Space.snug) {
                        Text(backend.name)
                            .font(Chamfer.TypeScale.pageHeading)
                            .foregroundStyle(Chamfer.Palette.pageText)
                        Pill(backend.status, tone: backend.tone)
                    }
                    Text(backend.detail)
                        .font(Chamfer.TypeScale.body)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Chamfer.Space.loose)
            }
        }
    }

    private var appleUnavailableReason: String? {
        if case let .rewritingUnavailable(reason) = runState { return reason }
        return nil
    }

    private var backends: [(name: String, status: String, tone: Pill.Tone, detail: String)] {
        [
            (
                "Apple Foundation Models",
                appleUnavailableReason == nil ? "Active" : "Unavailable",
                appleUnavailableReason == nil ? .positive : .danger,
                appleUnavailableReason
                    ?? "The on-device model built into macOS. Nothing to download, nothing leaves the Mac."
            ),
            (
                "Ollama",
                "Not configured",
                .neutral,
                "Point Chamfer at a local Ollama server to use a larger model, if this Mac has the memory for it."
            ),
            (
                "Bundled MLX",
                "Not installed",
                .neutral,
                "Ships a small model inside the app. Works without Apple Intelligence, at the cost of a large download."
            )
        ]
    }
}

/// Shared page chrome: the same measure and margins everywhere, so every tab
/// reads as the same sheet of paper.
private struct PageScroll<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Chamfer.TypeScale.pageTitle)
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .padding(.bottom, Chamfer.Space.loose)
                content
            }
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 56)
            .padding(.top, 64)
            .padding(.bottom, 56)
        }
        .scrollContentBackground(.hidden)
    }
}
