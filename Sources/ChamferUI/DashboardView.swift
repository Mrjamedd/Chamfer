import ChamferCore
import SwiftUI

/// The whole dashboard, rendered from one value.
///
/// It takes a `DashboardState` and nothing else — no store, no service, no
/// clock. That is what lets the gallery drive it through every state, and what
/// will let the real watcher drive it later without any view changing.
public struct DashboardView: View {
    private let state: DashboardState

    public init(state: DashboardState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
                header
                RunStateBanner(state.runState)
                HStack(alignment: .top, spacing: Chamfer.Space.loose) {
                    queue
                    rail.frame(width: 300)
                }
            }
            .padding(Chamfer.Space.section)
        }
        .background(Chamfer.Palette.canvas)
    }

    // MARK: - Header

    /// Sits directly on the canvas with no surface of its own, so the cards
    /// below are the only things floating.
    private var header: some View {
        HStack(alignment: .bottom, spacing: Chamfer.Space.regular) {
            VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
                Text("Chamfer")
                    .font(Chamfer.TypeScale.display)
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                Text(folderSummary)
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
            }
            Spacer()
            if case let .sweeping(completed, total) = state.runState {
                ProgressView(value: Double(completed), total: Double(total))
                    .progressViewStyle(.linear)
                    .tint(Chamfer.Palette.brass)
                    .frame(width: 140)
            }
            RunStateBadge(state.runState)
        }
    }

    private var folderSummary: String {
        guard !state.folders.isEmpty else { return "No folders watched yet" }
        let notes = state.folders.reduce(0) { $0 + $1.noteCount }
        let folders = state.folders.count == 1 ? "1 folder" : "\(state.folders.count) folders"
        return "\(folders) · \(notes.formatted()) notes"
    }

    // MARK: - Queue

    private var queue: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            SectionHeader("Pending review", count: state.pendingProposals.count)
            if state.folders.isEmpty {
                Card(interactive: false) {
                    EmptyState(
                        symbol: "folder.badge.plus",
                        title: "Point Chamfer at a folder",
                        message: "Pick the folder your notes live in — an Obsidian vault, an iA Writer library, or any folder of Markdown. Nothing is changed until you say so."
                    )
                }
            } else if state.pendingProposals.isEmpty {
                Card(interactive: false) {
                    EmptyState(
                        symbol: emptyQueueSymbol,
                        title: emptyQueueTitle,
                        message: emptyQueueMessage
                    )
                }
            } else {
                LazyVStack(spacing: Chamfer.Space.regular) {
                    ForEach(state.pendingProposals) { proposal in
                        ProposalCard(proposal)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The resting state has to tell the truth about *why* it is empty —
    // "your notes are tidy" is a lie when rewrites are switched off.
    private var rewritesDisabled: Bool {
        if case .rewritingUnavailable = state.runState { return true }
        return false
    }

    private var emptyQueueSymbol: String {
        rewritesDisabled ? "wand.and.stars.inverse" : "checkmark.seal"
    }

    private var emptyQueueTitle: String {
        rewritesDisabled ? "No rewrites to review" : "Nothing to review"
    }

    private var emptyQueueMessage: String {
        rewritesDisabled
            ? "Formatting rules are still running on every save. Turn Apple Intelligence back on and Chamfer will start suggesting rewrites again."
            : "Your notes are tidy. Chamfer will queue anything it wants to rewrite here."
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.loose) {
            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                SectionHeader("Watching")
                Card(padding: Chamfer.Space.regular) {
                    if state.folders.isEmpty {
                        Placeholder("No folders yet.")
                    } else {
                        VStack(spacing: Chamfer.Space.regular) {
                            ForEach(state.folders) { folder in
                                FolderRow(folder)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                SectionHeader("Cleaned automatically")
                Card(padding: Chamfer.Space.regular) {
                    if state.recentlyCleaned.isEmpty {
                        Placeholder("Nothing yet today.")
                    } else {
                        VStack(spacing: Chamfer.Space.regular) {
                            ForEach(state.recentlyCleaned) { record in
                                CleanupRow(record)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Rows

private struct Placeholder: View {
    @Environment(\.chamferSurface) private var surface

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Chamfer.TypeScale.body)
            .foregroundStyle(surface.textFaint)
    }
}

public struct FolderRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.chamferSurface) private var surface

    private let folder: WatchedFolder

    public init(_ folder: WatchedFolder) {
        self.folder = folder
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: folder.isReachable ? "folder" : "folder.badge.questionmark")
                .font(.system(size: 12))
                .foregroundStyle(folder.isReachable ? surface.textFaint : surface.danger)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(folder.url.lastPathComponent)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(surface.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(folder.isReachable ? surface.textFaint : surface.danger)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var detail: String {
        guard folder.isReachable else { return "Unreachable — reconnect the disk to resume" }
        let notes = "\(folder.noteCount.formatted()) notes"
        guard let sweep = folder.lastSweep else { return "\(notes) · sweeping now" }
        return "\(notes) · swept \(RelativeTime.string(sweep, since: now))"
    }
}

public struct CleanupRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.chamferSurface) private var surface

    private let record: CleanupRecord

    public init(_ record: CleanupRecord) {
        self.record = record
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(surface.positive)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(record.note.title)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(surface.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(record.rules.count) rule\(record.rules.count == 1 ? "" : "s") · \(RelativeTime.string(record.appliedAt, since: now))")
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(surface.textFaint)
            }
            Spacer(minLength: 0)
        }
    }
}
