import ChamferCore
import Foundation
import SwiftUI

/// The facts above a note are a snapshot of the index at the moment it opens.
///
/// In particular, neither the word count nor title visibility follows the live
/// editor text. Those facts belong to the saved document, and recomputing them
/// while somebody types would make quiet page chrome part of the hot path.
struct NotePageMetadata: Equatable {
    let title: String
    let vaultName: String
    let wordCount: Int
    let modifiedAt: Date?
    let showsFilenameTitle: Bool

    static func snapshot(
        for document: NoteDocument,
        in state: DashboardState
    ) -> NotePageMetadata {
        let key = document.url.standardizedFileURL
        let summary = state.recentNotes.first {
            $0.url.standardizedFileURL == key
        }
        let vault = state.vaults
            .filter {
                NoteEligibility.relativePath(of: key, under: $0.url) != nil
            }
            .max {
                $0.url.standardizedFileURL.pathComponents.count
                    < $1.url.standardizedFileURL.pathComponents.count
            }

        return NotePageMetadata(
            // The editable H1 is what the note calls itself. This title is the
            // file's identity, so deriving it from indexed heading text would
            // make the two labels duplicates with different responsibilities.
            title: key.deletingPathExtension().lastPathComponent,
            vaultName: vault?.name
                ?? key.deletingLastPathComponent().lastPathComponent,
            // Real connected notes have a summary. The fallback is taken once
            // for fixture and degraded states, never recomputed as text moves.
            wordCount: summary?.wordCount
                ?? document.text.split { $0.isWhitespace || $0.isNewline }.count,
            modifiedAt: summary?.modifiedAt,
            showsFilenameTitle: showsFilenameTitle(in: document.text)
        )
    }

    func detail(since reference: Date) -> String {
        var parts = [vaultName, "\(wordCount.formatted()) words"]
        if let modifiedAt {
            parts.append("edited \(RelativeTime.string(modifiedAt, since: reference))")
        }
        return parts.joined(separator: " · ")
    }

    static func showsFilenameTitle(in text: String) -> Bool {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var index = 0

        while index < lines.count, lines[index].isEmpty { index += 1 }

        // Front matter is file metadata rather than prose. A first H1 after
        // it still opens the human-readable note and would still be repeated
        // by a filename title above the editor.
        if index < lines.count, lines[index] == "---" || lines[index] == "+++" {
            let fence = lines[index]
            index += 1
            while index < lines.count, lines[index] != fence { index += 1 }
            if index < lines.count { index += 1 }
            while index < lines.count, lines[index].isEmpty { index += 1 }
        }

        guard index < lines.count else { return true }
        let line = lines[index]
        guard line.hasPrefix("#"), !line.hasPrefix("##") else { return true }
        let remainder = line.dropFirst()
        guard let separator = remainder.first,
              separator == " " || separator == "\t",
              !remainder.trimmingCharacters(in: .whitespaces).isEmpty
        else { return true }
        return false
    }
}

/// The editor owns the live draft. The surrounding header reads only its
/// opening snapshot, and the footer observes the coarse save state rather than
/// the text itself, so repeated keystrokes stay local to the native editor.
struct NotePageView: View {
    let model: NoteEditorModel
    let metadata: NotePageMetadata

    var body: some View {
        VStack(spacing: 0) {
            NotePageHeader(metadata: metadata, isReadOnly: false)

            EditableNoteBody(model: model)
                .padding(.top, Chamfer.Space.roomy)
                .padding(.bottom, Chamfer.Space.snug)

            ObservedNoteSaveFooter(model: model)
        }
        .background(Chamfer.Palette.page)
    }
}

private struct EditableNoteBody: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: NoteEditorModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: Chamfer.Page.margin)

            PlainTextEditor(text: $model.text)
                .frame(maxWidth: Chamfer.Page.measure)
                .accessibilityLabel("Note text")

            Spacer(minLength: Chamfer.Page.margin)
        }
        .onChange(of: model.text) {
            model.textDidChange()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            model.flush()
        }
        .onDisappear {
            model.flush()
        }
    }
}

/// Fixture notes without a real file remain selectable and copyable, but are
/// visibly read-only instead of accepting edits that cannot be persisted.
struct ReadOnlyNotePageView: View {
    let document: NoteDocument
    let metadata: NotePageMetadata

    var body: some View {
        VStack(spacing: 0) {
            NotePageHeader(metadata: metadata, isReadOnly: true)

            ScrollView(.vertical, showsIndicators: false) {
                Text(document.text)
                    .font(Chamfer.TypeScale.pageBody)
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .frame(maxWidth: Chamfer.Page.measure, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, Chamfer.Page.margin)
                    .padding(.top, Chamfer.Space.roomy)
                    .padding(.bottom, Chamfer.Space.section)
            }
            .scrollContentBackground(.hidden)

            NoteSaveFooter(status: .saved)
        }
        .background(Chamfer.Palette.page)
    }
}

private struct NotePageHeader: View {
    @Environment(\.chamferNow) private var now

    let metadata: NotePageMetadata
    let isReadOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if metadata.showsFilenameTitle {
                HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.roomy) {
                    Text(metadata.title)
                        .font(Chamfer.TypeScale.pageTitle)
                        .foregroundStyle(Chamfer.Palette.pageText)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Spacer(minLength: Chamfer.Space.roomy)

                    if isReadOnly {
                        readOnlyPill
                    }
                }

                metadataLine
                    .padding(.top, Chamfer.Space.snug)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.roomy) {
                    metadataLine
                    Spacer(minLength: Chamfer.Space.roomy)
                    if isReadOnly {
                        readOnlyPill
                    }
                }
            }

            PageRule()
                .padding(.top, Chamfer.Space.roomy)
        }
        .frame(maxWidth: Chamfer.Page.measure, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Chamfer.Page.margin)
        .padding(.top, Chamfer.Page.margin)
    }

    private var metadataLine: some View {
        Text(metadata.detail(since: now))
            .font(Chamfer.TypeScale.caption)
            .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var readOnlyPill: some View {
        Pill("Read only", symbol: "lock", tone: .neutral)
    }
}

private struct ObservedNoteSaveFooter: View {
    @Bindable var model: NoteEditorModel

    var body: some View {
        NoteSaveFooter(status: model.saveStatus)
    }
}

private struct NoteSaveFooter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let status: NoteSaveStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageRule()

            ZStack(alignment: .leading) {
                if status != .saved {
                    statusLabel
                        .id(status)
                        .transition(statusTransition)
                }
            }
            .font(Chamfer.TypeScale.caption)
            .frame(
                maxWidth: .infinity,
                minHeight: Chamfer.Space.section,
                maxHeight: Chamfer.Space.section,
                alignment: .topLeading
            )
            .padding(.top, Chamfer.Space.snug)
        }
        .frame(maxWidth: Chamfer.Page.measure, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Chamfer.Page.margin)
        // Matching the page's side margin below the rule moves this terminus
        // into the writing column while leaving calm paper beneath it.
        .padding(.bottom, Chamfer.Page.margin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityHidden(accessibilityLabel == nil)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .saved:
            EmptyView()
        case .saving:
            Text("Saving…")
                .foregroundStyle(Chamfer.Palette.textOnPaperSoft)
        case let .failed(message):
            Text(message)
                .foregroundStyle(Chamfer.Palette.danger)
                .lineLimit(2)
        }
    }

    /// A status arrives calmly and leaves in half the time. Opacity alone is
    /// enough here: moving the label would make the page beneath quiet prose
    /// look busier than the save itself warrants.
    private var statusTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(
                Chamfer.Motion.reduce(
                    Chamfer.Motion.contentArrival,
                    when: reduceMotion
                )
            ),
            removal: .opacity.animation(
                Chamfer.Motion.reduce(
                    Chamfer.Motion.contentDeparture,
                    when: reduceMotion
                )
            )
        )
    }

    private var accessibilityLabel: String? {
        switch status {
        case .saved: nil
        case .saving: "Saving"
        case let .failed(message): "Autosave error: \(message)"
        }
    }
}
