import Foundation
import Testing

@testable import ChamferCore

/// Base, Balanced and Max have to be three genuinely different amounts of work.
/// A mode that only changed a label would be the worst kind of setting: one
/// that looks like a choice and is not.

@Test func eachModeAsksForStrictlyMoreWorkThanTheOneBelowIt() {
    let base = ModelEffort.base.profile
    let balanced = ModelEffort.balanced.profile
    let max = ModelEffort.max.profile

    #expect(base.segmentTargetCharacters < balanced.segmentTargetCharacters)
    #expect(balanced.segmentTargetCharacters < max.segmentTargetCharacters)

    #expect(base.unitTargetCharacters < balanced.unitTargetCharacters)
    #expect(balanced.unitTargetCharacters < max.unitTargetCharacters)

    #expect(base.contextTokens < balanced.contextTokens)
    #expect(balanced.contextTokens < max.contextTokens)

    #expect(base.responseTokenCeiling < balanced.responseTokenCeiling)
    #expect(balanced.responseTokenCeiling < max.responseTokenCeiling)

    #expect(base.reviewPasses < balanced.reviewPasses)
    #expect(balanced.reviewPasses < max.reviewPasses)
}

/// The checking pass is what Base gives up and Max doubles, so the number of
/// model calls per unit is the mode's clearest behavioural difference.
@Test func theNumberOfRequestsPerUnitRisesWithTheMode() {
    #expect(ModelEffort.base.profile.requestsPerUnit == 1)
    #expect(ModelEffort.balanced.profile.requestsPerUnit == 2)
    #expect(ModelEffort.max.profile.requestsPerUnit == 3)
}

@Test func onlyMaxSpendsTimeOnDeliberationAndOnlyBaseWorksWithoutNeighbours() {
    #expect(!ModelEffort.base.profile.allowsDeliberation)
    #expect(!ModelEffort.balanced.profile.allowsDeliberation)
    #expect(ModelEffort.max.profile.allowsDeliberation)

    #expect(!ModelEffort.base.profile.includesNeighbourContext)
    #expect(ModelEffort.balanced.profile.includesNeighbourContext)
    #expect(ModelEffort.max.profile.includesNeighbourContext)
}

/// The panel promises a tradeoff. Speed and accuracy have to move in opposite
/// directions across the three modes, or the promise is a decoration.
@Test func theReadoutsDescribeARealTradeoffRatherThanAnUpgrade() {
    func level(_ effort: ModelEffort, _ axis: ModelEffortReadout.Axis) -> Double {
        effort.profile.readouts.first { $0.axis == axis }?.level ?? -1
    }

    #expect(level(.base, .speed) > level(.balanced, .speed))
    #expect(level(.balanced, .speed) > level(.max, .speed))

    #expect(level(.base, .accuracy) < level(.balanced, .accuracy))
    #expect(level(.balanced, .accuracy) < level(.max, .accuracy))

    #expect(level(.base, .time) < level(.max, .time))
    #expect(level(.base, .impact) < level(.max, .impact))
}

@Test func everyModeReportsAllFourAxesInAStableOrder() {
    for effort in ModelEffort.allCases {
        let axes = effort.profile.readouts.map(\.axis)
        #expect(axes == [.speed, .accuracy, .time, .impact])
        #expect(effort.profile.readouts.allSatisfy { (0...1).contains($0.level) })
        #expect(effort.profile.readouts.allSatisfy { !$0.caption.isEmpty })
    }
}

/// Time and system impact read the other way round: a taller bar there is worse,
/// and drawing all four in the same direction would say Max is bad at two
/// things it is not.
@Test func theAxesKnowWhichDirectionIsTheGoodOne() {
    #expect(ModelEffortReadout.Axis.speed.higherIsBetter)
    #expect(ModelEffortReadout.Axis.accuracy.higherIsBetter)
    #expect(!ModelEffortReadout.Axis.time.higherIsBetter)
    #expect(!ModelEffortReadout.Axis.impact.higherIsBetter)
}

@Test func balancedIsTheDefaultAndEveryModeExplainsWhatItGivesUp() {
    #expect(ModelEffort.standard == .balanced)

    for effort in ModelEffort.allCases {
        #expect(!effort.title.isEmpty)
        #expect(!effort.tagline.isEmpty)
        #expect(effort.summary.count > 40)
        #expect(effort.profile.effort == effort)
        #expect(effort.profile.mechanics.contains("characters per request"))
    }
}

@Test func aModeSurvivesBeingWrittenDownAndReadBack() throws {
    for effort in ModelEffort.allCases {
        let data = try JSONEncoder().encode(effort)
        #expect(try JSONDecoder().decode(ModelEffort.self, from: data) == effort)
        #expect(ModelEffort(rawValue: effort.rawValue) == effort)
    }
}
