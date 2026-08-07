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

/// A model that was used because the chosen one could not be.
///
/// Recorded rather than inferred: the scope requires fallback to be visible
/// after the fact, including when it moved processing off the device.
public struct FallbackRecord: Sendable, Equatable, Hashable, Codable {
    public let requestedModel: String
    public let usedModel: String
    public let reason: RewriteFailure
    /// True when the fallback sent note contents off the device. Carried
    /// explicitly so history can be honest about it without having to know
    /// what every model identifier means.
    public let leftDevice: Bool

    public init(
        requestedModel: String,
        usedModel: String,
        reason: RewriteFailure,
        leftDevice: Bool
    ) {
        self.requestedModel = requestedModel
        self.usedModel = usedModel
        self.reason = reason
        self.leftDevice = leftDevice
    }
}

// MARK: - Entry

/// One rewrite that reached a conclusion, kept forever.
///
/// Holds both texts in full rather than a diff. A diff is smaller but it can
/// only be replayed against the exact bytes it was made from, and the one
/// moment this record has to work is the moment the file on disk is *not*
/// what it was. Restoring must never depend on the thing being restored.
public struct HistoryEntry: Sendable, Identifiable, Equatable {
    public enum Outcome: Sendable, Equatable {
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
    public let fallback: FallbackRecord?
    public let retryCount: Int
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
        fallback: FallbackRecord? = nil,
        retryCount: Int = 0,
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
        self.fallback = fallback
        self.retryCount = retryCount
        self.outcome = outcome
    }

    /// Only an applied rewrite that has not already been undone can be undone.
    public var canRestore: Bool { outcome.isApplied }

    /// The short facts under the title: mode, model, and anything unusual.
    /// Reads as a sentence rather than a row of pills, because most entries
    /// are unremarkable and should not shout.
    public func summary(since reference: Date) -> String {
        var parts = [mode.title, modelID]
        if fallback != nil { parts.append("fallback") }
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
        sorted(entries.filter { $0.path == url })
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
