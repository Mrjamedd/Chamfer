import ChamferCore
import Foundation
import Testing

@testable import Chamfer

@Test @MainActor
func connectedVaultEditorEditsAnySupportedNoteAndRefreshesTheDashboard() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let firstURL = root.appendingPathComponent("First.md")
    let secondURL = root.appendingPathComponent("Second.txt")
    let outsideURL = root.deletingLastPathComponent().appendingPathComponent("Outside.md")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("First".utf8).write(to: firstURL)
    try Data("Second".utf8).write(to: secondURL)
    try Data("Outside".utf8).write(to: outsideURL)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outsideURL)
    }

    let vault = Vault(url: root, noteCount: 2)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            searchableNotes: [
                NoteDocument(url: firstURL, text: "First"),
                NoteDocument(url: secondURL, text: "Second")
            ],
            openNote: NoteDocument(url: firstURL, text: "First"),
            vaults: [vault]
        )
    )
    let notes = NoteService(model: model)
    let editor = ConnectedVaultNoteEditor(model: model, notes: notes)

    #expect(editor.canEdit(firstURL))
    #expect(editor.canEdit(secondURL))
    #expect(!editor.canEdit(outsideURL))
    #expect(!editor.canEdit(root.appendingPathComponent("Archive.rtf")))

    try editor.save(NoteDocument(url: secondURL, text: "Edited in Chamfer"))

    #expect(try String(contentsOf: secondURL, encoding: .utf8) == "Edited in Chamfer")
    #expect(
        model.dashboard.searchableNotes.first {
            $0.url.standardizedFileURL == secondURL.standardizedFileURL
        }?.text == "Edited in Chamfer"
    )
    #expect(notes.settling[secondURL.standardizedFileURL] != nil)
}

@Test @MainActor
func connectedVaultEditorStopsSavingWhenTheVaultBecomesUnavailable() throws {
    let root = URL(filePath: "/Vault")
    let url = root.appendingPathComponent("Note.md")
    let vault = Vault(url: root, availability: .offline, noteCount: 1)
    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            vaults: [vault]
        )
    )
    let editor = ConnectedVaultNoteEditor(model: model, notes: NoteService(model: model))

    #expect(!editor.canEdit(url))
    var refused = false
    do {
        try editor.save(NoteDocument(url: url, text: "No write"))
    } catch {
        refused = true
    }
    #expect(refused)
}

@Test @MainActor
func connectedVaultEditorNeverOverwritesATextChangedOutsideChamfer() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = root.appendingPathComponent("Note.md")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("Original".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: root) }

    let model = AppModel(
        dashboard: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            searchableNotes: [NoteDocument(url: url, text: "Original")],
            openNote: NoteDocument(url: url, text: "Original"),
            vaults: [Vault(url: root, noteCount: 1)]
        )
    )
    let editor = ConnectedVaultNoteEditor(model: model, notes: NoteService(model: model))

    try Data("External edit".utf8).write(to: url, options: .atomic)
    var refused = false
    do {
        try editor.save(
            NoteDocument(url: url, text: "Chamfer draft"),
            replacing: "Original"
        )
    } catch {
        refused = true
    }

    #expect(refused)
    #expect(try String(contentsOf: url, encoding: .utf8) == "External edit")
}
