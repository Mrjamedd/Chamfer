import ChamferCore
import SwiftUI

/// One change, shown as what it was and what it would become.
///
/// Monospaced on purpose: the user is judging an edit, and proportional type
/// hides exactly the whitespace and punctuation differences that matter.
///
/// The two lines carry a quiet wash of their tint; the words that actually
/// moved carry a stronger one on top. In spelling and grammar modes most hunks
/// differ by a single word, and a whole-line tint made a typo fix look like a
/// rewritten paragraph — so the size of the highlight now matches the size of
/// the edit.
public struct DiffHunkView: View {
    @Environment(\.chamferSurface) private var surface

    private let hunk: Hunk
    private let isSelected: Bool

    public init(_ hunk: Hunk, isSelected: Bool = true) {
        self.hunk = hunk
        self.isSelected = isSelected
    }

    private var segments: (before: [DiffSegment], after: [DiffSegment]) {
        TextDiff.segments(before: hunk.before, after: hunk.after)
    }

    public var body: some View {
        let segments = segments

        VStack(alignment: .leading, spacing: 1) {
            // A pure insertion has nothing to show as "before", and an empty
            // tinted band reads as a bug rather than as an absence.
            if !hunk.before.isEmpty {
                line(
                    marker: "−",
                    segments: segments.before,
                    tint: isSelected ? surface.danger : surface.textFaint,
                    background: isSelected ? surface.removedFill : surface.sunken,
                    emphasis: isSelected ? surface.removedEmphasis : surface.stroke,
                    text: isSelected ? surface.textPrimary : surface.textSecondary
                )
            }
            if !hunk.after.isEmpty {
                line(
                    marker: "+",
                    segments: segments.after,
                    tint: isSelected ? surface.positive : surface.textFaint,
                    background: isSelected ? surface.addedFill : surface.sunken,
                    emphasis: isSelected ? surface.addedEmphasis : surface.stroke,
                    text: isSelected ? surface.textPrimary : surface.textSecondary
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
                .strokeBorder(surface.stroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func line(
        marker: String,
        segments: [DiffSegment],
        tint: Color,
        background: Color,
        emphasis: Color,
        text: Color
    ) -> some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Text(marker)
                .font(Chamfer.TypeScale.mono)
                .foregroundStyle(tint)
                .frame(width: 10, alignment: .center)
            marked(segments, emphasis: emphasis)
                .font(Chamfer.TypeScale.mono)
                .foregroundStyle(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Chamfer.Space.regular)
        .padding(.horizontal, Chamfer.Space.roomy)
        .background(background)
    }

    /// One `Text` over an `AttributedString`, rather than a row of views.
    ///
    /// A stack of per-word views cannot wrap mid-sentence, which is the one
    /// thing a diff line has to do. Concatenated `Text` cannot carry a
    /// background either — `.background` returns a view, not a `Text`, so the
    /// pieces stop being concatenable. An attributed string does both: it
    /// reflows as one run of type and takes a background per segment.
    private func marked(_ segments: [DiffSegment], emphasis: Color) -> Text {
        var string = AttributedString()
        for segment in segments {
            var run = AttributedString(segment.text)
            if segment.kind != .unchanged {
                run.backgroundColor = emphasis
            }
            string.append(run)
        }
        return Text(string)
    }

    /// VoiceOver gets the whole change as a sentence. Reading a tinted run of
    /// words aloud without saying what the tint means is worse than useless.
    private var accessibilityDescription: String {
        if hunk.before.isEmpty { return "Added: \(hunk.after)" }
        if hunk.after.isEmpty { return "Removed: \(hunk.before)" }
        return "Changed from: \(hunk.before). To: \(hunk.after)"
    }
}

/// A pending rewrite in the queue.
public struct ProposalCard: View {
    @Environment(\.chamferNow) private var now

    private let proposal: Proposal
    private let onAccept: () -> Void
    private let onReject: () -> Void
    private let onOpen: (() -> Void)?

    public init(
        _ proposal: Proposal,
        onAccept: @escaping () -> Void = {},
        onReject: @escaping () -> Void = {},
        onOpen: (() -> Void)? = nil
    ) {
        self.proposal = proposal
        self.onAccept = onAccept
        self.onReject = onReject
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            Header(proposal: proposal, subtitle: subtitle)
            if let first = proposal.hunks.first {
                DiffHunkView(first)
            }
            if proposal.hunks.count > 1 {
                Overflow(count: proposal.hunks.count - 1)
            }
            Actions(onAccept: onAccept, onReject: onReject, onOpen: onOpen)
        }
        .padding(Chamfer.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Chamfer.Palette.paper)
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
                .strokeBorder(Chamfer.Palette.paperStroke, lineWidth: 1)
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
        let onOpen: (() -> Void)?

        var body: some View {
            HStack(spacing: Chamfer.Space.snug) {
                Button("Accept", action: onAccept)
                    .buttonStyle(ChamferButtonStyle(.primary))
                Button("Reject", action: onReject)
                    .buttonStyle(ChamferButtonStyle(.secondary))
                Spacer()
                if let onOpen {
                    Button("Open note", action: onOpen)
                        .buttonStyle(ChamferButtonStyle(.quiet))
                }
            }
        }
    }
}
