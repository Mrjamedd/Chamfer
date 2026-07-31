import ChamferCore
import CoreGraphics
import Foundation
import Testing
@testable import ChamferUI

@Test func bottomBarPointerTracksVariableWidthDestinations() {
    let frames = [
        "models": CGRect(x: 176, y: 0, width: 72, height: 30),
        "notes": CGRect(x: 0, y: 0, width: 76, height: 30),
        "review": CGRect(x: 82, y: 0, width: 88, height: 30)
    ]

    #expect(BottomBarPointerTarget.itemID(at: 32, frames: frames) == "notes")
    #expect(BottomBarPointerTarget.itemID(at: 120, frames: frames) == "review")
    #expect(BottomBarPointerTarget.itemID(at: 212, frames: frames) == "models")
    #expect(BottomBarPointerTarget.itemID(at: 79, frames: frames) == nil)
}

@Test func twoFingerHorizontalSwipeStepsTabsWithoutWrapping() {
    let tabs = ["notes", "review", "models"]

    #expect(
        DashboardTabGesture.destination(
            from: "notes",
            direction: .left,
            orderedIDs: tabs
        ) == "review"
    )
    #expect(
        DashboardTabGesture.destination(
            from: "review",
            direction: .right,
            orderedIDs: tabs
        ) == "notes"
    )
    #expect(
        DashboardTabGesture.destination(
            from: "models",
            direction: .left,
            orderedIDs: tabs
        ) == "models"
    )
}

@Test func twoFingerTabNavigationKeepsSearchOpen() {
    let result = DashboardTabGesture.transition(
        from: "notes",
        isSearching: true,
        showingHome: true,
        direction: .left,
        orderedIDs: ["notes", "review", "models"]
    )

    #expect(result.tab == "review")
    #expect(result.isSearching)
    #expect(!result.showingHome)
}

@Test func preciseScrollGestureEmitsOnceAfterDominantHorizontalTravel() {
    var gesture = TrackpadScrollAccumulator()

    #expect(
        gesture.update(
            phase: .began,
            physicalDelta: .zero,
            isMomentum: false
        ) == nil
    )
    #expect(
        gesture.update(
            phase: .changed,
            physicalDelta: CGSize(width: -20, height: 2),
            isMomentum: false
        ) == nil
    )
    #expect(
        gesture.update(
            phase: .changed,
            physicalDelta: CGSize(width: -22, height: 3),
            isMomentum: false
        ) == .left
    )
    #expect(
        gesture.update(
            phase: .changed,
            physicalDelta: CGSize(width: -50, height: 0),
            isMomentum: false
        ) == nil
    )
}

@Test func preciseScrollGestureKeepsVerticalAndDiagonalMovementOutOfTabNavigation() {
    var vertical = TrackpadScrollAccumulator()
    _ = vertical.update(phase: .began, physicalDelta: .zero, isMomentum: false)
    #expect(
        vertical.update(
            phase: .changed,
            physicalDelta: CGSize(width: 5, height: 48),
            isMomentum: false
        ) == .up
    )

    var diagonal = TrackpadScrollAccumulator()
    _ = diagonal.update(phase: .began, physicalDelta: .zero, isMomentum: false)
    #expect(
        diagonal.update(
            phase: .changed,
            physicalDelta: CGSize(width: 42, height: 38),
            isMomentum: false
        ) == nil
    )
}

@Test func preciseScrollGestureIgnoresMomentumAndResetsAfterCancellation() {
    var gesture = TrackpadScrollAccumulator()

    _ = gesture.update(phase: .began, physicalDelta: .zero, isMomentum: false)
    #expect(
        gesture.update(
            phase: .changed,
            physicalDelta: CGSize(width: -80, height: 0),
            isMomentum: true
        ) == nil
    )
    #expect(
        gesture.update(
            phase: .cancelled,
            physicalDelta: .zero,
            isMomentum: false
        ) == nil
    )
    #expect(
        gesture.update(
            phase: .changed,
            physicalDelta: CGSize(width: 40, height: 0),
            isMomentum: false
        ) == .right
    )
}

@Test func trackpadGestureRequiresTheExactFingerCountAndDominantTravel() {
    #expect(
        TrackpadPanClassifier.direction(
            touchCount: 3,
            requiredTouchCount: 3,
            translation: CGSize(width: -72, height: 8),
            velocity: CGSize(width: -520, height: 30)
        ) == .left
    )
    #expect(
        TrackpadPanClassifier.direction(
            touchCount: 2,
            requiredTouchCount: 3,
            translation: CGSize(width: -72, height: 8),
            velocity: CGSize(width: -520, height: 30)
        ) == nil
    )
    #expect(
        TrackpadPanClassifier.direction(
            touchCount: 3,
            requiredTouchCount: 3,
            translation: CGSize(width: -12, height: 9),
            velocity: CGSize(width: -80, height: 60)
        ) == nil
    )
    #expect(
        TrackpadPanClassifier.direction(
            touchCount: 2,
            requiredTouchCount: 2,
            translation: CGSize(width: 5, height: 66),
            velocity: CGSize(width: 20, height: 480)
        ) == .up
    )
}

@Test func expandedBottomBarListsScrollAfterFourVisibleEntries() {
    #expect(BottomBarListLayout.visibleEntryLimit(showsSearch: false) == 4)
    #expect(!BottomBarListLayout.needsScrolling(entryCount: 4, showsSearch: false))
    #expect(BottomBarListLayout.needsScrolling(entryCount: 5, showsSearch: false))
}

@Test func notesKeepSearchPinnedAfterThreeVisibleEntries() {
    #expect(BottomBarListLayout.visibleEntryLimit(showsSearch: true) == 3)
    #expect(!BottomBarListLayout.needsScrolling(entryCount: 3, showsSearch: true))
    #expect(BottomBarListLayout.needsScrolling(entryCount: 4, showsSearch: true))
    #expect(
        BottomBarListLayout.entryViewportHeight(entryCount: 8, showsSearch: true)
            == BottomBarListLayout.entryViewportHeight(entryCount: 3, showsSearch: true)
    )
}

@Test func notesDestinationShowsTheTenMostRecentUniqueNotes() throws {
    let baseline = Date(timeIntervalSince1970: 1_800_000_000)
    var recentNotes = (0..<12).map { index in
        NoteSummary(
            url: URL(fileURLWithPath: "/Notes/Note \(index).md"),
            title: "Note \(index)",
            wordCount: 100 + index,
            modifiedAt: baseline.addingTimeInterval(Double(index) * 60)
        )
    }
    recentNotes.append(
        NoteSummary(
            url: URL(fileURLWithPath: "/Notes/Note 11.md"),
            title: "Stale duplicate",
            wordCount: 1,
            modifiedAt: baseline.addingTimeInterval(-60)
        )
    )

    let state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: [],
        recentNotes: recentNotes
    )

    let notes = try #require(
        DashboardBottomBarItems.make(for: state).first { $0.id == "notes" }
    )

    #expect(notes.entries.count == 10)
    #expect(notes.entries.map(\.title) == [
        "Note 11", "Note 10", "Note 9", "Note 8", "Note 7",
        "Note 6", "Note 5", "Note 4", "Note 3", "Note 2"
    ])
    #expect(notes.entries.first?.detail == "111 words")
}

@Test func bottomBarScrollIndicatorOnlyAppearsDuringHoverOrScroll() {
    #expect(
        !BottomBarScrollIndicator.shouldShow(
            needsScrolling: true,
            isHovered: false,
            isScrolling: false
        )
    )
    #expect(
        BottomBarScrollIndicator.shouldShow(
            needsScrolling: true,
            isHovered: true,
            isScrolling: false
        )
    )
    #expect(
        BottomBarScrollIndicator.shouldShow(
            needsScrolling: true,
            isHovered: false,
            isScrolling: true
        )
    )
    #expect(
        !BottomBarScrollIndicator.shouldShow(
            needsScrolling: false,
            isHovered: true,
            isScrolling: true
        )
    )
}

@Test func bottomBarScrollThumbRepresentsViewportAndOffset() {
    let metrics = BottomBarScrollIndicator.metrics(
        contentHeight: 250,
        viewportHeight: 100,
        contentOffset: 75
    )

    #expect(metrics.thumbHeight == 40)
    #expect(metrics.thumbOffset == 30)
}

@Test func bottomBarScrollPrecisionAdaptsToTheNumberOfHiddenRows() {
    #expect(
        BottomBarScrollPrecision.tier(entryCount: 5, visibleLimit: 4)
            == .oneRow
    )
    #expect(
        BottomBarScrollPrecision.tier(entryCount: 6, visibleLimit: 4)
            == .oneRow
    )
    #expect(
        BottomBarScrollPrecision.tier(entryCount: 8, visibleLimit: 4)
            == .fewRows
    )
    #expect(
        BottomBarScrollPrecision.tier(entryCount: 12, visibleLimit: 4)
            == .native
    )
}

@Test func bottomBarScrollableRowsKeepAConcreteWidthBesideTheIndicator() {
    #expect(
        BottomBarListLayout.entryContentWidth(
            viewportWidth: 262,
            needsScrolling: false
        ) == 262
    )
    #expect(
        BottomBarListLayout.entryContentWidth(
            viewportWidth: 262,
            needsScrolling: true
        ) == 252
    )
}

@Test func bottomBarSectionsExposeStableAnimatedHeights() {
    #expect(
        BottomBarListLayout.expandedContentHeight(
            entryCount: 3,
            showsSearch: false
        ) == 76
    )
    #expect(
        BottomBarListLayout.expandedContentHeight(
            entryCount: 4,
            showsSearch: false
        ) == 97
    )
    #expect(
        BottomBarListLayout.expandedContentHeight(
            entryCount: 3,
            showsSearch: true
        ) == 107
    )
    #expect(
        BottomBarListLayout.expandedContentHeight(
            entryCount: 0,
            showsSearch: true
        ) == 34
    )
}

@Test func bottomBarSpringPassesItsRestingSizeBeforeSettling() {
    #expect(BottomBarBounceProfile.overshootScale(for: .opening) > 1)
    #expect(BottomBarBounceProfile.overshootScale(for: .closing) < 1)
    #expect(BottomBarBounceProfile.restingScale == 1)
}

@Test func bottomBarBounceHasVisibleButRestrainedTravel() {
    let openingTravel = BottomBarBounceProfile.overshootScale(for: .opening) - 1
    let closingTravel = 1 - BottomBarBounceProfile.overshootScale(for: .closing)

    #expect(openingTravel >= 0.02)
    #expect(openingTravel < 0.03)
    #expect(closingTravel >= 0.014)
    #expect(closingTravel < 0.025)
}

@Test func bottomBarContentHandoffFollowsTabDirection() {
    let orderedIDs = ["notes", "review", "models"]

    let movingRight = BottomBarContentMotion.direction(
        from: "notes",
        to: "models",
        orderedIDs: orderedIDs
    )
    #expect(movingRight == .forward)
    #expect(BottomBarContentMotion.outgoingOffset(for: movingRight) < 0)
    #expect(BottomBarContentMotion.incomingOffset(for: movingRight) > 0)

    let movingLeft = BottomBarContentMotion.direction(
        from: "models",
        to: "review",
        orderedIDs: orderedIDs
    )
    #expect(movingLeft == .backward)
    #expect(BottomBarContentMotion.outgoingOffset(for: movingLeft) > 0)
    #expect(BottomBarContentMotion.incomingOffset(for: movingLeft) < 0)
}

@Test func bottomBarContentHandoffLeavesNoPerceptibleBlankInterval() {
    let completeHandoff = BottomBarMotionTiming.contentHandoffDelay
        + BottomBarMotionTiming.contentEntranceDuration

    #expect(BottomBarMotionTiming.contentHandoffDelay == 0)
    #expect(BottomBarMotionTiming.contentExitDuration <= 0.016)
    #expect(BottomBarMotionTiming.contentEntranceDuration <= 0.048)
    #expect(completeHandoff <= 0.055)
}

@Test func bottomBarSelectionCompensatesForTheSurfaceBounce() {
    for direction in [
        BottomBarBounceProfile.Direction.opening,
        .closing
    ] {
        let surfaceScale = BottomBarBounceProfile.overshootScale(for: direction)
        let contentScale = BottomBarBounceProfile.compensatingScale(
            for: surfaceScale
        )

        #expect(abs(surfaceScale * contentScale - 1) < 0.0001)
    }
}

@Test func expandedBottomBarStartsClosingPromptlyAfterPointerExit() {
    #expect(BottomBarMotionTiming.pointerExitDelay <= 0.06)
    #expect(BottomBarMotionTiming.pointerExitDelay >= 0.04)
}

@Test func closingSearchClipsResultsToTheCollapsedBarHeight() {
    #expect(
        BottomBarSearchLayout.fieldHeight(
            isSearching: false,
            hasQuery: true,
            matchCount: 4,
            barHeight: 34
        ) == 34
    )
    #expect(
        BottomBarSearchLayout.fieldHeight(
            isSearching: true,
            hasQuery: true,
            matchCount: 4,
            barHeight: 34
        ) == 207
    )
}

@Test func searchTransitionDefersStructuralCleanupUntilGeometrySettles() {
    #expect(
        BottomBarSearchTransition.cleanup(
            direction: .opening,
            geometrySettled: false
        ) == .none
    )
    #expect(
        BottomBarSearchTransition.cleanup(
            direction: .opening,
            geometrySettled: true
        ) == .expandedSection
    )
    #expect(
        BottomBarSearchTransition.cleanup(
            direction: .closing,
            geometrySettled: false
        ) == .none
    )
    #expect(
        BottomBarSearchTransition.cleanup(
            direction: .closing,
            geometrySettled: true
        ) == .query
    )
}

@Test func movingAcrossBottomBarSectionsSwapsContentWithoutReopeningTheBar() {
    #expect(
        BottomBarSectionTransition.action(displayedID: nil, targetID: "notes")
            == .open
    )
    #expect(
        BottomBarSectionTransition.action(displayedID: "notes", targetID: "review")
            == .swap
    )
    #expect(
        BottomBarSectionTransition.action(displayedID: "review", targetID: "review")
            == .unchanged
    )
    #expect(
        BottomBarSectionTransition.action(displayedID: "review", targetID: nil)
            == .close
    )
}

@Test func noteSearchMatchesTitlesAndContentsWithTitleHitsFirst() {
    let notes = [
        NoteDocument(
            url: URL(fileURLWithPath: "/Notes/Retry plan.md"),
            text: "# Retry plan\n\nQueue behavior."
        ),
        NoteDocument(
            url: URL(fileURLWithPath: "/Notes/Operations.md"),
            text: "# Operations\n\nThe retry plan needs backoff."
        ),
        NoteDocument(
            url: URL(fileURLWithPath: "/Notes/Unrelated.md"),
            text: "# Unrelated\n\nNothing applicable."
        )
    ]

    let matches = BottomBarSearchIndex.matches(query: "retry", notes: notes)

    #expect(matches.map(\.document.url.lastPathComponent) == [
        "Retry plan.md",
        "Operations.md"
    ])
    #expect(matches[0].kind == .titlePrefix)
    #expect(matches[1].kind == .content)
}

@Test func noteSearchIsCaseAndDiacriticInsensitive() {
    let note = NoteDocument(
        url: URL(fileURLWithPath: "/Notes/Café.md"),
        text: "# Café\n\nRésumé ideas."
    )

    #expect(BottomBarSearchIndex.matches(query: "cafe", notes: [note]).count == 1)
    #expect(BottomBarSearchIndex.matches(query: "RESUME", notes: [note]).count == 1)
}

@Test func emptyNoteSearchDoesNotShowEveryNote() {
    let note = NoteDocument(
        url: URL(fileURLWithPath: "/Notes/Anything.md"),
        text: "# Anything"
    )

    #expect(BottomBarSearchIndex.matches(query: "   ", notes: [note]).isEmpty)
}
