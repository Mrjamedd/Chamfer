import SwiftUI

/// A named set of related controls on paper.
///
/// The light mark and tracked heading make the subject findable; the caption
/// carries context once for the group so each row can stay about its own
/// choice. Shared by app Settings and each vault's policy editor so the same
/// kind of content always arrives in the same surface vocabulary.
struct ConfigurationGroup<Content: View>: View {
    let title: String
    let caption: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Chamfer.Space.regular) {
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                HStack(spacing: Chamfer.Space.tight + 2) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                        .frame(width: 12)
                    Text(title.uppercased())
                        .font(Chamfer.TypeScale.captionStrong)
                        .kerning(0.8)
                        .foregroundStyle(Chamfer.Palette.pageTextSoft)
                }
                Text(caption)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    // Aligned under the title rather than the icon, so the
                    // heading reads as one object with a mark in front of it.
                    .padding(.leading, 12 + Chamfer.Space.tight + 2)
            }

            content
        }
        .padding(Chamfer.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A region set into the page rather than a card laid on it. One shade,
        // a hairline, and the app's shared middle radius are enough to gather
        // the controls without making a second page inside the first.
        .background(Chamfer.Palette.pageInset)
        .clipShape(
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Chamfer.Radius.medium, style: .continuous)
                .strokeBorder(Chamfer.Palette.pageInsetStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
