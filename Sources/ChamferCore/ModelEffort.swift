import Foundation

/// How much inference work Chamfer spends on one note.
///
/// Three named modes rather than a panel of inference parameters. A person
/// tuning their notes app should be choosing between *outcomes* — quick, even,
/// thorough — not between a context length and a sampling temperature. Every
/// low-level consequence is derived from the mode in exactly one place
/// (`ModelEffortProfile`), so the modes cannot drift into being cosmetic.
public enum ModelEffort: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    case base
    case balanced
    case max

    public var id: String { rawValue }

    /// What the app opens on. Balanced is the only defensible default: base
    /// gives up the review pass that catches a model's worst answers, and max
    /// costs enough time that nobody should be opted into it silently.
    public static let standard = ModelEffort.balanced

    public var title: String {
        switch self {
        case .base: "Base"
        case .balanced: "Balanced"
        case .max: "Max"
        }
    }

    /// Three words, set in the dashboard beside the title.
    public var tagline: String {
        switch self {
        case .base: "Fast and light"
        case .balanced: "The everyday setting"
        case .max: "Slow and careful"
        }
    }

    /// One sentence saying what is actually traded away. Each names the thing
    /// it gives up, because a mode that only advertises its advantage is a
    /// marketing label rather than a choice.
    public var summary: String {
        switch self {
        case .base:
            "One pass, small slices of the note, minimal memory. The quickest way through a vault, and the most likely to leave something behind."
        case .balanced:
            "Larger slices with their neighbours for context, then a second pass that checks the rewrite against the original before it is kept."
        case .max:
            "Whole sections at a time, deliberate reasoning, and two checking passes. The most accurate, and noticeably the slowest."
        }
    }
}

/// One readout on the configuration panel.
///
/// `level` is deliberately relative rather than a measurement: nobody can
/// promise tokens per second on an unknown Mac, and a fabricated number would
/// be worse than an honest comparison between the three modes.
public struct ModelEffortReadout: Sendable, Equatable, Identifiable {
    public enum Axis: String, Sendable, Equatable, CaseIterable {
        case speed
        case accuracy
        case time
        case impact

        public var title: String {
            switch self {
            case .speed: "Speed"
            case .accuracy: "Accuracy"
            case .time: "Time per note"
            case .impact: "System impact"
            }
        }

        /// Whether a taller bar is the desirable end of this axis. Time and
        /// system impact read the other way, and drawing all four in the same
        /// direction would say max is worse at two things it is not.
        public var higherIsBetter: Bool {
            switch self {
            case .speed, .accuracy: true
            case .time, .impact: false
            }
        }
    }

    public let axis: Axis
    /// 0…1 across the three modes, not an absolute rate.
    public let level: Double
    /// The value in words, for the row and for VoiceOver.
    public let caption: String

    public var id: String { axis.rawValue }

    public init(axis: Axis, level: Double, caption: String) {
        self.axis = axis
        self.level = level
        self.caption = caption
    }
}

/// Everything a mode actually changes at runtime.
///
/// The single source of truth for the Base/Balanced/Max tradeoff. The pipeline
/// reads it for segmentation and passes, the Ollama client reads it for context
/// and generation budget, and the dashboard reads it for the tradeoff readout —
/// so what the panel promises and what the model is asked to do cannot disagree.
public struct ModelEffortProfile: Sendable, Equatable {
    public let effort: ModelEffort

    /// Characters per document segment. Segments still break only on headings
    /// and blank lines, so this is a target rather than a hard cut.
    public let segmentTargetCharacters: Int

    /// Characters per model request inside a segment. Smaller units fail
    /// smaller: a discarded answer costs one paragraph rather than one section.
    public let unitTargetCharacters: Int

    /// `num_ctx`. Sent explicitly because Ollama's own default is small enough
    /// to silently truncate a long section's prompt, which reads as the model
    /// ignoring its instructions rather than as a configuration problem.
    public let contextTokens: Int

    /// The ceiling on one response, before the request's own length-derived
    /// budget is applied. Both are enforced; the smaller wins.
    public let responseTokenCeiling: Int

    /// How many times a candidate is checked against its original by the model
    /// before it is accepted. Zero means the deterministic guards are the only
    /// check, which is the Base bargain.
    public let reviewPasses: Int

    /// Whether the neighbouring units are supplied as read-only context.
    public let includesNeighbourContext: Bool

    /// Whether the model may think before answering, where the backend
    /// supports it. Off below max: on a small hybrid-reasoning model the
    /// thinking is slower than the edit it is deciding on.
    public let allowsDeliberation: Bool

    public init(
        effort: ModelEffort,
        segmentTargetCharacters: Int,
        unitTargetCharacters: Int,
        contextTokens: Int,
        responseTokenCeiling: Int,
        reviewPasses: Int,
        includesNeighbourContext: Bool,
        allowsDeliberation: Bool
    ) {
        self.effort = effort
        self.segmentTargetCharacters = segmentTargetCharacters
        self.unitTargetCharacters = unitTargetCharacters
        self.contextTokens = contextTokens
        self.responseTokenCeiling = responseTokenCeiling
        self.reviewPasses = reviewPasses
        self.includesNeighbourContext = includesNeighbourContext
        self.allowsDeliberation = allowsDeliberation
    }

    /// Total model calls for one unit: the rewrite, plus its checks.
    public var requestsPerUnit: Int { 1 + reviewPasses }

    public static func profile(for effort: ModelEffort) -> ModelEffortProfile {
        switch effort {
        case .base:
            ModelEffortProfile(
                effort: .base,
                segmentTargetCharacters: 2_400,
                unitTargetCharacters: 1_200,
                contextTokens: 8_192,
                responseTokenCeiling: 1_024,
                reviewPasses: 0,
                includesNeighbourContext: false,
                allowsDeliberation: false
            )
        case .balanced:
            ModelEffortProfile(
                effort: .balanced,
                segmentTargetCharacters: 4_000,
                unitTargetCharacters: 2_200,
                contextTokens: 16_384,
                responseTokenCeiling: 2_048,
                reviewPasses: 1,
                includesNeighbourContext: true,
                allowsDeliberation: false
            )
        case .max:
            ModelEffortProfile(
                effort: .max,
                segmentTargetCharacters: 6_000,
                unitTargetCharacters: 3_400,
                contextTokens: 32_768,
                responseTokenCeiling: 4_096,
                reviewPasses: 2,
                includesNeighbourContext: true,
                allowsDeliberation: true
            )
        }
    }

    /// The four axes, in the order the panel draws them.
    public var readouts: [ModelEffortReadout] {
        switch effort {
        case .base:
            [
                .init(axis: .speed, level: 1.00, caption: "Fastest"),
                .init(axis: .accuracy, level: 0.55, caption: "Good"),
                .init(axis: .time, level: 0.20, caption: "Shortest"),
                .init(axis: .impact, level: 0.30, caption: "Light")
            ]
        case .balanced:
            [
                .init(axis: .speed, level: 0.62, caption: "Quick"),
                .init(axis: .accuracy, level: 0.80, caption: "High"),
                .init(axis: .time, level: 0.52, caption: "Moderate"),
                .init(axis: .impact, level: 0.58, caption: "Moderate")
            ]
        case .max:
            [
                .init(axis: .speed, level: 0.28, caption: "Slowest"),
                .init(axis: .accuracy, level: 1.00, caption: "Highest"),
                .init(axis: .time, level: 1.00, caption: "Longest"),
                .init(axis: .impact, level: 0.94, caption: "Heavy")
            ]
        }
    }

    /// The one line under the readout that says what the mode literally does,
    /// in the app's own terms rather than in inference vocabulary.
    public var mechanics: String {
        let passes = switch reviewPasses {
        case 0: "no checking pass"
        case 1: "one checking pass"
        default: "\(reviewPasses) checking passes"
        }
        let context = includesNeighbourContext
            ? "neighbouring text supplied"
            : "each slice read alone"
        return "\(unitTargetCharacters.formattedThousands) characters per request · \(passes) · \(context)"
    }
}

public extension ModelEffort {
    var profile: ModelEffortProfile { ModelEffortProfile.profile(for: self) }
}

private extension Int {
    /// A thousands separator without pulling a formatter into a value that is
    /// rendered on every frame of the mode transition.
    var formattedThousands: String {
        guard self >= 1_000 else { return String(self) }
        let digits = String(self)
        var result = ""
        for (offset, character) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return result
    }
}
