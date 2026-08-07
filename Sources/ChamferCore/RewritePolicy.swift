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
/// `review` is the default everywhere, and nothing may promote itself to
/// `automatic`: the scope requires the user to have said so for the exact
/// vault or folder in question.
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

// MARK: - Preservation

/// The Markdown structures a rewrite may not disturb.
///
/// An option set rather than a struct of booleans because the interesting
/// operations are set operations: what a folder adds to its vault's
/// protections, and which of them a failed rewrite reports as violated.
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

    /// What is protected before the user changes anything.
    ///
    /// Not `all`: formatting mode exists to reflow headings and lists, so
    /// protecting those by default would make one of the five modes a no-op.
    /// What is on by default is everything a rewrite has no business editing —
    /// the parts that are addresses and payloads rather than prose.
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

// MARK: - Policy

/// Everything that decides how one note gets rewritten, with no gaps.
///
/// This is the resolved shape — what the processor is handed after global,
/// vault and folder settings have been layered. Every field has a value, so
/// nothing downstream has to decide what a missing setting means.
public struct RewritePolicy: Sendable, Equatable, Codable {
    public var mode: RewriteMode
    public var application: RewriteApplication
    /// How long a note must go unchanged before it is eligible.
    public var inactivityDelay: TimeInterval
    public var sweep: SweepSchedule
    public var preserved: MarkdownStructure
    /// Identifier of the chosen model, as `ChamferRewrite` names them.
    public var modelID: String
    /// Tried only when the chosen model fails, and only when set.
    public var fallbackModelID: String?

    public init(
        mode: RewriteMode = .fullCleanup,
        application: RewriteApplication = .review,
        inactivityDelay: TimeInterval = 600,
        sweep: SweepSchedule = .never,
        preserved: MarkdownStructure = .standard,
        modelID: String = "apple.foundation",
        fallbackModelID: String? = nil
    ) {
        self.mode = mode
        self.application = application
        self.inactivityDelay = inactivityDelay
        self.sweep = sweep
        self.preserved = preserved
        self.modelID = modelID
        self.fallbackModelID = fallbackModelID
    }

    /// What a fresh install does: full cleanup, queued for review, ten minutes
    /// after you stop typing. Review rather than automatic is the important
    /// half — nothing writes to a note until the user has asked it to.
    public static let standard = RewritePolicy()

    public var inactivityMinutes: Int {
        max(1, Int((inactivityDelay / 60).rounded()))
    }
}

/// One setting a policy is made of.
///
/// Exists so the interface can say *which* settings a vault has taken into its
/// own hands, and show only those. Without it the Vaults page would have to
/// render the entire policy at every level and let the user hunt for the
/// differences.
public enum PolicyField: String, Sendable, CaseIterable, Identifiable, Codable {
    case mode
    case application
    case inactivityDelay
    case sweep
    case preserved
    case model
    case fallbackModel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mode: "Rewrite mode"
        case .application: "Applying rewrites"
        case .inactivityDelay: "Inactivity delay"
        case .sweep: "Schedule"
        case .preserved: "Markdown preservation"
        case .model: "Model"
        case .fallbackModel: "Fallback model"
        }
    }
}

/// A partial policy. Every field is optional, and `nil` means "inherit".
///
/// Vaults and folders hold one of these rather than a whole policy, so a
/// setting changed globally reaches everything that has not deliberately
/// broken away from it.
public struct PolicyOverride: Sendable, Equatable, Codable {
    public var mode: RewriteMode?
    public var application: RewriteApplication?
    public var inactivityDelay: TimeInterval?
    public var sweep: SweepSchedule?
    public var preserved: MarkdownStructure?
    public var modelID: String?
    /// Double-optional: the outer says whether this level has an opinion, the
    /// inner says whether that opinion is "no fallback at all". Collapsing
    /// them would make turning a fallback off indistinguishable from
    /// inheriting one.
    public var fallbackModelID: String??

    public init(
        mode: RewriteMode? = nil,
        application: RewriteApplication? = nil,
        inactivityDelay: TimeInterval? = nil,
        sweep: SweepSchedule? = nil,
        preserved: MarkdownStructure? = nil,
        modelID: String? = nil,
        fallbackModelID: String?? = nil
    ) {
        self.mode = mode
        self.application = application
        self.inactivityDelay = inactivityDelay
        self.sweep = sweep
        self.preserved = preserved
        self.modelID = modelID
        self.fallbackModelID = fallbackModelID
    }

    public static let inherited = PolicyOverride()

    /// Which settings this level has an opinion about.
    public var fields: Set<PolicyField> {
        var fields: Set<PolicyField> = []
        if mode != nil { fields.insert(.mode) }
        if application != nil { fields.insert(.application) }
        if inactivityDelay != nil { fields.insert(.inactivityDelay) }
        if sweep != nil { fields.insert(.sweep) }
        if preserved != nil { fields.insert(.preserved) }
        if modelID != nil { fields.insert(.model) }
        if fallbackModelID != nil { fields.insert(.fallbackModel) }
        return fields
    }

    public var isInherited: Bool { fields.isEmpty }

    /// Drops this level's opinion about one setting, so it inherits again.
    public mutating func clear(_ field: PolicyField) {
        switch field {
        case .mode: mode = nil
        case .application: application = nil
        case .inactivityDelay: inactivityDelay = nil
        case .sweep: sweep = nil
        case .preserved: preserved = nil
        case .model: modelID = nil
        case .fallbackModel: fallbackModelID = nil
        }
    }
}

// MARK: - Resolution

/// A policy plus the story of where each of its settings came from.
public struct ResolvedPolicy: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case global
        case vault
        case folder

        public var title: String {
            switch self {
            case .global: "your defaults"
            case .vault: "this vault"
            case .folder: "this folder"
            }
        }
    }

    public let policy: RewritePolicy
    /// Where each field's winning value was set. Fields resolved from global
    /// defaults are present too, so this is always complete.
    public let sources: [PolicyField: Source]

    public init(policy: RewritePolicy, sources: [PolicyField: Source]) {
        self.policy = policy
        self.sources = sources
    }

    public func source(of field: PolicyField) -> Source {
        sources[field] ?? .global
    }

    /// The fields that are not simply inherited from global defaults — what
    /// the Vaults page shows before you ask to see everything.
    public var overriddenFields: [PolicyField] {
        PolicyField.allCases.filter { source(of: $0) != .global }
    }
}

/// Layers global defaults, a vault's override and a folder's override into one
/// complete policy. More specific always wins.
public enum PolicyResolver {
    public static func resolve(
        global: RewritePolicy,
        vault: PolicyOverride = .inherited,
        folder: PolicyOverride = .inherited
    ) -> ResolvedPolicy {
        var policy = global
        var sources: [PolicyField: ResolvedPolicy.Source] = [:]

        // Applied vault-first so the folder pass overwrites it, which is the
        // whole hierarchy in two lines.
        for (override, source) in [
            (vault, ResolvedPolicy.Source.vault),
            (folder, ResolvedPolicy.Source.folder)
        ] {
            if let mode = override.mode {
                policy.mode = mode
                sources[.mode] = source
            }
            if let application = override.application {
                policy.application = application
                sources[.application] = source
            }
            if let delay = override.inactivityDelay {
                policy.inactivityDelay = delay
                sources[.inactivityDelay] = source
            }
            if let sweep = override.sweep {
                policy.sweep = sweep
                sources[.sweep] = source
            }
            if let preserved = override.preserved {
                policy.preserved = preserved
                sources[.preserved] = source
            }
            if let modelID = override.modelID {
                policy.modelID = modelID
                sources[.model] = source
            }
            if let fallback = override.fallbackModelID {
                policy.fallbackModelID = fallback
                sources[.fallbackModel] = source
            }
        }

        for field in PolicyField.allCases where sources[field] == nil {
            sources[field] = .global
        }

        return ResolvedPolicy(policy: policy, sources: sources)
    }
}
