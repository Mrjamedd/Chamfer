import ChamferCore
import Foundation
import SwiftUI

/// Copy for the home page. The selection advances every twelve minutes and
/// changes its vocabulary with the time of day.
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

    public static func text(
        at date: Date,
        name: String,
        calendar: Calendar = .current
    ) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let greetings = availableGreetings(hour: hour, name: name)
        let rotationWindow = day * 120 + hour * 5 + minute / 12
        return greetings[rotationWindow % greetings.count]
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
    public let scale: CGFloat
    public let depth: Double
}

public enum HomeNoteWallLayout {
    public static func placements(for cards: [HomeNoteCardModel]) -> [HomeNotePlacement] {
        var placements: [HomeNotePlacement] = []
        let featured = cards.first { $0.role == .featured }
        let supportingNotes = cards.filter { $0.role == .supporting }
        let cleanedNotes = cards.filter { $0.role == .recentlyCleaned }
        let backgroundNotes = cards.filter { $0.role == .background }

        if let featured {
            placements.append(
                .init(
                    id: featured.id,
                    x: 0.52,
                    y: 0.27,
                    rotation: 1.2,
                    scale: 1.10,
                    depth: 4
                )
            )
        }

        let supportingSlots: [(CGFloat, CGFloat, Double, CGFloat, Double)] = [
            (0.22, 0.31, -2.0, 0.98, 3),
            (0.84, 0.29, 1.6, 0.97, 3),
            (0.85, 0.66, -1.3, 0.94, 2),
            (0.24, 0.73, 1.8, 0.91, 2),
            (0.52, 0.79, -1.0, 0.89, 1)
        ]
        for (card, slot) in zip(supportingNotes, supportingSlots) {
            placements.append(
                .init(
                    id: card.id,
                    x: slot.0,
                    y: slot.1,
                    rotation: slot.2,
                    scale: slot.3,
                    depth: slot.4
                )
            )
        }

        let cleanedSlots: [(CGFloat, CGFloat, Double, CGFloat, Double)] = [
            (0.38, 0.71, 1.2, 0.90, 1),
            (0.54, 0.76, -1.3, 0.88, 1)
        ]
        for (card, slot) in zip(cleanedNotes, cleanedSlots) {
            placements.append(
                .init(
                    id: card.id,
                    x: slot.0,
                    y: slot.1,
                    rotation: slot.2,
                    scale: slot.3,
                    depth: slot.4
                )
            )
        }

        let backgroundSlots: [(CGFloat, CGFloat, Double, CGFloat, Double)] = [
            (0.14, 0.57, -1.5, 0.84, 0),
            (0.87, 0.55, 1.7, 0.83, 0),
            (0.18, 0.78, -1.8, 0.82, 0),
            (0.83, 0.78, 1.4, 0.81, 0),
            (0.50, 0.82, -0.8, 0.80, 0)
        ]
        for (card, slot) in zip(backgroundNotes, backgroundSlots) {
            placements.append(
                .init(
                    id: card.id,
                    x: slot.0,
                    y: slot.1,
                    rotation: slot.2,
                    scale: slot.3,
                    depth: slot.4
                )
            )
        }

        return placements
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
    @State private var openingID: String?
    @State private var clockRotation = 0.0
    @State private var clockIsHovered = false
    @State private var hasEntered = false
    @State private var noteDeck: HomeNoteDeck
    @State private var replacementSlot: Int?
    @State private var replacementMotion = HomeNoteReplacementMotion.idle
    @State private var replacementTask: Task<Void, Never>?

    private let state: DashboardState
    private let name: String
    private let onOpenNote: (NoteDocument) -> Void
    private let slotPlacements: [HomeNotePlacement]

    public init(
        state: DashboardState,
        name: String = "Anthony",
        onOpenNote: @escaping (NoteDocument) -> Void
    ) {
        self.state = state
        self.name = name
        self.onOpenNote = onOpenNote
        let deck = HomeNoteDeck(cards: HomeNoteCardModel.deckCards(from: state))
        let placementsByID = Dictionary(
            uniqueKeysWithValues: HomeNoteWallLayout.placements(for: deck.visible).map {
                ($0.id, $0)
            }
        )
        slotPlacements = deck.visible.compactMap { placementsByID[$0.id] }
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
                    reduceMotion
                        ? Chamfer.Motion.quick
                        : .easeOut(duration: 0.20).delay(0.02),
                    value: hasEntered
                )

                Text("Start with the interesting part.")
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                    .foregroundStyle(Chamfer.Palette.pageText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: 620)
                    .opacity(hasEntered ? 1 : 0)
                    .offset(y: !reduceMotion && !hasEntered ? 8 : 0)
                    .animation(
                        reduceMotion
                            ? Chamfer.Motion.quick
                            : .easeOut(duration: 0.22).delay(0.04),
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
            VStack(alignment: .leading, spacing: Chamfer.Space.snug) {
                Text("Your notes will gather here.")
                    .font(Chamfer.TypeScale.pageHeading)
                    .foregroundStyle(Chamfer.Palette.pageText)
                Text("A quiet place for the things you are thinking about.")
                    .font(Chamfer.TypeScale.body)
                    .foregroundStyle(Chamfer.Palette.pageTextSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        } else {
            GeometryReader { geometry in
                ZStack {
                    AmbientClusterGlow()
                        .frame(
                            width: geometry.size.width * 0.90,
                            height: geometry.size.height * 0.92
                        )
                        .position(
                            x: geometry.size.width * 0.52,
                            y: geometry.size.height * 0.46
                        )
                        .opacity(hasEntered ? 1 : 0)
                        .scaleEffect(hasEntered || reduceMotion ? 1 : 0.92)
                        .animation(
                            reduceMotion
                                ? Chamfer.Motion.quick
                                : .easeOut(duration: 0.26),
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
            reduceMotion
                ? Chamfer.Motion.quick
                : .spring(duration: 0.18, bounce: 0.025)
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
                reduceMotion
                    ? Chamfer.Motion.quick
                    : .spring(duration: 0.24, bounce: 0.08)
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

private struct AmbientClusterGlow: View {
    var body: some View {
        ZStack {
            GlowField(
                color: Color(red: 0.99, green: 0.25, blue: 0.55),
                opacity: 0.54
            )
                .scaleEffect(x: 0.74, y: 0.78)
                .offset(x: 20, y: -44)

            GlowField(
                color: Color(red: 1.00, green: 0.48, blue: 0.28),
                opacity: 0.48
            )
                .scaleEffect(x: 1.04, y: 0.88)
                .offset(x: -88, y: -14)

            GlowField(
                color: Color(red: 1.00, green: 0.64, blue: 0.16),
                opacity: 0.38
            )
                .scaleEffect(x: 0.96, y: 0.76)
                .offset(x: -56, y: 76)

            GlowField(
                color: Color(red: 1.00, green: 0.46, blue: 0.64),
                opacity: 0.22
            )
                .scaleEffect(x: 0.62, y: 0.74)
                .offset(x: 124, y: -6)
        }
            .compositingGroup()
            .blur(radius: 72)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct GlowField: View {
    let color: Color
    let opacity: Double

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0.52), location: 0.42),
                        .init(color: color.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 260
                )
            )
            .opacity(opacity)
    }
}

private struct StickyNoteButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

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
        guard !reduceMotion else { return Chamfer.Motion.quick }
        let delay = min(Double(tapeVariant) * 0.015, 0.08)
        return Chamfer.Motion.navigation
            .delay(delay)
    }

    var body: some View {
        Button(action: action) {
            StickyNotePreview(
                card: card,
                fill: fill,
                tapeVariant: tapeVariant,
                isHovered: isHovered || isOpening
            )
        }
        .buttonStyle(.plain)
        .frame(width: 178, height: 162)
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
            reduceMotion
                ? Chamfer.Motion.quick
                : Chamfer.Motion.interactive,
            value: isHovered
        )
        .animation(
            reduceMotion
                ? Chamfer.Motion.quick
                : Chamfer.Motion.navigation,
            value: openingID
        )
        .animation(homeEntryAnimation, value: homeIsPresented)
        .accessibilityLabel("\(card.title), \(card.detail.lowercased())")
    }
}

private struct StickyNotePreview: View {
    let card: HomeNoteCardModel
    let fill: Color
    let tapeVariant: Int
    let isHovered: Bool

    private var tapeWidth: CGFloat {
        let widths: [CGFloat] = [39, 44, 36, 41, 38, 43]
        return widths[tapeVariant % widths.count]
    }

    private var tapeOpacity: Double {
        let opacities = [0.56, 0.48, 0.61, 0.52, 0.58, 0.50]
        return opacities[tapeVariant % opacities.count]
    }

    private var tapeRotation: Double {
        let rotations = [-1.2, 0.8, -0.5, 1.1, -0.9, 0.4]
        return rotations[tapeVariant % rotations.count]
    }

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
                .fill(Color.white.opacity(tapeOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(Chamfer.Palette.ink.opacity(0.055), lineWidth: 0.6)
                }
                .frame(width: tapeWidth, height: 9)
                .rotationEffect(.degrees(tapeRotation))
                .offset(y: -4)
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

    private var normalShadowOpacity: Double {
        switch card.role {
        case .featured: 0.14
        case .supporting: 0.105
        case .recentlyCleaned: 0.085
        case .background: 0.065
        }
    }

    private var normalShadowRadius: CGFloat {
        switch card.role {
        case .featured: 9
        case .supporting: 8
        case .recentlyCleaned: 8
        case .background: 7
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
