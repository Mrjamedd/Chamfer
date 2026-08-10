import Foundation

/// What this Mac can actually run.
///
/// A value rather than a set of live lookups so the selection below is a pure
/// function of the hardware: the same profile always chooses the same model, in
/// the app and in a test, with no way for a probe to answer differently on the
/// second call.
public struct DeviceProfile: Sendable, Equatable {
    public let physicalMemoryBytes: UInt64
    /// Performance cores, where the platform reports them separately.
    /// Generation speed tracks these rather than the total.
    public let performanceCoreCount: Int
    public let totalCoreCount: Int
    /// Unified memory is the whole reason a 9B model is reasonable on a laptop.
    /// Without it the weights cross the bus on every token.
    public let isAppleSilicon: Bool
    /// Free space where Ollama keeps its blobs, when it can be read.
    public let availableDiskBytes: UInt64?

    public init(
        physicalMemoryBytes: UInt64,
        performanceCoreCount: Int,
        totalCoreCount: Int,
        isAppleSilicon: Bool,
        availableDiskBytes: UInt64? = nil
    ) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.performanceCoreCount = performanceCoreCount
        self.totalCoreCount = totalCoreCount
        self.isAppleSilicon = isAppleSilicon
        self.availableDiskBytes = availableDiskBytes
    }

    public static let bytesPerGigabyte: UInt64 = 1_073_741_824

    /// Rounded down, the way every memory threshold in the catalogue is
    /// written. A 16 GB Mac reports slightly under 16 × 2³⁰ on some machines,
    /// so the division is done once here and compared as an integer everywhere.
    public var memoryGB: Int {
        Int(physicalMemoryBytes / Self.bytesPerGigabyte)
    }

    public var availableDiskGB: Int? {
        availableDiskBytes.map { Int($0 / Self.bytesPerGigabyte) }
    }

    /// One line for the dashboard: what the recommendation was made from.
    public var summary: String {
        let chip = isAppleSilicon ? "Apple silicon" : "Intel"
        return "\(memoryGB) GB memory · \(performanceCoreCount) performance cores · \(chip)"
    }

    public static func current(
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> DeviceProfile {
        DeviceProfile(
            physicalMemoryBytes: processInfo.physicalMemory,
            performanceCoreCount: SystemHardware.performanceCoreCount
                ?? processInfo.activeProcessorCount,
            totalCoreCount: processInfo.processorCount,
            isAppleSilicon: SystemHardware.isAppleSilicon,
            availableDiskBytes: SystemHardware.availableDiskBytes(
                fileManager: fileManager
            )
        )
    }
}

/// The sysctl reads behind `DeviceProfile.current`, kept apart so the profile
/// itself stays a plain value with no platform surface.
enum SystemHardware {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        // A translated build still runs the model natively through Ollama, so
        // ask the kernel rather than trusting the compile-time architecture.
        return integer(named: "hw.optional.arm64") == 1
        #endif
    }

    static var performanceCoreCount: Int? {
        // perflevel0 is the performance cluster on every Apple silicon Mac.
        // Absent on Intel, where every core is the same and the total is right.
        guard let count = integer(named: "hw.perflevel0.physicalcpu"), count > 0 else {
            return nil
        }
        return count
    }

    /// Ollama keeps its blobs in `~/.ollama`, so that volume is the one that
    /// has to have room — not whichever volume the app happens to be on.
    static func availableDiskBytes(fileManager: FileManager) -> UInt64? {
        let home = fileManager.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ), let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return capacity > 0 ? UInt64(capacity) : 0
    }

    private static func integer(named name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

/// One downloadable model Chamfer supports.
///
/// Chamfer picks exactly one of these for a given Mac. The list is a hardware
/// ladder rather than a menu — nothing here is offered to the user to choose
/// between, and `LocalModelSelection` is the only thing that reads it.
public struct LocalModelDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// Parameters, written the way the model family writes them.
    public let parameterLabel: String
    public let downloadBytes: UInt64
    /// The floor this tier is chosen at. Inclusive.
    public let minimumMemoryGB: Int
    /// What the model is good for, in the app's own terms. Shown on the card.
    public let characterisation: String

    public init(
        id: String,
        displayName: String,
        parameterLabel: String,
        downloadBytes: UInt64,
        minimumMemoryGB: Int,
        characterisation: String
    ) {
        self.id = id
        self.displayName = displayName
        self.parameterLabel = parameterLabel
        self.downloadBytes = downloadBytes
        self.minimumMemoryGB = minimumMemoryGB
        self.characterisation = characterisation
    }

    /// Rounded to one decimal, which is how a download size is written
    /// everywhere else in the interface.
    public var downloadSizeLabel: String {
        let gigabytes = Double(downloadBytes) / Double(DeviceProfile.bytesPerGigabyte)
        return String(format: "%.1f GB", gigabytes)
    }

    /// Room to unpack a download as well as store it. Ollama writes the blob
    /// and then the manifest, so a volume with exactly the download's size free
    /// runs out partway through and leaves an incomplete pull behind.
    public var requiredDiskBytes: UInt64 {
        downloadBytes + downloadBytes / 4
    }
}

/// The device-to-model mapping.
///
/// Deterministic and total: every Mac gets exactly one recommendation, and the
/// smallest tier is a floor rather than a failure, so there is no "unsupported
/// hardware" state for the rest of the app to carry.
///
/// The thresholds are deliberately more conservative than the memory a model
/// strictly needs to load. Chamfer is a background app running beside whatever
/// the person is actually doing, so each tier leaves the rest of the Mac roughly
/// twice the model's resident size to work in.
public enum LocalModelCatalog {
    public static let floor = LocalModelDescriptor(
        id: "qwen3.5:0.8b",
        displayName: "Qwen3.5",
        parameterLabel: "0.8B",
        downloadBytes: 1_073_741_824,
        minimumMemoryGB: 0,
        characterisation: "Sized for Macs with little memory to spare. Reliable on spelling and grammar, lighter on judgement."
    )

    /// Ordered by the memory each tier asks for, ascending. The floor is first
    /// and its threshold is zero, which is what makes selection total.
    public static let ladder: [LocalModelDescriptor] = [
        floor,
        LocalModelDescriptor(
            id: "qwen3.5:2b",
            displayName: "Qwen3.5",
            parameterLabel: "2B",
            downloadBytes: 2_899_102_924,
            minimumMemoryGB: 8,
            characterisation: "A careful copy editor that keeps its footprint small enough to ignore."
        ),
        LocalModelDescriptor(
            id: "qwen3.5:4b",
            displayName: "Qwen3.5",
            parameterLabel: "4B",
            downloadBytes: 3_650_722_201,
            minimumMemoryGB: 16,
            characterisation: "Holds a whole section in mind at once, which is where clarity edits start being worth reading."
        ),
        LocalModelDescriptor(
            id: "qwen3.5:9b",
            displayName: "Qwen3.5",
            parameterLabel: "9B",
            downloadBytes: 7_086_696_038,
            minimumMemoryGB: 24,
            characterisation: "Follows a mode's restraint closely enough that a spelling pass stays a spelling pass."
        ),
        LocalModelDescriptor(
            id: "gpt-oss:20b",
            displayName: "GPT-OSS",
            parameterLabel: "20B",
            downloadBytes: 15_032_385_536,
            minimumMemoryGB: 48,
            characterisation: "The most capable model Chamfer runs locally, for Macs with memory to spend on it."
        )
    ]

    /// Above this, a model without unified memory spends more time moving
    /// weights than generating. Intel Macs are held to the small tiers whatever
    /// their memory says.
    static let intelCeilingMemoryGB = 8
}

/// The one place that decides which local model a Mac runs.
///
/// Every other part of the app — the dashboard, the installer, the rewrite
/// pipeline, the bottom bar — asks this rather than storing a chosen model, so
/// there is exactly one answer and it cannot go stale against the hardware.
public enum LocalModelSelection {
    /// Never fails. A Mac too small for any tier gets the floor model.
    public static func recommended(for device: DeviceProfile) -> LocalModelDescriptor {
        let ceiling = device.isAppleSilicon
            ? Int.max
            : LocalModelCatalog.intelCeilingMemoryGB

        return LocalModelCatalog.ladder.last {
            device.memoryGB >= $0.minimumMemoryGB && $0.minimumMemoryGB <= ceiling
        } ?? LocalModelCatalog.floor
    }

    /// Why this Mac got this model, in one sentence for the dashboard.
    public static func rationale(
        for device: DeviceProfile,
        model: LocalModelDescriptor
    ) -> String {
        if !device.isAppleSilicon {
            return "Chosen for an Intel Mac, where a larger model would spend more time moving weights than writing."
        }
        if model.id == LocalModelCatalog.floor.id {
            return "Chosen because \(device.memoryGB) GB leaves little room beside the work you are actually doing."
        }
        let next = LocalModelCatalog.ladder.first {
            $0.minimumMemoryGB > model.minimumMemoryGB
        }
        guard let next else {
            return "Chosen because \(device.memoryGB) GB of unified memory runs the largest model Chamfer supports."
        }
        return "Chosen because \(device.memoryGB) GB comfortably runs \(model.parameterLabel); \(next.parameterLabel) wants \(next.minimumMemoryGB) GB."
    }

    /// Whether there is room to install. Nil disk information is treated as
    /// enough room: refusing to download because a volume would not answer is
    /// worse than letting the pull report its own failure.
    public static func hasRoom(
        for model: LocalModelDescriptor,
        on device: DeviceProfile
    ) -> Bool {
        guard let available = device.availableDiskBytes else { return true }
        return available >= model.requiredDiskBytes
    }
}
