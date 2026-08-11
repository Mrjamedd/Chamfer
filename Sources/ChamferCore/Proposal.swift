import Foundation

/// A note, described well enough to list and inspect without reading the file.
public struct NoteSummary: Sendable, Identifiable, Equatable, Codable {
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
public struct Hunk: Sendable, Identifiable, Equatable, Codable {
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

public enum ProposalState: Sendable, Equatable, Codable {
    case pending
    case accepted
    case rejected
    /// Being generated again from the current source text.
    case regenerating
    /// Generation itself failed. The note was never touched.
    case failed(RewriteFailure)

    public var isPending: Bool { self == .pending }

    public var isActionable: Bool {
        switch self {
        case .pending, .regenerating, .failed: true
        case .accepted, .rejected: false
        }
    }

    public var failure: RewriteFailure? {
        if case let .failed(failure) = self { return failure }
        return nil
    }
}

/// Why an Automatic vault was prevented from writing a plausible model result.
/// Malformed results are failures instead; this is reserved for readable edits
/// whose breadth makes human judgement safer than automatic application.
/// Why a rewrite has to be looked at by a person, whatever the vault asked for.
///
/// These used to be the only alternative to a rewrite being *discarded*. A
/// rewrite that failed a check produced nothing at all: no diff, no queue
/// entry, nothing to accept or reject, and a note that stayed exactly as
/// misspelled as it was. That is the most expensive answer available — the work
/// was done, the model was right about most of it, and the user was told
/// nothing except a sentence about a protected region.
///
/// Now a check that fails demotes rather than discards. Anything Chamfer is
/// unsure of arrives in the review queue with its reason attached, and the only
/// thing a failed check costs is the right to apply itself silently.
public enum RewriteReviewRecommendation: String, Sendable, Equatable, Codable {
    case broaderThanExpectedForMode
    /// One passage's answer was rejected and its original kept, so the rewrite
    /// is real but incomplete.
    case partOfTheNoteWasKeptAsItWas
    /// The finished text failed the deterministic gate — a preserved structure
    /// moved, or the length changed more than the mode can explain.
    case structureChangedUnexpectedly

    public func explanation(for mode: RewriteMode) -> String {
        switch self {
        case .broaderThanExpectedForMode:
            "Chamfer moved this rewrite from Automatic to Review because its changes were broader than expected for \(mode.title)."
        case .partOfTheNoteWasKeptAsItWas:
            "Part of this note came back from the model in a state Chamfer would not use, so that part was left exactly as you wrote it. The rest of the rewrite is here to judge."
        case .structureChangedUnexpectedly:
            "This rewrite changed the note's structure in a way \(mode.title) does not explain. It is shown rather than applied so you can see what moved."
        }
    }
}

/// A rewrite waiting for judgement. Nothing here has been written to disk.
///
/// `Codable` because the scope requires a crash to lose neither applied nor
/// pending state: the queue is written back to disk whenever it changes, so a
/// rewrite generated at 3am is still waiting after a reboot.
public struct Proposal: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let note: NoteSummary
    public let hunks: [Hunk]
    /// Exact source and candidate text. Optional only for decoding queues made
    /// by older builds; every new proposal supplies both.
    public let baseText: String?
    public let proposedText: String?
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
    public let retryCount: Int
    public let automaticReviewReason: RewriteReviewRecommendation?
    public var state: ProposalState

    public init(
        id: UUID = UUID(),
        note: NoteSummary,
        hunks: [Hunk],
        baseText: String? = nil,
        proposedText: String? = nil,
        createdAt: Date,
        sourceModifiedAt: Date? = nil,
        mode: RewriteMode = .fullCleanup,
        modelID: String = RewritePolicy.localModelIdentifier,
        vaultID: UUID? = nil,
        retryCount: Int = 0,
        automaticReviewReason: RewriteReviewRecommendation? = nil,
        state: ProposalState = .pending
    ) {
        self.id = id
        self.note = note
        self.hunks = hunks
        self.baseText = baseText
        self.proposedText = proposedText
        self.createdAt = createdAt
        // Defaults to the note's own modification date, which is what it was
        // at the moment the rewrite was generated.
        self.sourceModifiedAt = sourceModifiedAt ?? note.modifiedAt
        self.mode = mode
        self.modelID = modelID
        self.vaultID = vaultID
        self.retryCount = retryCount
        self.automaticReviewReason = automaticReviewReason
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
public struct CleanupRecord: Sendable, Identifiable, Equatable, Codable {
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
