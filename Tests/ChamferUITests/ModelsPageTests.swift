import CoreGraphics
import ChamferFixtures
import Testing
@testable import ChamferUI

@Test func onlyTheActiveBackendTitleIsEmphasized() {
    for active in ModelsBackendID.allCases {
        for backend in ModelsBackendID.allCases {
            let presentation = ModelsTitleResponse.presentation(
                for: backend,
                active: active
            )

            #expect(presentation.isBold == (backend == active))
            #expect(presentation.size == 27)
        }
    }
}

@Test func localCatalogChoosesOneRecommendedModelForAvailableMemory() throws {
    let catalog = LocalModelCatalog.standard
    let memory = UInt64(16) * 1_073_741_824
    let assessments = catalog.map {
        LocalModelCatalog.assessment(for: $0, physicalMemory: memory)
    }

    #expect(assessments.filter { $0.fit == .recommended }.count == 1)
    let recommended = try #require(
        zip(catalog, assessments).first { $0.1.fit == .recommended }
    )
    #expect(recommended.0.id == "qwen3.5:9b")
}

@Test func localCatalogDistinguishesUsableAndUnusableModels() throws {
    let catalog = LocalModelCatalog.standard
    let memory = UInt64(8) * 1_073_741_824
    let small = try #require(catalog.first { $0.id == "qwen3.5:2b" })
    let large = try #require(catalog.first { $0.id == "gpt-oss:20b" })

    #expect(
        LocalModelCatalog.assessment(for: small, physicalMemory: memory).fit
            == .recommended
    )
    #expect(
        LocalModelCatalog.assessment(for: large, physicalMemory: memory).fit
            == .unusable
    )
}

@Test func selectingALocalModelTracksWhetherThatExactModelIsInstalled() {
    var state = ModelsLandscapeState(
        selectedLocalModelID: "qwen3.5:4b",
        installedLocalModelIDs: ["qwen3.5:2b"]
    )

    #expect(state.installation == .notInstalled)
    state.selectLocalModel("qwen3.5:2b")
    #expect(state.installation == .installed)

    state.selectLocalModel("qwen3.5:9b")
    #expect(state.installation == .notInstalled)
}

@Test func selectingAModelOpensOnlyItsConfigurationWithoutChangingTheActiveModel() {
    var state = ModelsLandscapeState()

    state.select(.mlx)

    #expect(state.active == .apple)
    #expect(state.selected == .mlx)
    #expect(state.expanded == .mlx)
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
    state.select(.mlx)
    state.finishDownload()

    state.activateSelected()

    #expect(state.active == .mlx)
    #expect(state.selected == .mlx)
    #expect(state.expanded == nil)
    #expect(state.status(for: .mlx, appleAvailable: true) == "ACTIVE")
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

@Test func modelsPageUsesProductFacingNamesAndPurposefulActions() throws {
    let backends = Backend.all(
        runState: Fixtures.state(for: .typical).runState,
        landscapeState: ModelsLandscapeState()
    )
    let apple = try #require(backends.first { $0.id == .apple })
    let local = try #require(backends.first { $0.id == .mlx })
    let cloud = try #require(backends.first { $0.id == .ollama })

    #expect(apple.name == "Apple Foundation Models")
    #expect(apple.status == "ACTIVE")
    #expect(apple.detail == "Private, fast and built into macOS.")
    #expect(apple.actionTitle == "Manage settings")
    #expect(apple.actionSymbol == "arrow.right")

    #expect(local.name == "Local Model")
    #expect(local.status == "NOT INSTALLED")
    #expect(local.detail == "Download a private model that runs entirely on your Mac.")
    #expect(local.actionTitle == "Download model")
    #expect(local.actionSymbol == "arrow.down")

    #expect(cloud.name == "Cloud Model")
    #expect(cloud.status == "NOT CONNECTED")
    #expect(cloud.detail == "Connect a supported cloud provider for access to larger models.")
    #expect(cloud.actionTitle == "Connect provider")
    #expect(cloud.actionSymbol == "arrow.up.right")
}

@Test func hoveringAlwaysAddsBloomExpansionAndIntensityIncludingApple() {
    for backend in ModelsBackendID.allCases {
        let resting = ModelsBloomResponse.presentation(
            for: backend,
            active: .apple,
            selected: .apple,
            hovered: nil
        )
        let hovered = ModelsBloomResponse.presentation(
            for: backend,
            active: .apple,
            selected: .apple,
            hovered: backend
        )

        #expect(hovered.scale > resting.scale)
        #expect(hovered.opacity > resting.opacity)
        #expect(hovered.inwardProgress > resting.inwardProgress)
    }
}

@Test func activeAppleGlowRemainsStrongerThanInactiveHoverGlows() {
    let activeApple = ModelsBloomResponse.presentation(
        for: .apple,
        active: .apple,
        selected: .apple,
        hovered: nil
    )
    let hoveredLocal = ModelsBloomResponse.presentation(
        for: .mlx,
        active: .apple,
        selected: .apple,
        hovered: .mlx
    )
    let hoveredCloud = ModelsBloomResponse.presentation(
        for: .ollama,
        active: .apple,
        selected: .apple,
        hovered: .ollama
    )

    #expect(activeApple.opacity > hoveredLocal.opacity)
    #expect(activeApple.opacity > hoveredCloud.opacity)
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

@Test func expandingAppleLiftsItsSummaryAwayFromTheConfigurationSheet() {
    var state = ModelsLandscapeState()
    let restingApple = ModelsLandscapeLayout.placement(for: .apple, state: state)

    state.select(.apple)
    let expandedApple = ModelsLandscapeLayout.placement(for: .apple, state: state)

    #expect(expandedApple.y <= restingApple.y)
}

@Test func modelSelectionMotionUsesAFastSymmetricalMorphSequence() {
    let standard = ModelsMotionResponse.timing(reduceMotion: false)
    let reduced = ModelsMotionResponse.timing(reduceMotion: true)

    #expect(standard.peripheralDuration <= 0.18)
    #expect(standard.focusDuration <= 0.26)
    #expect(standard.bloomDuration <= 0.32)
    // Was an equality. Opening is showing you something; closing is getting out
    // of the way, and should not take as long as arriving did.
    #expect(standard.morphCloseDuration < standard.morphOpenDuration)
    #expect(standard.morphOpenDuration <= 0.24)
    #expect(standard.contentRevealDelay > 0)
    // Pinned to the timeline's own window rather than to a number repeated
    // here. The sheet's content starts when the pill's label has finished
    // leaving, and these two descriptions of the morph must not drift apart.
    #expect(
        standard.contentRevealDelay
            == standard.morphOpenDuration
                * Double(ModelsConfigurationTimeline.contentBegins)
    )
    #expect(
        standard.contentRevealDuration
            >= standard.morphOpenDuration * 0.60
    )
    #expect(
        standard.contentRevealDelay + standard.contentRevealDuration
            <= standard.morphOpenDuration
    )
    #expect(standard.contentHideDuration >= 0.08)
    #expect(
        standard.contentHideDuration
            <= standard.morphCloseDuration * 0.50
    )
    #expect(standard.contentHideDuration < standard.contentRevealDuration)
    #expect(standard.bloomDuration > standard.focusDuration)
    #expect(standard.sheetRise == 0)

    #expect(reduced.contentRevealDelay == 0)
    #expect(reduced.sheetRise == 0)
    #expect(reduced.focusDuration < standard.focusDuration)
    #expect(reduced.bloomDuration < standard.bloomDuration)
}

@Test func everyLandscapeActionHasAPersistentRectangularPillSurface() {
    for backend in ModelsBackendID.allCases {
        let resting = ModelsZoneActionResponse.presentation(
            for: backend,
            isHovered: false
        )
        let hovered = ModelsZoneActionResponse.presentation(
            for: backend,
            isHovered: true
        )

        #expect(resting.fillOpacity >= 0.12)
        #expect(resting.borderOpacity >= 0.30)
        #expect(resting.minimumHeight >= 38)
        #expect(resting.cornerRadius >= 10)
        #expect(resting.cornerRadius < resting.minimumHeight / 2)
        #expect(hovered.fillOpacity > resting.fillOpacity)
        #expect(hovered.borderOpacity > resting.borderOpacity)
    }
}

@Test func configurationSurfaceMorphUsesAReversibleButtonToSheetLifecycle() {
    var morph = ModelsConfigurationMorphState()

    morph.beginOpening(.apple)
    #expect(morph.phase == .mounted)
    #expect(morph.mountedBackend == .apple)
    #expect(!morph.contentVisible)

    morph.beginExpanding()
    #expect(morph.phase == .expanding)
    #expect(morph.contentVisible)

    morph.finishOpening()
    #expect(morph.phase == .sheet)
    #expect(morph.contentVisible)

    morph.beginClosing()
    #expect(morph.phase == .collapsing)
    #expect(!morph.contentVisible)

    morph.finishClosing()
    #expect(morph.phase == .button)
    #expect(morph.mountedBackend == nil)
}

@Test func contentRevealWaitsUntilTheSurfaceHasBegunExpanding() {
    let timing = ModelsMotionResponse.timing(reduceMotion: false)

    #expect(timing.contentRevealDelay >= timing.morphOpenDuration * 0.20)
    #expect(
        timing.contentRevealDelay + timing.contentRevealDuration
            <= timing.morphOpenDuration
    )
}

@Test func closingKeepsTheSurfaceMountedUntilItReachesItsButton() {
    var morph = ModelsConfigurationMorphState()

    morph.beginOpening(.mlx)
    morph.beginExpanding()
    morph.finishOpening()
    morph.beginClosing()

    #expect(morph.phase == .collapsing)
    #expect(morph.mountedBackend == .mlx)
    #expect(!morph.contentVisible)

    morph.finishClosing()

    #expect(morph.phase == .button)
    #expect(morph.mountedBackend == nil)
}

@Test func explicitConfigurationMorphUsesOneMonotonicFramePath() {
    let source = CGRect(x: 42, y: 510, width: 124, height: 38)
    let destination = CGRect(x: 176, y: 248, width: 470, height: 302)

    let start = ModelsConfigurationMorphGeometry.frame(
        from: source,
        to: destination,
        progress: 0
    )
    let midpoint = ModelsConfigurationMorphGeometry.frame(
        from: source,
        to: destination,
        progress: 0.5
    )
    let end = ModelsConfigurationMorphGeometry.frame(
        from: source,
        to: destination,
        progress: 1
    )

    #expect(start == source)
    #expect(end == destination)
    #expect(midpoint.midX == (source.midX + destination.midX) / 2)
    #expect(midpoint.midY == (source.midY + destination.midY) / 2)
    #expect(midpoint.width == (source.width + destination.width) / 2)
    #expect(midpoint.height == (source.height + destination.height) / 2)

    let clampedStart = ModelsConfigurationMorphGeometry.frame(
        from: source,
        to: destination,
        progress: -0.5
    )
    let clampedEnd = ModelsConfigurationMorphGeometry.frame(
        from: source,
        to: destination,
        progress: 1.5
    )

    #expect(clampedStart == source)
    #expect(clampedEnd == destination)

    #expect(
        ModelsConfigurationMorphGeometry.cornerRadius(progress: 0)
            == 12
    )
    #expect(
        ModelsConfigurationMorphGeometry.cornerRadius(progress: 0.5)
            == 19.5
    )
    #expect(
        ModelsConfigurationMorphGeometry.cornerRadius(progress: 1)
            == 27
    )
}

@Test func configurationSheetUsesAStableBackendSpecificEndpoint() {
    let canvas = CGSize(width: 1_000, height: 700)
    let apple = ModelsConfigurationLayout.sheetFrame(
        for: .apple,
        canvasSize: canvas
    )
    let local = ModelsConfigurationLayout.sheetFrame(
        for: .mlx,
        canvasSize: canvas
    )
    let cloud = ModelsConfigurationLayout.sheetFrame(
        for: .ollama,
        canvasSize: canvas
    )

    #expect(apple.width == 470)
    #expect(apple.midX == 390)
    #expect(local.midX == 610)
    #expect(cloud.midX == 500)
    #expect(apple.midY == 462)
    #expect(local.midY == 462)
    #expect(cloud.midY == 462)
    #expect(cloud.height > local.height)
    #expect(local.height > apple.height)
}

@Test func configurationSheetWidthClampsToTheAvailableCanvas() {
    let frame = ModelsConfigurationLayout.sheetFrame(
        for: .apple,
        canvasSize: CGSize(width: 400, height: 620)
    )

    #expect(frame.width == 344)
    #expect(frame.minX >= 0)
    #expect(frame.maxX <= 400)
}

@Test func oneTimelineRevealsSettingsWhileRetiringThePillLabel() {
    let start = ModelsConfigurationTimeline.presentation(progress: 0)
    let end = ModelsConfigurationTimeline.presentation(progress: 1)

    #expect(start.sheetContentOpacity == 0)
    #expect(start.pillLabelOpacity == 1)
    #expect(start.peripheralProgress == 0)

    #expect(end.sheetContentOpacity == 1)
    #expect(end.pillLabelOpacity == 0)
    #expect(end.peripheralProgress == 1)

    // Both layers draw text, in the same place, at the same size. While their
    // windows overlapped the morph cross-dissolved one glyph run through
    // another, which is what read as the label mangling itself on the way out
    // and back. The pill must be gone before the sheet says anything.
    for step in 0...200 {
        let frame = ModelsConfigurationTimeline.presentation(
            progress: CGFloat(step) / 200
        )
        #expect(frame.pillLabelOpacity == 0 || frame.sheetContentOpacity == 0)
    }
}

/// `ModelsBackendTintResponse` promises the action and its replacement surface
/// share one tint source "so mounting the morph cannot introduce a one-frame
/// color discontinuity". That was only true of an unhovered button — and the
/// button being morphed has just been clicked, so it is never unhovered.
@Test func mountingTheMorphReproducesTheButtonItGrewFrom() {
    for backend in [ModelsBackendID.apple, .mlx, .ollama] {
        for hovered in [true, false] {
            let button = ModelsZoneActionResponse.presentation(
                for: backend,
                isHovered: hovered
            )
            let mounted = ModelsSheetSurfaceResponse.morphPresentation(
                for: backend,
                progress: 0,
                isHovered: hovered
            )

            #expect(mounted.paperOpacity == button.paperOpacity)
            #expect(mounted.primaryOpacity == button.fillOpacity)
            #expect(mounted.borderOpacity == button.borderOpacity)
            #expect(mounted.shadowOpacity == button.shadowOpacity)
        }
    }
}

@Test func landscapePlacementFollowsTheSameReversibleProgressAsTheSheet() {
    let resting = ModelsLandscapeLayout.transitionPlacement(
        for: .apple,
        active: .apple,
        expanded: .ollama,
        progress: 0
    )
    let midpoint = ModelsLandscapeLayout.transitionPlacement(
        for: .apple,
        active: .apple,
        expanded: .ollama,
        progress: 0.5
    )
    let focused = ModelsLandscapeLayout.transitionPlacement(
        for: .apple,
        active: .apple,
        expanded: .ollama,
        progress: 1
    )

    #expect(resting.x == 0.24)
    #expect(resting.opacity == 1)
    #expect(focused.x == 0.14)
    #expect(focused.opacity == 0.12)
    #expect(midpoint.x == 0.19)
    #expect(midpoint.opacity == 0.56)
}

@Test func modelZoneContentFadesWithoutChangingItsStructuralRole() {
    let selectedStart = ModelsZoneTimeline.presentation(
        for: .apple,
        active: .apple,
        expanded: .apple,
        progress: 0
    )
    let selectedEnd = ModelsZoneTimeline.presentation(
        for: .apple,
        active: .apple,
        expanded: .apple,
        progress: 1
    )
    let peripheralEnd = ModelsZoneTimeline.presentation(
        for: .mlx,
        active: .apple,
        expanded: .apple,
        progress: 1
    )

    #expect(selectedStart.titleOpacity == 1)
    #expect(selectedStart.detailOpacity == 1)
    #expect(selectedStart.actionOpacity == 1)
    #expect(selectedStart.topStatusOpacity == 0)
    #expect(selectedStart.besideStatusOpacity == 1)

    #expect(selectedEnd.titleOpacity == 1)
    #expect(selectedEnd.detailOpacity == 1)
    #expect(selectedEnd.actionOpacity == 0)
    #expect(selectedEnd.topStatusOpacity == 1)
    #expect(selectedEnd.besideStatusOpacity == 0)

    #expect(peripheralEnd.titleOpacity == 0.12)
    #expect(peripheralEnd.detailOpacity == 0)
    #expect(peripheralEnd.actionOpacity == 0)
}

@Test func ambientBloomFollowsTheConfigurationProgressInsteadOfSelectionState() {
    let resting = ModelsBloomResponse.presentation(
        for: .mlx,
        active: .apple,
        selected: .apple,
        hovered: nil
    )
    let selected = ModelsBloomResponse.presentation(
        for: .mlx,
        active: .apple,
        selected: .mlx,
        hovered: nil
    )
    let start = ModelsBloomResponse.transitionPresentation(
        for: .mlx,
        active: .apple,
        selected: .mlx,
        hovered: nil,
        progress: 0
    )
    let end = ModelsBloomResponse.transitionPresentation(
        for: .mlx,
        active: .apple,
        selected: .mlx,
        hovered: nil,
        progress: 1
    )

    #expect(start == resting)
    #expect(end == selected)
}

@Test func expandedCloudUsesAHeaderClearFocusBandAboveItsSheet() {
    var state = ModelsLandscapeState()
    state.select(.ollama)

    let focusedCloud = ModelsLandscapeLayout.placement(for: .ollama, state: state)

    #expect(focusedCloud.y >= 0.35)
    #expect(focusedCloud.y <= 0.37)
}

@Test func restingUpperModelCopyClearsThePageHeading() {
    let state = ModelsLandscapeState()
    let apple = ModelsLandscapeLayout.placement(for: .apple, state: state)
    let local = ModelsLandscapeLayout.placement(for: .mlx, state: state)

    #expect(apple.y >= 0.35)
    #expect(local.y >= 0.36)
}

@Test func expandedUpperModelCopyStaysInAHeaderSafeBand() {
    for selected in ModelsBackendID.allCases {
        var state = ModelsLandscapeState()
        state.select(selected)

        for backend in ModelsBackendID.allCases {
            let placement = ModelsLandscapeLayout.placement(
                for: backend,
                state: state
            )

            if placement.y < 0.70 {
                #expect(placement.y >= 0.35)
            }
        }
    }
}

@Test func expandedSheetPushesInactiveModelsToQuietOuterPositions() {
    var state = ModelsLandscapeState()
    state.select(.ollama)

    let apple = ModelsLandscapeLayout.placement(for: .apple, state: state)
    let local = ModelsLandscapeLayout.placement(for: .mlx, state: state)

    #expect(apple.x <= 0.15)
    #expect(local.x >= 0.85)
    #expect(apple.opacity <= 0.12)
    #expect(local.opacity <= 0.12)
    #expect(apple.scale <= 0.91)
    #expect(local.scale <= 0.91)
}

@Test func expandedConfigurationUsesConciseNonOverlappingModelCopy() {
    var state = ModelsLandscapeState()

    #expect(ModelsLandscapeContent.mode(for: .apple, state: state) == .full)
    #expect(ModelsLandscapeContent.mode(for: .mlx, state: state) == .full)
    #expect(ModelsLandscapeContent.mode(for: .ollama, state: state) == .full)

    state.select(.ollama)

    #expect(
        ModelsLandscapeContent.mode(for: .ollama, state: state)
            == .focusedSummary
    )
    #expect(
        ModelsLandscapeContent.mode(for: .apple, state: state)
            == .titleOnly
    )
    #expect(
        ModelsLandscapeContent.mode(for: .mlx, state: state)
            == .titleOnly
    )
}

@Test func expandedActiveStatusMovesAboveTheTitleAwayFromTheSheetEdge() {
    var state = ModelsLandscapeState()

    #expect(
        ModelsLandscapeContent.statusPlacement(for: .apple, state: state)
            == .besideAction
    )

    state.select(.apple)

    #expect(
        ModelsLandscapeContent.statusPlacement(for: .apple, state: state)
            == .aboveTitle
    )
}

/// Zones are drawn inside `.scaleEffect(placement.scale)` and their action
/// frames are measured through it, so the source frame's height over the
/// button's unscaled height recovers that scale. The stand-in label sits
/// outside the transform and has to reapply it, or it draws 11pt text into a
/// box built for 11.66pt and the two swap sizes at the handover.
@Test func theStandInLabelCarriesTheScaleOfTheZoneItReplaces() {
    let unscaled = ModelsZoneActionResponse
        .presentation(for: .apple, isHovered: true)
        .minimumHeight

    // Measured from a running build: the active zone sits at 1.06, the
    // resting ones at 0.95, and everything drops to 0.90 while a sheet is open.
    #expect(abs(ModelsMorphLabelScale.scale(
        sourceHeight: 40.28, unscaledHeight: unscaled
    ) - 1.06) < 0.001)
    #expect(abs(ModelsMorphLabelScale.scale(
        sourceHeight: 36.10, unscaledHeight: unscaled
    ) - 0.95) < 0.001)
    #expect(abs(ModelsMorphLabelScale.scale(
        sourceHeight: 34.20, unscaledHeight: unscaled
    ) - 0.90) < 0.001)

    // A missing or degenerate measurement must not collapse the label.
    #expect(ModelsMorphLabelScale.scale(sourceHeight: 0, unscaledHeight: unscaled) == 1)
    #expect(ModelsMorphLabelScale.scale(sourceHeight: 40, unscaledHeight: 0) == 1)
}

/// Mounting the morph happens inside a transaction that disables animations,
/// with progress still at zero. So nothing may look different at progress zero
/// for having mounted — anything that does, changes in a single frame. The
/// zone's glow used to drop 0.34 → 0.14 and shrink 1.10 → 0.95 right there,
/// behind the very button being pressed.
@Test func mountingTheMorphDoesNotDisturbTheGlowBehindTheButton() {
    for isHovered in [true, false] {
        for isActive in [true, false] {
            let beforeMount = ModelsZoneGlowResponse.presentation(
                isHovered: isHovered,
                isActive: isActive,
                isMorphSource: false,
                transitionProgress: 0
            )
            let atMount = ModelsZoneGlowResponse.presentation(
                isHovered: isHovered,
                isActive: isActive,
                isMorphSource: true,
                transitionProgress: 0
            )

            #expect(beforeMount == atMount)
        }
    }

    // And it does still travel once progress moves — the continuity above is
    // not simply the morph having no effect on the glow at all.
    let settled = ModelsZoneGlowResponse.presentation(
        isHovered: true,
        isActive: true,
        isMorphSource: true,
        transitionProgress: 1
    )
    #expect(settled.opacity == 0.18)
    #expect(settled.scale == 0.98)
}

/// The anti-flash invariant, and the one that actually mattered: a hovered
/// action pill already looks like the sheet it becomes, so mounting the morph
/// never has to travel the fill. Apple broke this by a hair — and its green is
/// too pale to disguise the paper climbing underneath while it crossed.
@Test func everyActionPillHandsOverToItsSheetWithoutChangingTint() {
    for backend in ModelsBackendID.allCases {
        let hoveredPill = ModelsZoneActionResponse.presentation(
            for: backend,
            isHovered: true
        )
        let sheet = ModelsSheetSurfaceResponse.intensity(for: backend)

        #expect(abs(hoveredPill.fillOpacity - sheet.primaryOpacity) < 0.001)
    }
}

/// Apple's stronger tint is deliberate compensation, not an inconsistency: its
/// hue is the palest in the set and needs the extra opacity to carry the same
/// visual weight over the sheet's near-white paper. Flattening it made Apple's
/// panel open as a growing white rectangle.
@Test func appleConfigurationSurfaceCarriesTheStrongestTintPresence() {
    let apple = ModelsSheetSurfaceResponse.intensity(for: .apple)
    let local = ModelsSheetSurfaceResponse.intensity(for: .mlx)
    let cloud = ModelsSheetSurfaceResponse.intensity(for: .ollama)

    #expect(apple.primaryOpacity >= local.primaryOpacity * 1.35)
    #expect(apple.primaryOpacity >= cloud.primaryOpacity * 1.35)
    #expect(apple.secondaryOpacity > local.secondaryOpacity)
    #expect(apple.secondaryOpacity > cloud.secondaryOpacity)
    #expect(apple.washOpacity >= local.washOpacity * 2)
    #expect(apple.washOpacity >= cloud.washOpacity * 2)
}

@Test func morphingSurfaceBeginsAsTheActionPillAndBuildsIntoTheSheetTint() {
    for backend in ModelsBackendID.allCases {
        let action = ModelsZoneActionResponse.presentation(
            for: backend,
            isHovered: false
        )
        let sheet = ModelsSheetSurfaceResponse.intensity(for: backend)
        let start = ModelsSheetSurfaceResponse.morphPresentation(
            for: backend,
            progress: 0
        )
        let midpoint = ModelsSheetSurfaceResponse.morphPresentation(
            for: backend,
            progress: 0.5
        )
        let end = ModelsSheetSurfaceResponse.morphPresentation(
            for: backend,
            progress: 1
        )

        #expect(start.paperOpacity == action.paperOpacity)
        #expect(start.borderOpacity == action.borderOpacity)
        // Every gradient stop starts level with the button's flat fill. This
        // used to assert `secondaryOpacity == 0`, which is precisely what made
        // the surface *not* begin as the action pill: its tint drained across
        // its own width the instant it mounted.
        #expect(start.primaryOpacity == action.fillOpacity)
        #expect(start.secondaryOpacity == action.fillOpacity)
        #expect(start.trailingOpacity == action.fillOpacity)

        #expect(end.paperOpacity == 0.90)
        #expect(end.primaryOpacity == sheet.primaryOpacity)
        #expect(end.secondaryOpacity == sheet.secondaryOpacity)
        #expect(end.trailingOpacity == 0)
        #expect(end.borderOpacity == sheet.borderOpacity)
        #expect(midpoint.trailingOpacity < start.trailingOpacity)
        #expect(midpoint.shadowRadius > start.shadowRadius)
        #expect(midpoint.shadowRadius < end.shadowRadius)
    }
}

@Test func actionPillAndMorphSurfaceUseTheSameTintAtHandoff() {
    for backend in ModelsBackendID.allCases {
        let actionTint = ModelsBackendTintResponse.actionTint(for: backend)
        let surfaceTint = ModelsBackendTintResponse.surfaceTint(for: backend)

        #expect(actionTint == surfaceTint)
    }
}

@Test func morphingPillContentKeepsItsSourceSizeWhileFollowingTheSurface() {
    let source = CGRect(x: 40, y: 500, width: 124, height: 38)
    let destination = CGRect(x: 180, y: 220, width: 470, height: 330)
    let midpoint = ModelsMorphContentGeometry.frame(
        from: source,
        to: destination,
        progress: 0.5
    )
    let end = ModelsMorphContentGeometry.frame(
        from: source,
        to: destination,
        progress: 1
    )

    #expect(midpoint.width == 124)
    #expect(midpoint.height == 38)
    #expect(midpoint.midX == 258.5)
    #expect(midpoint.midY == 452)
    #expect(end.width == 124)
    #expect(end.height == 38)
    #expect(end.midX == destination.midX)
    #expect(end.midY == destination.midY)
}

@Test func restingModelsFormTheApprovedAsymmetricalHierarchy() {
    let state = ModelsLandscapeState()
    let apple = ModelsLandscapeLayout.placement(for: .apple, state: state)
    let local = ModelsLandscapeLayout.placement(for: .mlx, state: state)
    let cloud = ModelsLandscapeLayout.placement(for: .ollama, state: state)

    #expect(apple.x < cloud.x)
    #expect(local.x > cloud.x)
    #expect(apple.y < cloud.y)
    #expect(local.y < cloud.y)
    #expect(apple.scale > local.scale)
    #expect(apple.scale > cloud.scale)
    #expect(abs(cloud.x - 0.5) < 0.01)
}

@Test func activeModelStatusFlowsIntoTheExistingBottomBar() throws {
    var modelsState = ModelsLandscapeState()
    modelsState.select(.mlx)
    modelsState.finishDownload()
    modelsState.activateSelected()

    let items = DashboardBottomBarItems.make(
        for: Fixtures.state(for: .typical),
        modelsState: modelsState
    )
    let modelsItem = try #require(items.first { $0.id == DashboardView.Tab.models })
    let local = try #require(modelsItem.entries.first { $0.title == "Local Model" })
    let apple = try #require(
        modelsItem.entries.first { $0.title == "Foundation Models" }
    )

    #expect(local.detail == "ACTIVE")
    #expect(apple.detail == "AVAILABLE")
}
