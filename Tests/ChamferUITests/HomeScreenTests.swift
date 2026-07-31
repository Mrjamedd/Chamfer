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

@Test func greetingChangesBetweenRotationWindows() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

    let first = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9, minute: 0))
    )
    let second = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9, minute: 12))
    )

    #expect(
        HomeGreetingRotation.text(at: first, name: "Anthony", calendar: calendar)
            != HomeGreetingRotation.text(at: second, name: "Anthony", calendar: calendar)
    )
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

@Test func typicalWallUsesARestrainedDiamondHierarchy() throws {
    let state = Fixtures.state(for: .typical)
    let cards = HomeNoteCardModel.cards(from: state)
    let placements = HomeNoteWallLayout.placements(for: cards)
    let featuredCard = try #require(cards.first { $0.isFeatured })
    let featured = try #require(placements.first { $0.id == featuredCard.id })
    let cleanedCard = try #require(cards.first { $0.source == .cleaned })
    let cleaned = try #require(placements.first { $0.id == cleanedCard.id })

    #expect(featuredCard.document.url == state.pendingProposals[1].note.url)
    #expect(featured.x > 0.48 && featured.x < 0.58)
    #expect(featured.y > 0.22 && featured.y < 0.34)
    #expect(featured.scale >= 1.08 && featured.scale <= 1.12)
    #expect(abs(featured.rotation) < 3)
    #expect(cleaned.y > featured.y)
    #expect(cleaned.scale < featured.scale)
    #expect(placements.allSatisfy { abs($0.rotation) <= 3 })
}

@Test func everyVisibleNoteReceivesAWallPlacement() {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .flooded))
    let placements = HomeNoteWallLayout.placements(for: cards)

    #expect(placements.count == cards.count)
    #expect(Set(placements.map(\.id)) == Set(cards.map(\.id)))
}

@Test func typicalWallContainsSixNotesWithDistinctHierarchyRoles() {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))

    #expect(cards.count == 6)
    #expect(cards.filter { $0.role == .featured }.count == 1)
    #expect(cards.filter { $0.role == .supporting }.count == 3)
    #expect(cards.filter { $0.role == .recentlyCleaned }.count == 1)
    #expect(cards.filter { $0.role == .background }.count == 1)
}

@Test func sixNoteConstellationKeepsQuietNotesLowAndOneSupportAtLowerRight() throws {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))
    let placements = HomeNoteWallLayout.placements(for: cards)
    let lowerRightCard = try #require(
        cards.filter { $0.role == .supporting }.last
    )
    let lowerRight = try #require(placements.first { $0.id == lowerRightCard.id })
    let cleanedCard = try #require(cards.first { $0.role == .recentlyCleaned })
    let cleaned = try #require(placements.first { $0.id == cleanedCard.id })
    let backgroundCard = try #require(cards.first { $0.role == .background })
    let background = try #require(placements.first { $0.id == backgroundCard.id })

    #expect(lowerRight.x > 0.65 && lowerRight.y > 0.55)
    #expect(cleaned.x > 0.24 && cleaned.x < 0.50 && cleaned.y > 0.58)
    #expect(background.x < 0.20)
    #expect(background.scale < cleaned.scale)
    #expect(background.depth < cleaned.depth)
}

@Test func featuredNoteSitsAboveItsTwoUpperSupports() throws {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))
    let placements = HomeNoteWallLayout.placements(for: cards)
    let featuredCard = try #require(cards.first { $0.role == .featured })
    let upperSupports = Array(cards.filter { $0.role == .supporting }.prefix(2))
    let featured = try #require(placements.first { $0.id == featuredCard.id })
    let supportPlacements = upperSupports.compactMap { card in
        placements.first { $0.id == card.id }
    }

    #expect(supportPlacements.count == 2)
    #expect(supportPlacements.allSatisfy { featured.y < $0.y })
}

@Test func readingListLeavesLaunchChecklistTitleClear() throws {
    let cards = HomeNoteCardModel.cards(from: Fixtures.state(for: .typical))
    let placements = HomeNoteWallLayout.placements(for: cards)
    let reading = try #require(cards.first { $0.title == "Reading list" })
    let launch = try #require(cards.first { $0.title == "Launch checklist" })
    let readingPlacement = try #require(placements.first { $0.id == reading.id })
    let launchPlacement = try #require(placements.first { $0.id == launch.id })

    #expect(launchPlacement.y - readingPlacement.y >= 0.30)
    #expect(launchPlacement.x >= readingPlacement.x)
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
