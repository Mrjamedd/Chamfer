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

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 7
        let font = Self.editorFont
        let textColor = NSColor(
            srgbRed: 20 / 255,
            green: 17 / 255,
            blue: 14 / 255,
            alpha: 1
        )
        textView.font = font
        textView.textColor = textColor
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        textView.textStorage?.setAttributes(
            textView.typingAttributes,
            range: NSRange(location: 0, length: textView.string.utf16.count)
        )

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
        textView.setSelectedRange(
            NSRange(
                location: min(selection.location, text.utf16.count),
                length: 0
            )
        )
    }

    private static var editorFont: NSFont {
        let system = NSFont.systemFont(ofSize: 17)
        guard let descriptor = system.fontDescriptor.withDesign(.serif),
              let serif = NSFont(descriptor: descriptor, size: 17)
        else { return system }
        return serif
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
