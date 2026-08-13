import AppKit
import SwiftUI

/// A native plain-text editor whose scroll view never installs scrollbars.
/// Scrolling still works through wheel, trackpad, and keyboard input.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil

        let textView = NSTextView(frame: scrollView.bounds)
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        textView.font = NoteTextStyle.bodyFont
        textView.textColor = NoteTextStyle.bodyColor
        textView.defaultParagraphStyle = NoteTextStyle.paragraphStyle
        textView.typingAttributes = NoteTextStyle.bodyAttributes
        if let storage = textView.textStorage {
            NoteTextStyle.apply(to: storage)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text
        else { return }

        let selection = textView.selectedRange()
        textView.string = text
        textView.typingAttributes = NoteTextStyle.bodyAttributes
        if let storage = textView.textStorage {
            // An external replacement can alter any paragraph. Interactive
            // typing takes the narrower path in the coordinator below.
            NoteTextStyle.apply(to: storage)
        }
        let location = min(selection.location, text.utf16.count)
        textView.setSelectedRange(
            NSRange(
                location: location,
                length: min(selection.length, text.utf16.count - location)
            )
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        private var pendingEditedRange: NSRange?

        init(text: Binding<String>) {
            self.text = text
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // TextKit reports the pre-edit range here. Retaining the insertion
            // point and replacement length is enough to recover the changed
            // paragraph after the edit, including a paragraph newly split or
            // joined by a newline.
            pendingEditedRange = NSRange(
                location: affectedCharRange.location,
                length: replacementString?.utf16.count ?? 0
            )
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selection = textView.selectedRange()
            if let storage = textView.textStorage {
                // A whole-document attribute pass on every keystroke is linear
                // in the note's length. Keeping this to the edited paragraph
                // and the paragraph a new separator may create makes the cost
                // follow what changed instead, while full replacements are
                // still normalized in `updateNSView`.
                NoteTextStyle.apply(
                    to: storage,
                    editedRange: pendingEditedRange ?? selection
                )
                textView.typingAttributes = NoteTextStyle.bodyAttributes
                textView.setSelectedRange(selection)
            }
            pendingEditedRange = nil
            text.wrappedValue = textView.string
        }
    }
}

@MainActor
private enum NoteTextStyle {
    static let bodyFont = Chamfer.TypeScale.pageBodyNSFont
    static let bodyColor = NSColor(Chamfer.Palette.pageText)
    static let markerColor = NSColor(Chamfer.Palette.textOnPaperFaint)

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 7
        return style
    }()

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: bodyColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    static func apply(
        to storage: NSTextStorage,
        editedRange: NSRange? = nil
    ) {
        guard storage.length > 0 else { return }

        let string = storage.string as NSString
        let range = paragraphRange(
            in: string,
            around: editedRange ?? NSRange(location: 0, length: storage.length)
        )

        storage.beginEditing()
        storage.setAttributes(bodyAttributes, range: range)

        var cursor = range.location
        while cursor < NSMaxRange(range) {
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            string.getParagraphStart(
                &paragraphStart,
                end: &paragraphEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: cursor, length: 0)
            )

            let contents = NSRange(
                location: paragraphStart,
                length: contentsEnd - paragraphStart
            )
            if let level = headingLevel(in: string, contents: contents) {
                storage.addAttribute(
                    .font,
                    value: Chamfer.TypeScale.noteHeadingNSFont(level: level),
                    range: contents
                )
                storage.addAttribute(
                    .foregroundColor,
                    value: markerColor,
                    range: NSRange(location: paragraphStart, length: level)
                )
            }

            cursor = max(paragraphEnd, cursor + 1)
        }

        storage.endEditing()
    }

    private static func paragraphRange(
        in string: NSString,
        around editedRange: NSRange
    ) -> NSRange {
        let location = min(editedRange.location, string.length)
        let availableLength = string.length - location
        let length = min(editedRange.length, availableLength)
        let trailingLength = location + length < string.length ? 1 : 0
        return string.paragraphRange(
            // The separator belongs to the paragraph before it. Looking one
            // character beyond the edit also reaches the paragraph created by
            // an inserted newline, without widening ordinary edits beyond the
            // paragraph they already occupy.
            for: NSRange(
                location: location,
                length: length + trailingLength
            )
        )
    }

    private static func headingLevel(
        in string: NSString,
        contents: NSRange
    ) -> Int? {
        guard contents.length > 0 else { return nil }

        var level = 0
        while level < min(3, contents.length),
              string.character(at: contents.location + level) == 0x23
        {
            level += 1
        }
        guard level > 0 else { return nil }

        let next = contents.location + level
        guard next == NSMaxRange(contents)
                || string.character(at: next) == 0x20
                || string.character(at: next) == 0x09
        else { return nil }

        return level
    }
}
