import ChamferCore
import ChamferFixtures
import CoreGraphics
import Testing
@testable import ChamferUI

/// Settings is reached from the gutter and the menu bar, and from neither the
/// bottom bar nor the page. The scope is explicit that system surfaces leave
/// the window and that the bar does not grow; these pin both halves of that.

@Test func settingsIsNotABottomBarDestinationOrFootAction() {
    let items = DashboardBottomBarItems.make(for: Fixtures.vaultScenario())

    #expect(items.count == 3)
    #expect(!items.contains { $0.footAction?.id.contains("settings") == true })
    #expect(
        items.compactMap(\.footAction).map(\.id)
            == [DashboardView.FootAction.manageVaults]
    )
}

/// The gutter reveal is one gesture with three controls on it, so Settings
/// answers exactly the rule close already did. The consequence worth recording
/// is the last case: on the Home screen the gutter is suppressed entirely, and
/// Settings is reachable only from the menu bar or Command-comma.
@Test func settingsRidesTheSameGutterRevealAsClose() {
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
    #expect(
        !DashboardCloseControlVisibility.shouldShow(
            pointerAtTop: true,
            showingHome: true
        )
    )
}

/// History is a stable note action, not a notification badge. It remains in
/// the gutter for a note with zero queued or recorded changes so users can
/// discover where future work will appear.
@Test func noteHistoryControlDependsOnTheOpenNoteRatherThanAChangeCount() {
    #expect(
        DashboardNoteHistoryControlVisibility.shouldShow(
            showingNotes: true,
            showingHome: false,
            hasOpenNote: true
        )
    )
    #expect(
        !DashboardNoteHistoryControlVisibility.shouldShow(
            showingNotes: true,
            showingHome: false,
            hasOpenNote: false
        )
    )
    #expect(
        !DashboardNoteHistoryControlVisibility.shouldShow(
            showingNotes: false,
            showingHome: false,
            hasOpenNote: true
        )
    )
}

/// The panel builds its own actions rather than reading an environment it does
/// not have — it is hosted outside the scene tree. If this stops compiling,
/// the menu bar has lost its route to the window.
@MainActor
@Test func theMenuBarPanelCarriesAnOpenSettingsAction() {
    var opened = false
    let actions = MenuBarActions(openSettings: { opened = true })

    actions.openSettings()

    #expect(opened)
}

@MainActor
@Test func anOpenMenuBarPanelReadsTheLatestDashboardState() {
    var state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: []
    )
    let panel = MenuBarPanel(state: { state })

    #expect(panel.presentedState.runState == .idle)
    state.runState = .paused
    #expect(panel.presentedState.runState == .paused)
}

/// The third tab owns only the cross-vault reset; individual choices still
/// live on the vault they configure.
@Test func settingsExposesTheCrossVaultResetWithoutMovingVaultEditors() {
    #expect(SettingsView.Section.allCases == [.privacy, .notifications, .vaults])
    #expect(SettingsView.Section.allCases.first == .privacy)
}

// MARK: - Gutter cluster

/// The reason the flanking slots are a fixed, equal width. Versions arriving,
/// leaving, or growing a digit must not shift the one control the hand already
/// knows where to find.
@Test func closeSitsAtTheExactCentreOfTheGutterCluster() {
    #expect(
        DashboardGutterLayout.closeCentre
            == DashboardGutterLayout.clusterWidth / 2
    )
}

/// Three controls close enough to read as one group, far enough apart that
/// aiming at the middle one cannot land on a neighbour. The 44pt target is
/// six past each 32pt edge, so anything under a 12pt gap overlaps.
@Test func noTwoGutterControlsShareAHitArea() {
    #expect(DashboardGutterLayout.hitAreaClearance > 0)
    #expect(
        DashboardGutterLayout.controlDiameter
            + DashboardGutterLayout.hitInset * 2 == 44
    )
}

/// The versions capsule has to fit its slot at the counts it actually reaches,
/// or it overflows into the page margin instead of sitting in the cluster.
@Test func theVersionsSlotHoldsAThreeDigitCount() {
    // 12pt padding, an 11pt glyph, 5pt, three monospaced digits, 12pt again.
    let widestCapsule: CGFloat = 12 + 11 + 5 + 20 + 12
    #expect(DashboardGutterLayout.slot >= widestCapsule)
}
