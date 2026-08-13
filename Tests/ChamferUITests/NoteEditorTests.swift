import AppKit
import ChamferCore
import Foundation
import SwiftUI
import Testing

@testable import ChamferUI

@Test func retainingASavedNoteUpdatesEveryDashboardCopyOfThatDocument() {
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

    DashboardNoteDocuments.retain(
        NoteDocument(url: editedURL, text: "Edited"),
        in: &state
    )

    #expect(state.openNote?.text == "Edited")
    #expect(state.searchableNotes[0] == other)
    #expect(state.searchableNotes[1].text == "Edited")
}

@Test func notePageMetadataUsesTheDeepestVaultAndStoredSummarySnapshot() {
    let now = Date(timeIntervalSince1970: 20_000)
    let outerURL = URL(fileURLWithPath: "/Notes")
    let innerURL = outerURL.appendingPathComponent("Projects", isDirectory: true)
    let noteURL = innerURL.appendingPathComponent("Filename.md")
    let document = NoteDocument(url: noteURL, text: "# Written title\nTwo words")
    let state = DashboardState(
        runState: .idle,
        folders: [],
        proposals: [],
        recentlyCleaned: [],
        recentNotes: [
            NoteSummary(
                url: noteURL,
                title: "Written title",
                wordCount: 87,
                modifiedAt: now.addingTimeInterval(-7_200)
            )
        ],
        searchableNotes: [document],
        openNote: document,
        vaults: [
            Vault(url: outerURL, noteCount: 10),
            Vault(url: innerURL, noteCount: 4)
        ]
    )

    let metadata = NotePageMetadata.snapshot(for: document, in: state)

    #expect(metadata.title == "Filename")
    #expect(!metadata.showsFilenameTitle)
    #expect(metadata.detail(since: now) == "Projects · 87 words · edited 2 hr ago")
}

@Test func notePageTitleIsSuppressedOnlyWhenTheNoteOpensWithAMarkdownH1() {
    #expect(!NotePageMetadata.showsFilenameTitle(in: "# Own title\nBody"))
    #expect(!NotePageMetadata.showsFilenameTitle(in: "\n# Own title\nBody"))
    #expect(
        !NotePageMetadata.showsFilenameTitle(
            in: "---\ntags: [work]\n---\n# Own title\nBody"
        )
    )
    #expect(NotePageMetadata.showsFilenameTitle(in: "## First section\nBody"))
    #expect(NotePageMetadata.showsFilenameTitle(in: "Opening prose\n# Later heading"))
    #expect(NotePageMetadata.showsFilenameTitle(in: "#Not a heading\nBody"))
}

@Test @MainActor
func noteEditorSessionsKeepAnUnsavedDraftWhenReturningToANote() {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .seconds(10),
        save: { _ in }
    )
    let sessions = DashboardNoteEditorSessions()
    sessions.retain(model, for: url)

    model.text = "Unsaved draft"
    model.textDidChange()

    #expect(sessions.editor(for: url) === model)
    #expect(sessions.editor(for: url)?.text == "Unsaved draft")
    #expect(sessions.editor(for: url)?.hasUnsavedChanges == true)
}

@Test @MainActor
func noteEditingConfigurationSupportsEveryDocumentApprovedByItsBackingStore() {
    let firstURL = URL(fileURLWithPath: "/Notes/First.md")
    let secondURL = URL(fileURLWithPath: "/Notes/Second.md")
    let outsideURL = URL(fileURLWithPath: "/Elsewhere/Fake.md")
    var saved: [URL] = []
    let configuration = NoteEditingConfiguration(
        canEdit: { $0.deletingLastPathComponent().path == "/Notes" },
        save: { saved.append($0.url) }
    )

    #expect(configuration.canEdit(firstURL))
    #expect(configuration.canEdit(secondURL))
    #expect(!configuration.canEdit(outsideURL))

    try? configuration.save(NoteDocument(url: secondURL, text: "Edited"))
    #expect(saved == [secondURL])
    #expect(throws: NoteEditingError.self) {
        try configuration.save(NoteDocument(url: outsideURL, text: "No"))
    }
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

    // Nothing yet: the second edit restarted the pause.
    #expect(!FileManager.default.fileExists(atPath: url.path))

    // Waited for rather than slept past. This previously asserted at a fixed
    // 130ms against an 80ms timer, which held until the machine was busy — and
    // a suite that fails once in five is a suite nobody trusts.
    try await untilTrue { FileManager.default.fileExists(atPath: url.path) }

    // The save closure appends, so two writes would leave both drafts behind.
    // That the file holds only the last one is the debounce working, and it is
    // true whenever the write lands rather than only at one instant.
    #expect(
        try String(contentsOf: url, encoding: .utf8)
            == "Final draft\n"
    )
}

@Test @MainActor
func noteEditorSuppliesTheLastSavedTextForConflictDetection() {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    var writes: [(text: String, replacing: String)] = []
    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .seconds(10),
        saveReplacing: { text, expectedText in
            writes.append((text, expectedText))
        }
    )

    model.text = "First save"
    model.textDidChange()
    model.flush()
    model.text = "Second save"
    model.textDidChange()
    model.flush()

    #expect(writes.map(\.text) == ["First save", "Second save"])
    #expect(writes.map(\.replacing) == ["Original", "First save"])
    #expect(!model.hasUnsavedChanges)
}

@Test @MainActor
func noteEditorReportsSavingAndRetainsOnlySuccessfulSaves() {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    var retained: [String] = []
    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .seconds(10),
        didSave: { retained.append($0) },
        save: { _ in }
    )

    #expect(model.saveStatus == .saved)

    model.text = "Draft"
    model.textDidChange()

    #expect(model.saveStatus == .saving)
    #expect(retained.isEmpty)

    model.flush()

    #expect(model.saveStatus == .saved)
    #expect(retained == ["Draft"])
}

@Test @MainActor
func noteEditorReportsTheExistingErrorAfterASaveFails() {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    var retained: [String] = []
    let model = NoteEditorModel(
        document: NoteDocument(url: url, text: "Original"),
        autosaveDelay: .seconds(10),
        didSave: { retained.append($0) },
        save: { _ in throw CocoaError(.fileWriteNoPermission) }
    )

    model.text = "Unsaved"
    model.textDidChange()
    model.flush()

    guard case let .failed(message) = model.saveStatus else {
        Issue.record("Expected the failed save state.")
        return
    }
    #expect(message == model.saveErrorMessage)
    #expect(retained.isEmpty)
    #expect(model.hasUnsavedChanges)
}

/// Polls until `condition` holds, or gives up.
///
/// The timeout is generous on purpose: it is there to fail a genuinely broken
/// autosave rather than to measure how fast a correct one is.
private func untilTrue(
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for the autosave to land.")
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
func notePageMeasureFitsAboutSixtyFiveCharactersInTheActualEditorFont() throws {
    let prose = """
    The strongest parts are the large centered canvas, generous margins, restrained typography, and the warm paper-like background. The note feels focused and readable instead of looking like a generic text editor. Moving the metadata closer to the content makes the whole page feel more cohesive, while a narrower measure gives each line a deliberate rhythm. Calm and precise controls should support the writing without drawing attention away from it. When a document is comfortable to read, the eye returns to the beginning of the next line without searching. That quiet rhythm matters more in a writing environment than filling every available point of space.
    """
    let hostingView = NSHostingView(
        rootView: PlainTextEditor(text: .constant(prose))
            .frame(width: Chamfer.Page.measure, height: 300)
    )
    hostingView.frame = NSRect(
        x: 0,
        y: 0,
        width: Chamfer.Page.measure,
        height: 300
    )
    hostingView.layoutSubtreeIfNeeded()

    let textView = try #require(
        hostingView.descendants.compactMap { $0 as? NSTextView }.first
    )
    let font = try #require(textView.font)
    let fragmentPadding = try #require(textView.textContainer?.lineFragmentPadding)
    let proseWidth = (prose as NSString).size(withAttributes: [.font: font]).width
    let averageCharacterWidth = proseWidth / CGFloat((prose as NSString).length)
    let charactersPerLine = (
        Chamfer.Page.measure - fragmentPadding * 2
    ) / averageCharacterWidth

    #expect(charactersPerLine >= 64.5)
    #expect(charactersPerLine <= 65.5)
}

@Test @MainActor
func noteSaveStatesKeepTheEditableViewportAtOneHeight() throws {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    let document = NoteDocument(url: url, text: "A short note.")
    let metadata = NotePageMetadata.snapshot(
        for: document,
        in: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            searchableNotes: [document],
            openNote: document
        )
    )
    let saved = NoteEditorModel(document: document, save: { _ in })
    let saving = NoteEditorModel(
        document: document,
        autosaveDelay: .seconds(10),
        save: { _ in }
    )
    saving.text = "A short edited note."
    saving.textDidChange()

    let failed = NoteEditorModel(document: document) { _ in
        throw LongLocalizedSaveError()
    }
    failed.text = "An edit that cannot be saved."
    failed.textDidChange()
    failed.flush()

    let savedHeight = try noteEditorViewportHeight(model: saved, metadata: metadata)
    let savingHeight = try noteEditorViewportHeight(model: saving, metadata: metadata)
    let failedHeight = try noteEditorViewportHeight(model: failed, metadata: metadata)

    #expect(savedHeight == savingHeight)
    #expect(savingHeight == failedHeight)
}

@Test @MainActor
func plainTextEditorWeightsOnlyHashHeadingsWithoutChangingTheirText() throws {
    let note = """
    # First
    ## Second
    ### Third
    Body
    #### Four
    #Not a heading
    """
    let hostingView = NSHostingView(
        rootView: PlainTextEditor(text: .constant(note))
            .frame(width: Chamfer.Page.measure, height: 600)
    )
    hostingView.frame = NSRect(
        x: 0,
        y: 0,
        width: Chamfer.Page.measure,
        height: 600
    )
    hostingView.layoutSubtreeIfNeeded()

    let textView = try #require(
        hostingView.descendants.compactMap { $0 as? NSTextView }.first
    )
    let storage = try #require(textView.textStorage)
    let string = storage.string as NSString
    let first = string.range(of: "First").location
    let second = string.range(of: "Second").location
    let third = string.range(of: "Third").location
    let body = string.range(of: "Body").location
    let fourth = string.range(of: "Four").location
    let notHeading = string.range(of: "Not a heading").location

    #expect(storage.string == note)
    #expect(try font(at: first, in: storage).pointSize == 23)
    #expect(try font(at: second, in: storage).pointSize == 21)
    #expect(try font(at: third, in: storage).pointSize == 19)
    #expect(try font(at: body, in: storage).pointSize == 17)
    #expect(try font(at: fourth, in: storage).pointSize == 17)
    #expect(try font(at: notHeading, in: storage).pointSize == 17)
    #expect(
        NSFontManager.shared.weight(of: try font(at: first, in: storage))
            > NSFontManager.shared.weight(of: try font(at: body, in: storage))
    )
    #expect(
        NSFontManager.shared.weight(of: try font(at: third, in: storage))
            > NSFontManager.shared.weight(of: try font(at: body, in: storage))
    )

    let markerColor = try color(at: 0, in: storage)
    let headingColor = try color(at: first, in: storage)
    #expect(colorsMatch(markerColor, NSColor(Chamfer.Palette.textOnPaperFaint)))
    #expect(colorsMatch(headingColor, NSColor(Chamfer.Palette.pageText)))
}

@Test @MainActor
func plainTextEditorRestylesOnlyTheParagraphChangedByTyping() throws {
    var note = "# First\nBody\nAnother paragraph\n# Far heading"
    let hostingView = NSHostingView(
        rootView: PlainTextEditor(
            text: Binding(
                get: { note },
                set: { note = $0 }
            )
        )
        .frame(width: Chamfer.Page.measure, height: 600)
    )
    hostingView.frame = NSRect(
        x: 0,
        y: 0,
        width: Chamfer.Page.measure,
        height: 600
    )
    hostingView.layoutSubtreeIfNeeded()

    let textView = try #require(
        hostingView.descendants.compactMap { $0 as? NSTextView }.first
    )
    let coordinator = try #require(
        textView.delegate as? PlainTextEditor.Coordinator
    )
    let storage = try #require(textView.textStorage)
    let oldBodyRange = (storage.string as NSString).range(of: "Body")
    let oldFarRange = (storage.string as NSString).range(of: "Far heading")
    let sentinel = NSAttributedString.Key("ChamferUITests.sentinel")
    storage.addAttribute(sentinel, value: true, range: oldFarRange)

    let delegate: NSTextViewDelegate = coordinator
    _ = delegate.textView?(
        textView,
        shouldChangeTextIn: oldBodyRange,
        replacementString: "Changed"
    )
    storage.replaceCharacters(in: oldBodyRange, with: "Changed")
    let newBodyRange = (storage.string as NSString).range(of: "Changed")
    storage.addAttribute(
        .font,
        value: NSFont.boldSystemFont(ofSize: 30),
        range: newBodyRange
    )
    textView.setSelectedRange(
        NSRange(location: NSMaxRange(newBodyRange), length: 0)
    )
    let selection = textView.selectedRange()

    coordinator.textDidChange(
        Notification(name: NSText.didChangeNotification, object: textView)
    )

    let newFarRange = (storage.string as NSString).range(of: "Far heading")
    #expect(note == textView.string)
    #expect(textView.selectedRange() == selection)
    #expect(try font(at: newBodyRange.location, in: storage).pointSize == 17)
    #expect(storage.attribute(sentinel, at: newFarRange.location, effectiveRange: nil) != nil)
}

@Test @MainActor
func plainTextEditorRestylesBothParagraphsCreatedByANewline() throws {
    var note = "# HeadBody"
    let hostingView = NSHostingView(
        rootView: PlainTextEditor(
            text: Binding(
                get: { note },
                set: { note = $0 }
            )
        )
        .frame(width: Chamfer.Page.measure, height: 300)
    )
    hostingView.frame = NSRect(
        x: 0,
        y: 0,
        width: Chamfer.Page.measure,
        height: 300
    )
    hostingView.layoutSubtreeIfNeeded()

    let textView = try #require(
        hostingView.descendants.compactMap { $0 as? NSTextView }.first
    )
    let coordinator = try #require(
        textView.delegate as? PlainTextEditor.Coordinator
    )
    let storage = try #require(textView.textStorage)
    let split = (storage.string as NSString).range(of: "Body").location

    let delegate: NSTextViewDelegate = coordinator
    _ = delegate.textView?(
        textView,
        shouldChangeTextIn: NSRange(location: split, length: 0),
        replacementString: "\n"
    )
    storage.replaceCharacters(
        in: NSRange(location: split, length: 0),
        with: "\n"
    )
    textView.setSelectedRange(NSRange(location: split + 1, length: 0))
    coordinator.textDidChange(
        Notification(name: NSText.didChangeNotification, object: textView)
    )

    let body = (storage.string as NSString).range(of: "Body").location
    #expect(note == "# Head\nBody")
    #expect(textView.selectedRange() == NSRange(location: split + 1, length: 0))
    #expect(try font(at: 2, in: storage).pointSize == 23)
    #expect(try font(at: body, in: storage).pointSize == 17)
}

@Test @MainActor
func plainTextEditorStylesAHeadingCreatedByANewline() throws {
    var note = "Body# Heading"
    let hostingView = NSHostingView(
        rootView: PlainTextEditor(
            text: Binding(
                get: { note },
                set: { note = $0 }
            )
        )
        .frame(width: Chamfer.Page.measure, height: 300)
    )
    hostingView.frame = NSRect(
        x: 0,
        y: 0,
        width: Chamfer.Page.measure,
        height: 300
    )
    hostingView.layoutSubtreeIfNeeded()

    let textView = try #require(
        hostingView.descendants.compactMap { $0 as? NSTextView }.first
    )
    let coordinator = try #require(
        textView.delegate as? PlainTextEditor.Coordinator
    )
    let storage = try #require(textView.textStorage)
    let split = (storage.string as NSString).range(of: "#").location

    let delegate: NSTextViewDelegate = coordinator
    _ = delegate.textView?(
        textView,
        shouldChangeTextIn: NSRange(location: split, length: 0),
        replacementString: "\n"
    )
    storage.replaceCharacters(
        in: NSRange(location: split, length: 0),
        with: "\n"
    )
    textView.setSelectedRange(NSRange(location: split + 1, length: 0))
    coordinator.textDidChange(
        Notification(name: NSText.didChangeNotification, object: textView)
    )

    let marker = (storage.string as NSString).range(of: "#").location
    let heading = (storage.string as NSString).range(of: "Heading").location
    #expect(note == "Body\n# Heading")
    #expect(textView.selectedRange() == NSRange(location: split + 1, length: 0))
    #expect(try font(at: 0, in: storage).pointSize == 17)
    #expect(try font(at: heading, in: storage).pointSize == 23)
    #expect(
        colorsMatch(
            try color(at: marker, in: storage),
            NSColor(Chamfer.Palette.textOnPaperFaint)
        )
    )
}

@Test @MainActor
func overflowingNoteEditorDoesNotInstallAVerticalScroller() async throws {
    let url = URL(fileURLWithPath: "/Notes/Example.md")
    let document = NoteDocument(
        url: url,
        text: Array(repeating: "A long editable line", count: 200)
            .joined(separator: "\n")
    )
    let model = NoteEditorModel(
        document: document,
        save: { _ in }
    )
    let metadata = NotePageMetadata.snapshot(
        for: document,
        in: DashboardState(
            runState: .idle,
            folders: [],
            proposals: [],
            recentlyCleaned: [],
            searchableNotes: [document],
            openNote: document
        )
    )
    let hostingView = NSHostingView(
        rootView: NotePageView(model: model, metadata: metadata)
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

private func font(at location: Int, in storage: NSTextStorage) throws -> NSFont {
    try #require(
        storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    )
}

private func color(at location: Int, in storage: NSTextStorage) throws -> NSColor {
    try #require(
        storage.attribute(.foregroundColor, at: location, effectiveRange: nil)
            as? NSColor
    )
}

private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    guard let lhs = lhs.usingColorSpace(.sRGB),
          let rhs = rhs.usingColorSpace(.sRGB)
    else { return false }

    return abs(lhs.redComponent - rhs.redComponent) < 0.001
        && abs(lhs.greenComponent - rhs.greenComponent) < 0.001
        && abs(lhs.blueComponent - rhs.blueComponent) < 0.001
        && abs(lhs.alphaComponent - rhs.alphaComponent) < 0.001
}

private struct LongLocalizedSaveError: LocalizedError {
    var errorDescription: String? {
        "The note could not be written because the destination stopped accepting changes while Chamfer was saving it."
    }
}

@MainActor
private func noteEditorViewportHeight(
    model: NoteEditorModel,
    metadata: NotePageMetadata
) throws -> CGFloat {
    let hostingView = NSHostingView(
        rootView: NotePageView(model: model, metadata: metadata)
            .frame(width: 900, height: 700)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
    hostingView.layoutSubtreeIfNeeded()

    let editor = try #require(
        hostingView.descendants
            .compactMap { $0 as? NSScrollView }
            .first { $0.documentView is NSTextView }
    )
    return editor.frame.height
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
