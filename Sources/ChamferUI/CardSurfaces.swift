import SwiftUI

/// The layered paper surface established by the Models page and shared with
/// pages that need the same hierarchy without inheriting a backend colour.
struct ChamferCardSurface: View {
    struct Tint {
        let primary: Color
        let secondary: Color
    }

    let tint: Tint
    let radius: CGFloat
    let presentation: ModelsSurfacePresentation

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Chamfer.Palette.paper.opacity(presentation.paperOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.primary.opacity(presentation.tintOpacity),
                                tint.secondary.opacity(presentation.secondaryTintOpacity),
                                tint.primary.opacity(0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        tint.primary.opacity(presentation.borderOpacity),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: tint.primary.opacity(presentation.shadowOpacity),
                radius: presentation.shadowRadius,
                y: presentation.shadowY
            )
            .shadow(
                color: Color(red: 0.31, green: 0.21, blue: 0.10)
                    .opacity(presentation.neutralShadowOpacity),
                radius: presentation.neutralShadowRadius,
                y: presentation.neutralShadowY
            )
    }
}

struct ModelsInsetSurface: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Chamfer.Palette.canvas.opacity(0.50))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Chamfer.Palette.paperStroke.opacity(0.72),
                        lineWidth: 1
                    )
            }
    }
}
