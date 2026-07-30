import ChamferCore
import SwiftUI

/// One change, shown as what it was and what it would become.
///
/// Monospaced on purpose: the user is judging an edit, and proportional type
/// hides exactly the whitespace and punctuation differences that matter.
public struct DiffHunkView: View {
    @Environment(\.chamferSurface) private var surface

    private let hunk: Hunk

    public init(_ hunk: Hunk) {
        self.hunk = hunk
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            line(marker: "−", text: hunk.before, tint: surface.danger, background: surface.removedFill)
            line(marker: "+", text: hunk.after, tint: surface.positive, background: surface.addedFill)
        }
        .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous))
    }

    private func line(marker: String, text: String, tint: Color, background: Color) -> some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Text(marker)
                .font(Chamfer.TypeScale.mono)
                .foregroundStyle(tint)
                .frame(width: 10, alignment: .center)
            Text(text)
                .font(Chamfer.TypeScale.mono)
                .foregroundStyle(surface.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Chamfer.Space.snug)
        .padding(.horizontal, Chamfer.Space.regular)
        .background(background)
    }
}

/// A pending rewrite in the queue.
public struct ProposalCard: View {
    @Environment(\.chamferNow) private var now

    private let proposal: Proposal
    private let onAccept: () -> Void
    private let onReject: () -> Void

    public init(
        _ proposal: Proposal,
        onAccept: @escaping () -> Void = {},
        onReject: @escaping () -> Void = {}
    ) {
        self.proposal = proposal
        self.onAccept = onAccept
        self.onReject = onReject
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                Header(proposal: proposal, subtitle: subtitle)
                if let first = proposal.hunks.first {
                    DiffHunkView(first)
                }
                if proposal.hunks.count > 1 {
                    Overflow(count: proposal.hunks.count - 1)
                }
                Actions(onAccept: onAccept, onReject: onReject)
            }
        }
    }

    private var subtitle: String {
        var parts = ["\(proposal.note.wordCount.formatted()) words"]
        if let first = proposal.hunks.first {
            parts.append("line \(first.startLine)")
        }
        parts.append(RelativeTime.string(proposal.createdAt, since: now))
        return parts.joined(separator: " · ")
    }

    private struct Header: View {
        @Environment(\.chamferSurface) private var surface

        let proposal: Proposal
        let subtitle: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.snug) {
                VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                    Text(proposal.note.title)
                        .font(Chamfer.TypeScale.title)
                        .foregroundStyle(surface.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(surface.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: Chamfer.Space.snug)
                Pill(
                    "\(proposal.hunks.count) change\(proposal.hunks.count == 1 ? "" : "s")",
                    tone: .accent
                )
            }
        }
    }

    private struct Overflow: View {
        @Environment(\.chamferSurface) private var surface

        let count: Int

        var body: some View {
            Text("+ \(count) more change\(count == 1 ? "" : "s") in this note")
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(surface.textFaint)
        }
    }

    private struct Actions: View {
        let onAccept: () -> Void
        let onReject: () -> Void

        var body: some View {
            HStack(spacing: Chamfer.Space.snug) {
                Button("Accept", action: onAccept)
                    .buttonStyle(ChamferButtonStyle(.primary))
                Button("Reject", action: onReject)
                    .buttonStyle(ChamferButtonStyle(.secondary))
                Spacer()
                Button("Open note") {}
                    .buttonStyle(ChamferButtonStyle(.quiet))
            }
        }
    }
}
