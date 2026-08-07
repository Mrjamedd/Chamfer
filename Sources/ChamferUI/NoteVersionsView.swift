import ChamferCore
import SwiftUI

/// The gutter's second control: this note's own history.
///
/// Shaped exactly like `FloatingCloseButton` because it answers the same
/// gesture. The gutter is already the place you move the pointer when you want
/// something done *to* the page rather than *in* it, so versions belong there
/// and nowhere on the page itself.
public struct FloatingVersionsButton: View {
    @State private var isHovered = false

    private let count: Int
    private let action: () -> Void
    private let onHover: (Bool) -> Void

    public init(
        count: Int,
        onHover: @escaping (Bool) -> Void = { _ in },
        action: @escaping () -> Void
    ) {
        self.count = count
        self.onHover = onHover
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.pop()
            action()
        } label: {
            HStack(spacing: Chamfer.Space.tight + 1) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(Chamfer.TypeScale.captionStrong)
                    .monospacedDigit()
            }
            .foregroundStyle(Chamfer.Palette.textOnPaper)
            .padding(.horizontal, Chamfer.Space.regular)
            .frame(height: 32)
            .background {
                Capsule()
                    .fill(Chamfer.Palette.bar)
                    .overlay {
                        Capsule()
                            .fill(Chamfer.Palette.hoverTint)
                            .opacity(isHovered ? 1 : 0)
                    }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Chamfer.Palette.barStroke, lineWidth: 1))
            // Same trick as the close button: reads small, answers big.
            .padding(6)
            .contentShape(Rectangle())
            .padding(-6)
        }
        .buttonStyle(.plain)
        .chamferHoverRing(isHovered, radius: Chamfer.Radius.pill)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .help("Earlier versions of this note")
        .accessibilityLabel("\(count) earlier version\(count == 1 ? "" : "s")")
    }
}

/// Every version of one note, newest first, each restorable.
///
/// Deliberately not a diff viewer. Version 1.0 restores whole versions, so
/// this shows what each one was and how it got there, and the only verb is
/// "restore".
struct NoteVersionsSheet: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let noteTitle: String
    let entries: [HistoryEntry]
    let onRestore: (HistoryEntry) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                header

                if entries.isEmpty {
                    Text("Chamfer hasn't changed this note yet.")
                        .font(Chamfer.TypeScale.body)
                        .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                        .padding(.vertical, Chamfer.Space.regular)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                            ForEach(entries) { entry in
                                VersionRow(
                                    entry: entry,
                                    onRestore: { onRestore(entry) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 320)

                    Text("Restoring writes the earlier text back to the note and keeps a snapshot of what it replaced.")
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Done", action: onDismiss)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(Chamfer.Space.loose)
            .frame(width: 460)
            .background(Chamfer.Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous))
            .chamferFloat()
            .transition(sheetTransition)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
            Text(noteTitle)
                .font(Chamfer.TypeScale.title)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entries.isEmpty ? "No earlier versions" : "\(entries.count) earlier version\(entries.count == 1 ? "" : "s")")
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
        }
    }

    private var sheetTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
    }
}

private struct VersionRow: View {
    @Environment(\.chamferNow) private var now
    @State private var isHovered = false

    let entry: HistoryEntry
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.regular) {
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(RelativeTime.string(entry.occurredAt, since: now))
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(Chamfer.Palette.textOnPaper)
                Text(entry.summary(since: now))
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure = entry.outcome.failure {
                    Text(failure.title)
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.danger)
                }
            }

            Spacer(minLength: Chamfer.Space.snug)

            if entry.canRestore {
                Button("Restore") {
                    Haptics.commit()
                    onRestore()
                }
                .buttonStyle(ChamferButtonStyle(.secondary))
                .opacity(isHovered ? 1 : 0.45)
            }
        }
        .padding(Chamfer.Space.snug)
        .background(isHovered ? Chamfer.Palette.paperSunken : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
