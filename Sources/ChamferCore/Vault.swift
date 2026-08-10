import Foundation

/// Why a vault cannot be processed right now.
///
/// Separate cases rather than one `isReachable` flag because the user's next
/// move is different for each: plug the disk back in, grant access again, or
/// point Chamfer somewhere that still exists. A single boolean would make all
/// three read as the same shrug.
public enum VaultAvailability: Sendable, Equatable, Hashable, Codable {
    case available
    /// The bookmark resolves but the volume is not mounted.
    case offline
    /// The bookmark resolves and the volume is mounted, but the sandbox will
    /// not let us read it.
    case permissionDenied
    /// The folder is gone.
    case missing

    public var isAvailable: Bool { self == .available }

    public var title: String {
        switch self {
        case .available: "Watching"
        case .offline: "Disk not connected"
        case .permissionDenied: "No access"
        case .missing: "Folder missing"
        }
    }

    /// What the user can do about it, in the second line of the row.
    public var remedy: String? {
        switch self {
        case .available: nil
        case .offline: "Reconnect the disk and Chamfer resumes on its own."
        case .permissionDenied: "Grant access again to resume watching this vault."
        case .missing: "Reconnect this vault or remove it."
        }
    }

    public var symbol: String {
        switch self {
        case .available: "folder"
        case .offline: "externaldrive.badge.xmark"
        case .permissionDenied: "lock"
        case .missing: "folder.badge.questionmark"
        }
    }
}

/// A folder the user has excluded, or has narrowed processing down to.
public struct VaultRule: Sendable, Identifiable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// Never process anything under this path.
        case exclude
        /// Process only what is under this path.
        case includeOnly
    }

    public let id: UUID
    public let kind: Kind
    /// Relative to the vault root, so the rule survives the vault moving.
    public let path: String

    public init(id: UUID = UUID(), kind: Kind, path: String) {
        self.id = id
        self.kind = kind
        self.path = path
    }
}

/// Set operations for persisted vault rules.
public enum VaultRuleSet {
    /// Adds exact note paths as exclusions while preserving folder scope rules
    /// and avoiding duplicate rules when the same note is selected twice.
    public static func addingExclusions(
        paths: [String],
        to rules: [VaultRule]
    ) -> [VaultRule] {
        var result = rules
        var existing = Set(
            rules
                .filter { $0.kind == .exclude }
                .map(\.path)
        )

        for path in paths where !path.isEmpty && existing.insert(path).inserted {
            result.append(VaultRule(kind: .exclude, path: path))
        }
        return result
    }
}

/// A connected note folder, with everything the Vaults page needs to describe
/// it without touching the disk.
public struct Vault: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var url: URL
    public var availability: VaultAvailability
    public var noteCount: Int
    public var lastSweep: Date?
    /// How this vault is rewritten, or nil when nobody has said yet.
    ///
    /// Optional on purpose, and it is the most important property here. There
    /// are no defaults to fall back on: a vault Chamfer has not been told how
    /// to treat is a vault Chamfer does not touch. The previous design gave a
    /// newly connected folder a full cleanup inherited from settings the user
    /// had never looked at and started rewriting their notes without explicit
    /// per-vault permission.
    public var configuration: VaultConfiguration?
    /// Subfolders that hold notes. Kept for the exclusion editor to offer, and
    /// for nothing else — a folder no longer carries settings of its own.
    public var folders: [WatchedFolder]
    public var rules: [VaultRule]

    public init(
        id: UUID = UUID(),
        url: URL,
        availability: VaultAvailability = .available,
        noteCount: Int,
        lastSweep: Date? = nil,
        configuration: VaultConfiguration? = nil,
        folders: [WatchedFolder] = [],
        rules: [VaultRule] = []
    ) {
        self.id = id
        self.url = url
        self.availability = availability
        self.noteCount = noteCount
        self.lastSweep = lastSweep
        self.configuration = configuration
        self.folders = folders
        self.rules = rules
    }

    /// Whether this vault has been told what to do.
    ///
    /// Everything that could change a note checks this first.
    public var isConfigured: Bool { configuration?.isComplete == true }

    public var name: String { url.lastPathComponent }

    /// The path as the user thinks of it, with their home folder abbreviated.
    public var displayPath: String {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser
            .path(percentEncoded: false)
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public var excludedCount: Int {
        rules.filter { $0.kind == .exclude }.count
    }

    public var isNarrowed: Bool {
        rules.contains { $0.kind == .includeOnly }
    }
}
