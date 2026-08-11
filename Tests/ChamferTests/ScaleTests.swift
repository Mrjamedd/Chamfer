import ChamferCore
import ChamferRewrite
import ChamferWatch
import Foundation
import Testing

@testable import Chamfer

/// The sizes a real vault reaches, exercised once rather than assumed.
///
/// Everything else in the suite works on notes of a sentence or two, because
/// that is where behaviour lives. These are here for the other failure: the one
/// that only appears at two thousand notes or fifty kilobytes, where nothing is
/// wrong with the logic and the app is unusable anyway.

private func scaleDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ChamferScale-\(UUID().uuidString)", isDirectory: true)
}

/// A note that looks like somebody's, rather than one repeated sentence:
/// headings, prose, lists and a code block, so segmentation and masking meet
/// the shapes they were written for.
private func realisticNote(sections: Int) -> String {
    var parts: [String] = ["# Weekly review\n"]
    for index in 1...sections {
        parts.append("""
            ## Section \(index)

            The reports is ready and teh summary went out on Firday. Nothing \
            here is urgent, but the ordering of the steps matters because of \
            the dependencies between them.

            - Check the backlog for section \(index)
            - Chase the invoice
            - [The brief](https://example.com/brief/\(index))

            ```bash
            atlas check ./reports --section \(index)
            ```
            """)
    }
    return parts.joined(separator: "\n\n") + "\n"
}

@Test @MainActor
func aVaultOfTwoThousandNotesScansInReasonableTimeAndMemory() async throws {
    let root = scaleDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // Spread across folders, as a real vault is.
    for index in 0..<2_000 {
        let folder = root.appending(path: "Folder \(index % 20)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# Note \(index)\n\nSome teh text in note \(index).\n".utf8)
            .write(to: folder.appending(path: "Note \(index).md"))
    }

    let started = ContinuousClock.now
    let scan = await VaultScanner.scan(vaultID: UUID(), root: root, rules: [])
    let elapsed = ContinuousClock.now - started

    #expect(scan.summaries.count == 2_000)
    #expect(scan.failure == nil)
    // Generous by an order of magnitude: this is a smoke test for an accidental
    // quadratic, not a benchmark. A scan that takes a minute is a vault nobody
    // finishes connecting.
    #expect(elapsed < .seconds(30), "scan took \(elapsed)")
}

@Test @MainActor
func twoVaultsAtOnceKeepTheirNotesAndSettingsApart() throws {
    let first = scaleDirectory()
    let second = scaleDirectory()
    defer {
        try? FileManager.default.removeItem(at: first)
        try? FileManager.default.removeItem(at: second)
    }
    for root in [first, second] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    let vaultOne = Vault(url: first, noteCount: 1)
    let vaultTwo = Vault(url: second, noteCount: 1)
    let model = AppModel()
    #expect(model.addVault(vaultOne, bookmark: Data([0x01])))
    #expect(model.addVault(vaultTwo, bookmark: Data([0x02])))

    let noteOne = first.appending(path: "One.md")
    let noteTwo = second.appending(path: "Two.md")
    model.dashboard.searchableNotes = [
        NoteDocument(url: noteOne, text: "teh one"),
        NoteDocument(url: noteTwo, text: "teh two")
    ]
    model.dashboard.existingNoteURLs = [noteOne, noteTwo]
    model.updateConfiguration(
        VaultConfiguration(mode: .spelling, fixesCapitalisation: false),
        for: vaultOne.id
    )

    // Configuring one vault says nothing about the other.
    #expect(model.dashboard.vaults.first { $0.id == vaultOne.id }?.configuration?.mode == .spelling)
    #expect(model.dashboard.vaults.first { $0.id == vaultTwo.id }?.configuration == nil)

    // Removing one takes its notes and nothing else.
    model.removeVault(vaultOne.id)

    #expect(model.dashboard.vaults.map(\.id) == [vaultTwo.id])
    #expect(model.dashboard.searchableNotes.map(\.url) == [noteTwo])
    #expect(model.bookmark(for: vaultTwo.id) == Data([0x02]))
}

/// The property everything downstream rests on: whatever the model returns, the
/// parts of the note Chamfer never sent must come back byte for byte.
@Test
func aLargeStructuredNoteReassemblesByteForByte() async {
    // Past Balanced's 24,000-character segment target, so this crosses a
    // segment boundary as well as a unit one.
    let source = realisticNote(sections: 80)
    #expect(source.count > 24_000, "note is \(source.count) chars")

    for effort in ModelEffort.allCases {
        let outcome = await RewritePipeline.run(
            text: source,
            policy: RewritePolicy(
                mode: .spelling,
                application: .review,
                inactivityDelay: 60,
                sweep: .never,
                preserved: .all,
                modelID: "test"
            ),
            model: NamedRewriter(
                modelID: "local.test",
                rewriter: IdentityRewriter()
            ),
            effort: effort
        )

        // An identity model changes nothing, so the only way this is not
        // `.unchanged` is reassembly having altered the note by itself.
        guard case .unchanged = outcome else {
            Issue.record("\(effort): expected unchanged, got \(outcome)")
            return
        }
    }
}

/// The same note, with the model correcting one word per unit, still comes back
/// with every heading, list marker, link and code block exactly where it was.
@Test
func aLargeNoteKeepsEveryProtectedRegionWhileBeingEdited() async {
    let source = realisticNote(sections: 80)

    let outcome = await RewritePipeline.run(
        text: source,
        policy: RewritePolicy(
            mode: .spelling,
            application: .review,
            inactivityDelay: 60,
            sweep: .never,
            preserved: .all,
            modelID: "test"
        ),
        model: NamedRewriter(
            modelID: "local.test",
            rewriter: SpellingRewriter()
        ),
        effort: .balanced
    )

    guard case let .proposed(product) = outcome else {
        Issue.record("Expected a proposal, got \(outcome)")
        return
    }

    #expect(!product.text.contains("teh "))
    #expect(product.text.components(separatedBy: "## Section").count == 81)
    #expect(
        product.text.components(separatedBy: "```bash").count
            == source.components(separatedBy: "```bash").count
    )
    #expect(
        product.text.components(separatedBy: "https://example.com/brief/").count
            == source.components(separatedBy: "https://example.com/brief/").count
    )
    // Not one placeholder may survive into the note itself.
    #expect(!product.text.contains("{{KEEP"))
}

/// A note past the scanner's ceiling is skipped rather than read into memory.
@Test
func aNoteBeyondTheSizeCeilingIsSkippedRatherThanRead() throws {
    let root = scaleDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let huge = root.appending(path: "Huge.md")
    try Data(String(repeating: "a", count: VaultScanner.maximumNoteBytes + 1).utf8)
        .write(to: huge)

    let read = VaultScanner.read(huge)

    #expect(read?.summary != nil)
    #expect(read?.document == nil, "a note over the ceiling must not be loaded")
}

// MARK: - Models

private struct IdentityRewriter: Rewriter {
    var isAvailable: Bool { get async { true } }

    func rewrite(_ section: String, instructions: String) async throws -> String {
        section
    }
}

private struct SpellingRewriter: Rewriter {
    var isAvailable: Bool { get async { true } }

    func rewrite(_ section: String, instructions: String) async throws -> String {
        section.replacingOccurrences(of: "teh ", with: "the ")
    }
}

// MARK: - Shipping

/// The release pipeline is only as trustworthy as the bundle it signs, and the
/// bundle is assembled by a shell script that nothing else checks.
@Test
func thePackagingScriptDescribesAnAppThatCanUpdateItself() throws {
    let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let script = try String(
        contentsOf: root.appending(path: "Scripts/package.sh"),
        encoding: .utf8
    )

    // Sparkle reads both of these from Info.plist and does nothing without
    // them, so a build that omits one silently never updates.
    #expect(script.contains("SUFeedURL"))
    #expect(script.contains("SUPublicEDKey"))
    // And a bundle without the framework inside it cannot launch at all.
    #expect(script.contains("Sparkle.framework"))
    #expect(script.contains("@executable_path/../Frameworks"))
    // The identifier is what an update is matched against; it must not drift.
    #expect(script.contains("com.chamfer.app"))

    // Tags ship, pushes do not. If this ever inverts, every unfinished commit
    // on a branch becomes a release.
    let release = try String(
        contentsOf: root.appending(path: ".github/workflows/release.yml"),
        encoding: .utf8
    )
    #expect(release.contains("tags: [\"v*\"]"))
    #expect(!release.contains("branches:"))
    #expect(release.contains("notarytool"))
    #expect(release.contains("stapler"))
}
