import Foundation

// MARK: - Mode

/// The five rewrite modes of version 1.0.
///
/// Each is a promise about what the model is allowed to touch, which is why
/// they are an enum rather than a set of independent switches: "spelling only"
/// means grammar and structure are off limits, and a set could not say that.
public enum RewriteMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case spelling
    case grammar
    case formatting
    case clarity
    case fullCleanup

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spelling: "Spelling only"
        case .grammar: "Grammar only"
        case .formatting: "Formatting only"
        case .clarity: "Clarity only"
        case .fullCleanup: "Full cleanup"
        }
    }

    /// One line, written for the settings list. Says what is left alone as
    /// well as what changes — the restraint is the point of the mode.
    public var summary: String {
        switch self {
        case .spelling:
            "Misspellings, nothing else. Grammar, wording and structure are left as they are."
        case .grammar:
            "Grammatical errors, keeping your wording and formatting as close to intact as possible."
        case .formatting:
            "Spacing, headings and lists. The prose itself is not rewritten."
        case .clarity:
            "Awkward phrasing and hard sentences, without a full cleanup unless clarity needs it."
        case .fullCleanup:
            "Spelling, grammar, formatting and clarity together."
        }
    }

    public var symbol: String {
        switch self {
        case .spelling: "textformat.abc"
        case .grammar: "text.badge.checkmark"
        case .formatting: "text.alignleft"
        case .clarity: "sparkles"
        case .fullCleanup: "wand.and.stars"
        }
    }
}

// MARK: - Application

/// Whether a finished rewrite lands on disk or waits to be judged.
///
/// Neither case is a default. A vault stores nil until the user explicitly
/// chooses one, and nothing may promote itself to `automatic`.
public enum RewriteApplication: String, Sendable, Codable, CaseIterable, Identifiable {
    case review
    case automatic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .review: "Queue for review"
        case .automatic: "Apply automatically"
        }
    }

    public var detail: String {
        switch self {
        case .review: "The note is untouched until you accept the rewrite."
        case .automatic: "The rewrite is written to the note. A snapshot is taken first."
        }
    }
}

/// The final destination after the user's application choice and the
/// deterministic safety recommendation are considered together.
public enum RewriteApplicationDecision: Sendable, Equatable {
    case queueForReview(automaticReason: RewriteReviewRecommendation?)
    case applyAutomatically

    public static func decide(
        requested: RewriteApplication,
        recommendation: RewriteReviewRecommendation?
    ) -> RewriteApplicationDecision {
        switch (requested, recommendation) {
        case (.review, _):
            .queueForReview(automaticReason: nil)
        case let (.automatic, reason?):
            .queueForReview(automaticReason: reason)
        case (.automatic, nil):
            .applyAutomatically
        }
    }
}

// MARK: - Preservation

/// The Markdown structures a rewrite may not disturb.
///
/// An option set rather than a struct of booleans because the interesting
/// operations are set operations: which structures a vault protects and which
/// of them a failed rewrite reports as violated.
public struct MarkdownStructure: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let headings = MarkdownStructure(rawValue: 1 << 0)
    public static let lists = MarkdownStructure(rawValue: 1 << 1)
    public static let links = MarkdownStructure(rawValue: 1 << 2)
    public static let images = MarkdownStructure(rawValue: 1 << 3)
    public static let embeds = MarkdownStructure(rawValue: 1 << 4)
    public static let codeBlocks = MarkdownStructure(rawValue: 1 << 5)
    public static let frontMatter = MarkdownStructure(rawValue: 1 << 6)
    public static let taskCheckboxes = MarkdownStructure(rawValue: 1 << 7)
    public static let metadata = MarkdownStructure(rawValue: 1 << 8)

    public static let all: MarkdownStructure = [
        .headings, .lists, .links, .images, .embeds,
        .codeBlocks, .frontMatter, .taskCheckboxes, .metadata
    ]

    /// The named non-prose preset offered by an explicit button in the vault
    /// editor. A fresh vault still stores nil; this value is never selected on
    /// the user's behalf.
    ///
    /// Not `all`: formatting mode exists to reflow headings and lists, so
    /// protecting those by default would make one of the five modes a no-op.
    /// It protects parts that are addresses and payloads rather than prose.
    public static let standard: MarkdownStructure = [
        .links, .images, .embeds, .codeBlocks, .frontMatter, .taskCheckboxes, .metadata
    ]

    public static let ordered: [(structure: MarkdownStructure, title: String)] = [
        (.headings, "Headings"),
        (.lists, "Lists"),
        (.links, "Links"),
        (.images, "Images"),
        (.embeds, "Embedded files"),
        (.codeBlocks, "Code blocks"),
        (.frontMatter, "Front matter"),
        (.taskCheckboxes, "Task checkboxes"),
        (.metadata, "Metadata")
    ]

    public var titles: [String] {
        Self.ordered.filter { contains($0.structure) }.map(\.title)
    }
}

// MARK: - Schedule

/// How often a vault is swept, independent of anything the user is typing.
public enum SweepSchedule: Sendable, Codable, Equatable, Hashable {
    /// Notes are only ever processed after they go quiet. No sweep.
    case never
    case everyHours(Int)
    /// A single sweep each day, at the given hour on a 24-hour clock.
    case dailyAt(hour: Int)

    public var title: String {
        switch self {
        case .never: "Only after a note goes quiet"
        case let .everyHours(hours): hours == 1 ? "Every hour" : "Every \(hours) hours"
        case let .dailyAt(hour): "Every day at \(Self.clock(hour))"
        }
    }

    public static let choices: [SweepSchedule] = [
        .never, .everyHours(1), .everyHours(6), .everyHours(24), .dailyAt(hour: 3)
    ]

    private static func clock(_ hour: Int) -> String {
        let wrapped = ((hour % 24) + 24) % 24
        let suffix = wrapped < 12 ? "am" : "pm"
        let display = wrapped % 12 == 0 ? 12 : wrapped % 12
        return "\(display)\(suffix)"
    }
}

// MARK: - Run trigger

/// The single event that starts work for a vault.
///
/// These are alternatives, never two timers layered together. An inactivity
/// vault reacts to an edited note after it has gone quiet. A scheduled vault
/// ignores edit-settling events and processes its eligible notes only when its
/// recurring sweep is due.
public enum VaultRunTrigger: String, Sendable, Codable, CaseIterable, Identifiable {
    case inactivity
    case schedule

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inactivity: "After inactivity"
        case .schedule: "On a schedule"
        }
    }

    public var detail: String {
        switch self {
        case .inactivity:
            "Run an edited note once after it has stayed quiet. No scheduled sweep runs."
        case .schedule:
            "Sweep eligible notes at the chosen interval. Edits do not start an inactivity timer."
        }
    }
}

// MARK: - Policy

/// The choices a person has made for one vault.
///
/// Every field is optional on purpose. A connected vault may be configured a
/// row at a time and that partial intent has to survive a relaunch without the
/// rest of the rows quietly acquiring values. Only `resolve(modelID:)` may
/// turn this into something the processor can use, and it refuses until every
/// required vault choice and the app-wide model choice exist.
public struct VaultConfiguration: Sendable, Equatable, Codable {
    public var mode: RewriteMode?
    public var application: RewriteApplication?
    public var runTrigger: VaultRunTrigger?
    public var inactivityDelay: TimeInterval?
    public var sweep: SweepSchedule?
    public var preserved: MarkdownStructure?
    /// Whether a lower-case word that should be capitalised — or the reverse —
    /// counts as something to fix.
    ///
    /// A choice rather than a rule because both answers are defensible and the
    /// right one is about the person's notes, not about English. "friday" and
    /// "i think" are mistakes in a document somebody else will read, and how
    /// half the world types in a note only they will open. Chamfer cannot tell
    /// which kind of vault it is looking at, so it asks.
    ///
    /// Unset means on: it is part of spelling for most people, and it is the
    /// answer that surprises fewest of them.
    public var fixesCapitalisation: Bool?

    public init(
        mode: RewriteMode? = nil,
        application: RewriteApplication? = nil,
        runTrigger: VaultRunTrigger? = nil,
        inactivityDelay: TimeInterval? = nil,
        sweep: SweepSchedule? = nil,
        preserved: MarkdownStructure? = nil,
        fixesCapitalisation: Bool? = nil
    ) {
        self.mode = mode
        self.application = application
        self.runTrigger = runTrigger
        self.inactivityDelay = inactivityDelay
        self.sweep = sweep
        self.preserved = preserved
        self.fixesCapitalisation = fixesCapitalisation
    }

    /// Migration bridge for state written before partial configuration was
    /// representable. Every legacy policy was complete by construction.
    public init(resolved policy: RewritePolicy) {
        mode = policy.mode
        application = policy.application
        runTrigger = policy.runTrigger
        inactivityDelay = policy.inactivityDelay
        sweep = policy.sweep
        preserved = policy.preserved
        fixesCapitalisation = policy.fixesCapitalisation
    }

    /// Missing in the same order as the editor presents the rows.
    public var missingFields: [PolicyField] {
        var fields: [PolicyField] = []
        if mode == nil { fields.append(.mode) }
        if application == nil { fields.append(.application) }
        switch runTrigger {
        case nil:
            fields.append(.runTrigger)
        case .inactivity:
            if inactivityDelay == nil { fields.append(.inactivityDelay) }
        case .schedule:
            if sweep == nil || sweep == .never { fields.append(.sweep) }
        }
        if preserved == nil { fields.append(.preserved) }
        return fields
    }

    public var isComplete: Bool { missingFields.isEmpty }

    public func resolve(modelID: String?) -> RewritePolicy? {
        guard let mode,
              let application,
              let runTrigger,
              let preserved,
              let modelID,
              !modelID.isEmpty
        else { return nil }

        let resolvedDelay: TimeInterval
        let resolvedSweep: SweepSchedule
        switch runTrigger {
        case .inactivity:
            guard let inactivityDelay else { return nil }
            resolvedDelay = inactivityDelay
            resolvedSweep = .never
        case .schedule:
            guard let sweep, sweep != .never else { return nil }
            resolvedDelay = 0
            resolvedSweep = sweep
        }

        return RewritePolicy(
            mode: mode,
            application: application,
            runTrigger: runTrigger,
            inactivityDelay: resolvedDelay,
            sweep: resolvedSweep,
            preserved: preserved,
            // Deliberately absent from `missingFields`: a vault configured
            // before this option existed keeps working, and gets the answer
            // most people mean by "spelling".
            fixesCapitalisation: fixesCapitalisation ?? RewritePolicy.capitalisationDefault,
            modelID: modelID
        )
    }
}

/// Everything that decides how one note gets rewritten, with no gaps.
///
/// This is the resolved shape handed to the processor. Every field has a
/// value, so nothing downstream decides what a missing setting means.
public struct RewritePolicy: Sendable, Equatable, Codable {
    public var mode: RewriteMode
    public var application: RewriteApplication
    public var runTrigger: VaultRunTrigger
    /// How long a note must go unchanged before it is eligible.
    public var inactivityDelay: TimeInterval
    public var sweep: SweepSchedule
    public var preserved: MarkdownStructure
    /// Whether case corrections are in scope. See `VaultConfiguration`.
    public var fixesCapitalisation: Bool
    /// Identifier of the chosen model, as `ChamferRewrite` names them.
    public var modelID: String

    /// What a vault gets when it has never been asked.
    public static let capitalisationDefault = true

    /// What a vault stores for "the model on this Mac".
    ///
    /// Deliberately not a model name. Which local model Chamfer downloads is
    /// decided by the hardware, so a policy naming one would go stale the
    /// moment the vault opened on a different Mac — and a stale name means a
    /// second multi-gigabyte download of a model nobody chose. `ChamferRewrite`
    /// resolves this to the device's own recommendation.
    public static let localModelIdentifier = "local.ollama"

    public init(
        mode: RewriteMode,
        application: RewriteApplication,
        runTrigger: VaultRunTrigger? = nil,
        inactivityDelay: TimeInterval,
        sweep: SweepSchedule,
        preserved: MarkdownStructure,
        fixesCapitalisation: Bool = RewritePolicy.capitalisationDefault,
        modelID: String
    ) {
        self.mode = mode
        self.application = application
        self.runTrigger = runTrigger ?? (sweep == .never ? .inactivity : .schedule)
        self.inactivityDelay = inactivityDelay
        self.sweep = sweep
        self.preserved = preserved
        self.fixesCapitalisation = fixesCapitalisation
        self.modelID = modelID
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case application
        case runTrigger
        case inactivityDelay
        case sweep
        case preserved
        case fixesCapitalisation
        case modelID
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(RewriteMode.self, forKey: .mode)
        application = try values.decode(RewriteApplication.self, forKey: .application)
        inactivityDelay = try values.decode(TimeInterval.self, forKey: .inactivityDelay)
        sweep = try values.decode(SweepSchedule.self, forKey: .sweep)
        runTrigger = try values.decodeIfPresent(VaultRunTrigger.self, forKey: .runTrigger)
            ?? (sweep == .never ? .inactivity : .schedule)
        preserved = try values.decode(MarkdownStructure.self, forKey: .preserved)
        // Absent in state written before the option existed.
        fixesCapitalisation = try values.decodeIfPresent(
            Bool.self,
            forKey: .fixesCapitalisation
        ) ?? Self.capitalisationDefault
        modelID = try values.decode(String.self, forKey: .modelID)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(mode, forKey: .mode)
        try values.encode(application, forKey: .application)
        try values.encode(runTrigger, forKey: .runTrigger)
        try values.encode(inactivityDelay, forKey: .inactivityDelay)
        try values.encode(sweep, forKey: .sweep)
        try values.encode(preserved, forKey: .preserved)
        try values.encode(fixesCapitalisation, forKey: .fixesCapitalisation)
        try values.encode(modelID, forKey: .modelID)
    }

    public var inactivityMinutes: Int {
        max(1, Int((inactivityDelay / 60).rounded()))
    }
}

/// One setting a policy is made of.
///
/// Kept only as a source of titles for the rows that edit them. The override
/// machinery that used to live here — `PolicyOverride`, `PolicyResolver`,
/// `ResolvedPolicy` — is gone with the hierarchy it served: a vault now holds
/// a complete policy or none at all, so there is nothing left to resolve.
public enum PolicyField: String, Sendable, CaseIterable, Identifiable, Codable {
    case mode
    case application
    case runTrigger
    case inactivityDelay
    case sweep
    case preserved
    case fixesCapitalisation
    case model

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mode: "Rewrite mode"
        case .application: "Applying rewrites"
        case .runTrigger: "When it runs"
        case .inactivityDelay: "Inactivity delay"
        case .sweep: "Schedule"
        case .preserved: "Markdown preservation"
        case .fixesCapitalisation: "Capitalisation"
        case .model: "Model"
        }
    }
}
