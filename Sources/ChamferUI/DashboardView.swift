import ChamferCore
import SwiftUI

/// The whole window: one page floating on beige, a bar floating over the page,
/// and a close control that only appears when you reach for it.
public struct DashboardView: View {
    @State private var tab: String
    @State private var pointerAtTop = false

    private let state: DashboardState
    private let onClose: () -> Void

    private static let topGutter: CGFloat = 54
    private static let bottomGutter: CGFloat = 20

    public init(state: DashboardState, tab: String = Tab.notes, onClose: @escaping () -> Void = {}) {
        self.state = state
        self.onClose = onClose
        _tab = State(initialValue: tab)
    }

    public enum Tab {
        public static let apps = "apps"
        public static let review = "review"
        public static let notes = "notes"
    }

    private var items: [BottomBar.Item] {
        [
            .init(id: Tab.apps, symbol: "macwindow", label: "Apps"),
            .init(id: Tab.review, symbol: "chevron.left.forwardslash.chevron.right", label: "Review"),
            .init(id: Tab.notes, symbol: "paperclip", label: "Notes")
        ]
    }

    public var body: some View {
        ZStack {
            Chamfer.Palette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: Self.topGutter)
                page
                Color.clear.frame(height: Self.bottomGutter)
            }
            .padding(.horizontal, Chamfer.Space.section)

            // The close control lives in the gutter above the page and is
            // revealed by moving towards it, so nothing sits over the note
            // while you are reading.
            VStack(spacing: 0) {
                closeZone
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                BottomBar(items: items, selection: $tab)
                    .padding(.bottom, Chamfer.Space.section)
            }
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
        case Tab.apps:
            FolderPage(folders: state.folders)
        case Tab.review:
            ReviewPage(proposals: state.pendingProposals)
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

private struct FolderPage: View {
    @Environment(\.chamferNow) private var now

    let folders: [WatchedFolder]

    var body: some View {
        if folders.isEmpty {
            PageMessage(
                title: "No folders yet",
                detail: "Point Chamfer at a folder of Markdown and it will start watching."
            )
        } else {
            PageScroll(title: "Watching") {
                ForEach(folders) { folder in
                    VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
                        Text(folder.url.lastPathComponent)
                            .font(Chamfer.TypeScale.pageHeading)
                            .foregroundStyle(Chamfer.Palette.pageText)
                        Text(detail(for: folder))
                            .font(Chamfer.TypeScale.body)
                            .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    }
                    .padding(.bottom, Chamfer.Space.loose)
                }
            }
        }
    }

    private func detail(for folder: WatchedFolder) -> String {
        guard folder.isReachable else { return "Unreachable — reconnect the disk to resume" }
        let notes = "\(folder.noteCount.formatted()) notes"
        guard let sweep = folder.lastSweep else { return "\(notes) · sweeping now" }
        return "\(notes) · swept \(RelativeTime.string(sweep, since: now))"
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

/// Shared page chrome: the same measure and margins as the note page, so
/// every tab reads as the same sheet of paper.
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
            .padding(.top, 72)
            .padding(.bottom, 96)
        }
        .scrollContentBackground(.hidden)
    }
}
