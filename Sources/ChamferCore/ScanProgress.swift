import Foundation

/// How far through a vault a sweep has got.
///
/// Reported rather than inferred, so a vault row can say "240 of 4,000" instead
/// of "not swept yet" for the several seconds a large vault takes to walk.
///
/// Lives in `ChamferCore` rather than beside the scanner that produces it
/// because the interface has to render it, and `ChamferUI` has no business
/// depending on the filesystem layer to describe a pair of integers.
public struct ScanProgress: Sendable, Equatable {
    public let vaultID: UUID
    public let completed: Int
    public let total: Int

    public init(vaultID: UUID, completed: Int, total: Int) {
        self.vaultID = vaultID
        self.completed = completed
        self.total = total
    }

    /// Zero when there is nothing to do, so a caller can divide without
    /// checking. A sweep of an empty vault is finished, not stuck at nothing.
    public var fraction: Double {
        guard total > 0 else { return 1 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    public var isFinished: Bool { completed >= total }
}
