import Foundation
import Testing
@testable import ChamferCore

// MARK: - Hierarchy

@Test func folderSettingsBeatVaultSettingsWhichBeatGlobalDefaults() {
    let global = RewritePolicy(mode: .spelling, application: .review)
    let vault = PolicyOverride(mode: .grammar)
    let folder = PolicyOverride(mode: .fullCleanup)

    #expect(PolicyResolver.resolve(global: global).policy.mode == .spelling)
    #expect(PolicyResolver.resolve(global: global, vault: vault).policy.mode == .grammar)
    #expect(
        PolicyResolver.resolve(global: global, vault: vault, folder: folder).policy.mode
            == .fullCleanup
    )
}

@Test func aLevelWithNothingToSayLeavesEverythingInherited() {
    let global = RewritePolicy(mode: .clarity, inactivityDelay: 900)
    let resolved = PolicyResolver.resolve(
        global: global,
        vault: .inherited,
        folder: .inherited
    )

    #expect(resolved.policy == global)
    #expect(resolved.overriddenFields.isEmpty)
}

@Test func resolutionRecordsWhereEachSettingCameFrom() {
    let resolved = PolicyResolver.resolve(
        global: .standard,
        vault: PolicyOverride(application: .automatic),
        folder: PolicyOverride(inactivityDelay: 60)
    )

    #expect(resolved.source(of: .application) == .vault)
    #expect(resolved.source(of: .inactivityDelay) == .folder)
    #expect(resolved.source(of: .mode) == .global)
    #expect(Set(resolved.overriddenFields) == [.application, .inactivityDelay])
}

@Test func aFolderCanOverrideTheSameFieldItsVaultOverrode() {
    let resolved = PolicyResolver.resolve(
        global: RewritePolicy(application: .review),
        vault: PolicyOverride(application: .automatic),
        folder: PolicyOverride(application: .review)
    )

    #expect(resolved.policy.application == .review)
    #expect(resolved.source(of: .application) == .folder)
}

/// Turning a fallback off has to be distinguishable from not having an opinion
/// about it, or a vault could never opt out of a global fallback model.
@Test func aVaultCanTurnOffAFallbackWithoutInheritingOne() {
    let global = RewritePolicy(fallbackModelID: "cloud.sonnet")

    let inheriting = PolicyResolver.resolve(global: global, vault: .inherited)
    #expect(inheriting.policy.fallbackModelID == "cloud.sonnet")
    #expect(inheriting.source(of: .fallbackModel) == .global)

    let switchedOff = PolicyResolver.resolve(
        global: global,
        vault: PolicyOverride(fallbackModelID: .some(nil))
    )
    #expect(switchedOff.policy.fallbackModelID == nil)
    #expect(switchedOff.source(of: .fallbackModel) == .vault)
}

@Test func clearingAFieldReturnsItToInherited() {
    var override = PolicyOverride(mode: .spelling, sweep: .everyHours(6))
    #expect(override.fields == [.mode, .sweep])

    override.clear(.mode)
    #expect(override.fields == [.sweep])

    override.clear(.sweep)
    #expect(override.isInherited)
}

// MARK: - Defaults

/// The scope is explicit that nothing writes to a note until the user has
/// asked for it, for the exact place in question.
@Test func nothingAppliesAutomaticallyOutOfTheBox() {
    #expect(RewritePolicy.standard.application == .review)
    #expect(PolicyResolver.resolve(global: .standard).policy.application == .review)
}

/// Formatting mode exists to reflow headings and lists, so protecting those by
/// default would leave one of the five modes with nothing it may touch.
@Test func standardPreservationProtectsPayloadsButNotProse() {
    #expect(MarkdownStructure.standard.contains(.codeBlocks))
    #expect(MarkdownStructure.standard.contains(.frontMatter))
    #expect(MarkdownStructure.standard.contains(.links))
    #expect(!MarkdownStructure.standard.contains(.headings))
    #expect(!MarkdownStructure.standard.contains(.lists))
}

@Test func preservationNamesTheStructuresItProtects() {
    let structure: MarkdownStructure = [.headings, .codeBlocks]
    #expect(structure.titles == ["Headings", "Code blocks"])
}
