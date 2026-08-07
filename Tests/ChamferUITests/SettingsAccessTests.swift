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

/// Deep-linking exists so a future entry point can land on the section it is
/// about; the plain route still opens where it always did.
@Test func settingsOpensOnRewritingUnlessAskedOtherwise() {
    #expect(SettingsView.Section.allCases.first == .rewriting)
    #expect(SettingsView.Section.allCases.count == 3)
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
