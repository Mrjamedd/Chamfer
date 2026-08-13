import ChamferCore
import Foundation
import SwiftUI

/// Copy for the home page. The vocabulary follows the time of day; which line
/// is shown is decided by `HomeGreetingSchedule`.
public enum HomeGreetingRotation {
    private static let general = [
        "Hello, {name}.",
        "What should we dig into today?",
        "Where should we begin?",
        "What is worth returning to?",
        "What is on your mind?",
        "Pick up a thought.",
        "Let’s find the thread.",
        "What deserves a closer look?",
        "A good place to think.",
        "Which idea needs some room?",
        "What are we making sense of?",
        "Start with the interesting part.",
        "There is more here to uncover.",
        "Which note is calling you back?",
        "Let’s continue where you left off.",
        "Make a little space for the idea.",
        "What should we open?",
        "Follow the thought that stayed with you.",
        "Ready when you are.",
        "Let’s see what is taking shape."
    ]

    public static func availableGreetings(hour: Int, name: String) -> [String] {
        let timeSpecific: [String]
        switch hour {
        case 5..<12:
            timeSpecific = [
                "Good morning, {name}.",
                "A fresh page for the morning.",
                "What is worth beginning today?"
            ]
        case 12..<17:
            timeSpecific = [
                "Good afternoon, {name}.",
                "Where should the afternoon take us?",
                "A good moment to gather the threads."
            ]
        case 17..<22:
            timeSpecific = [
                "Good evening, {name}.",
                "What is worth revisiting tonight?",
                "Let’s settle into an idea."
            ]
        default:
            timeSpecific = [
                "Hello, {name}.",
                "A quiet hour for a thought.",
                "What is still on your mind?"
            ]
        }

        return (timeSpecific + general).map {
            $0.replacingOccurrences(of: "{name}", with: name)
        }
    }

    /// The user's first name, as macOS knows it.
    ///
    /// Hardcoding a name is fine in a harness and embarrassing in a shipped
    /// app. Falls back to a greeting that works without one rather than to
    /// somebody else's name.
    public static func currentUserName() -> String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        guard let first = full.split(separator: " ").first, first.count > 1 else {
            return NSUserName()
        }
        return String(first)
    }

    /// The line for a given rotation window.
    ///
    /// The day is folded into the offset so two sessions started at the same
    /// hour on different days do not open on the same greeting.
    public static func text(
        window: Int,
        at date: Date,
        name: String,
        calendar: Calendar = .current
    ) -> String {
        let hour = calendar.component(.hour, from: date)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let greetings = availableGreetings(hour: hour, name: name)
        let offset = day &* 7 &+ hour &+ window
        return greetings[((offset % greetings.count) + greetings.count) % greetings.count]
    }
}

/// When the greeting is allowed to change.
///
/// Two rules, and the second is the reason this is a type rather than a
/// function of the clock:
///
/// 1. It advances once every 45 minutes **the app has been open**, not on a
///    wall-clock boundary. A session is the unit, so the first line lasts the
///    same 45 minutes whether the app opened at 9:00 or at 9:44.
/// 2. It never changes while the home screen is the thing being looked at.
///    The window can come due while you are reading it; the new line waits
///    until you have gone somewhere else and come back. A greeting that
///    rewrote itself under the cursor would be the one piece of copy on the
///    page that behaves like an advertisement.
///
/// The consequence of (2) is deliberate: leave the home screen open all day and
/// the greeting stays put all day. It is a welcome, and it has nobody to
/// welcome while you are already here.
public struct HomeGreetingSchedule: Equatable, Sendable {
    /// Long enough that returning after a coffee is the shortest interval that
    /// can produce a change.
    public static let interval: TimeInterval = 45 * 60

    public let openedAt: Date
    /// The window whose line is currently on screen. Only `resolve` moves it.
    public private(set) var shownWindow: Int

    public init(openedAt: Date, shownWindow: Int = 0) {
        self.openedAt = openedAt
        self.shownWindow = shownWindow
    }

    /// How many 45-minute intervals of app-open time have elapsed.
    public func window(at date: Date) -> Int {
        let elapsed = date.timeIntervalSince(openedAt)
        guard elapsed > 0 else { return 0 }
        return Int(elapsed / Self.interval)
    }

    public func isDue(at date: Date) -> Bool {
        window(at: date) != shownWindow
    }

    /// Catches the shown line up to the current window and returns it.
    ///
    /// Called as the home screen appears, never while it is on screen, which is
    /// what makes rule 2 structural rather than a promise.
    public mutating func resolve(
        at date: Date,
        name: String,
        calendar: Calendar = .current
    ) -> String {
        shownWindow = window(at: date)
        return HomeGreetingRotation.text(
            window: shownWindow,
            at: date,
            name: name,
            calendar: calendar
        )
    }
}

/// The one schedule for the running app.
///
/// Process-scoped because "45 minutes that the app is open" is a fact about the
/// process, not about a view: `HomeScreenView` is created and destroyed every
/// time you leave the home screen and come back, and a schedule living in its
/// state would restart on every visit and never reach 45 minutes.
@MainActor
public final class HomeGreetingClock {
    public static let shared = HomeGreetingClock()

    private var schedule: HomeGreetingSchedule

    public init(openedAt: Date = Date()) {
        schedule = HomeGreetingSchedule(openedAt: openedAt)
    }

    /// The line to show now. Safe to call only when the home screen is about to
    /// appear or has just appeared.
    public func greeting(
        at date: Date = Date(),
        name: String,
        calendar: Calendar = .current
    ) -> String {
        schedule.resolve(at: date, name: name, calendar: calendar)
    }
}

public struct HomeClockAngles: Equatable {
    public let hour: Double
    public let minute: Double
}

public enum HomeClockGeometry {
    public static func handAngles(
        at date: Date,
        calendar: Calendar = .current
    ) -> HomeClockAngles {
        let hour = Double(calendar.component(.hour, from: date) % 12)
        let minute = Double(calendar.component(.minute, from: date))
        let second = Double(calendar.component(.second, from: date))
        let preciseMinute = minute + second / 60

        return HomeClockAngles(
            hour: hour * 30 + preciseMinute * 0.5,
            minute: preciseMinute * 6
        )
    }

    public static func timeText(at date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelveHour):\(String(format: "%02d", minute))"
    }
}

public enum HomeClockHoverMotion {
    public static func nextRotation(after current: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? current : current + 360
    }
}

/// The small amount of note information the home page needs to render a
/// preview and open that preview in the existing note reader.
public struct HomeNoteCardModel: Identifiable, Equatable {
    public enum Source: Equatable {
        case review
        case cleaned
        case open
        case recent
    }

    public enum Role: Equatable {
        case featured
        case supporting
        case recentlyCleaned
        case background
    }

    public let id: String
    public let title: String
    public let detail: String
    public let preview: String
    public let document: NoteDocument
    public let source: Source
    public let isFeatured: Bool
    public let role: Role

    public static func cards(from state: DashboardState) -> [HomeNoteCardModel] {
        Array(deckCards(from: state).prefix(6))
    }

    public static func deckCards(from state: DashboardState) -> [HomeNoteCardModel] {
        let deckLimit = 11
        var cards: [HomeNoteCardModel] = []
        var seenURLs = Set<URL>()
        var cleanupRuleCounts: [URL: Int] = [:]

        for cleanup in state.recentlyCleaned {
            cleanupRuleCounts[cleanup.note.url] = max(
                cleanupRuleCounts[cleanup.note.url, default: 0],
                cleanup.rules.count
            )
        }

        let featuredURL = state.pendingProposals.max { left, right in
            let leftScore = reviewScore(left, cleanupRuleCounts: cleanupRuleCounts)
            let rightScore = reviewScore(right, cleanupRuleCounts: cleanupRuleCounts)
            if leftScore == rightScore {
                return left.note.modifiedAt < right.note.modifiedAt
            }
            return leftScore < rightScore
        }?.note.url

        var visibleProposals = Array(state.pendingProposals.prefix(6))
        if
            let featuredURL,
            !visibleProposals.contains(where: { $0.note.url == featuredURL }),
            let featuredProposal = state.pendingProposals.first(where: { $0.note.url == featuredURL }),
            !visibleProposals.isEmpty
        {
            visibleProposals[visibleProposals.count - 1] = featuredProposal
        }

        for proposal in visibleProposals where cards.count < deckLimit {
            guard seenURLs.insert(proposal.note.url).inserted else { continue }

            let preview = proposal.hunks
                .lazy
                .map(\.after)
                .map(cleanPreview)
                .first { !$0.isEmpty }
                ?? "\(proposal.hunks.count) changes are ready to review."

            let proposedText = proposal.hunks
                .map(\.after)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")

            let body: String
            if let openNote = state.openNote, openNote.url == proposal.note.url {
                body = removingLeadingTitle(from: openNote.text)
            } else {
                body = proposedText.isEmpty ? preview : proposedText
            }

            cards.append(
                HomeNoteCardModel(
                    id: proposal.note.url.absoluteString,
                    title: proposal.note.title,
                    detail: "READY TO REVIEW  ·  \(proposal.note.wordCount.formatted()) WORDS",
                    preview: preview,
                    document: NoteDocument(
                        url: proposal.note.url,
                        text: "# \(proposal.note.title)\n\n\(body)"
                    ),
                    source: .review,
                    isFeatured: proposal.note.url == featuredURL,
                    role: proposal.note.url == featuredURL ? .featured : .supporting
                )
            )
        }

        var assignedCleanedRole = false
        for cleanup in state.recentlyCleaned where cards.count < deckLimit {
            guard seenURLs.insert(cleanup.note.url).inserted else { continue }

            let ruleCount = cleanup.rules.count
            let preview = ruleCount == 1
                ? "A small cleanup left this note ready to read."
                : "\(ruleCount) careful cleanups left this note ready to read."

            cards.append(
                HomeNoteCardModel(
                    id: cleanup.note.url.absoluteString,
                    title: cleanup.note.title,
                    detail: "RECENTLY CLEANED  ·  \(cleanup.note.wordCount.formatted()) WORDS",
                    preview: preview,
                    document: NoteDocument(
                        url: cleanup.note.url,
                        text: "# \(cleanup.note.title)\n\n\(preview)"
                    ),
                    source: .cleaned,
                    isFeatured: false,
                    role: assignedCleanedRole ? .background : .recentlyCleaned
                )
            )
            assignedCleanedRole = true
        }

        if
            cards.count < deckLimit,
            let openNote = state.openNote,
            seenURLs.insert(openNote.url).inserted
        {
            let title = openNote.url.deletingPathExtension().lastPathComponent
            cards.append(
                HomeNoteCardModel(
                    id: openNote.url.absoluteString,
                    title: title,
                    detail: "OPEN NOTE",
                    preview: firstParagraph(in: openNote.text),
                    document: openNote,
                    source: .open,
                    isFeatured: false,
                    role: .background
                )
            )
        }

        let searchableByURL = Dictionary(
            state.searchableNotes.map { ($0.url.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sortedRecentNotes = state.recentNotes.sorted { left, right in
            if left.modifiedAt != right.modifiedAt {
                return left.modifiedAt > right.modifiedAt
            }
            return left.url.path < right.url.path
        }

        for note in sortedRecentNotes where cards.count < deckLimit {
            let standardizedURL = note.url.standardizedFileURL
            guard seenURLs.insert(standardizedURL).inserted,
                  let document = searchableByURL[standardizedURL]
            else { continue }

            cards.append(
                HomeNoteCardModel(
                    id: standardizedURL.absoluteString,
                    title: note.title,
                    detail: "RECENT NOTE  ·  \(note.wordCount.formatted()) WORDS",
                    preview: firstParagraph(in: document.text),
                    document: document,
                    source: .recent,
                    isFeatured: false,
                    role: .background
                )
            )
        }

        return cards
    }

    private static func reviewScore(
        _ proposal: Proposal,
        cleanupRuleCounts: [URL: Int]
    ) -> Int {
        proposal.hunks.count * 100
            + cleanupRuleCounts[proposal.note.url, default: 0] * 20
            + min(proposal.note.wordCount / 100, 20)
    }

    private static func cleanPreview(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func removingLeadingTitle(from text: String) -> String {
        guard let firstBreak = text.firstIndex(of: "\n") else { return text }
        let firstLine = text[..<firstBreak]
        guard firstLine.hasPrefix("# ") else { return text }
        return String(text[text.index(after: firstBreak)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstParagraph(in text: String) -> String {
        let blocks = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return cleanPreview(blocks.first ?? "Open this note to continue reading.")
    }
}

public struct HomeNoteDeck: Equatable {
    public private(set) var visible: [HomeNoteCardModel]
    public private(set) var reserve: [HomeNoteCardModel]

    public init(cards: [HomeNoteCardModel], visibleLimit: Int = 6) {
        let clampedLimit = max(0, visibleLimit)
        visible = Array(cards.prefix(clampedLimit))
        reserve = Array(cards.dropFirst(clampedLimit))
    }

    @discardableResult
    public mutating func replace(cardID: String) -> HomeNoteCardModel? {
        guard let visibleIndex = visible.firstIndex(where: { $0.id == cardID }),
              !reserve.isEmpty
        else { return nil }

        let outgoing = visible[visibleIndex]
        let incoming = reserve.removeFirst()
        visible[visibleIndex] = incoming
        reserve.append(outgoing)
        return incoming
    }
}

public struct HomeNotePlacement: Identifiable, Equatable {
    public let id: String
    public let x: CGFloat
    public let y: CGFloat
    public let rotation: Double
    /// A multiplier the motion applies on top of `size`. Placement variation
    /// lives in `size`, so hover and opening arithmetic stays about motion.
    public let scale: CGFloat
    /// This note's own dimensions, in points. Notes are not all one rectangle:
    /// a two-line scribble is smaller than a paragraph, the way it would be if
    /// somebody had torn one off a pad.
    public let size: CGSize
    public let depth: Double
}

/// The small deviations that separate "placed by hand" from "laid out".
///
/// Derived from the note's own identity rather than its slot, and derived
/// rather than random: a wall that rearranges itself every time the view is
/// rebuilt is worse than a tidy one. The same note gets the same character
/// every launch, and no two notes share one.
public struct HomeNoteHand: Equatable {
    public let offset: CGSize
    public let rotation: Double
    public let widthScale: CGFloat
    public let tapeWidth: CGFloat
    public let tapeOpacity: Double
    public let tapeRotation: Double
    public let tapeOffset: CGSize

    /// FNV-1a. Any stable hash would do; this one is short and does not vary
    /// between processes the way `hashValue` does.
    static func seed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A value in `range`, taken from `slice` bits of the seed.
    static func value(
        _ seed: UInt64,
        slice: Int,
        in range: ClosedRange<Double>
    ) -> Double {
        let shifted = (seed >> UInt64(slice * 8)) & 0xff
        let fraction = Double(shifted) / 255.0
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }

    public init(id: String) {
        let seed = Self.seed(id)
        // Eight to twenty points, in whichever direction this note leans. Below
        // eight it reads as a rendering error rather than as placement.
        let distance = Self.value(seed, slice: 0, in: 8...20)
        let angle = Self.value(seed, slice: 1, in: 0...(2 * .pi))
        offset = CGSize(
            width: distance * cos(angle),
            height: distance * sin(angle)
        )
        rotation = Self.value(seed, slice: 2, in: -2.0...2.0)
        widthScale = CGFloat(Self.value(seed, slice: 3, in: 0.90...1.08))
        tapeWidth = CGFloat(Self.value(seed, slice: 4, in: 30...52))
        tapeOpacity = Self.value(seed, slice: 5, in: 0.38...0.66)
        tapeRotation = Self.value(seed, slice: 6, in: -7.0...7.0)
        // Tape a person tore off and pressed down lands off-centre and at
        // varying depth over the edge. Centred, identical strips are the single
        // clearest sign nobody put these here.
        tapeOffset = CGSize(
            width: Self.value(seed, slice: 7, in: -26...26),
            height: Self.value(seed, slice: 3, in: -7...(-1))
        )
    }
}

public enum HomeNoteWallLayout {
    /// The card's base dimensions before this note's own variation.
    public static let cardSize = CGSize(width: 178, height: 162)

    /// The most notes the wall shows at once.
    public static let slotCount = 6

    /// How far each row slides sideways, and each column sits up or down.
    ///
    /// Per-note wobble is not enough on its own: however much each note moves,
    /// a column still shares a left edge and a row still shares a baseline, and
    /// that is the grid you can read in a screenshot. These shifts are the
    /// wall's doing rather than any note's, which is why they are indexed by
    /// position and not by identity.
    private static let rowShift: [CGFloat] = [-0.07, 0.10]
    private static let columnShift: [CGFloat] = [0.06, -0.09, 0.03]

    static func rowStagger(row: Int, cell: CGSize) -> CGFloat {
        rowShift[row % rowShift.count] * cell.width
    }

    static func columnLift(column: Int, cell: CGSize) -> CGFloat {
        columnShift[column % columnShift.count] * cell.height
    }

    /// Cards are seated on a three-by-two lattice and then knocked off it.
    ///
    /// The lattice is what makes overlap impossible; it is not what the wall
    /// should look like. Left at their cell centres the notes read as a
    /// contact sheet — equally spaced, equally sized, equally angled — so each
    /// one is moved by eight to twenty points in its own direction, turned by
    /// up to two degrees, and sized to how much it has to say. Every one of
    /// those deviations is clamped to the room inside its own cell, so the
    /// wall can be as irregular as it likes and still never stack.
    ///
    /// Controlled imperfection: the offsets come from the note's identity, so
    /// they are the same on every launch. A wall that reshuffles itself while
    /// you look at it is not more natural, only less trustworthy.
    public static func placements(
        for cards: [HomeNoteCardModel],
        canvas: CGSize = CGSize(width: 736, height: 420)
    ) -> [HomeNotePlacement] {
        guard !cards.isEmpty else { return [] }

        let columns = 3
        let rows = 2
        let cell = CGSize(
            width: canvas.width / CGFloat(columns),
            height: canvas.height / CGFloat(rows)
        )

        return cards.prefix(slotCount).enumerated().map { index, card in
            let hand = HomeNoteHand(id: card.id)
            let wanted = size(for: card, hand: hand)

            // Shrink only if this note cannot fit its cell at all.
            let fit = min(
                1.0,
                min(cell.width / wanted.width, cell.height / wanted.height)
            )
            let placed = CGSize(width: wanted.width * fit, height: wanted.height * fit)

            // Whatever room is left is how far the note may wander.
            let slack = CGSize(
                width: max(0, cell.width - placed.width) / 2,
                height: max(0, cell.height - placed.height) / 2
            )
            // The wall's shifts and the note's own wobble come out of one
            // budget, and it is their sum that has to stay inside the cell. Two
            // separate clamps would each pass while together walking the note
            // into its neighbour.
            let displacement = CGSize(
                width: hand.offset.width + rowStagger(row: index / columns, cell: cell),
                height: hand.offset.height + columnLift(column: index % columns, cell: cell)
            )
            let offset = CGSize(
                width: min(max(displacement.width, -slack.width), slack.width),
                height: min(max(displacement.height, -slack.height), slack.height)
            )

            let column = index % columns
            let row = index / columns
            // Rows are staggered and columns are stepped, and neither is the
            // note's own doing — it is the wall's. Without this every note in
            // a column shares a left edge and every note in a row shares a
            // baseline, which is the grid you can still read however much the
            // individual notes wobble. The shifts are a fraction of a cell, so
            // they come out of the same slack budget as everything else.
            let centreX = (CGFloat(column) + 0.5) * cell.width
            let centreY = (CGFloat(row) + 0.5) * cell.height

            return HomeNotePlacement(
                id: card.id,
                x: (centreX + offset.width) / max(canvas.width, 1),
                y: (centreY + offset.height) / max(canvas.height, 1),
                rotation: hand.rotation,
                scale: 1,
                size: placed,
                depth: depth(for: card.role)
            )
        }
    }

    /// How big this note wants to be.
    ///
    /// A note with two words on it is a smaller piece of paper than one
    /// carrying a paragraph. Forcing both into the same rectangle is most of
    /// what made the wall look printed rather than pinned.
    static func size(for card: HomeNoteCardModel, hand: HomeNoteHand) -> CGSize {
        let content = card.title.count + card.preview.count
        // Roughly a short scribble at 40 characters and a full note at 220.
        let fullness = min(max(Double(content - 40) / 180, 0), 1)
        let height = cardSize.height * CGFloat(0.86 + 0.26 * fullness)
        // A featured note earns a little more room; it is the one being
        // recommended.
        let emphasis: CGFloat = card.role == .featured ? 1.05 : 1.0
        return CGSize(
            width: cardSize.width * hand.widthScale * emphasis,
            height: height * emphasis
        )
    }

    private static func depth(for role: HomeNoteCardModel.Role) -> Double {
        switch role {
        case .featured: 4
        case .supporting: 3
        case .recentlyCleaned: 2
        case .background: 1
        }
    }

    /// Whether two placements would draw over one another on `canvas`.
    /// Used by the test that keeps this honest.
    public static func overlaps(
        _ first: HomeNotePlacement,
        _ second: HomeNotePlacement,
        canvas: CGSize
    ) -> Bool {
        func rect(_ placement: HomeNotePlacement) -> CGRect {
            CGRect(
                x: placement.x * canvas.width - placement.size.width / 2,
                y: placement.y * canvas.height - placement.size.height / 2,
                width: placement.size.width,
                height: placement.size.height
            )
        }
        return rect(first).intersects(rect(second))
    }

    public static func openingOffset(
        for placement: HomeNotePlacement,
        canvasSize: CGSize
    ) -> CGSize {
        CGSize(
            width: (0.52 - placement.x) * canvasSize.width * 0.25,
            height: (0.43 - placement.y) * canvasSize.height * 0.22
        )
    }
}

public enum HomeReturnMotion {
    public static func cardEntryOffset(
        for placement: HomeNotePlacement,
        canvasSize: CGSize,
        reduceMotion: Bool
    ) -> CGSize {
        guard !reduceMotion else { return .zero }
        return HomeNoteWallLayout.openingOffset(
            for: placement,
            canvasSize: canvasSize
        )
    }
}

public enum HomeNoteSlotPalette {
    public enum Tone: Equatable, Sendable {
        case orangeYellow
        case pink
        case green
        case warmIvory
        case cleanPaper
        case quietPaper
    }

    private static let tones: [Tone] = [
        .orangeYellow,
        .pink,
        .green,
        .warmIvory,
        .cleanPaper,
        .quietPaper
    ]

    public static func tone(for slot: Int) -> Tone {
        guard tones.indices.contains(slot) else { return .quietPaper }
        return tones[slot]
    }

    static func fill(for slot: Int) -> Color {
        switch tone(for: slot) {
        case .orangeYellow:
            return Color(red: 0.996, green: 0.938, blue: 0.870)
        case .pink:
            return Chamfer.Palette.pinkSoft.opacity(0.86)
        case .green:
            return Chamfer.Palette.positiveSoft.opacity(0.84)
        case .warmIvory:
            return Color(red: 0.984, green: 0.974, blue: 0.947)
        case .cleanPaper:
            return Color(red: 0.988, green: 0.968, blue: 0.918)
        case .quietPaper:
            return Color(red: 0.965, green: 0.947, blue: 0.912)
        }
    }
}

private enum HomeNoteReplacementMotion: Equatable {
    case idle
    case lifting
    case arriving
}

public struct HomeScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var openingID: String?
    @LegacyState private var clockRotation = 0.0
    @LegacyState private var clockIsHovered = false
    @LegacyState private var hasEntered = false
    @LegacyState private var noteDeck: HomeNoteDeck
    @LegacyState private var replacementSlot: Int?
    @LegacyState private var replacementMotion = HomeNoteReplacementMotion.idle
    @LegacyState private var replacementTask: Task<Void, Never>?
    /// The line on screen. Written on appear and never again while this view
    /// exists, which is the whole of the "does not rotate while you are looking
    /// at it" rule.
    @LegacyState private var greeting: String

    private let state: DashboardState
    private let name: String
    private let clock: HomeGreetingClock
    private let onOpenNote: (NoteDocument) -> Void
    private let slotPlacements: [HomeNotePlacement]

    /// The card leaving the wall, and its replacement dropping into the gap.
    /// Named so the two halves of one gesture cannot drift apart, and kept out
    /// of the shared tokens on purpose: these answer a swipe's momentum rather
    /// than a pointer, which is what earns the arrival its bounce.
    private static let cardLiftCurve = Animation.spring(duration: 0.18, bounce: 0.025)
    private static let cardArriveCurve = Animation.spring(duration: 0.24, bounce: 0.08)

    private let onConnectVault: (@MainActor () -> Void)?

    public init(
        state: DashboardState,
        name: String = HomeGreetingRotation.currentUserName(),
        clock: HomeGreetingClock = .shared,
        onOpenNote: @escaping (NoteDocument) -> Void,
        onConnectVault: (@MainActor () -> Void)? = nil
    ) {
        self.state = state
        self.name = name
        self.clock = clock
        self.onOpenNote = onOpenNote
        self.onConnectVault = onConnectVault
        // Resolved here as well as in `onAppear` so the first frame is already
        // the right line rather than an empty one that pops in.
        _greeting = State(initialValue: clock.greeting(name: name))
        let deck = HomeNoteDeck(cards: HomeNoteCardModel.deckCards(from: state))
        slotPlacements = HomeNoteWallLayout.placements(for: deck.visible)
        _noteDeck = State(initialValue: deck)
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .center, spacing: 0) {
                HStack(spacing: 6) {
                    LiveClockGlyph(date: context.date)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(clockRotation))
                        .scaleEffect(reduceMotion && clockIsHovered ? 1.08 : 1)
                        .animation(
                            .spring(duration: 0.30, bounce: 0.06),
                            value: clockRotation
                        )
                        .animation(Chamfer.Motion.quick, value: clockIsHovered)

                    Text(HomeClockGeometry.timeText(at: context.date))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Chamfer.Palette.pageTextSoft.opacity(0.78))
                .contentShape(Rectangle())
                .onHover(perform: handleClockHover)
                .padding(.bottom, 12)
                .opacity(hasEntered ? 1 : 0)
                .offset(y: !reduceMotion && !hasEntered ? 5 : 0)
                .animation(
                    Chamfer.Motion.reduce(
                        Chamfer.Motion.interactive.delay(0.02),
                        when: reduceMotion
                    ),
                    value: hasEntered
                )

                // Resolved once, as the page appears — deliberately not read
                // from `context.date`. This view is inside a one-second
                // `TimelineView` for the clock above it, and taking the
                // greeting from that tick is what used to let it change while
                // somebody was reading it.
                Text(greeting)
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: 620)
                    // Only ever fires on arrival, since `greeting` cannot
                    // change while this view is on screen. Kept so a returning
                    // visit settles rather than snapping.
                    .animation(
                        Chamfer.Motion.reduce(
                            Chamfer.Motion.navigation,
                            when: reduceMotion
                        ),
                        value: greeting
                    )
                    .opacity(hasEntered ? 1 : 0)
                    .offset(y: !reduceMotion && !hasEntered ? 8 : 0)
                    .animation(
                        Chamfer.Motion.reduce(
                            Chamfer.Motion.interactive.delay(0.04),
                            when: reduceMotion
                        ),
                        value: hasEntered
                    )

                Spacer(minLength: 18)

                noteCards

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 10)
        }
        .onAppear {
            // The one moment the greeting may change: arriving. If a 45-minute
            // window came due while the home screen was closed, the new line is
            // simply the one that is here when you get back.
            greeting = clock.greeting(name: name)
            hasEntered = false
            Task { @MainActor in
                await Task.yield()
                hasEntered = true
            }
        }
        .onDisappear {
            replacementTask?.cancel()
            replacementTask = nil
        }
    }

    @ViewBuilder
    private var noteCards: some View {
        let cards = noteDeck.visible

        if cards.isEmpty {
            emptyWall
        } else {
            GeometryReader { geometry in
                ZStack {
                    AmbientClusterGlow()
                        .frame(
                            width: geometry.size.width * 0.72,
                            height: geometry.size.height * 0.66
                        )
                        .position(
                            x: geometry.size.width * 0.52,
                            y: geometry.size.height * 0.46
                        )
                        .opacity(hasEntered ? 1 : 0)
                        .scaleEffect(hasEntered || reduceMotion ? 1 : 0.92)
                        // The slowest of the three: the glow is the backdrop the
                        // other two arrive on top of, so it settles last.
                        .animation(
                            Chamfer.Motion.reduce(
                                Chamfer.Motion.navigation,
                                when: reduceMotion
                            ),
                            value: hasEntered
                        )

                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        if slotPlacements.indices.contains(index) {
                            let placement = slotPlacements[index]
                            StickyNoteButton(
                                card: card,
                                placement: placement,
                                fill: HomeNoteSlotPalette.fill(for: index),
                                tapeVariant: index,
                                openingID: openingID,
                                openingOffset: HomeNoteWallLayout.openingOffset(
                                    for: placement,
                                    canvasSize: geometry.size
                                ),
                                entryOffset: HomeReturnMotion.cardEntryOffset(
                                    for: placement,
                                    canvasSize: geometry.size,
                                    reduceMotion: reduceMotion
                                ),
                                homeIsPresented: hasEntered,
                                replacementMotion: replacementSlot == index
                                    ? replacementMotion
                                    : .idle,
                                action: { beginOpening(card) },
                                onTrackpadSwipe: { direction in
                                    beginReplacing(
                                        cardID: card.id,
                                        slot: index,
                                        direction: direction
                                    )
                                }
                            )
                            .position(
                                x: geometry.size.width * placement.x,
                                y: geometry.size.height * placement.y
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The wall with nothing on it.
    ///
    /// The previous version was a left-aligned pair of lines inside a
    /// centre-aligned frame, so the text sat off-axis in a 260pt void with the
    /// glow switched off — the one screen a new user sees first, and the least
    /// finished thing in the app.
    ///
    /// This keeps the composition: the glow still sits behind, and a single
    /// card holds the slot the featured note would occupy, tape and tilt
    /// included. An empty wall should look like a wall waiting for something,
    /// not like a page that failed to load.
    private var emptyWall: some View {
        WaitingCardScene(
            title: "A wall with nothing on it",
            detail: "Point Chamfer at a folder of notes and they will gather here — the ones you are working on, and the ones it has tidied while you were elsewhere.",
            footerLabel: onConnectVault == nil ? "NOTHING CONNECTED" : "CONNECT A VAULT",
            action: onConnectVault,
            isPresented: hasEntered
        )
        .frame(minHeight: 260)
    }

    private func handleClockHover(_ isHovered: Bool) {
        guard isHovered != clockIsHovered else { return }
        clockIsHovered = isHovered
        guard isHovered else { return }

        clockRotation = HomeClockHoverMotion.nextRotation(
            after: clockRotation,
            reduceMotion: reduceMotion
        )
    }

    private func beginOpening(_ card: HomeNoteCardModel) {
        guard openingID == nil else { return }
        openingID = card.id

        let delay = reduceMotion ? Duration.milliseconds(120) : .milliseconds(280)
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            onOpenNote(card.document)
        }
    }

    private func beginReplacing(
        cardID: String,
        slot: Int,
        direction: TrackpadPanDirection
    ) {
        guard direction == .up,
              openingID == nil,
              replacementSlot == nil,
              !noteDeck.reserve.isEmpty
        else { return }

        replacementTask?.cancel()
        replacementSlot = slot
        Haptics.pop()
        withAnimation(
            Chamfer.Motion.reduce(Self.cardLiftCurve, when: reduceMotion)
        ) {
            replacementMotion = .lifting
        }

        replacementTask = Task { @MainActor in
            do {
                try await Task.sleep(
                    for: reduceMotion ? .milliseconds(90) : .milliseconds(150)
                )
            } catch {
                return
            }
            guard !Task.isCancelled, replacementSlot == slot else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                _ = noteDeck.replace(cardID: cardID)
                replacementMotion = .arriving
            }

            await Task.yield()
            guard !Task.isCancelled, replacementSlot == slot else { return }
            Haptics.commit()
            withAnimation(
                Chamfer.Motion.reduce(Self.cardArriveCurve, when: reduceMotion)
            ) {
                replacementMotion = .idle
            }

            do {
                try await Task.sleep(
                    for: reduceMotion ? .milliseconds(100) : .milliseconds(240)
                )
            } catch {
                return
            }
            guard !Task.isCancelled, replacementSlot == slot else { return }
            replacementSlot = nil
            replacementTask = nil
        }
    }
}

private struct LiveClockGlyph: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1
            let color = Chamfer.Palette.pageTextSoft.opacity(0.78)
            let handColor = Chamfer.Palette.canvas.opacity(0.95)

            var rim = Path()
            rim.addEllipse(
                in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            context.fill(rim, with: .color(color))

            let angles = HomeClockGeometry.handAngles(at: date)
            context.stroke(
                hand(
                    from: center,
                    degrees: angles.hour,
                    length: radius * 0.48
                ),
                with: .color(handColor),
                style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
            )
            context.stroke(
                hand(
                    from: center,
                    degrees: angles.minute,
                    length: radius * 0.70
                ),
                with: .color(handColor),
                style: StrokeStyle(lineWidth: 1.05, lineCap: .round)
            )

            var pin = Path()
            pin.addEllipse(
                in: CGRect(
                    x: center.x - 1,
                    y: center.y - 1,
                    width: 2,
                    height: 2
                )
            )
            context.fill(pin, with: .color(handColor))
        }
        .accessibilityHidden(true)
    }

    private func hand(from center: CGPoint, degrees: Double, length: CGFloat) -> Path {
        let radians = (degrees - 90) * .pi / 180
        let end = CGPoint(
            x: center.x + cos(radians) * length,
            y: center.y + sin(radians) * length
        )
        var path = Path()
        path.move(to: center)
        path.addLine(to: end)
        return path
    }
}

private struct StickyNoteButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LegacyState private var isHovered = false

    let card: HomeNoteCardModel
    let placement: HomeNotePlacement
    let fill: Color
    let tapeVariant: Int
    let openingID: String?
    let openingOffset: CGSize
    let entryOffset: CGSize
    let homeIsPresented: Bool
    let replacementMotion: HomeNoteReplacementMotion
    let action: () -> Void
    let onTrackpadSwipe: (TrackpadPanDirection) -> Void

    private var isOpening: Bool {
        openingID == card.id
    }

    private var anotherNoteIsOpening: Bool {
        openingID != nil && !isOpening
    }

    private var renderedRotation: Double {
        guard !reduceMotion else { return placement.rotation }
        if replacementMotion == .lifting { return placement.rotation * 0.30 }
        if isOpening { return placement.rotation * 0.18 }
        if isHovered { return placement.rotation * 0.38 }
        return placement.rotation
    }

    private var renderedScale: CGFloat {
        if !homeIsPresented {
            return placement.scale * (reduceMotion ? 1 : 0.94)
        }
        if isOpening {
            return placement.scale * (reduceMotion ? 1.015 : 1.08)
        }
        if replacementMotion == .lifting {
            return placement.scale * (reduceMotion ? 1 : 0.94)
        }
        if replacementMotion == .arriving {
            return placement.scale * (reduceMotion ? 1 : 0.96)
        }
        if isHovered {
            return placement.scale * (card.isFeatured ? 1.018 : 1.012)
        }
        return placement.scale
    }

    private var horizontalOffset: CGFloat {
        if !homeIsPresented { return entryOffset.width }
        guard !reduceMotion, isOpening else { return 0 }
        return openingOffset.width
    }

    private var verticalOffset: CGFloat {
        if !homeIsPresented { return entryOffset.height }
        guard !reduceMotion else { return 0 }
        if replacementMotion == .lifting { return -82 }
        if replacementMotion == .arriving { return 28 }
        if isOpening { return openingOffset.height }
        if isHovered { return card.isFeatured ? -5 : -3 }
        return 0
    }

    private var opacity: Double {
        if !homeIsPresented { return 0 }
        if replacementMotion != .idle { return 0 }
        if anotherNoteIsOpening { return reduceMotion ? 0.18 : 0.22 }
        if reduceMotion && isOpening { return 0.90 }
        if isHovered { return 1 }
        switch card.role {
        case .recentlyCleaned: return 0.95
        case .background: return 0.86
        default: return 1
        }
    }

    private var homeEntryAnimation: Animation {
        guard !reduceMotion else { return Chamfer.Motion.reduced }
        let delay = min(Double(tapeVariant) * 0.015, 0.08)
        return Chamfer.Motion.navigation
            .delay(delay)
    }

    var body: some View {
        Button(action: action) {
            StickyNotePreview(
                card: card,
                fill: fill,
                hand: HomeNoteHand(id: card.id),
                isHovered: isHovered || isOpening
            )
        }
        .buttonStyle(.plain)
        .frame(width: placement.size.width, height: placement.size.height)
        .chamferFocusable(radius: 5)
        .background {
            TrackpadPanGesture(onEnded: onTrackpadSwipe)
        }
        .scaleEffect(renderedScale)
        .rotationEffect(.degrees(renderedRotation))
        .offset(x: horizontalOffset, y: verticalOffset)
        .opacity(opacity)
        .zIndex(isOpening || replacementMotion == .lifting ? 20 : placement.depth)
        .onHover { isHovered = $0 }
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.interactive, when: reduceMotion),
            value: isHovered
        )
        .animation(
            Chamfer.Motion.reduce(Chamfer.Motion.navigation, when: reduceMotion),
            value: openingID
        )
        .animation(homeEntryAnimation, value: homeIsPresented)
        .accessibilityLabel("\(card.title), \(card.detail.lowercased())")
    }
}

struct StickyNotePreview: View {
    let card: HomeNoteCardModel
    let fill: Color
    /// Everything about this note that a person would have done slightly
    /// differently: how wide the tape is, how hard it was pressed down, where
    /// it landed and at what angle.
    let hand: HomeNoteHand
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageText)
                .lineLimit(2)

            Text(card.preview)
                .font(.system(size: 11, weight: .regular, design: .serif))
                .foregroundStyle(Chamfer.Palette.pageTextSoft)
                .lineSpacing(3)
                .lineLimit(
                    card.isFeatured
                        ? 5
                        : (card.role == .supporting ? 3 : 2)
                )
                .padding(.top, 8)

            Spacer(minLength: 6)

            Text(card.detail)
                .font(.system(size: 8, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Chamfer.Palette.textOnPaperFaint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 15)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Chamfer.Palette.ink.opacity(0.07), lineWidth: 0.8)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.white.opacity(hand.tapeOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(Chamfer.Palette.ink.opacity(0.055), lineWidth: 0.6)
                }
                .frame(width: hand.tapeWidth, height: 9)
                .rotationEffect(.degrees(hand.tapeRotation))
                .offset(x: hand.tapeOffset.width, y: hand.tapeOffset.height)
        }
        .shadow(
            color: Chamfer.Palette.ink.opacity(
                isHovered
                    ? (card.isFeatured ? 0.19 : 0.15)
                    : normalShadowOpacity
            ),
            radius: isHovered ? (card.isFeatured ? 12 : 10) : normalShadowRadius,
            x: 1,
            y: isHovered ? 8 : normalShadowY
        )
        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    /// Darker and tighter than it was. A note is a piece of paper on a surface,
    /// and the contact shadow is what says so — the ambient glow used to be
    /// carrying that impression, badly, for all six at once.
    private var normalShadowOpacity: Double {
        switch card.role {
        case .featured: 0.20
        case .supporting: 0.17
        case .recentlyCleaned: 0.15
        case .background: 0.13
        }
    }

    /// Short. A wide soft radius is a glow; a paper note casts a shadow that
    /// stays near its own edge.
    private var normalShadowRadius: CGFloat {
        switch card.role {
        case .featured: 6
        case .supporting: 5
        case .recentlyCleaned: 5
        case .background: 4
        }
    }

    private var normalShadowY: CGFloat {
        switch card.role {
        case .featured: 6
        case .supporting, .recentlyCleaned: 7
        case .background: 6
        }
    }
}
