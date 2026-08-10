import Foundation

/// A note that settled on disk and is ready to be considered for cleaning.
///
/// Emitted only after the debounce window has passed, so a note being actively
/// typed into does not produce a change per keystroke.
public struct NoteChange: Sendable, Equatable {
    public let url: URL
    public let detectedAt: Date
    public let requiresRescan: Bool

    public init(url: URL, detectedAt: Date, requiresRescan: Bool = false) {
        self.url = url
        self.detectedAt = detectedAt
        self.requiresRescan = requiresRescan
    }
}

/// Watches one or more folders and reports notes that have settled.
///
/// Implementations must suppress echoes of Chamfer's own writes; otherwise the
/// app reacts to its own edits forever.
public protocol FolderObserving: Sendable {
    func start(onChange: @escaping @Sendable (NoteChange) -> Void) throws
    func stop()
    func expectOwnWrite(to url: URL)
    func cancelExpectedOwnWrite(to url: URL)
}
