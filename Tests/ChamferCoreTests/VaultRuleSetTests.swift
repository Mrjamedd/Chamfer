import Testing

@testable import ChamferCore

@Test func selectedNotesBecomeDistinctExclusionsWithoutReplacingFolderRules() {
    let existing = [
        VaultRule(kind: .includeOnly, path: "Projects"),
        VaultRule(kind: .exclude, path: "Projects/Archived.md")
    ]

    let merged = VaultRuleSet.addingExclusions(
        paths: [
            "Projects/Roadmap.md",
            "Projects/Archived.md",
            "Projects/Roadmap.md"
        ],
        to: existing
    )

    #expect(merged.filter { $0.kind == .includeOnly }.map(\.path) == ["Projects"])
    #expect(merged.filter { $0.kind == .exclude }.map(\.path) == [
        "Projects/Archived.md",
        "Projects/Roadmap.md"
    ])
}
