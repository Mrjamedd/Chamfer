import SwiftUI

/// Shared page chrome: the same measure and margins everywhere, so every
/// destination reads as the same sheet of paper.
///
/// Lives here rather than inside `DashboardView` because it is now the thing
/// that makes Review, Vaults and History look like one app. A page that set
/// its own margins would be visible as a different page the moment you
/// switched to it.
struct PageScroll<Content: View>: View {
    let title: String
    /// Sits to the right of the title, on its baseline. Only for controls that
    /// act on the whole page — a bulk action, a count. Anything about a single
    /// row belongs on that row.
    var accessory: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Chamfer.Space.regular) {
                    Text(title)
                        .font(Chamfer.TypeScale.pageTitle)
                        .foregroundStyle(Chamfer.Palette.pageText)
                    if let accessory {
                        Spacer(minLength: Chamfer.Space.regular)
                        accessory
                    }
                }
                .padding(.bottom, Chamfer.Space.loose)
                content
            }
            .frame(maxWidth: Chamfer.Page.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Chamfer.Page.margin)
            .padding(.top, 64)
            .padding(.bottom, 56)
        }
        .scrollContentBackground(.hidden)
    }
}

/// The page's own empty state: centred, quiet, and always saying what would
/// put something here.
///
/// Takes an optional action, because most of this app's empty states are not
/// waiting for time to pass — they are waiting for the user to connect a vault,
/// and telling somebody what to do while giving them no way to do it is the
/// difference between an empty state and a dead end. The shipping app opened on
/// exactly that dead end.
struct PageMessage: View {
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Chamfer.Space.snug) {
            Text(title)
                .font(Chamfer.TypeScale.pageHeading)
                .foregroundStyle(Chamfer.Palette.pageText)
            Text(detail)
                .font(Chamfer.TypeScale.body)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if let actionTitle, let action {
                Button(actionTitle) {
                    Haptics.pop()
                    action()
                }
                .buttonStyle(ChamferButtonStyle(.primary))
                .padding(.top, Chamfer.Space.snug)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A quiet division between stretches of a page.
///
/// A hairline rather than a heading where the change of subject is obvious —
/// the timeline's drop from "waiting on you" into "already done" reads from
/// the content itself, and a second big title there would compete with the
/// page's own.
struct PageRule: View {
    var body: some View {
        Rectangle()
            .fill(Chamfer.Palette.paperStroke)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// A group heading inside a page: small, tracked-out capitals with an optional
/// count, matching `SectionHeader` but sized for the serif page rather than
/// for a card.
struct PageSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: Chamfer.Space.snug) {
            Text(title.uppercased())
                .font(Chamfer.TypeScale.captionStrong)
                .kerning(0.8)
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
            if let count {
                Text("\(count)")
                    .font(Chamfer.TypeScale.captionStrong)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
                    .padding(.horizontal, Chamfer.Space.tight + 1)
                    .padding(.vertical, 1)
                    .background(Chamfer.Palette.paperSunken)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}
