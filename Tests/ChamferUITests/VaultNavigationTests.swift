import ChamferCore
import ChamferFixtures
import Testing
@testable import ChamferUI

/// The whole point of reaching Vaults from the Notes list is that the bar does
/// not grow. If this ever reads four, the interface decision has been undone.
@Test func theBottomBarStaysAtThreeDestinations() {
    let items = DashboardBottomBarItems.make(for: Fixtures.vaultScenario())

    #expect(items.count == 3)
    #expect(items.map(\.id) == [
        DashboardView.Tab.notes,
        DashboardView.Tab.review,
        DashboardView.Tab.models
    ])
    #expect(!items.contains { $0.id == DashboardView.Tab.vaults })
}

@Test func vaultsIsReachedFromTheFootOfTheNotesList() throws {
    let items = DashboardBottomBarItems.make(for: Fixtures.vaultScenario())
    let notes = try #require(items.first { $0.id == DashboardView.Tab.notes })
    let foot = try #require(notes.footAction)

    #expect(foot.id == DashboardView.FootAction.manageVaults)
    #expect(foot.title == "1 vault needs setting up…")
    #expect(notes.showsSearch)
}

/// With nothing connected the same row has to be an invitation rather than a
/// filing cabinet, or a new user has no way in at all.
@Test func theFootActionAsksYouToConnectAVaultWhenThereAreNone() throws {
    let items = DashboardBottomBarItems.make(for: Fixtures.state(for: .firstRun))
    let notes = try #require(items.first { $0.id == DashboardView.Tab.notes })

    #expect(notes.footAction?.title == "Connect a vault…")
}

@Test func theSwipeGestureNeverLandsOnVaults() {
    let ordered = [
        DashboardView.Tab.notes,
        DashboardView.Tab.review,
        DashboardView.Tab.models
    ]

    for start in ordered {
        for direction in [TrackpadPanDirection.left, .right] {
            let destination = DashboardTabGesture.destination(
                from: start,
                direction: direction,
                orderedIDs: ordered
            )
            #expect(destination != DashboardView.Tab.vaults)
        }
    }
}

// MARK: - Bar layout

@Test func aFootActionAddsExactlyOneRowToAnOpenList() {
    let withoutFoot = BottomBarListLayout.expandedContentHeight(
        entryCount: 3,
        showsSearch: true
    )
    let withFoot = BottomBarListLayout.expandedContentHeight(
        entryCount: 3,
        showsSearch: true,
        hasFootAction: true
    )

    #expect(withFoot > withoutFoot)
    #expect(
        withFoot - withoutFoot
            == BottomBarListLayout.rowHeight + BottomBarListLayout.rowSpacing
    )
}

/// Search and the foot action share one separator. Two rules stacked above a
/// two-row foot would read as a broken list.
@Test func aFootActionAloneStillOpensTheListWithoutASecondRule() {
    let searchOnly = BottomBarListLayout.expandedContentHeight(
        entryCount: 0,
        showsSearch: true
    )
    let footOnly = BottomBarListLayout.expandedContentHeight(
        entryCount: 0,
        showsSearch: false,
        hasFootAction: true
    )

    #expect(footOnly == searchOnly)
    #expect(footOnly > 0)
}
