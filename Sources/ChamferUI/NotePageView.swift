import ChamferCore
import SwiftUI

/// A deliberately plain editor for raw Markdown. Its model is owned by the
/// dashboard so an unsaved draft and any write error survive page navigation.
struct NotePageView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: NoteEditorModel

    let onTextChange: (String) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                Spacer(minLength: Chamfer.Page.margin)

                PlainTextEditor(text: $model.text)
                    .frame(maxWidth: Chamfer.Page.measure)
                    .accessibilityLabel("Note text")

                Spacer(minLength: Chamfer.Page.margin)
            }
            .padding(.top, 58)
            .padding(.bottom, 50)

            if let message = model.saveErrorMessage {
                Text(message)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.danger)
                    .padding(.leading, Chamfer.Page.margin)
                    .padding(.bottom, 24)
                    .accessibilityLabel("Autosave error: \(message)")
            }
        }
        .background(Chamfer.Palette.page)
        .onChange(of: model.text) {
            onTextChange(model.text)
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(document.text)
                .font(Chamfer.TypeScale.pageBody)
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineSpacing(7)
                .textSelection(.enabled)
                .frame(maxWidth: Chamfer.Page.measure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, Chamfer.Page.margin)
                .padding(.top, 64)
                .padding(.bottom, 56)
        }
        .scrollContentBackground(.hidden)
        .background(Chamfer.Palette.page)
    }
}
