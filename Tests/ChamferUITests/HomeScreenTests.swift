import ChamferCore
import ChamferFixtures
import Foundation
import Testing
@testable import ChamferUI

@Test func interactionMotionUsesSnappyNativeResponseWindows() {
    #expect(Chamfer.Motion.quickDuration <= 0.11)
    #expect(Chamfer.Motion.interactiveDuration <= 0.22)
    #expect(Chamfer.Motion.navigationDuration <= 0.32)
    #expect(Chamfer.Motion.quickDuration < Chamfer.Motion.interactiveDuration)
    #expect(Chamfer.Motion.interactiveDuration < Chamfer.Motion.navigationDuration)
}

@Test func greetingsIncludeTimeSpecificCopyAndEnoughVariety() {
    let morning = HomeGreetingRotation.availableGreetings(hour: 8, name: "Anthony")
    let afternoon = HomeGreetingRotation.availableGreetings(hour: 14, name: "Anthony")
    let evening = HomeGreetingRotation.availableGreetings(hour: 20, name: "Anthony")

    #expect(morning.contains("Good morning, Anthony."))
    #expect(afternoon.contains("Good afternoon, Anthony."))
    #expect(evening.contains("Good evening, Anthony."))
    #expect(Set(morning + afternoon + evening).count >= 20)
}

@Test func theGreetingAdvancesOnceEveryFortyFiveMinutesTheAppIsOpen() {
    let opened = Date(timeIntervalSince1970: 1_800_000_000)
    let schedule = HomeGreetingSchedule(openedAt: opened)

    #expect(schedule.window(at: opened) == 0)
    #expect(schedule.window(at: opened.addingTimeInterval(44 * 60)) == 0)
    #expect(schedule.window(at: opened.addingTimeInterval(45 * 60)) == 1)
    #expect(schedule.window(at: opened.addingTimeInterval(89 * 60)) == 1)
    #expect(schedule.window(at: opened.addingTimeInterval(90 * 60)) == 2)
    // A session is the unit, so the clock on the wall never brings a window
    // forward on its own.
    #expect(schedule.window(at: opened.addingTimeInterval(-3_600)) == 0)
}

/// Consecutive windows have to actually read differently, or the interval is a
/// number with nothing behind it.
@Test func consecutiveWindowsProduceDifferentLines() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let date = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9))
    )

    let lines = (0..<6).map {
        HomeGreetingRotation.text(
            window: $0,
            at: date,
            name: "Anthony",
            calendar: calendar
        )
    }

    #expect(Set(lines).count == lines.count)
    #expect(zip(lines, lines.dropFirst()).allSatisfy { $0 != $1 })
}

/// The rule the request turns on: the line may only move when the page is not
/// being looked at. `resolve` is the only thing that moves it, and the view
/// calls it on appear alone.
@Test func theGreetingHoldsStillUntilItIsResolvedAgain() {
    let opened = Date(timeIntervalSince1970: 1_800_000_000)
    var schedule = HomeGreetingSchedule(openedAt: opened)

    let first = schedule.resolve(at: opened, name: "Anthony")
    #expect(schedule.shownWindow == 0)

    // Two hours of staring at the home screen. The window has come due twice
    // and the shown line has not moved, because nothing resolved it.
    let later = opened.addingTimeInterval(2 * 60 * 60)
    #expect(schedule.isDue(at: later))
    #expect(schedule.shownWindow == 0)

    // Leaving and coming back is what collects it.
    let second = schedule.resolve(at: later, name: "Anthony")
    #expect(schedule.shownWindow == 2)
    #expect(second != first)
    #expect(!schedule.isDue(at: later))
}

@Test func resolvingTwiceInsideOneWindowKeepsTheSameLine() {
    let opened = Date(timeIntervalSince1970: 1_800_000_000)
    var schedule = HomeGreetingSchedule(openedAt: opened)

    let first = schedule.resolve(at: opened, name: "Anthony")
    let again = schedule.resolve(
        at: opened.addingTimeInterval(44 * 60),
        name: "Anthony"
    )

    // Bouncing in and out of the home screen must not shuffle the greeting.
    #expect(first == again)
    #expect(schedule.shownWindow == 0)
}

@MainActor
@Test func theClockIsSharedAcrossVisitsRatherThanRestartingOnEachOne() {
    let opened = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = HomeGreetingClock(openedAt: opened)

    let first = clock.greeting(at: opened, name: "Anthony")
    let sameVisit = clock.greeting(at: opened.addingTimeInterval(60), name: "Anthony")
    let afterAnHour = clock.greeting(
        at: opened.addingTimeInterval(46 * 60),
        name: "Anthony"
    )

    #expect(first == sameVisit)
    #expect(afterAnHour != first)
}

@Test func homeCardsAreUniqueAndCarryUsefulPreviewText() {
    let state = Fixtures.state(for: .typical)
    let cards = HomeNoteCardModel.cards(from: state)

    #expect(cards.count >= 3)
    #expect(Set(cards.map(\.id)).count == cards.count)
    #expect(cards.allSatisfy { !$0.title.isEmpty })
    #expect(cards.allSatisfy { !$0.preview.isEmpty })
    #expect(cards.allSatisfy { !$0.document.text.isEmpty })
    #expect(cards.first?.preview == state.pendingProposals.first?.hunks.first?.after)
}

@Test func homeDeckReplacesOnlyTheSwipedSlotAndCyclesRemovedNotes() throws {
    let cards = (0..<8).map(homeDeckCard)
    var deck = HomeNoteDeck(cards: cards, visibleLimit: 6)

    #expect(deck.visible.map(\.id) == ["note-0", "note-1", "note-2", "note-3", "note-4", "note-5"])
    #expect(deck.reserve.map(\.id) == ["note-6", "note-7"])

    let firstResult = deck.replace(cardID: "note-2")
    let firstReplacement = try #require(firstResult)
    #expect(firstReplacement.id == "note-6")
    #expect(deck.visible.map(\.id) == ["note-0", "note-1", "note-6", "note-3", "note-4", "note-5"])
    #expect(deck.reserve.map(\.id) == ["note-7", "note-2"])

    _ = deck.replace(cardID: "note-6")
    let cycledResult = deck.replace(cardID: "note-7")
    let cycledReplacement = try #require(cycledResult)
    #expect(cycledReplacement.id == "note-2")
    #expect(deck.visible[2].id == "note-2")
}

@Test func typicalFixtureProvidesSixVisibleNotesAndFiveReserves() {
    let state = Fixtures.state(for: .typical)
    let deckCards = HomeNoteCardModel.deckCards(from: state)

    #expect(Set(state.searchableNotes.map(\.url)).count == 11)
    #expect(Set(state.recentNotes.map(\.url)).count == 11)
    #expect(deckCards.count == 11)
    #expect(HomeNoteDeck(cards: deckCards).visible.count == 6)
    #expect(HomeNoteDeck(cards: deckCards).reserve.count == 5)
}

@Test func stickyNoteColorsBelongToWallSlotsInsteadOfNotes() {
    #expect((0..<6).map { HomeNoteSlotPalette.tone(for: $0) } == [
        .orangeYellow,
        .pink,
        .green,
        .warmIvory,
        .cleanPaper,
        .quietPaper
    ])

    #expect(HomeNoteSlotPalette.tone(for: 0) == .orangeYellow)
    #expect(HomeNoteSlotPalette.tone(for: 1) == .pink)
    #expect(HomeNoteSlotPalette.tone(for: 2) == .green)
}

@Test func proposalCardKeepsTheNoteIdentityWhenOpened() throws {
    let state = Fixtures.state(for: .typical)
    let proposal = try #require(state.pendingProposals.dropFirst().first)
    let card = try #require(
        HomeNoteCardModel.cards(from: state).first { $0.document.url == proposal.note.url }
    )

    #expect(card.document.url == proposal.note.url)
    #expect(card.document.text.contains(proposal.note.title))
}

@Test func featuredNoteFavorsTheMostMeaningfulPendingReview() throws {
    let now = Date(timeIntervalSince1970: 1_785_000_000)
    let quickNote = NoteSummary(
        url: URL(fileURLWithPath: "/Notes/Quick.md"),
        title: "Quick",
        wordCount: 80,
        modifiedAt: now
    )
    let meaningfulNote = NoteSummary(
        url: URL(fileURLWithPath: "/Notes/Meaningful.md"),
        title: "Meaningful",
        wordCount: 420,
        modifiedAt: now.addingTimeInterval(-600)
    )
    let quick = Proposal(
        note: quickNote,
        hunks: [Hunk(before: "a", after: "A", startLine: 1)],
        createdAt: now
    )
    let meaningful = Proposal(
        note: meaningfulNote,
        hunks: [
            Hunk(before: "a", after: "A", startLine: 1),
            Hunk(before: "b", after: "B", startLine: 8),
            Hunk(before: "c", after: "C", startLine: 15)
        ],
        createdAt: now.addingTimeInterval(-600)
    )
    let state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [quick, meaningful],
        recentlyCleaned: []
    )

    let featured = try #require(
        HomeNoteCardModel.cards(from: state).first { $0.isFeatured }
    )

    #expect(featured.document.url == meaningfulNote.url)
}

@Test func everyVisibleNoteReceivesAWallPlacement() {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .flooded))
    let placements = HomeNoteWallLayout.placements(for: cards)

    #expect(placements.count == min(cards.count, HomeNoteWallLayout.slotCount))
    #expect(Set(placements.map(\.id)).isSubset(of: Set(cards.map(\.id))))
    #expect(Set(placements.map(\.id)).count == placements.count)
}

@Test func typicalWallContainsSixNotesWithDistinctHierarchyRoles() {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))

    #expect(cards.count == 6)
    #expect(cards.filter { $0.role == .featured }.count == 1)
    #expect(cards.filter { $0.role == .supporting }.count == 3)
    #expect(cards.filter { $0.role == .recentlyCleaned }.count == 1)
    #expect(cards.filter { $0.role == .background }.count == 1)
}

/// The wall is a scatter, not a pile. This is the check that keeps it one.
///
/// The hand-placed version read well at the height it was drawn at and
/// collided at every other: two slots sat 0.14 apart across a canvas where a
/// card is 0.26 wide, so notes covered each other's titles. Nothing in the
/// coordinates said so, which is why the rule is now measured rather than
/// eyeballed — at the shortest window Chamfer allows as well as the tallest.
@Test func noTwoNotesOnTheWallEverOverlap() {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))

    for canvas in [
        CGSize(width: 736, height: 300),
        CGSize(width: 736, height: 420),
        CGSize(width: 736, height: 560)
    ] {
        let placements = HomeNoteWallLayout.placements(for: cards, canvas: canvas)
        for (index, placement) in placements.enumerated() {
            for other in placements[(index + 1)...] {
                #expect(
                    !HomeNoteWallLayout.overlaps(placement, other, canvas: canvas),
                    "\(placement.id) overlaps \(other.id) at \(canvas)"
                )
            }
        }
    }
}

/// And stays on the wall it is scattered across.
@Test func everyNoteStaysInsideTheCanvas() {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))
    let canvas = CGSize(width: 736, height: 420)

    for placement in HomeNoteWallLayout.placements(for: cards, canvas: canvas) {
        let halfWidth = HomeNoteWallLayout.cardSize.width * placement.scale / 2
        let halfHeight = HomeNoteWallLayout.cardSize.height * placement.scale / 2
        #expect(placement.x * canvas.width - halfWidth >= -1)
        #expect(placement.x * canvas.width + halfWidth <= canvas.width + 1)
        #expect(placement.y * canvas.height - halfHeight >= -1)
        #expect(placement.y * canvas.height + halfHeight <= canvas.height + 1)
    }
}

/// Not overlapping is the floor, not the goal. A wall where every note is the
/// same size at the same angle on the same spacing reads as a contact sheet —
/// which is what the lattice produced before the notes were knocked off it.
@Test func theWallIsIrregularEnoughToLookPlacedRatherThanLaidOut() {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))
    let canvas = CGSize(width: 736, height: 420)
    let placements = HomeNoteWallLayout.placements(for: cards, canvas: canvas)

    #expect(placements.count == 6)

    // Angles vary, and stay subtle. Past a couple of degrees it stops reading
    // as a note somebody pressed on and starts reading as an effect.
    let rotations = placements.map(\.rotation)
    #expect(Set(rotations.map { ($0 * 100).rounded() }).count == rotations.count)
    #expect(rotations.allSatisfy { abs($0) <= 2 })
    #expect(rotations.contains { $0 < -0.4 })
    #expect(rotations.contains { $0 > 0.4 })

    // Sizes vary: a short scribble is not the same piece of paper as a note
    // with a paragraph on it.
    let heights = Set(placements.map { ($0.size.height).rounded() })
    let widths = Set(placements.map { ($0.size.width).rounded() })
    #expect(heights.count >= 4, "only \(heights.count) distinct heights")
    #expect(widths.count >= 4, "only \(widths.count) distinct widths")

    // And neither a row nor a column shares an edge, which is the giveaway a
    // grid leaves however much the individual notes wobble.
    let topRow = placements.prefix(3).map { ($0.y * canvas.height).rounded() }
    #expect(Set(topRow).count == 3, "the top row is aligned: \(topRow)")
    let rowSpread = (topRow.max() ?? 0) - (topRow.min() ?? 0)
    #expect(rowSpread > 20, "the top row varies by only \(rowSpread)pt")

    for column in 0..<3 {
        let above = placements[column].x * canvas.width
        let below = placements[column + 3].x * canvas.width
        #expect(abs(above - below) > 15, "column \(column) is stacked: \(above), \(below)")
    }
}

/// The same note has to look the same tomorrow. Deriving the imperfection from
/// the note's identity is what separates "placed" from "shuffled every render".
@Test func aNoteKeepsItsOwnCharacterBetweenLaunches() {
    let first = HomeNoteHand(id: "notes/Project Atlas.md")
    let again = HomeNoteHand(id: "notes/Project Atlas.md")
    let other = HomeNoteHand(id: "notes/Grocery List.md")

    #expect(first == again)
    #expect(first != other)
    #expect(first.offset != other.offset)
    // Eight points is where an offset stops reading as a mistake.
    let distance = (first.offset.width * first.offset.width
        + first.offset.height * first.offset.height).squareRoot()
    #expect(distance >= 7.9 && distance <= 20.1, "offset is \(distance)pt")
}

/// Tape a person tore and pressed down is never the same twice, and never
/// centred. Identical strips were the strongest signal nobody put these here.
@Test func noTwoNotesShareTheSameTape() {
    let hands = HomeNoteCardModel
        .cards(from: Fixtures.state(for: .typical))
        .prefix(6)
        .map { HomeNoteHand(id: $0.id) }

    #expect(Set(hands.map { ($0.tapeWidth).rounded() }).count >= 5)
    #expect(Set(hands.map { ($0.tapeOpacity * 100).rounded() }).count >= 5)
    #expect(Set(hands.map { ($0.tapeRotation * 10).rounded() }).count >= 5)
    #expect(hands.allSatisfy { abs($0.tapeRotation) <= 7 })
    // Off-centre, and over the edge rather than floating above it.
    #expect(hands.contains { $0.tapeOffset.width < -3 })
    #expect(hands.contains { $0.tapeOffset.width > 3 })
    #expect(hands.allSatisfy { $0.tapeOffset.height < 0 })
}

/// Hierarchy survives the lattice: the featured note leads on depth, and the
/// quiet ones sit behind it rather than growing to compete.
@Test func theFeaturedNoteLeadsOnDepthRatherThanOnSize() throws {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))
    let placements = HomeNoteWallLayout.placements(for: cards)
    let featuredCard = try #require(cards.first { $0.role == .featured })
    let featured = try #require(placements.first { $0.id == featuredCard.id })
    let backgroundCard = try #require(cards.first { $0.role == .background })
    let background = try #require(placements.first { $0.id == backgroundCard.id })

    #expect(featured.depth > background.depth)
    #expect(featured.scale >= background.scale)
    // A wall of notes, not a fan of playing cards.
    #expect(placements.allSatisfy { abs($0.rotation) <= 3 })
}



@Test func closeControlIsSuppressedOnHomeButAvailableOnPages() {
    #expect(
        !DashboardCloseControlVisibility.shouldShow(
            pointerAtTop: true,
            showingHome: true
        )
    )
    #expect(
        DashboardCloseControlVisibility.shouldShow(
            pointerAtTop: true,
            showingHome: false
        )
    )
    #expect(
        !DashboardCloseControlVisibility.shouldShow(
            pointerAtTop: false,
            showingHome: false
        )
    )
}

@Test func bottomBarSelectionIsNeutralOnHome() {
    #expect(
        !DashboardBottomBarSelectionVisibility.shouldShow(showingHome: true)
    )
    #expect(
        DashboardBottomBarSelectionVisibility.shouldShow(showingHome: false)
    )
}

@Test func openingOffsetMovesPeripheralNotesTowardTheClusterCenter() {
    let placement = HomeNotePlacement(
        id: "left-note",
        x: 0.25,
        y: 0.30,
        rotation: -2,
        scale: 1,
        size: HomeNoteWallLayout.cardSize,
        depth: 2
    )

    let offset = HomeNoteWallLayout.openingOffset(
        for: placement,
        canvasSize: CGSize(width: 600, height: 500)
    )

    #expect(offset.width > 0)
    #expect(offset.height > 0)
    #expect(offset.width < 50)
    #expect(offset.height < 50)
}

@Test func homeReturnStartsPeripheralNotesCloserToTheClusterCenter() {
    let placement = HomeNotePlacement(
        id: "left-note",
        x: 0.20,
        y: 0.25,
        rotation: -2,
        scale: 1,
        size: HomeNoteWallLayout.cardSize,
        depth: 2
    )

    let moving = HomeReturnMotion.cardEntryOffset(
        for: placement,
        canvasSize: CGSize(width: 600, height: 500),
        reduceMotion: false
    )
    let reduced = HomeReturnMotion.cardEntryOffset(
        for: placement,
        canvasSize: CGSize(width: 600, height: 500),
        reduceMotion: true
    )

    #expect(moving.width > 0)
    #expect(moving.height > 0)
    #expect(reduced == .zero)
}

@Test func liveClockHandsTrackTheDisplayedTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let date = try #require(
        calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 30,
                hour: 11,
                minute: 30,
                second: 0
            )
        )
    )

    let angles = HomeClockGeometry.handAngles(at: date, calendar: calendar)

    #expect(angles.hour == 345)
    #expect(angles.minute == 180)
}

@Test func clockHoverAddsOneFullTurnButReduceMotionKeepsItsOrientation() {
    #expect(HomeClockHoverMotion.nextRotation(after: 0, reduceMotion: false) == 360)
    #expect(HomeClockHoverMotion.nextRotation(after: 360, reduceMotion: false) == 720)
    #expect(HomeClockHoverMotion.nextRotation(after: 360, reduceMotion: true) == 360)
}

private func homeDeckCard(_ index: Int) -> HomeNoteCardModel {
    HomeNoteCardModel(
        id: "note-\(index)",
        title: "Note \(index)",
        detail: "RECENT NOTE",
        preview: "Preview \(index)",
        document: NoteDocument(
            url: URL(fileURLWithPath: "/Notes/Note \(index).md"),
            text: "# Note \(index)\n\nPreview \(index)"
        ),
        source: .open,
        isFeatured: false,
        role: .background
    )
}

