import ChamferCore
import SwiftUI

/// Which note to open, out of everything in one vault.
///
/// The button that raises this used to open `searchableNotes.first { … }` —
/// whichever note the directory listing happened to return first. That is a
/// coin flip on any vault with more than one note in it, and a control whose
/// label says "a note" is already admitting it does not know which.
///
/// Shaped like `NoteChangeHistorySheet` on purpose: a card over a dimmed page, a
/// scrolling list of rows, one verb, Escape and click-away both closing it.
/// The app has one sheet vocabulary and this is it.
struct VaultNotesSheet: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let vaultName: String
    let notes: [NoteSummary]
    let onOpen: (NoteSummary) -> Void
    let onDismiss: () -> Void

    @LegacyState private var query = ""
    @FocusState private var queryFocused: Bool

    /// Newest first, because the note you want is nearly always one you
    /// touched recently — the same order the bar's Notes list uses.
    private var matches: [NoteSummary] {
        let sorted = notes.sorted { left, right in
            if left.modifiedAt != right.modifiedAt {
                return left.modifiedAt > right.modifiedAt
            }
            return left.url.path < right.url.path
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.url.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Only worth a field when the list is long enough to be worth narrowing.
    /// A search box over four notes is furniture.
    private var showsFilter: Bool { notes.count > 8 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
                header

                if showsFilter { filterField }

                if notes.isEmpty {
                    message("Chamfer hasn't found any notes in this vault yet.")
                } else if matches.isEmpty {
                    message("No note here matches “\(query)”.")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Chamfer.Space.tight) {
                            ForEach(matches) { note in
                                NoteChoiceRow(note: note) { onOpen(note) }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onDismiss)
                        .buttonStyle(ChamferButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(Chamfer.Space.loose)
            .frame(width: 460)
            .background(Chamfer.Palette.paper)
            .clipShape(
                RoundedRectangle(cornerRadius: Chamfer.Radius.large, style: .continuous)
            )
            .chamferRing(radius: Chamfer.Radius.large)
            .chamferFloat()
            .transition(sheetTransition)
        }
        .onAppear { queryFocused = showsFilter }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
            Text(vaultName)
                .font(Chamfer.TypeScale.title)
                .foregroundStyle(Chamfer.Palette.textOnPaper)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(notes.count == 1 ? "1 note" : "\(notes.count.formatted()) notes")
                .font(Chamfer.TypeScale.caption)
                .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
        }
    }

    private var filterField: some View {
        TextField("Filter", text: $query)
            .textFieldStyle(.plain)
            .font(Chamfer.TypeScale.body)
            .foregroundStyle(Chamfer.Palette.textOnPaper)
            .focused($queryFocused)
            .padding(.horizontal, Chamfer.Space.regular)
            .padding(.vertical, Chamfer.Space.snug)
            .background(Chamfer.Palette.paperSunken)
            .clipShape(
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
            )
            .accessibilityLabel("Filter notes in this vault")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Chamfer.TypeScale.body)
            .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
            .padding(.vertical, Chamfer.Space.regular)
    }

    private var sheetTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
    }
}

private struct NoteChoiceRow: View {
    @Environment(\.chamferNow) private var now
    @LegacyState private var isHovered = false

    let note: NoteSummary
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.regular) {
                VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                    Text(note.title)
                        .font(Chamfer.TypeScale.bodyStrong)
                        .foregroundStyle(Chamfer.Palette.textOnPaper)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(Chamfer.TypeScale.caption)
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Chamfer.Space.snug)
                Text(RelativeTime.string(note.modifiedAt, since: now))
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
            }
            .padding(Chamfer.Space.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Chamfer.Palette.paperSunken : .clear)
            .clipShape(
                RoundedRectangle(cornerRadius: Chamfer.Radius.small, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .chamferFocusable(radius: Chamfer.Radius.small)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(note.title), \(detail)")
        .accessibilityAddTraits(.isButton)
    }

    /// The folder it sits in, so two notes called "Notes" are tellable apart.
    private var detail: String {
        let folder = note.url.deletingLastPathComponent().lastPathComponent
        return "\(folder) · \(note.wordCount.formatted()) words"
    }
}
