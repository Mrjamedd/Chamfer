import Foundation
import Testing

@testable import ChamferCore

@Test func automaticBroadRewriteIsReroutedWithoutChangingIntentionalReview() {
    #expect(
        RewriteApplicationDecision.decide(
            requested: .automatic,
            recommendation: .broaderThanExpectedForMode
        ) == .queueForReview(automaticReason: .broaderThanExpectedForMode)
    )
    #expect(
        RewriteApplicationDecision.decide(
            requested: .review,
            recommendation: .broaderThanExpectedForMode
        ) == .queueForReview(automaticReason: nil)
    )
    #expect(
        RewriteApplicationDecision.decide(
            requested: .automatic,
            recommendation: nil
        ) == .applyAutomatically
    )
}

@Test func proposalsFromBeforeAutomaticReviewReasonsStillDecode() throws {
    let note = NoteSummary(
        url: URL(filePath: "/Notes/Old.md"),
        title: "Old",
        wordCount: 2,
        modifiedAt: Date(timeIntervalSince1970: 100)
    )
    let oldProposal = Proposal(
        note: note,
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: Date(timeIntervalSince1970: 200)
    )

    let dataWithoutTheNewOptionalKey = try JSONEncoder().encode(oldProposal)
    let decoded = try JSONDecoder().decode(
        Proposal.self,
        from: dataWithoutTheNewOptionalKey
    )

    #expect(decoded.automaticReviewReason == nil)
}

// MARK: - No defaults

@Test func aNewlyConnectedVaultHasNoConfigurationAtAll() {
    let vault = Vault(url: URL(filePath: "/Notes"), noteCount: 12)

    // The whole safety story. A vault Chamfer has not been told how to treat
    // is a vault Chamfer does not touch — there is nothing to inherit from.
    #expect(vault.configuration == nil)
    #expect(!vault.isConfigured)
}

@Test func aPartialVaultConfigurationCannotRunBySubstitutingDefaults() {
    var vault = Vault(url: URL(filePath: "/Notes"), noteCount: 12)
    vault.configuration = VaultConfiguration(mode: .spelling)

    #expect(!vault.isConfigured)
    #expect(vault.configuration?.mode == .spelling)
    #expect(vault.configuration?.missingFields == [
        .application, .runTrigger, .preserved
    ])
    #expect(vault.configuration?.resolve(modelID: RewritePolicy.localModelIdentifier) == nil)
}

@Test func everyIntentionalVaultChoiceResolvesWithoutChangingItsValue() throws {
    let configuration = VaultConfiguration(
        mode: .grammar,
        application: .automatic,
        runTrigger: .schedule,
        inactivityDelay: 300,
        sweep: .everyHours(6),
        preserved: [.links, .codeBlocks]
    )

    let policy = try #require(configuration.resolve(modelID: "local.qwen3:4b"))
    #expect(configuration.missingFields.isEmpty)
    #expect(policy.mode == .grammar)
    #expect(policy.application == .automatic)
    #expect(policy.runTrigger == .schedule)
    #expect(policy.inactivityDelay == 0)
    #expect(policy.sweep == .everyHours(6))
    #expect(policy.preserved == [.links, .codeBlocks])
    #expect(policy.modelID == "local.qwen3:4b")
}

@Test func aCompleteVaultStillCannotRunBeforeAModelIsChosen() {
    let configuration = VaultConfiguration(
        mode: .spelling,
        application: .review,
        runTrigger: .inactivity,
        inactivityDelay: 120,
        preserved: []
    )

    #expect(configuration.resolve(modelID: nil) == nil)
}

@Test func inactivityAndScheduledRunsAreMutuallyExclusiveConfigurationPaths() throws {
    let inactivity = VaultConfiguration(
        mode: .spelling,
        application: .review,
        runTrigger: .inactivity,
        inactivityDelay: 300,
        preserved: .standard
    )
    let scheduled = VaultConfiguration(
        mode: .spelling,
        application: .review,
        runTrigger: .schedule,
        sweep: .dailyAt(hour: 3),
        preserved: .standard
    )

    #expect(inactivity.isComplete)
    #expect(inactivity.missingFields.isEmpty)
    #expect(inactivity.resolve(modelID: "test")?.runTrigger == .inactivity)
    #expect(inactivity.resolve(modelID: "test")?.sweep == .never)

    #expect(scheduled.isComplete)
    #expect(scheduled.missingFields.isEmpty)
    #expect(scheduled.resolve(modelID: "test")?.runTrigger == .schedule)
    #expect(scheduled.resolve(modelID: "test")?.inactivityDelay == 0)
}

@Test func choosingATriggerOnlyRequiresThatTriggersSpecificSetting() {
    var inactivity = VaultConfiguration(runTrigger: .inactivity)
    var scheduled = VaultConfiguration(runTrigger: .schedule)

    #expect(inactivity.missingFields.contains(.inactivityDelay))
    #expect(!inactivity.missingFields.contains(.sweep))
    #expect(scheduled.missingFields.contains(.sweep))
    #expect(!scheduled.missingFields.contains(.inactivityDelay))

    inactivity.inactivityDelay = 600
    scheduled.sweep = .everyHours(6)

    #expect(!inactivity.missingFields.contains(.inactivityDelay))
    #expect(!scheduled.missingFields.contains(.sweep))
}

// MARK: - What the dashboard reports

@Test func unconfiguredVaultsAreReportedSoTheInterfaceCanSaySo() {
    let waiting = Vault(url: URL(filePath: "/Notes/Waiting"), noteCount: 3)
    let ready = Vault(
        url: URL(filePath: "/Notes/Ready"),
        noteCount: 4,
            configuration: VaultConfiguration(
                mode: .fullCleanup,
                application: .review,
                runTrigger: .inactivity,
                inactivityDelay: 600,
                preserved: .standard
        )
    )
    let state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: [],
        vaults: [waiting, ready]
    )

    #expect(state.unconfiguredVaults.map(\.id) == [waiting.id])
    #expect(state.needsConfiguration)
}

@Test func anUnreachableVaultIsNotAlsoNaggedAboutSetup() {
    let offline = Vault(
        url: URL(filePath: "/Volumes/Gone/Notes"),
        availability: .offline,
        noteCount: 9
    )
    let state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: [],
        vaults: [offline]
    )

    // A folder on an unplugged disk already says what is wrong with it. Two
    // warnings about the same vault would be one too many.
    #expect(state.unconfiguredVaults.isEmpty)
    #expect(!state.needsConfiguration)
}

@Test func aFullyConfiguredSetOfVaultsNeedsNothing() {
    let state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: [],
        vaults: [
            Vault(
                url: URL(filePath: "/Notes"),
                noteCount: 4,
                configuration: VaultConfiguration(
                    mode: .fullCleanup,
                    application: .review,
                    runTrigger: .inactivity,
                    inactivityDelay: 600,
                    preserved: .standard
                )
            )
        ]
    )

    #expect(!state.needsConfiguration)
}

// MARK: - Preservation

@Test func standardPreservationProtectsPayloadsButNotProse() {
    let standard = MarkdownStructure.standard

    // Addresses and payloads: things a rewrite has no business editing.
    #expect(standard.contains(.links))
    #expect(standard.contains(.codeBlocks))
    #expect(standard.contains(.frontMatter))
    #expect(standard.contains(.taskCheckboxes))

    // Headings and lists are left out so formatting mode is not a no-op.
    #expect(!standard.contains(.headings))
    #expect(!standard.contains(.lists))
}

@Test func preservationNamesTheStructuresItProtects() {
    let structure: MarkdownStructure = [.headings, .links]
    #expect(structure.titles == ["Headings", "Links"])
}
