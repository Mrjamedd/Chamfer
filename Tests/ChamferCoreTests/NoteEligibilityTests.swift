import Foundation
import Testing

@testable import ChamferCore

// MARK: - File kinds

@Test func onlyMarkdownAndPlainTextAreProcessed() {
    #expect(NoteEligibility.isSupportedFile("Kickoff.md"))
    #expect(NoteEligibility.isSupportedFile("Kickoff.txt"))
    #expect(NoteEligibility.isSupportedFile("Kickoff.MD"))

    // Everything the scope puts out of bounds. Reading one of these as UTF-8
    // and writing it back is how a file gets corrupted.
    #expect(!NoteEligibility.isSupportedFile("Kickoff.rtf"))
    #expect(!NoteEligibility.isSupportedFile("Kickoff.docx"))
    #expect(!NoteEligibility.isSupportedFile("Kickoff.html"))
    #expect(!NoteEligibility.isSupportedFile("Kickoff.pdf"))
    #expect(!NoteEligibility.isSupportedFile("diagram.png"))
    #expect(!NoteEligibility.isSupportedFile("Kickoff"))
}

@Test func hiddenFilesAreNeverProcessed() {
    #expect(!NoteEligibility.isSupportedFile(".hidden.md"))
    #expect(!NoteEligibility.isSupportedFile(".DS_Store"))
}

@Test func applicationOwnedFoldersAreSkippedWholesale() {
    #expect(NoteEligibility.isExcludedDirectory(".obsidian"))
    #expect(NoteEligibility.isExcludedDirectory(".git"))
    #expect(NoteEligibility.isExcludedDirectory(".trash"))
    #expect(NoteEligibility.isExcludedDirectory("node_modules"))
    // Any dot-folder, named or not: a leading dot is how the platform says
    // "this is not the user's content".
    #expect(NoteEligibility.isExcludedDirectory(".something-new"))

    #expect(!NoteEligibility.isExcludedDirectory("Projects"))
    #expect(!NoteEligibility.isExcludedDirectory("Daily Notes"))
}

@Test func aNoteInsideAnApplicationFolderIsIneligibleWhateverTheRulesSay() {
    #expect(
        !NoteEligibility.isEligible(
            relativePath: ".obsidian/plugins/notes.md",
            rules: [VaultRule(kind: .includeOnly, path: ".obsidian")]
        )
    )
    #expect(
        !NoteEligibility.isEligible(relativePath: ".git/COMMIT_EDITMSG.txt", rules: [])
    )
}

// MARK: - Rules

@Test func aVaultWithNoRulesProcessesEverythingSupported() {
    #expect(NoteEligibility.isEligible(relativePath: "Kickoff.md", rules: []))
    #expect(NoteEligibility.isEligible(relativePath: "Projects/Deep/Retro.txt", rules: []))
}

@Test func exclusionsRemoveAWholeBranch() {
    let rules = [VaultRule(kind: .exclude, path: "Archive")]

    #expect(!NoteEligibility.isEligible(relativePath: "Archive/Old.md", rules: rules))
    #expect(!NoteEligibility.isEligible(relativePath: "Archive/2019/Older.md", rules: rules))
    #expect(NoteEligibility.isEligible(relativePath: "Kickoff.md", rules: rules))
}

@Test func anExclusionMatchesWholeComponentsRatherThanPrefixes() {
    let rules = [VaultRule(kind: .exclude, path: "Work")]

    #expect(!NoteEligibility.isEligible(relativePath: "Work/Notes.md", rules: rules))
    // "Workshop" is a different folder and must survive a rule about "Work".
    #expect(NoteEligibility.isEligible(relativePath: "Workshop/Notes.md", rules: rules))
}

@Test func includeOnlyNarrowsTheVaultToWhatWasChosen() {
    let rules = [
        VaultRule(kind: .includeOnly, path: "Projects"),
        VaultRule(kind: .includeOnly, path: "Journal")
    ]

    #expect(NoteEligibility.isEligible(relativePath: "Projects/Kickoff.md", rules: rules))
    #expect(NoteEligibility.isEligible(relativePath: "Journal/2026-08-07.md", rules: rules))
    #expect(!NoteEligibility.isEligible(relativePath: "Scratch/Idea.md", rules: rules))
    #expect(!NoteEligibility.isEligible(relativePath: "Loose.md", rules: rules))
}

@Test func anExclusionCarvesOutOfAnIncludeOnly() {
    let rules = [
        VaultRule(kind: .includeOnly, path: "Projects"),
        VaultRule(kind: .exclude, path: "Projects/Archive")
    ]

    #expect(NoteEligibility.isEligible(relativePath: "Projects/Kickoff.md", rules: rules))
    #expect(!NoteEligibility.isEligible(relativePath: "Projects/Archive/Old.md", rules: rules))
    #expect(!NoteEligibility.isEligible(relativePath: "Elsewhere/Note.md", rules: rules))
}

@Test func ruleAndPathSlashesAreForgiven() {
    let rules = [VaultRule(kind: .exclude, path: "/Archive/")]
    #expect(!NoteEligibility.isEligible(relativePath: "Archive/Old.md", rules: rules))
    #expect(!NoteEligibility.isEligible(relativePath: "/Archive/Old.md", rules: rules))
}

// MARK: - Relative paths

@Test func relativePathsAreMeasuredFromTheVaultRoot() {
    let root = URL(filePath: "/Users/someone/Notes")

    #expect(
        NoteEligibility.relativePath(
            of: URL(filePath: "/Users/someone/Notes/Projects/Kickoff.md"),
            under: root
        ) == "Projects/Kickoff.md"
    )
    #expect(
        NoteEligibility.relativePath(
            of: URL(filePath: "/Users/someone/Elsewhere/Kickoff.md"),
            under: root
        ) == nil
    )
    // The root itself is not a note in it.
    #expect(NoteEligibility.relativePath(of: root, under: root) == nil)
}

@Test func aSiblingFolderWithASharedPrefixIsNotInsideTheVault() {
    #expect(
        NoteEligibility.relativePath(
            of: URL(filePath: "/Users/someone/NotesArchive/Old.md"),
            under: URL(filePath: "/Users/someone/Notes")
        ) == nil
    )
}
