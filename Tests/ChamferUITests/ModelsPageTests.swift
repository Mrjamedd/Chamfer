import CoreGraphics
import ChamferFixtures
import Testing
@testable import ChamferUI

@Test func selectingAModelOpensOnlyItsConfigurationWithoutChangingTheActiveModel() {
    var state = ModelsLandscapeState()

    state.select(.ollama)

    #expect(state.active == .apple)
    #expect(state.selected == .ollama)
    #expect(state.expanded == .ollama)
}

@Test func closingConfigurationReturnsFocusToTheActiveModel() {
    var state = ModelsLandscapeState()
    state.select(.mlx)

    state.closeConfiguration()

    #expect(state.active == .apple)
    #expect(state.selected == .apple)
    #expect(state.expanded == nil)
}

@Test func activatingTheSelectedModelUpdatesStatusAndCollapsesTheSheet() {
    var state = ModelsLandscapeState()
    state.select(.ollama)

    state.activateSelected()

    #expect(state.active == .ollama)
    #expect(state.selected == .ollama)
    #expect(state.expanded == nil)
    #expect(state.status(for: .ollama, appleAvailable: true) == "ACTIVE")
    #expect(state.status(for: .apple, appleAvailable: true) == "AVAILABLE")
}

@Test func connectionTestingMovesFromTestingToTheReportedResult() {
    var state = ModelsLandscapeState()

    state.beginConnectionTest()
    #expect(state.connection == .testing)

    state.finishConnectionTest(connected: true)
    #expect(state.connection == .connected)
}

@Test func bundledModelBecomesReadyOnlyAfterItsDownloadFinishes() {
    var state = ModelsLandscapeState()

    #expect(state.status(for: .mlx, appleAvailable: true) == "NOT INSTALLED")
    state.beginDownload()
    #expect(state.installation == .downloading)
    state.finishDownload()

    #expect(state.installation == .installed)
    #expect(state.status(for: .mlx, appleAvailable: true) == "READY")
}

@Test func expandedLandscapeMovesFocusInwardAndSoftensOtherModels() {
    var state = ModelsLandscapeState()
    let restingMLX = ModelsLandscapeLayout.placement(for: .mlx, state: state)
    let restingApple = ModelsLandscapeLayout.placement(for: .apple, state: state)

    state.select(.mlx)
    let focusedMLX = ModelsLandscapeLayout.placement(for: .mlx, state: state)
    let softenedApple = ModelsLandscapeLayout.placement(for: .apple, state: state)

    #expect(focusedMLX.y < restingMLX.y)
    #expect(focusedMLX.opacity == 1)
    #expect(softenedApple.x < restingApple.x)
    #expect(softenedApple.opacity < 0.4)
}

@Test func restingModelsFormTheApprovedLooseTriangle() {
    let state = ModelsLandscapeState()
    let apple = ModelsLandscapeLayout.placement(for: .apple, state: state)
    let ollama = ModelsLandscapeLayout.placement(for: .ollama, state: state)
    let mlx = ModelsLandscapeLayout.placement(for: .mlx, state: state)

    #expect(apple.x < mlx.x)
    #expect(ollama.x > mlx.x)
    #expect(apple.y < mlx.y)
    #expect(ollama.y < mlx.y)
}

@Test func activeModelStatusFlowsIntoTheExistingBottomBar() throws {
    var modelsState = ModelsLandscapeState()
    modelsState.select(.ollama)
    modelsState.activateSelected()

    let items = DashboardBottomBarItems.make(
        for: Fixtures.state(for: .typical),
        modelsState: modelsState
    )
    let modelsItem = try #require(items.first { $0.id == DashboardView.Tab.models })
    let ollama = try #require(modelsItem.entries.first { $0.title == "Ollama" })
    let apple = try #require(
        modelsItem.entries.first { $0.title == "Foundation Models" }
    )

    #expect(ollama.detail == "ACTIVE")
    #expect(apple.detail == "AVAILABLE")
}
