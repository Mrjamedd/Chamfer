import CoreServices
import Foundation
import Testing

@testable import ChamferWatch

/// Scaffold-level check. Debounce, echo suppression and atomic-write tests
/// arrive with the watcher implementation.
@Test func changesCompareByURLAndTimestamp() {
    let url = URL(fileURLWithPath: "/tmp/note.md")
    let moment = Date(timeIntervalSince1970: 0)
    #expect(NoteChange(url: url, detectedAt: moment) == NoteChange(url: url, detectedAt: moment))
}

@Test func renameAndDirectoryEventsRequireWholeVaultReconciliation() {
    #expect(
        FolderObserver.requiresReconciliation(
            for: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        )
    )
    #expect(
        FolderObserver.requiresReconciliation(
            for: FSEventStreamEventFlags(
                kFSEventStreamEventFlagItemIsDir
                    | kFSEventStreamEventFlagItemRemoved
            )
        )
    )
    #expect(
        !FolderObserver.requiresReconciliation(
            for: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        )
    )
}

@Test func exampleNoteStoreCreatesARealMarkdownFileFromTheSeed() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ExampleNoteStore(directory: directory)
    let document = try store.loadOrCreate(seedText: "# Example\n\nStart here.")

    #expect(document.url == directory.appendingPathComponent("Example.md"))
    #expect(document.text == "# Example\n\nStart here.")
    #expect(
        try String(contentsOf: document.url, encoding: .utf8)
            == "# Example\n\nStart here."
    )
}

@Test func exampleNoteStorePreservesAutosavedEditsAcrossReloads() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ExampleNoteStore(directory: directory)
    _ = try store.loadOrCreate(seedText: "Original")
    try store.save(text: "Edited in Chamfer")

    let reloaded = try store.loadOrCreate(seedText: "Original")

    #expect(reloaded.text == "Edited in Chamfer")
    #expect(
        try String(contentsOf: reloaded.url, encoding: .utf8)
            == "Edited in Chamfer"
    )
}
