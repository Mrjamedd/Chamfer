import ChamferCore
import Testing

@testable import ChamferUI

@Test func setupFlowHasARealNextStepInsteadOfAnIdempotentEnableAction() {
    let partial = VaultConfiguration(mode: .spelling)
    let complete = VaultConfiguration(
        mode: .spelling,
        application: .review,
        runTrigger: .inactivity,
        inactivityDelay: 300,
        preserved: .standard
    )

    #expect(VaultSetupPresentation.nextStep(configuration: nil, activeModel: false) == .vaultSettings)
    #expect(VaultSetupPresentation.nextStep(configuration: partial, activeModel: true) == .vaultSettings)
    #expect(VaultSetupPresentation.nextStep(configuration: complete, activeModel: false) == .model)
    #expect(VaultSetupPresentation.nextStep(configuration: complete, activeModel: true) == .enabled)
}
