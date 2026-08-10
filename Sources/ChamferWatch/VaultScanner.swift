import ChamferCore
import Foundation

/// Everything one walk of a vault found.
public struct VaultScan: Sendable {
    public let vaultID: UUID
    /// Full note values, for search and for the rewrite pipeline.
    public let documents: [NoteDocument]
    public let summaries: [NoteSummary]
    /// Supported note files that exist whether or not current vault rules make
    /// them eligible. A rule change must not make durable history look deleted.
    public let existingNoteURLs: Set<URL>
    /// Subfolders that contain notes, so the Vaults page can offer them as
    /// places to set an override without listing the whole tree.
    public let folders: [URL]
    public let scannedAt: Date
    /// Set when the vault could not be read at all. The scan is then empty and
    /// the interface says why rather than showing a vault with no notes in it.
    public let failure: RewriteFailure?

    public init(
        vaultID: UUID,
        documents: [NoteDocument] = [],
        summaries: [NoteSummary] = [],
        existingNoteURLs: Set<URL> = [],
        folders: [URL] = [],
        scannedAt: Date = Date(),
        failure: RewriteFailure? = nil
    ) {
        self.vaultID = vaultID
        self.documents = documents
        self.summaries = summaries
        self.existingNoteURLs = existingNoteURLs
        self.folders = folders
        self.scannedAt = scannedAt
        self.failure = failure
    }

    public var noteCount: Int { summaries.count }
}

/// Walking a connected folder and reading what is in it.
///
/// Two passes rather than one. The first collects eligible paths, which is
/// cheap and gives an honest total to count progress against; the second reads
/// them. A single pass would have to report progress against a total it did not
/// yet know, which is how you end up with a bar that finishes at 140%.
public enum VaultScanner {
    /// Notes above this are indexed but not read into memory.
    ///
    /// A 20MB "note" is a log, an export, or something that got pasted by
    /// accident. Holding a thousand of them in the search index would cost more
    /// than the feature is worth, and rewriting one would take a model an hour.
    public static let maximumNoteBytes = 2 * 1024 * 1024

    public static func scan(
        vaultID: UUID,
        root: URL,
        rules: [VaultRule],
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> VaultScan {
        let granted = root.startAccessingSecurityScopedResource()
        defer {
            if granted { root.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.isReadableFile(atPath: root.path) else {
            return VaultScan(vaultID: vaultID, failure: .filePermissionDenied)
        }

        let found = eligibleFiles(under: root, rules: rules)
        guard !found.paths.isEmpty else {
            return VaultScan(
                vaultID: vaultID,
                existingNoteURLs: found.existingNoteURLs,
                folders: found.folders
            )
        }

        var documents: [NoteDocument] = []
        var summaries: [NoteSummary] = []
        documents.reserveCapacity(found.paths.count)
        summaries.reserveCapacity(found.paths.count)

        for (index, url) in found.paths.enumerated() {
            if Task.isCancelled { break }

            if let read = read(url) {
                summaries.append(read.summary)
                if let document = read.document {
                    documents.append(document)
                }
            }

            // Reported every so often rather than per file: a callback per note
            // on a four-thousand-note vault is four thousand hops to the main
            // actor to move a counter nobody can read that fast.
            if let onProgress, index % 25 == 0 || index == found.paths.count - 1 {
                onProgress(
                    ScanProgress(
                        vaultID: vaultID,
                        completed: index + 1,
                        total: found.paths.count
                    )
                )
            }

            // Yields the thread periodically so a large vault cannot starve
            // everything else the app is trying to do.
            if index % 50 == 0 { await Task.yield() }
        }

        return VaultScan(
            vaultID: vaultID,
            documents: documents,
            summaries: summaries,
            existingNoteURLs: found.existingNoteURLs,
            folders: found.folders
        )
    }

    /// Reads one note, if it is still there and still text.
    ///
    /// A file that is not valid UTF-8 is summarised but never loaded: the scope
    /// requires an unsupported encoding to leave the file strictly alone, and
    /// the surest way to honour that is never to hold a lossy copy of it.
    public static func read(_ url: URL) -> (summary: NoteSummary, document: NoteDocument?)? {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let modifiedAt = (attributes[.modificationDate] as? Date) ?? Date()
        let size = (attributes[.size] as? Int) ?? 0

        guard size <= maximumNoteBytes,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return (
                NoteSummary(
                    url: url,
                    title: title(for: url, text: nil),
                    wordCount: 0,
                    modifiedAt: modifiedAt
                ),
                nil
            )
        }

        return (
            NoteSummary(
                url: url,
                title: title(for: url, text: text),
                wordCount: wordCount(of: text),
                modifiedAt: modifiedAt
            ),
            NoteDocument(url: url, text: text)
        )
    }

    /// The note's first heading, or its filename.
    ///
    /// The heading wins because that is what the user called it; the filename
    /// is often a timestamp or a slug. Only the first few lines are examined —
    /// a heading further down is a section, not a title.
    public static func title(for url: URL, text: String?) -> String {
        let fallback = url.deletingPathExtension().lastPathComponent
        guard let text else { return fallback }

        // Only the head of the file is examined. A title is in the first few
        // lines by definition, and splitting a megabyte to find one is work
        // done four thousand times a sweep.
        let lines = text.prefix(4_096)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var index = 0
        while index < lines.count, lines[index].isEmpty { index += 1 }

        // A fence on the very first line opens front matter; the same fence
        // further down is a horizontal rule, which is why this is only checked
        // here and never inside the loop below.
        if index < lines.count, lines[index] == "---" || lines[index] == "+++" {
            let fence = lines[index]
            index += 1
            while index < lines.count, lines[index] != fence { index += 1 }
            if index < lines.count { index += 1 }
        }

        var examined = 0
        while index < lines.count, examined < 8 {
            let line = lines[index]
            index += 1
            guard !line.isEmpty else { continue }
            examined += 1

            guard line.hasPrefix("#") else {
                // Prose before any heading means the note does not open with a
                // title, and its filename is the better answer.
                break
            }
            let heading = line
                .drop { $0 == "#" }
                .trimmingCharacters(in: .whitespaces)
            if !heading.isEmpty { return heading }
        }
        return fallback
    }

    public static func wordCount(of text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    // MARK: - Walking

    private struct Found {
        var paths: [URL] = []
        var existingNoteURLs = Set<URL>()
        var folders: [URL] = []
    }

    /// One walk of the tree, skipping whole branches rather than filtering at
    /// the end. Descending into `node_modules` to discard everything in it
    /// would cost more than the rest of the scan put together.
    private static func eligibleFiles(under root: URL, rules: [VaultRule]) -> Found {
        var found = Found()
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return found }

        var foldersWithNotes = Set<URL>()

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false

            if isDirectory {
                if NoteEligibility.isExcludedDirectory(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard let relative = NoteEligibility.relativePath(of: url, under: root),
                  NoteEligibility.isEligible(relativePath: relative, rules: [])
            else { continue }

            found.existingNoteURLs.insert(url.standardizedFileURL)
            guard NoteEligibility.isEligible(relativePath: relative, rules: rules) else {
                continue
            }

            found.paths.append(url)
            let parent = url.deletingLastPathComponent().standardizedFileURL
            if parent != root.standardizedFileURL {
                foldersWithNotes.insert(parent)
            }
        }

        found.folders = foldersWithNotes.sorted {
            $0.path(percentEncoded: false) < $1.path(percentEncoded: false)
        }
        return found
    }
}
