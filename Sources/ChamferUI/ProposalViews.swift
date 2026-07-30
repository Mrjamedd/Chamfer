import ChamferCore
import SwiftUI

/// One change, shown as what it was and what it would become.
///
/// Monospaced on purpose: the user is judging an edit, and proportional type
/// hides exactly the whitespace and punctuation differences that matter.
public struct DiffHunkView: View {
    private let hunk: Hunk

    public init(_ hunk: Hunk) {
        self.hunk = hunk
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            line(marker: "−", text: hunk.before, tint: Chamfer.Palette.danger, background: Chamfer.Palette.dangerSoft)
            line(marker: "+", text: hunk.after, tint: Chamfer.Palette.positive, background: Chamfer.Palette.positiveSoft)
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
                .foregroundStyle(Chamfer.Palette.textPrimary)
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
                header
                if let first = proposal.hunks.first {
                    DiffHunkView(first)
                }
                if proposal.hunks.count > 1 {
                    Text("+ \(proposal.hunks.count - 1) more change\(proposal.hunks.count == 2 ? "" : "s") in this note")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textTertiary)
                }
                actions
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.snug) {
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(proposal.note.title)
                    .font(Chamfer.TypeScale.title)
                    .foregroundStyle(Chamfer.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Chamfer.Space.snug)
            Pill(
                "\(proposal.hunks.count) change\(proposal.hunks.count == 1 ? "" : "s")",
                tone: .accent
            )
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

    private var actions: some View {
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
