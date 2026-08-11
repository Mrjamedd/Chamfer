import ChamferCore
import Foundation
import Testing

@testable import ChamferWatch

// MARK: - Helpers

private struct Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    func write(_ relativePath: String, _ text: String = "Some text.") throws -> URL {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
        return url
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Walking

@Test func aScanFindsMarkdownAndTextAnywhereInTheTree() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Kickoff.md")
    try sandbox.write("Notes.txt")
    try sandbox.write("Projects/Deep/Nested/Retro.md")

    let scan = await VaultScanner.scan(vaultID: UUID(), root: sandbox.root, rules: [])

    #expect(scan.noteCount == 3)
    #expect(scan.failure == nil)
    #expect(Set(scan.summaries.map(\.url.lastPathComponent))
        == ["Kickoff.md", "Notes.txt", "Retro.md"])
}

@Test func unsupportedFormatsAreLeftEntirelyAlone() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Kickoff.md")
    try sandbox.write("Report.rtf")
    try sandbox.write("Contract.docx")
    try sandbox.write("Page.html")

    let scan = await VaultScanner.scan(vaultID: UUID(), root: sandbox.root, rules: [])

    #expect(scan.noteCount == 1)
    #expect(scan.summaries.first?.url.lastPathComponent == "Kickoff.md")
}

@Test func applicationFoldersAreNeverDescendedInto() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Kickoff.md")
    try sandbox.write(".obsidian/workspace.md")
    try sandbox.write(".git/COMMIT_EDITMSG.txt")
    try sandbox.write("node_modules/package/readme.md")

    let scan = await VaultScanner.scan(vaultID: UUID(), root: sandbox.root, rules: [])

    #expect(scan.noteCount == 1)
    #expect(scan.summaries.first?.url.lastPathComponent == "Kickoff.md")
}

@Test func exclusionsAreHonouredDuringTheWalk() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Kickoff.md")
    try sandbox.write("Archive/Old.md")
    try sandbox.write("Archive/2019/Older.md")

    let scan = await VaultScanner.scan(
        vaultID: UUID(),
        root: sandbox.root,
        rules: [VaultRule(kind: .exclude, path: "Archive")]
    )

    #expect(scan.noteCount == 1)
    #expect(scan.summaries.first?.url.lastPathComponent == "Kickoff.md")
}

@Test func includeOnlyLimitsTheScanToTheChosenFolders() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Loose.md")
    try sandbox.write("Projects/Kickoff.md")
    try sandbox.write("Scratch/Idea.md")

    let scan = await VaultScanner.scan(
        vaultID: UUID(),
        root: sandbox.root,
        rules: [VaultRule(kind: .includeOnly, path: "Projects")]
    )

    #expect(scan.noteCount == 1)
    #expect(scan.summaries.first?.url.lastPathComponent == "Kickoff.md")
}

@Test func aScanRemembersExcludedFilesSoTheirHistoryCanStayActionable() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    let included = try sandbox.write("Projects/Kickoff.md")
    let excluded = try sandbox.write("Archive/Old.md")

    let scan = await VaultScanner.scan(
        vaultID: UUID(),
        root: sandbox.root,
        rules: [VaultRule(kind: .includeOnly, path: "Projects")]
    )

    #expect(scan.existingNoteURLs == Set([included, excluded].map(\.standardizedFileURL)))
    #expect(scan.summaries.map { $0.url.standardizedFileURL } == [included.standardizedFileURL])
}

@Test func foldersHoldingNotesAreReportedForTheVaultsPage() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Root.md")
    try sandbox.write("Projects/Kickoff.md")
    try sandbox.write("Journal/Daily/Monday.md")
    // A folder with nothing eligible in it is not somewhere to set an override.
    try FileManager.default.createDirectory(
        at: sandbox.root.appending(path: "Empty"),
        withIntermediateDirectories: true
    )

    let scan = await VaultScanner.scan(vaultID: UUID(), root: sandbox.root, rules: [])
    let names = scan.folders.map(\.lastPathComponent)

    #expect(names.contains("Projects"))
    #expect(names.contains("Daily"))
    #expect(!names.contains("Empty"))
}

// MARK: - Reading

@Test func aNotesTitleComesFromItsFirstHeading() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("2026-08-07.md", "# Kickoff meeting\n\nWe agreed on three things.")

    let scan = await VaultScanner.scan(vaultID: UUID(), root: sandbox.root, rules: [])

    #expect(scan.summaries.first?.title == "Kickoff meeting")
}

@Test func aNoteWithoutAHeadingFallsBackToItsFilename() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Shopping list.md", "milk\nbread\n\n# Not the title")

    let scan = await VaultScanner.scan(vaultID: UUID(), root: sandbox.root, rules: [])

    #expect(scan.summaries.first?.title == "Shopping list")
}

@Test func frontMatterDoesNotHideTheHeadingBelowIt() {
    let text = "---\ntags: [meeting]\n---\n\n# Kickoff meeting\n\nBody."
    #expect(
        VaultScanner.title(for: URL(filePath: "/Vault/note.md"), text: text)
            == "Kickoff meeting"
    )
}

@Test func wordCountsCountWords() {
    #expect(VaultScanner.wordCount(of: "one two three") == 3)
    #expect(VaultScanner.wordCount(of: "  spaced   out \n across lines ") == 4)
    #expect(VaultScanner.wordCount(of: "") == 0)
}

@Test func aScanReadsTheFullTextForSearch() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    try sandbox.write("Kickoff.md", "# Kickoff\n\nThe quiet part out loud.")

    let scan = await VaultScanner.scan(vaultID: UUID(), root: sandbox.root, rules: [])

    #expect(scan.documents.count == 1)
    #expect(scan.documents.first?.text.contains("quiet part") == true)
}

@Test func theRealisticFixtureVaultContainsAndIndexesExactlyTwentyMarkdownNotes() async throws {
    let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repository.appending(path: "TestVaultFixtures", directoryHint: .isDirectory)
    let entries = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )

    #expect(entries.count == 20)
    #expect(entries.allSatisfy { $0.pathExtension == "md" })

    let scan = await VaultScanner.scan(vaultID: UUID(), root: root, rules: [])
    #expect(scan.failure == nil)
    #expect(scan.noteCount == 20)
    #expect(scan.summaries.count == 20)
    #expect(scan.documents.count == 20)
    #expect(Set(scan.summaries.map(\.title)).count == 20)
}

@Test func anUnreadableVaultReportsRatherThanLookingEmpty() async throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let scan = await VaultScanner.scan(vaultID: UUID(), root: missing, rules: [])

    // An empty vault and an unreachable one must never look the same: one needs
    // notes putting in it, the other needs a disk plugging in.
    #expect(scan.failure == .filePermissionDenied)
    #expect(scan.noteCount == 0)
}

// MARK: - Progress

@Test func progressIsReportedAgainstAKnownTotal() async throws {
    let sandbox = try Sandbox()
    defer { sandbox.tearDown() }

    for index in 0..<60 {
        try sandbox.write("Note\(index).md")
    }

    let collected = Reports()
    _ = await VaultScanner.scan(
        vaultID: UUID(),
        root: sandbox.root,
        rules: []
    ) { progress in
        collected.append(progress)
    }

    let reports = collected.all
    #expect(!reports.isEmpty)
    // The total is known before any file is read, so it never moves.
    #expect(reports.allSatisfy { $0.total == 60 })
    #expect(reports.last?.completed == 60)
    #expect(reports.allSatisfy { $0.completed <= $0.total })
}

/// The progress callback is `@Sendable` and fires from the scanning task, so
/// the test needs somewhere thread-safe to put what it sees.
private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanProgress] = []

    func append(_ progress: ScanProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }

    var all: [ScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
