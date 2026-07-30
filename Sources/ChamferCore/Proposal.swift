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
}

/// A rewrite waiting for judgement. Nothing here has been written to disk.
public struct Proposal: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let note: NoteSummary
    public let hunks: [Hunk]
    public let createdAt: Date
    public var state: ProposalState

    public init(
        id: UUID = UUID(),
        note: NoteSummary,
        hunks: [Hunk],
        createdAt: Date,
        state: ProposalState = .pending
    ) {
        self.id = id
        self.note = note
        self.hunks = hunks
        self.createdAt = createdAt
        self.state = state
    }
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
