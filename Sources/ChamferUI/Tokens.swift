import AppKit
import SwiftUI

/// The design system's vocabulary. Nothing in `ChamferUI` hardcodes a colour,
/// a radius or a font size — if a value is worth using twice it belongs here.
public enum Chamfer {}

// MARK: - Colour

public extension Chamfer {
    /// A fixed theme rather than an appearance-following one: beige paper,
    /// dark ink, one pink highlight. The look is the brand, so it does not
    /// change with the system setting.
    enum Palette {
        // Warm cream throughout, with the page only a shade lighter than the
        // canvas it sits on. Separation comes from the shadow, not from
        // contrast.
        public static let canvas = rgb(0xF8EEDC)
        public static let canvasDeep = rgb(0xF0E4CE)
        public static let paper = rgb(0xFFFBF5)
        public static let paperSunken = rgb(0xF2E7D4)
        public static let paperStroke = rgb(0xE6D9C1)
        /// The bar sits deeper than the canvas so it reads as a distinct
        /// object rather than as part of the background.
        public static let bar = rgb(0xE8DBC4)
        public static let barStroke = rgb(0xDCCBAE)
        /// Interface hover feedback stays translucent so the material beneath
        /// it still reads, but leans toward ink rather than flashing white.
        public static let hoverTint = Color.black.opacity(0.075)
        /// The bottom bar's selected destination is an opaque black control,
        /// matching the reference rather than reading as tinted glass.
        public static let selectionTint = Color.black
        /// The hover ring: the one signal that says "the pointer is on this",
        /// used by every interactive surface in the app. Deliberately barely
        /// there — it should be felt more than seen.
        public static let ring = rgb(0xE79BC0).opacity(0.38)
        public static let barRing = rgb(0xE79BC0).opacity(0.20)
        public static let ringWidth: CGFloat = 1
        /// The same pink, drawn to be seen rather than felt.
        ///
        /// Keyboard focus has to be unambiguous in a way hover does not: the
        /// pointer user knows where they are pointing, and the keyboard user
        /// only knows what the ring tells them.
        public static let focusRing = rgb(0xE079AC)
        public static let focusRingWidth: CGFloat = 2

        /// A region set very slightly into the page.
        ///
        /// Barely a shade off `page` on purpose: enough to group what sits on
        /// it, not enough to read as a card. `paperSunken` was the nearest
        /// existing value and is twice as dark as this wants — four of those
        /// stacked in a panel would look like boxed settings rows, which is
        /// exactly what this is avoiding.
        public static let pageInset = rgb(0xFBF6EC)
        /// The hairline around an inset region, when it needs one at all.
        public static let pageInsetStroke = rgb(0xF1E7D6)
        /// Amber at the strength a resting surface can carry.
        public static let attentionSoft = rgb(0xF0A020).opacity(0.10)
        public static let attentionRing = rgb(0xF0A020).opacity(0.40)

        // The note page: the lightest surface, with black type on it.
        public static let page = rgb(0xFFFCF7)
        public static let pageText = rgb(0x14110E)
        public static let pageTextSoft = rgb(0x5A5248)

        // Ink
        public static let ink = rgb(0x1A1613)
        public static let inkSunken = rgb(0x241E19)
        public static let inkStroke = rgb(0x342C24)

        // Type
        public static let textOnPaper = rgb(0x201B15)
        public static let textOnPaperSoft = rgb(0x6E6355)
        public static let textOnPaperFaint = rgb(0x9A8E7D)
        public static let textOnInk = rgb(0xF7F1E6)
        public static let textOnInkSoft = rgb(0xB5A896)
        public static let textOnInkFaint = rgb(0x877B6B)

        // Accents
        public static let brass = rgb(0xA8752A)
        public static let brassSoft = rgb(0xF0E4CE)
        public static let pink = rgb(0xFF7DB4)
        public static let pinkSoft = rgb(0xF6D2E3)
        public static let pinkOnInk = rgb(0xFF9CC6)

        /// The "waiting on you" amber, following Apple's warning badge rather
        /// than inventing a colour. Not the brass accent: brass is decoration
        /// and this has to be noticed.
        public static let attention = rgb(0xF0A020)
        public static let positive = rgb(0x3B7A55)
        public static let positiveSoft = rgb(0xDCEADF)
        public static let positiveOnInk = rgb(0x7CCB9E)
        public static let danger = rgb(0xB3402F)
        public static let dangerSoft = rgb(0xF3DCD6)
        public static let dangerOnInk = rgb(0xF0806C)

        // Diff tints, which need separate values per surface to stay legible.
        //
        // Two strengths each. The wash goes behind the whole line so it is
        // clear which side is which; the emphasis goes behind the words that
        // actually moved. The gap between them is what carries the meaning —
        // wide enough to find at a glance, narrow enough that a line whose
        // every word changed does not turn into a solid block.
        public static let removedOnPaper = rgb(0xF6E2DC)
        public static let addedOnPaper = rgb(0xE1EDE2)
        public static let removedOnInk = rgb(0x30201C)
        public static let addedOnInk = rgb(0x1D2C22)
        public static let removedEmphasisOnPaper = rgb(0xEEC3B7)
        public static let addedEmphasisOnPaper = rgb(0xC0DCC5)
        public static let removedEmphasisOnInk = rgb(0x4A2C24)
        public static let addedEmphasisOnInk = rgb(0x27452F)

        static func rgb(_ value: UInt32) -> Color {
            Color(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }
}

// MARK: - Surface

/// Which surface a view is currently sitting on.
///
/// Components read this from the environment instead of hardcoding a text
/// colour, which is what lets a card invert to ink on hover and have
/// everything inside it follow without any view knowing about hover.
public enum SurfaceMode: Sendable, Hashable, CaseIterable {
    case paper
    case ink

    public var background: Color {
        switch self {
        case .paper: Chamfer.Palette.paper
        case .ink: Chamfer.Palette.ink
        }
    }

    public var sunken: Color {
        switch self {
        case .paper: Chamfer.Palette.paperSunken
        case .ink: Chamfer.Palette.inkSunken
        }
    }

    public var stroke: Color {
        switch self {
        case .paper: Chamfer.Palette.paperStroke
        case .ink: Chamfer.Palette.inkStroke
        }
    }

    public var textPrimary: Color {
        switch self {
        case .paper: Chamfer.Palette.textOnPaper
        case .ink: Chamfer.Palette.textOnInk
        }
    }

    public var textSecondary: Color {
        switch self {
        case .paper: Chamfer.Palette.textOnPaperSoft
        case .ink: Chamfer.Palette.textOnInkSoft
        }
    }

    public var textFaint: Color {
        switch self {
        case .paper: Chamfer.Palette.textOnPaperFaint
        case .ink: Chamfer.Palette.textOnInkFaint
        }
    }

    /// Brass on paper, pink on ink — the accent picks up the shine.
    public var accent: Color {
        switch self {
        case .paper: Chamfer.Palette.brass
        case .ink: Chamfer.Palette.pinkOnInk
        }
    }

    public var accentSoft: Color {
        switch self {
        case .paper: Chamfer.Palette.brassSoft
        case .ink: Chamfer.Palette.inkSunken
        }
    }

    public var positive: Color {
        switch self {
        case .paper: Chamfer.Palette.positive
        case .ink: Chamfer.Palette.positiveOnInk
        }
    }

    public var positiveSoft: Color {
        switch self {
        case .paper: Chamfer.Palette.positiveSoft
        case .ink: Chamfer.Palette.inkSunken
        }
    }

    public var danger: Color {
        switch self {
        case .paper: Chamfer.Palette.danger
        case .ink: Chamfer.Palette.dangerOnInk
        }
    }

    public var dangerSoft: Color {
        switch self {
        case .paper: Chamfer.Palette.dangerSoft
        case .ink: Chamfer.Palette.inkSunken
        }
    }

    public var removedFill: Color {
        switch self {
        case .paper: Chamfer.Palette.removedOnPaper
        case .ink: Chamfer.Palette.removedOnInk
        }
    }

    public var addedFill: Color {
        switch self {
        case .paper: Chamfer.Palette.addedOnPaper
        case .ink: Chamfer.Palette.addedOnInk
        }
    }

    /// Behind the words that actually changed, over `removedFill`.
    public var removedEmphasis: Color {
        switch self {
        case .paper: Chamfer.Palette.removedEmphasisOnPaper
        case .ink: Chamfer.Palette.removedEmphasisOnInk
        }
    }

    public var addedEmphasis: Color {
        switch self {
        case .paper: Chamfer.Palette.addedEmphasisOnPaper
        case .ink: Chamfer.Palette.addedEmphasisOnInk
        }
    }
}

// MARK: - Space, shape, motion

public extension Chamfer {
    enum Space {
        public static let hair: CGFloat = 2
        public static let tight: CGFloat = 4
        public static let snug: CGFloat = 8
        public static let regular: CGFloat = 12
        public static let roomy: CGFloat = 16
        public static let loose: CGFloat = 24
        public static let section: CGFloat = 32
    }

    enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 18
        public static let pill: CGFloat = 999
    }

    enum Motion {
        public static let quickDuration: TimeInterval = 0.10
        public static let interactiveDuration: TimeInterval = 0.20
        public static let navigationDuration: TimeInterval = 0.30
        public static let reducedDuration: TimeInterval = 0.12

        /// A spring rather than an ease, at the same 100ms. At this length the
        /// two are all but indistinguishable standing still — the difference
        /// shows when you interrupt one. An ease restarts from a standstill
        /// every time it is retargeted, so flicking the pointer on and off
        /// something makes it stutter; a spring carries its velocity across and
        /// simply changes direction. Critically damped, so it never overshoots.
        public static let quick = Animation.spring(
            duration: quickDuration,
            bounce: 0
        )
        /// What every `reduceMotion` branch animates with.
        ///
        /// Deliberately its own token rather than an alias for `quick`. The two
        /// answer different questions — "how fast should this feel" and "how
        /// little should this move" — and while they shared a value, retuning
        /// the app's response silently retuned its accessibility behaviour.
        ///
        /// Symmetric easing, because what is left under reduced motion is a
        /// cross-fade: a fade has no direction, so it should not be shaped like
        /// something arriving.
        public static let reduced = Animation.easeInOut(duration: reducedDuration)

        /// Picks the reduced curve when the setting is on, the given one when
        /// it is off. Saves every call site spelling out the same ternary.
        public static func reduce(
            _ animation: Animation,
            when reduceMotion: Bool
        ) -> Animation {
            reduceMotion ? reduced : animation
        }
        /// The rise and pink bloom when a card is hovered.
        public static let lift = Animation.spring(
            duration: interactiveDuration,
            bounce: 0.06
        )
        public static let interactive = Animation.spring(
            duration: interactiveDuration,
            bounce: 0.035
        )
        public static let navigation = Animation.spring(
            duration: navigationDuration,
            bounce: 0.02
        )
    }
}

// MARK: - Page and window

public extension Chamfer {
    enum Page {
        /// Width of the text column. At 17pt serif this is roughly 68
        /// characters a line, inside the 60–75 that reads comfortably. The
        /// previous 660 ran to about 88, which is why the lines felt long.
        public static let measure: CGFloat = 540
        /// Space between the column and the edge of the sheet.
        public static let margin: CGFloat = 64
        /// The sheet's natural width: column plus its margins.
        public static var width: CGFloat { measure + margin * 2 }
    }

    /// Fixed, not merely a default. The sheet gets its natural width with a
    /// little cream to spare and stands taller than it is wide — a page, not a
    /// panel — and the window is locked to it so the composition cannot be
    /// pulled out of proportion.
    enum Window {
        public static let width: CGFloat = 780
        /// What the composition was drawn at.
        public static let designedHeight: CGFloat = 860
        /// Never shorter than this. Below it the bar starts crowding the page
        /// and the proportion stops being a page at all.
        public static let minimumHeight: CGFloat = 640
        /// Cream left between the window and the edge of the usable screen, so
        /// the bar reads as floating rather than as resting on the Dock.
        private static let breathingRoom: CGFloat = 32

        /// The designed height, or as much of it as the screen actually has.
        ///
        /// `visibleFrame` already excludes the menu bar and the Dock, so this
        /// is the space genuinely available. A hardcoded 860 was taller than a
        /// laptop display leaves once the Dock is showing, and the first thing
        /// to go was the bottom bar — the app's only navigation.
        public static var height: CGFloat {
            guard let visible = NSScreen.main?.visibleFrame else {
                return designedHeight
            }
            return min(
                designedHeight,
                max(minimumHeight, visible.height - breathingRoom)
            )
        }
    }

    /// Settings is its own window and deliberately a smaller one: it holds
    /// rows of controls rather than a page of prose, so the reading measure
    /// that governs `Window` would leave it mostly empty. Shared with the
    /// gallery so the harness shows it at the size it actually ships at.
    enum SettingsWindow {
        public static let width: CGFloat = 540
        /// Room above the tabs for the traffic lights, now that the window has
        /// no title bar for them to sit in.
        public static let titleBarClearance: CGFloat = 38
        /// What the gallery shows the window at, since a harness has to pick
        /// something. The real window has no fixed height at all — it is as
        /// tall as whichever tab is open.
        public static let previewHeight: CGFloat = 620
    }
}

// MARK: - Type

public extension Chamfer {
    /// Not named `Type` — `Chamfer.Type` would collide with metatype syntax.
    enum TypeScale {
        public static let display = Font.system(size: 26, weight: .semibold)
        public static let title = Font.system(size: 15, weight: .semibold)
        public static let body = Font.system(size: 13, weight: .regular)
        public static let bodyStrong = Font.system(size: 13, weight: .medium)
        public static let caption = Font.system(size: 11, weight: .regular)
        public static let captionStrong = Font.system(size: 11, weight: .semibold)
        public static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)

        // The note page reads as a printed page, so it is set in a serif at
        // reading sizes rather than in the UI font.
        public static let pageTitle = Font.system(size: 40, weight: .bold, design: .serif)
        public static let pageHeading = Font.system(size: 23, weight: .semibold, design: .serif)
        public static let pageBody = Font.system(size: 17, weight: .regular, design: .serif)
        /// The line under a page's heading: the serif voice, but stepped down
        /// far enough that it explains the heading rather than competing with
        /// it. Below `pageBody` because it is not prose to be read at length.
        public static let pageSubtitle = Font.system(size: 15, weight: .regular, design: .serif)
    }
}

// MARK: - Relative time

/// Formats against a supplied reference rather than the wall clock, so the
/// gallery renders identically on every launch.
public enum RelativeTime {
    public static func string(_ date: Date, since reference: Date) -> String {
        let seconds = Int(reference.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3_600) hr ago"
        case ..<604_800: return "\(seconds / 86_400) d ago"
        default: return "\(seconds / 604_800) wk ago"
        }
    }
}
