import Foundation

public enum LocalModelFit: String, Equatable, Sendable {
    case recommended
    case usable
    case unusable

    public var label: String {
        switch self {
        case .recommended: "USABLE · RECOMMENDED"
        case .usable: "USABLE · NOT RECOMMENDED"
        case .unusable: "UNUSABLE"
        }
    }
}

public enum AppleModelComparison: Equatable, Sendable {
    case faster
    case potentiallyStronger
    case noClearAdvantage

    public var label: String {
        switch self {
        case .faster: "Expected faster than Apple"
        case .potentiallyStronger: "Potentially stronger quality than Apple"
        case .noClearAdvantage: "No clear advantage over Apple"
        }
    }
}

public struct LocalModelDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let downloadSize: String
    public let minimumMemoryGB: Int
    public let recommendedMemoryGB: Int
    public let comparison: AppleModelComparison

    public init(
        id: String,
        displayName: String,
        downloadSize: String,
        minimumMemoryGB: Int,
        recommendedMemoryGB: Int,
        comparison: AppleModelComparison
    ) {
        self.id = id
        self.displayName = displayName
        self.downloadSize = downloadSize
        self.minimumMemoryGB = minimumMemoryGB
        self.recommendedMemoryGB = recommendedMemoryGB
        self.comparison = comparison
    }
}

public struct LocalModelAssessment: Equatable, Sendable {
    public let fit: LocalModelFit
    public let explanation: String
}

public enum LocalModelCatalog {
    public static let standard: [LocalModelDescriptor] = [
        .init(
            id: "qwen3.5:0.8b",
            displayName: "Qwen3.5 0.8B",
            downloadSize: "1.0 GB",
            minimumMemoryGB: 4,
            recommendedMemoryGB: 4,
            comparison: .faster
        ),
        .init(
            id: "qwen3.5:2b",
            displayName: "Qwen3.5 2B",
            downloadSize: "2.7 GB",
            minimumMemoryGB: 6,
            recommendedMemoryGB: 8,
            comparison: .faster
        ),
        .init(
            id: "qwen3.5:4b",
            displayName: "Qwen3.5 4B",
            downloadSize: "3.4 GB",
            minimumMemoryGB: 8,
            recommendedMemoryGB: 12,
            comparison: .noClearAdvantage
        ),
        .init(
            id: "qwen3.5:9b",
            displayName: "Qwen3.5 9B",
            downloadSize: "6.6 GB",
            minimumMemoryGB: 12,
            recommendedMemoryGB: 16,
            comparison: .potentiallyStronger
        ),
        .init(
            id: "gpt-oss:20b",
            displayName: "GPT-OSS 20B",
            downloadSize: "14 GB",
            minimumMemoryGB: 16,
            recommendedMemoryGB: 24,
            comparison: .potentiallyStronger
        )
    ]

    public static func assessment(
        for model: LocalModelDescriptor,
        physicalMemory: UInt64
    ) -> LocalModelAssessment {
        let memoryGB = Int(physicalMemory / 1_073_741_824)
        guard memoryGB >= model.minimumMemoryGB else {
            return LocalModelAssessment(
                fit: .unusable,
                explanation: "Needs at least \(model.minimumMemoryGB) GB memory"
            )
        }

        let recommended = standard
            .filter { memoryGB >= $0.recommendedMemoryGB }
            .max { $0.recommendedMemoryGB < $1.recommendedMemoryGB }

        if recommended?.id == model.id {
            return LocalModelAssessment(
                fit: .recommended,
                explanation: "Best fit for this Mac"
            )
        }
        return LocalModelAssessment(
            fit: .usable,
            explanation: "Usable, but not the best fit"
        )
    }
}
