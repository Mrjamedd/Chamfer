import ChamferCore
import Foundation
import Testing

@testable import ChamferWatch

// MARK: - Helpers

private struct Bench {
    let root: URL
    let note: URL
    let writer: NoteWriter

    init(contents: String = "The original text.\n") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        note = root.appendingPathComponent("Note.md")
        try Data(contents.utf8).write(to: note)
        writer = NoteWriter(
            snapshots: SnapshotStore(
                directory: root.appendingPathComponent("Snapshots", isDirectory: true)
            )
        )
    }

    var text: String {
        (try? String(contentsOf: note, encoding: .utf8)) ?? ""
    }

    var modifiedAt: Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: note.path)
        return (attributes?[.modificationDate] as? Date) ?? .distantPast
    }

    var snapshotCount: Int {
        let directory = root.appendingPathComponent("Snapshots", isDirectory: true)
        let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return contents?.count ?? 0
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Writing

@Test func aWriteReplacesTheNoteAndSnapshotsWhatItReplaced() throws {
    let bench = try Bench()
    defer { bench.tearDown() }

    let failure = bench.writer.write(
        "The corrected text.\n",
        to: bench.note,
        expectedModification: bench.modifiedAt
    )

    #expect(failure == nil)
    #expect(bench.text == "The corrected text.\n")
    // The snapshot is the only copy of what was replaced. No snapshot, no
    // write — that ordering is the whole safety story.
    #expect(bench.snapshotCount == 1)
}

/// The bug this guards: snapshot names were the note's key and a millisecond
/// timestamp, so writes landing inside one millisecond overwrote each other and
/// a replaced version — the only copy — was lost. Deterministic here, where the
/// three writes are back to back and the suite only caught it intermittently.
@Test func snapshotsTakenInTheSameMillisecondDoNotOverwriteEachOther() throws {
    let bench = try Bench()
    defer { bench.tearDown() }
    let store = SnapshotStore(
        directory: bench.root.appendingPathComponent("Snapshots", isDirectory: true)
    )

    let written = try (0..<25).map {
        try store.record(text: "version \($0)", for: bench.note)
    }

    #expect(Set(written).count == written.count)
    #expect(bench.snapshotCount == written.count)
    // Every version is still readable, not just present.
    let recovered = try written.map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(recovered == (0..<25).map { "version \($0)" })
}

@Test func aSnapshotIsTakenBeforeEveryWriteRatherThanOnce() throws {
    let bench = try Bench()
    defer { bench.tearDown() }

    _ = bench.writer.write("One.\n", to: bench.note, expectedModification: nil)
    _ = bench.writer.write("Two.\n", to: bench.note, expectedModification: nil)
    _ = bench.writer.write("Three.\n", to: bench.note, expectedModification: nil)

    #expect(bench.snapshotCount == 3)
    #expect(bench.text == "Three.\n")
}

@Test func aNoteThatChangedSinceItWasReadIsNotOverwritten() throws {
    let bench = try Bench()
    defer { bench.tearDown() }

    // The rewrite was generated against the note as it was two minutes ago.
    let stale = Date().addingTimeInterval(-120)
    let failure = bench.writer.write(
        "The model's version.\n",
        to: bench.note,
        expectedModification: stale
    )

    #expect(failure == .fileChangedDuringProcessing)
    // Untouched, and no snapshot: nothing happened at all.
    #expect(bench.text == "The original text.\n")
    #expect(bench.snapshotCount == 0)
}

@Test func aContentChangeInsideTheTimestampToleranceIsStillNotOverwritten() throws {
    let bench = try Bench()
    defer { bench.tearDown() }
    let expectedModification = bench.modifiedAt
    try Data("The user's newest text.\n".utf8).write(to: bench.note, options: .atomic)

    let failure = bench.writer.write(
        "The model's version.\n",
        to: bench.note,
        expectedModification: expectedModification,
        expectedText: "The original text.\n"
    )

    #expect(failure == .fileChangedDuringProcessing)
    #expect(bench.text == "The user's newest text.\n")
    #expect(bench.snapshotCount == 0)
}

@Test func skippingTheStaleCheckIsHowAnOutdatedRewriteIsDeliberatelyApplied() throws {
    let bench = try Bench()
    defer { bench.tearDown() }

    // The user was warned and chose to replace what they wrote since. The
    // version being replaced still goes into a snapshot.
    let failure = bench.writer.write(
        "Applied anyway.\n",
        to: bench.note,
        expectedModification: nil
    )

    #expect(failure == nil)
    #expect(bench.text == "Applied anyway.\n")
    #expect(bench.snapshotCount == 1)
}

@Test func aMissingNoteReportsRatherThanCreatingOne() throws {
    let bench = try Bench()
    defer { bench.tearDown() }
    try FileManager.default.removeItem(at: bench.note)

    let failure = bench.writer.write(
        "Text.\n",
        to: bench.note,
        expectedModification: nil
    )

    #expect(failure == .vaultUnavailable)
    #expect(!FileManager.default.fileExists(atPath: bench.note.path))
}

// MARK: - Restoring

@Test func restoringPutsTheEarlierTextBack() throws {
    let bench = try Bench()
    defer { bench.tearDown() }

    _ = bench.writer.write("Rewritten.\n", to: bench.note, expectedModification: nil)
    let failure = bench.writer.restore(text: "The original text.\n", to: bench.note)

    #expect(failure == nil)
    #expect(bench.text == "The original text.\n")
}

@Test func restoringSnapshotsWhatItOverwritesSoUndoCanBeUndone() throws {
    let bench = try Bench()
    defer { bench.tearDown() }

    _ = bench.writer.write("Rewritten.\n", to: bench.note, expectedModification: nil)
    _ = bench.writer.restore(text: "The original text.\n", to: bench.note)

    // One for the rewrite, one for the restore. The text a restore replaces is
    // no less the user's than any other.
    #expect(bench.snapshotCount == 2)
}

// MARK: - Snapshot naming

@Test func snapshotKeysAreStableAndDistinct() {
    let a = URL(filePath: "/Users/someone/Notes/Kickoff.md")
    let b = URL(filePath: "/Users/someone/Notes/Retro.md")

    #expect(SnapshotStore.key(for: a) == SnapshotStore.key(for: a))
    #expect(SnapshotStore.key(for: a) != SnapshotStore.key(for: b))
    // The same note reached by a scruffier path is the same note.
    #expect(
        SnapshotStore.key(for: a)
            == SnapshotStore.key(for: URL(filePath: "/Users/someone/Notes/./Kickoff.md"))
    )
}

@Test func snapshotKeysSurviveAPathNoFilenameCouldHold() {
    // Paths can be longer than a filename may be, and can hold characters a
    // filename may not.
    let awkward = URL(filePath: "/Users/someone/" + String(repeating: "deep/", count: 60) + "note:name.md")
    let key = SnapshotStore.key(for: awkward)

    #expect(!key.isEmpty)
    #expect(key.count < 32)
    #expect(!key.contains("/"))
    #expect(!key.contains(":"))
}

@Test func snapshotsLiveOutsideTheUsersVault() throws {
    let bench = try Bench()
    defer { bench.tearDown() }

    _ = bench.writer.write("Rewritten.\n", to: bench.note, expectedModification: nil)

    // The scope forbids backup files appearing beside the user's notes: they
    // would be indexed, synced and searched by whatever else reads that folder.
    let siblings = try FileManager.default.contentsOfDirectory(
        atPath: bench.note.deletingLastPathComponent().path
    )
    #expect(siblings.filter { $0.hasSuffix(".md") } == ["Note.md"])
    #expect(!siblings.contains { $0.hasSuffix(".bak") })
}
