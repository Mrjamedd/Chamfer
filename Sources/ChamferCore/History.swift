import Foundation

// MARK: - Failure

/// Why a rewrite did not finish.
///
/// Every case leaves the source file untouched. That is not a convention the
/// call sites are trusted to remember — it is why failures are a value that
/// gets recorded rather than an early `return`, so the interface can always
/// say what happened and offer the retry.
public enum RewriteFailure: Sendable, Equatable, Hashable, Codable {
    case modelUnavailable(model: String)
    case cloudRequestFailed(detail: String)
    case localModelFailed(detail: String)
    case filePermissionDenied
    case vaultUnavailable
    case unsupportedEncoding
    /// The note changed underneath us between reading and writing.
    case fileChangedDuringProcessing
    /// The rewrite came back having disturbed something the user protects.
    case preservationViolated(MarkdownStructure)
    case snapshotFailed(detail: String)

    /// Shown as the failure's headline.
    public var title: String {
        switch self {
        case .modelUnavailable: "Model unavailable"
        case .cloudRequestFailed: "Cloud request failed"
        case .localModelFailed: "Local model failed"
        case .filePermissionDenied: "No permission to write"
        case .vaultUnavailable: "Vault unavailable"
        case .unsupportedEncoding: "Unsupported encoding"
        case .fileChangedDuringProcessing: "The note changed while we worked"
        case .preservationViolated: "Preservation rules would be broken"
        case .snapshotFailed: "Couldn't take a snapshot"
        }
    }

    /// The second line: the useful reason, when there is one to give.
    public var detail: String {
        switch self {
        case let .modelUnavailable(model):
            "\(model) didn't respond. The note is unchanged."
        case let .cloudRequestFailed(detail):
            detail
        case let .localModelFailed(detail):
            detail
        case .filePermissionDenied:
            "Chamfer can read this note but cannot write to it. The note is unchanged."
        case .vaultUnavailable:
            "The vault this note lives in isn't reachable. Nothing was written."
        case .unsupportedEncoding:
            "This file isn't valid UTF-8, so rewriting it could corrupt it. Left alone."
        case .fileChangedDuringProcessing:
            "You edited the note mid-rewrite, so the result was discarded rather than overwrite you."
        case let .preservationViolated(structure):
            "The rewrite would have altered \(structure.titles.formattedList()). Discarded."
        case let .snapshotFailed(detail):
            "No snapshot, so nothing was applied. \(detail)"
        }
    }

    /// Whether trying the same thing again could plausibly work. A permission
    /// problem or a bad encoding will not fix itself, and offering a retry
    /// that cannot succeed is worse than offering none.
    public var isRetryable: Bool {
        switch self {
        case .modelUnavailable, .cloudRequestFailed, .localModelFailed,
             .vaultUnavailable, .fileChangedDuringProcessing, .snapshotFailed:
            true
        case .filePermissionDenied, .unsupportedEncoding, .preservationViolated:
            false
        }
    }
}

// MARK: - Entry

/// One rewrite that reached a conclusion, kept forever.
///
/// Holds both texts in full rather than a diff. A diff is smaller but it can
/// only be replayed against the exact bytes it was made from, and the one
/// moment this record has to work is the moment the file on disk is *not*
/// what it was. Restoring must never depend on the thing being restored.
public struct HistoryEntry: Sendable, Identifiable, Equatable, Codable {
    public enum Outcome: Sendable, Equatable, Codable {
        case applied
        case failed(RewriteFailure)
        /// Applied, then undone by the user.
        case reverted(at: Date)

        public var isApplied: Bool {
            if case .applied = self { return true }
            return false
        }

        public var failure: RewriteFailure? {
            if case let .failed(failure) = self { return failure }
            return nil
        }
    }

    public let id: UUID
    public let note: NoteSummary
    /// Where the note was when this happened. Kept separately from
    /// `note.url` so a moved or deleted note still has a truthful record.
    public let path: URL
    public let vaultID: UUID?
    public let occurredAt: Date
    public let mode: RewriteMode
    public let modelID: String
    public let previousText: String
    public let appliedText: String
    /// Automatic or manually approved.
    public let application: RewriteApplication
    /// The source had changed since the rewrite was generated, and the user
    /// approved it anyway.
    public let sourceWasOutdated: Bool
    public let retryCount: Int
    /// Non-empty for the deterministic cleanup pass. These entries represent
    /// a real snapshotted write, but no model was involved.
    public let ruleIDs: [String]
    public let outcome: Outcome

    public init(
        id: UUID = UUID(),
        note: NoteSummary,
        path: URL,
        vaultID: UUID? = nil,
        occurredAt: Date,
        mode: RewriteMode,
        modelID: String,
        previousText: String,
        appliedText: String,
        application: RewriteApplication,
        sourceWasOutdated: Bool = false,
        retryCount: Int = 0,
        ruleIDs: [String] = [],
        outcome: Outcome = .applied
    ) {
        self.id = id
        self.note = note
        self.path = path
        self.vaultID = vaultID
        self.occurredAt = occurredAt
        self.mode = mode
        self.modelID = modelID
        self.previousText = previousText
        self.appliedText = appliedText
        self.application = application
        self.sourceWasOutdated = sourceWasOutdated
        self.retryCount = retryCount
        self.ruleIDs = ruleIDs
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey {
        case id, note, path, vaultID, occurredAt, mode, modelID
        case previousText, appliedText, application, sourceWasOutdated
        case retryCount, ruleIDs, outcome
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        note = try values.decode(NoteSummary.self, forKey: .note)
        path = try values.decode(URL.self, forKey: .path)
        vaultID = try values.decodeIfPresent(UUID.self, forKey: .vaultID)
        occurredAt = try values.decode(Date.self, forKey: .occurredAt)
        mode = try values.decode(RewriteMode.self, forKey: .mode)
        modelID = try values.decode(String.self, forKey: .modelID)
        previousText = try values.decode(String.self, forKey: .previousText)
        appliedText = try values.decode(String.self, forKey: .appliedText)
        application = try values.decode(RewriteApplication.self, forKey: .application)
        sourceWasOutdated = try values.decode(Bool.self, forKey: .sourceWasOutdated)
        retryCount = try values.decode(Int.self, forKey: .retryCount)
        ruleIDs = try values.decodeIfPresent([String].self, forKey: .ruleIDs) ?? []
        outcome = try values.decode(Outcome.self, forKey: .outcome)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(note, forKey: .note)
        try values.encode(path, forKey: .path)
        try values.encodeIfPresent(vaultID, forKey: .vaultID)
        try values.encode(occurredAt, forKey: .occurredAt)
        try values.encode(mode, forKey: .mode)
        try values.encode(modelID, forKey: .modelID)
        try values.encode(previousText, forKey: .previousText)
        try values.encode(appliedText, forKey: .appliedText)
        try values.encode(application, forKey: .application)
        try values.encode(sourceWasOutdated, forKey: .sourceWasOutdated)
        try values.encode(retryCount, forKey: .retryCount)
        if !ruleIDs.isEmpty { try values.encode(ruleIDs, forKey: .ruleIDs) }
        try values.encode(outcome, forKey: .outcome)
    }

    /// Only an applied rewrite that has not already been undone can be undone.
    public var canRestore: Bool { outcome.isApplied }

    /// The short facts under the title: mode, model, and anything unusual.
    /// Reads as a sentence rather than a row of pills, because most entries
    /// are unremarkable and should not shout.
    public func summary(since reference: Date) -> String {
        if !ruleIDs.isEmpty {
            let count = ruleIDs.count
            return "Rules · \(count) repair\(count == 1 ? "" : "s") · automatic"
        }
        var parts = [mode.title, modelID]
        if sourceWasOutdated { parts.append("outdated source") }
        if retryCount > 0 { parts.append("retried \(retryCount)×") }
        parts.append(application == .automatic ? "automatic" : "approved")
        return parts.joined(separator: " · ")
    }
}

// MARK: - The window onto history

/// History as the interface reads it: a recent window, and everything.
///
/// The scope keeps every entry forever but shows 200. Splitting that here
/// rather than in the view means the rule is testable, and the full browse is
/// a different `limit` rather than a different code path.
public enum HistoryWindow {
    /// What the standard History view shows.
    public static let standardLimit = 200

    public static func recent(
        _ entries: [HistoryEntry],
        limit: Int = standardLimit
    ) -> [HistoryEntry] {
        sorted(entries).prefix(limit).map { $0 }
    }

    public static func sorted(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.sorted { $0.occurredAt > $1.occurredAt }
    }

    /// Entries for one note, newest first — the per-note history the gutter
    /// opens onto.
    public static func forNote(
        at url: URL,
        in entries: [HistoryEntry]
    ) -> [HistoryEntry] {
        let key = url.standardizedFileURL
        return sorted(entries.filter { $0.path.standardizedFileURL == key })
    }

    /// True when there is more stored than the standard view is showing, which
    /// is the only condition under which the "everything" control appears.
    public static func hasMore(
        than limit: Int = standardLimit,
        in entries: [HistoryEntry]
    ) -> Bool {
        entries.count > limit
    }
}

extension Array where Element == String {
    /// "headings", "headings and lists", "headings, lists and links".
    func formattedList() -> String {
        switch count {
        case 0: ""
        case 1: self[0].lowercased()
        default:
            dropLast().map { $0.lowercased() }.joined(separator: ", ")
                + " and " + self[count - 1].lowercased()
        }
    }
}
