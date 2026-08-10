import SwiftUI

/// The orange mark that says a vault is not finished being set up.
///
/// A status indicator, not a warning. Nothing is broken and nothing has been
/// lost — a connected vault simply is not usable until it has been told what to
/// do, and this is what says so. So: no red, no exclamation, no glyph at all.
/// A filled dot is the quietest thing that can still be noticed, and it reads
/// as *incomplete* where a badge with a mark in it reads as *wrong*.
public struct AttentionDot: View {
    public enum Size {
        /// Fixed to a glyph in the bar, where it has to survive the bar folding
        /// away and must not look like something that landed there by accident.
        case badge
        /// Beside a heading on the page.
        case inline

        var diameter: CGFloat {
            switch self {
            case .badge: 7
            case .inline: 8
            }
        }
    }

    private let size: Size
    /// The colour immediately behind the dot. A badge sits *on* something, and
    /// the way that reads as attached rather than floating is a ring of the
    /// surface punched out around it — the same trick every badge on this
    /// platform uses.
    private let punchedOutOf: Color?
    private let label: String

    public init(
        _ size: Size = .inline,
        punchedOutOf: Color? = nil,
        label: String = "Not set up yet"
    ) {
        self.size = size
        self.punchedOutOf = punchedOutOf
        self.label = label
    }

    public var body: some View {
        Circle()
            .fill(Chamfer.Palette.attention)
            .frame(width: size.diameter, height: size.diameter)
            .padding(punchedOutOf == nil ? 0 : 1.5)
            .background {
                if let punchedOutOf {
                    Circle().fill(punchedOutOf)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}
