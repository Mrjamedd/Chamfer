import Foundation

/// A note, described well enough to list and inspect without reading the file.
public struct NoteSummary: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let wordCount: Int
    public let modifiedAt: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        wordCount: Int,
        modifiedAt: Date
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.wordCount = wordCount
        self.modifiedAt = modifiedAt
    }
}

/// One contiguous stretch of a note the model wants to change.
public struct Hunk: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let before: String
    public let after: String
    /// First line of the hunk in the original note, 1-indexed.
    public let startLine: Int

    public init(id: UUID = UUID(), before: String, after: String, startLine: Int) {
        self.id = id
        self.before = before
        self.after = after
        self.startLine = startLine
    }
}

public enum ProposalState: Sendable, Equatable {
    case pending
    case accepted
    case rejected
    /// Being generated again from the current source text.
    case regenerating
    /// Generation itself failed. The note was never touched.
    case failed(RewriteFailure)

    public var isPending: Bool { self == .pending }

    public var failure: RewriteFailure? {
        if case let .failed(failure) = self { return failure }
        return nil
    }
}

/// A rewrite waiting for judgement. Nothing here has been written to disk.
public struct Proposal: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let note: NoteSummary
    public let hunks: [Hunk]
    public let createdAt: Date
    /// What the note's modification date was when we read it.
    ///
    /// The whole of outdated-source handling hangs off this one value: if the
    /// file has moved on since, this rewrite was written against text that no
    /// longer exists.
    public let sourceModifiedAt: Date
    public let mode: RewriteMode
    public let modelID: String
    public let vaultID: UUID?
    public let fallback: FallbackRecord?
    public let retryCount: Int
    public var state: ProposalState

    public init(
        id: UUID = UUID(),
        note: NoteSummary,
        hunks: [Hunk],
        createdAt: Date,
        sourceModifiedAt: Date? = nil,
        mode: RewriteMode = .fullCleanup,
        modelID: String = "apple.foundation",
        vaultID: UUID? = nil,
        fallback: FallbackRecord? = nil,
        retryCount: Int = 0,
        state: ProposalState = .pending
    ) {
        self.id = id
        self.note = note
        self.hunks = hunks
        self.createdAt = createdAt
        // Defaults to the note's own modification date, which is what it was
        // at the moment the rewrite was generated.
        self.sourceModifiedAt = sourceModifiedAt ?? note.modifiedAt
        self.mode = mode
        self.modelID = modelID
        self.vaultID = vaultID
        self.fallback = fallback
        self.retryCount = retryCount
        self.state = state
    }

    /// True when the file has changed since this rewrite was generated.
    ///
    /// Takes the current modification date rather than reading it, so the rule
    /// is a pure function and the queue can be exercised without a disk.
    public func isOutdated(currentModification: Date?) -> Bool {
        guard let currentModification else { return false }
        return currentModification > sourceModifiedAt
    }

    public var changeCount: Int { hunks.count }
}

/// A rule-pass write that already happened, kept so it can be reverted.
public struct CleanupRecord: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let note: NoteSummary
    /// Identifiers of the rules that changed something.
    public let rules: [String]
    public let appliedAt: Date

    public init(id: UUID = UUID(), note: NoteSummary, rules: [String], appliedAt: Date) {
        self.id = id
        self.note = note
        self.rules = rules
        self.appliedAt = appliedAt
    }
}
