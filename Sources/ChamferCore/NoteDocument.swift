import Foundation

/// A note as Chamfer sees it: its text and where that text came from.
///
/// Deliberately holds no file handle. Everything in `ChamferCore` operates on
/// values so the rule engine can be exercised without touching a disk.
public struct NoteDocument: Sendable, Equatable {
    /// Location the text was read from.
    public let url: URL
    /// Full contents of the note.
    public let text: String

    public init(url: URL, text: String) {
        self.url = url
        self.text = text
    }
}
