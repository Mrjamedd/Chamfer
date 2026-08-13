import ChamferUI
import SwiftUI

enum AboutWindow {
    static let id = "about-chamfer"
}

/// Replaces the generic bundle panel with the same small editorial voice as
/// the welcome. The version remains the single value update support already
/// exposes rather than becoming a second string to keep in sync.
struct AboutChamferView: View {
    var body: some View {
        VStack(spacing: Chamfer.Space.regular) {
            Text("Chamfer")
                .font(Chamfer.TypeScale.pageTitle)
                .foregroundStyle(Chamfer.Palette.pageText)

            Text(AppUpdates.versionDescription)
                .font(Chamfer.TypeScale.captionStrong)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)

            Rectangle()
                .fill(Chamfer.Palette.brass)
                .frame(width: Chamfer.Space.section, height: 1)
                .padding(.vertical, Chamfer.Space.tight)

            Text(WelcomeFlow.slides[0].title)
                .font(Chamfer.TypeScale.pageSubtitle)
                .foregroundStyle(Chamfer.Palette.pageText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Chamfer.Space.section)
        .frame(width: 360)
        .background(Chamfer.Palette.page)
    }
}

struct AboutChamferCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Chamfer") {
            openWindow(id: AboutWindow.id)
        }
    }
}
