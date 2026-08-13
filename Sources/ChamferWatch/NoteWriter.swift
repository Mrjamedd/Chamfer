import ChamferCore
import Foundation

/// Writing to somebody's note.
///
/// The single most dangerous thing the app does, and the rules are accordingly
/// blunt:
///
/// 1. Nothing is written until a snapshot of what is being replaced exists.
/// 2. Nothing is written if the file changed since it was read.
/// 3. Every write is atomic, so a crash mid-write cannot leave half a note.
///
/// Every one of those is a `guard` here rather than a convention call sites are
/// trusted to follow, because the cost of forgetting one is somebody's writing.
public struct NoteWriter: Sendable {
    public let snapshots: SnapshotStore

    public init(snapshots: SnapshotStore = SnapshotStore()) {
        self.snapshots = snapshots
    }

    /// Replaces a note's contents.
    ///
    /// - Parameters:
    ///   - url: the note.
    ///   - text: what it should say.
    ///   - expectedModification: what the file's modification date was when the
    ///     text being replaced was read. Nil skips the check, which is only
    ///     correct when the caller has just read the file itself.
    /// - Returns: the failure, or nil when the write succeeded.
    public func write(
        _ text: String,
        to url: URL,
        expectedModification: Date?,
        expectedText: String? = nil
    ) -> RewriteFailure? {
        switch replace(
            text,
            at: url,
            expectedModification: expectedModification,
            expectedText: expectedText
        ) {
        case .success:
            nil
        case let .failure(failure):
            failure
        }
    }

    /// Performs the guarded write and returns the exact text it replaced.
    /// A restore needs that receipt for its own before-and-after history; the
    /// ordinary write API deliberately keeps its smaller failure-only shape.
    private func replace(
        _ text: String,
        at url: URL,
        expectedModification: Date?,
        expectedText: String? = nil
    ) -> Result<String, RewriteFailure> {
        let manager = FileManager.default

        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else {
            return .failure(.vaultUnavailable)
        }
        guard manager.isWritableFile(atPath: url.path) else {
            return .failure(.filePermissionDenied)
        }

        // Checked before the snapshot rather than after: a snapshot of text the
        // user has already moved past is a snapshot of the wrong thing.
        if let expectedModification,
           let actual = attributes[.modificationDate] as? Date,
           actual.timeIntervalSince(expectedModification) > 1 {
            return .failure(.fileChangedDuringProcessing)
        }

        guard let previous = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure(.unsupportedEncoding)
        }
        // Some filesystems round modification dates coarsely. The bytes are
        // the final authority when the caller has already read them.
        if let expectedText, previous != expectedText {
            return .failure(.fileChangedDuringProcessing)
        }

        do {
            try snapshots.record(text: previous, for: url)
        } catch {
            // No snapshot, so nothing is applied. The scope's rule that a
            // snapshot precedes every applied rewrite is this ordering, and it
            // is not a step that can be skipped when storage is full.
            return .failure(.snapshotFailed(detail: error.localizedDescription))
        }

        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            return .failure(.filePermissionDenied)
        }

        return .success(previous)
    }

    /// Puts an earlier version back.
    ///
    /// Snapshots what it is about to overwrite first, exactly as a rewrite
    /// does — undoing an undo has to work, and the text being replaced by a
    /// restore is no less the user's than any other.
    public func restore(
        text: String,
        to url: URL
    ) -> RewriteFailure? {
        switch restoreRecordingReplacement(text: text, to: url) {
        case .success:
            nil
        case let .failure(failure):
            failure
        }
    }

    /// The same safe restore, with the receipt required by append-only
    /// history. Returning it from the writer avoids a second, racy file read.
    public func restoreRecordingReplacement(
        text: String,
        to url: URL
    ) -> Result<String, RewriteFailure> {
        replace(text, at: url, expectedModification: nil)
    }
}

/// Copies of what was replaced, kept in hidden local storage.
///
/// Deliberately not in the user's vault. The scope is explicit that backup
/// files are not inserted into connected folders, and a `.bak` appearing beside
/// every note would be indexed, synced and searched by whatever else the user
/// points at that folder.
public struct SnapshotStore: Sendable {
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
                .appendingPathComponent("Snapshots", isDirectory: true)
        }
    }

    /// Files a copy of `text` as it was for `url`.
    ///
    /// The name is never reused. It used to be the note's key and a millisecond
    /// timestamp, which is not enough: two writes to the same note inside one
    /// millisecond produced the same filename and the second silently replaced
    /// the first. A snapshot is the only copy of what a write replaced, so
    /// losing one loses an undo — and it happened often enough that the test
    /// suite caught it intermittently.
    ///
    /// The timestamp still leads, so the directory sorts chronologically;
    /// collisions take a suffix. Nothing parses these names, so the shape is
    /// free to change.
    @discardableResult
    public func record(text: String, for url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let payload = Data(text.utf8)
        for destination in Self.candidateNames(for: url, in: directory) {
            // Checked rather than assumed. Another process could in principle
            // take the name between here and the write; the timestamp makes
            // that window a millisecond wide, and the suffix means the
            // *observed* failure — two writes from this process in one
            // millisecond — cannot happen at all.
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }
            try payload.write(to: destination, options: .atomic)
            return destination
        }

        throw CocoaError(.fileWriteFileExists)
    }

    /// The names one snapshot may take, in order of preference.
    private static func candidateNames(
        for url: URL,
        in directory: URL
    ) -> [URL] {
        let key = key(for: url)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return (0..<512).map { attempt in
            let suffix = attempt == 0 ? "" : "-\(String(attempt, radix: 36))"
            return directory.appendingPathComponent(
                "\(key)-\(stamp)\(suffix).snapshot"
            )
        }
    }

    /// A stable, filesystem-safe name for a note's path.
    ///
    /// Hashed rather than escaped: a note's path can be longer than a filename
    /// is allowed to be, and can contain characters that are legal in a path
    /// and not in a name.
    static func key(for url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }
}
