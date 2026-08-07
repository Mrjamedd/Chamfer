import AppKit
import ChamferCore
import Foundation
import SwiftUI
import Testing

@testable import ChamferUI

@Test func retainingANoteDraftUpdatesEveryDashboardCopyOfThatDocument() {
    let editedURL = URL(fileURLWithPath: "/Notes/Example.md")
    let other = NoteDocument(
        url: URL(fileURLWithPath: "/Notes/Other.md"),
        text: "Other"
    )
    var state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: [],
        searchableNotes: [
            other,
            NoteDocument(url: editedURL, text: "Original")
        ],
        openNote: NoteDocument(url: editedURL, text: "Original")
    )

    DashboardNoteDrafts.retain(
        NoteDocument(url: editedURL, text: "Edited"),
        in: &state
    )

    #expect(state.openNote?.text == "Edited")
    #expect(state.searchableNotes[0] == other)
    #expect(state.searchableNotes[1].text == "Edited")
}

@Test func noteEditingConfigurationRejectsDocumentsWithoutRealBacking() {
    let realURL = URL(fileURLWithPath: "/Notes/Example.md")
    let configuration = NoteEditingConfiguration(
        documentURL: realURL,
        save: { _ in }
    )

    #expect(configuration.canEdit(realURL))
    #expect(!configuration.canEdit(URL(fileURLWithPath: "/Notes/Fake.md")))
}

@Test @MainActor
func noteEditorAutosaveWaitsForAPauseAndWritesOnlyTheLatestText() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("Example.md")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .milliseconds(80)
    ) { text in
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try Data("\(existing)\(text)\n".utf8).write(
            to: url,
            options: .atomic
        )
    }

    model.text = "First draft"
    model.textDidChange()
    try await Task.sleep(for: .milliseconds(20))
    model.text = "Final draft"
    model.textDidChange()

    try await Task.sleep(for: .milliseconds(40))
    #expect(!FileManager.default.fileExists(atPath: url.path))

    try await Task.sleep(for: .milliseconds(70))
    #expect(
        try String(contentsOf: url, encoding: .utf8)
            == "Final draft\n"
    )
}

@Test @MainActor
func noteEditorFlushImmediatelyPersistsAPendingEdit() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("Example.md")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .seconds(10)
    ) { text in
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    model.text = "Saved before leaving"
    model.textDidChange()
    model.flush()

    #expect(
        try String(contentsOf: url, encoding: .utf8)
            == "Saved before leaving"
    )
}

@Test @MainActor
func noteEditorReportsAutosaveFailuresWithoutDiscardingTheEdit() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory
        .appendingPathComponent("Missing", isDirectory: true)
        .appendingPathComponent("Example.md")
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .seconds(10)
    ) { text in
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    model.text = "Keep this edit"
    model.textDidChange()
    model.flush()

    #expect(model.text == "Keep this edit")
    #expect(model.saveErrorMessage != nil)
}

@Test @MainActor
func noteEditorClearsAStaleSaveErrorAfterRevertingToSavedText() {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .seconds(10)
    ) { _ in
        throw CocoaError(.fileWriteNoPermission)
    }

    model.text = "Unsaved edit"
    model.textDidChange()
    model.flush()
    #expect(model.saveErrorMessage != nil)

    model.text = "Original"
    model.textDidChange()

    #expect(model.saveErrorMessage == nil)
}

@Test @MainActor
func overflowingNoteEditorDoesNotInstallAVerticalScroller() async throws {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    let model = NoteEditorModel(
        document: NoteDocument(
            url: url,
            text: Array(repeating: "A long editable line", count: 200)
                .joined(separator: "\n")
        ),
        save: { _ in }
    )
    let hostingView = NSHostingView(
        rootView: NotePageView(model: model, onTextChange: { _ in })
            .frame(width: 900, height: 700)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    hostingView.frame = window.contentView?.bounds ?? .zero
    hostingView.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    hostingView.layoutSubtreeIfNeeded()

    let scrollViews = hostingView.descendants.compactMap { $0 as? NSScrollView }

    #expect(!scrollViews.isEmpty)
    #expect(scrollViews.allSatisfy { !$0.hasVerticalScroller })
    #expect(scrollViews.allSatisfy { $0.verticalScroller == nil })
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
