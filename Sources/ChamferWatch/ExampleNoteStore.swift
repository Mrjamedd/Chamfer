import ChamferCore
import Foundation

/// Owns the single editable example file used by the source-built app.
/// The UI receives loaded values and save closures, so filesystem access stays
/// in the filesystem layer.
public struct ExampleNoteStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.directory = applicationSupport
                .appendingPathComponent("Chamfer", isDirectory: true)
        }
    }

    public var documentURL: URL {
        directory.appendingPathComponent("Example.md")
    }

    public func loadOrCreate(seedText: String) throws -> NoteDocument {
        try createDirectoryIfNeeded()

        if !FileManager.default.fileExists(atPath: documentURL.path) {
            try write(seedText)
        }

        return NoteDocument(
            url: documentURL,
            text: try String(contentsOf: documentURL, encoding: .utf8)
        )
    }

    public func save(text: String) throws {
        try createDirectoryIfNeeded()
        try write(text)
    }

    private func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: documentURL, options: .atomic)
    }
}
