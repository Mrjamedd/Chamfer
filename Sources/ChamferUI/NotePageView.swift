import ChamferCore
import SwiftUI

/// The note itself, set as a printed page: white, black serif type, wide
/// margins, floating on the canvas.
public struct NotePageView: View {
    private let document: NoteDocument

    public init(_ document: NoteDocument) {
        self.document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Block.parse(document.text).enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .frame(maxWidth: Chamfer.Page.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Chamfer.Page.margin)
            .padding(.top, 64)
            .padding(.bottom, 56)
        }
        .scrollContentBackground(.hidden)
        .background(Chamfer.Palette.page)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case let .title(text):
            Text(text)
                .font(Chamfer.TypeScale.pageTitle)
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineSpacing(2)
                .padding(.bottom, Chamfer.Space.loose)
        case let .heading(text):
            Text(text)
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
                .padding(.top, Chamfer.Space.loose)
                .padding(.bottom, Chamfer.Space.snug)
        case let .paragraph(text):
            Text(text)
                .font(Chamfer.TypeScale.pageBody)
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineSpacing(9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Chamfer.Space.roomy)
        }
    }
}

/// The little of Markdown the page needs to render. Deliberately not a full
/// parser — headings and paragraphs are what a note is made of, and anything
/// more belongs in the rule engine, not the view.
enum Block {
    case title(String)
    case heading(String)
    case paragraph(String)

    static func parse(_ text: String) -> [Block] {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { chunk in
                if chunk.hasPrefix("## ") {
                    .heading(String(chunk.dropFirst(3)))
                } else if chunk.hasPrefix("# ") {
                    .title(String(chunk.dropFirst(2)))
                } else {
                    .paragraph(chunk)
                }
            }
    }
}
