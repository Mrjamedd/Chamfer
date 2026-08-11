import ChamferCore
import Foundation

/// One connected vault as it survives a quit.
///
/// The bookmark rather than the path is what is kept: a path is a guess about
/// where a folder will be next launch, and a security-scoped bookmark is a
/// promise the system honours across moves, renames and restarts. The path is
/// stored alongside it only so the interface has something truthful to show in
/// the moment before resolution finishes, or when resolution fails outright.
public struct StoredVault: Sendable, Equatable, Codable {
    public let id: UUID
    public let bookmark: Data
    /// Where the folder was when the bookmark was made. Display only.
    public let path: String
    public var noteCount: Int
    public var lastSweep: Date?
    /// What the user configured, or nil if they never did. Persisted as an
    /// optional so an unconfigured vault comes back unconfigured rather than
    /// quietly acquiring settings across a relaunch.
    public var configuration: VaultConfiguration?
    public var folders: [WatchedFolder]
    public var rules: [VaultRule]

    public init(
        id: UUID = UUID(),
        bookmark: Data,
        path: String,
        noteCount: Int = 0,
        lastSweep: Date? = nil,
        configuration: VaultConfiguration? = nil,
        folders: [WatchedFolder] = [],
        rules: [VaultRule] = []
    ) {
        self.id = id
        self.bookmark = bookmark
        self.path = path
        self.noteCount = noteCount
        self.lastSweep = lastSweep
        self.configuration = configuration
        self.folders = folders
        self.rules = rules
    }
}

/// Everything that has to outlive the process.
///
/// Deliberately not `DashboardState`. That type carries what is on screen —
/// run state, the open note, the search index — all of which is rebuilt from
/// the disk at launch and none of which should be trusted from a file written
/// by a version of the app that has since changed.
public struct StoredState: Sendable, Equatable, Codable {
    /// Bumped when the shape changes incompatibly. A file from the future is
    /// refused rather than misread.
    public static let currentVersion = 2

    public var version: Int
    public var vaults: [StoredVault]
    public var preferences: AppPreferences
    /// Rewrites that were waiting when the app stopped. The scope requires a
    /// crash to lose neither applied nor pending state.
    public var proposals: [Proposal]

    public init(
        version: Int = StoredState.currentVersion,
        vaults: [StoredVault] = [],
        preferences: AppPreferences = .unconfigured,
        proposals: [Proposal] = []
    ) {
        self.version = version
        self.vaults = vaults
        self.preferences = preferences
        self.proposals = proposals
    }

    public static let empty = StoredState()

    private enum CodingKeys: String, CodingKey {
        case version
        case vaults
        case preferences
        case proposals
    }

    private struct VersionOneVault: Decodable {
        let id: UUID
        let bookmark: Data
        let path: String
        let noteCount: Int
        let lastSweep: Date?
        let configuration: RewritePolicy?
        let folders: [WatchedFolder]
        let rules: [VaultRule]

        var migrated: StoredVault {
            StoredVault(
                id: id,
                bookmark: bookmark,
                path: path,
                noteCount: noteCount,
                lastSweep: lastSweep,
                configuration: configuration.map(VaultConfiguration.init(resolved:)),
                folders: folders,
                rules: rules
            )
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        version = storedVersion == 1 ? Self.currentVersion : storedVersion
        preferences = try values.decodeIfPresent(
            AppPreferences.self,
            forKey: .preferences
        ) ?? .unconfigured
        proposals = try values.decodeIfPresent([Proposal].self, forKey: .proposals) ?? []

        if storedVersion == 1 {
            vaults = try values.decodeIfPresent(
                [VersionOneVault].self,
                forKey: .vaults
            )?.map(\.migrated) ?? []
        } else {
            vaults = try values.decodeIfPresent([StoredVault].self, forKey: .vaults) ?? []
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(vaults, forKey: .vaults)
        try values.encode(preferences, forKey: .preferences)
        try values.encode(proposals, forKey: .proposals)
    }
}

/// Why a load produced nothing usable.
///
/// Reported rather than swallowed, because "your vaults are gone" and "this is
/// a fresh install" look identical to a user and must not look identical to us.
public enum StoreLoadFailure: Error, Sendable, Equatable {
    case unreadable(String)
    case corrupt(String)
    /// Written by a newer Chamfer than this one.
    case fromTheFuture(version: Int)

    public var message: String {
        switch self {
        case let .unreadable(detail):
            "Chamfer couldn't read its saved settings. \(detail)"
        case let .corrupt(detail):
            "Chamfer's saved settings were damaged and have been set aside. \(detail)"
        case let .fromTheFuture(version):
            "These settings were written by a newer version of Chamfer (format \(version)). They have been left untouched."
        }
    }
}

public struct StoreLoad: Sendable {
    public let state: StoredState
    public let history: [HistoryEntry]
    /// Non-nil when something was on disk but could not be used. The state and
    /// history above are then the defaults, and the interface says so rather
    /// than presenting an empty app as if it were new.
    public let failure: StoreLoadFailure?

    public init(
        state: StoredState,
        history: [HistoryEntry],
        failure: StoreLoadFailure? = nil
    ) {
        self.state = state
        self.history = history
        self.failure = failure
    }
}

/// Chamfer's own storage, in hidden local application support.
///
/// Two files rather than one. Settings and the pending queue are small, change
/// together, and are rewritten whole; history is append-heavy and grows without
/// bound, and the scope keeps it forever. Rewriting a megabyte of history every
/// time a toggle is flipped would be the kind of thing that is fine until
/// someone has used the app for a year.
///
/// Every write is atomic. A crash mid-save must leave the previous file intact,
/// because the alternative is losing the record of what was replaced — which is
/// the one thing history exists to prevent.
public struct StateStore: Sendable {
    public let directory: URL

    private static let stateFile = "state.json"
    private static let historyFile = "history.json"

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.directory = applicationSupport
                .appendingPathComponent("Chamfer", isDirectory: true)
        }
    }

    public var stateURL: URL { directory.appendingPathComponent(Self.stateFile) }
    public var historyURL: URL { directory.appendingPathComponent(Self.historyFile) }

    // MARK: Load

    /// Reads both files, tolerating either being absent.
    ///
    /// A missing file is a fresh install and not a failure. A present but
    /// unreadable one is moved aside before the defaults are returned, so the
    /// next save cannot quietly overwrite whatever was in it — a damaged
    /// history is still the only copy of the text it holds.
    public func load() -> StoreLoad {
        var failure: StoreLoadFailure?

        let state: StoredState
        switch decode(StoredState.self, at: stateURL) {
        case let .success(loaded):
            if let loaded {
                if loaded.version <= StoredState.currentVersion {
                    state = loaded
                } else {
                    // Settings from the future cannot be interpreted, but the
                    // separately readable history is still irreplaceable.
                    failure = .fromTheFuture(version: loaded.version)
                    state = .empty
                }
            } else {
                state = .empty
            }
        case let .failure(reason):
            failure = reason
            setAside(stateURL)
            state = .empty
        }

        let history: [HistoryEntry]
        switch decode([HistoryEntry].self, at: historyURL) {
        case let .success(loaded):
            history = loaded ?? []
        case let .failure(reason):
            failure = failure ?? reason
            setAside(historyURL)
            history = []
        }

        return StoreLoad(state: state, history: history, failure: failure)
    }

    // MARK: Save

    public func save(_ state: StoredState) throws {
        try write(state, to: stateURL)
    }

    public func save(history: [HistoryEntry]) throws {
        try write(history, to: historyURL)
    }

    // MARK: Coding

    /// ISO-8601 dates rather than the default reference-date doubles. The files
    /// are meant to be legible when something has gone wrong with them.
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// `.success(nil)` means the file is simply not there yet.
    private func decode<T: Decodable>(
        _ type: T.Type,
        at url: URL
    ) -> Result<T?, StoreLoadFailure> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .success(nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return .success(try Self.decoder().decode(type, from: data))
        } catch let error as DecodingError {
            return .failure(.corrupt(Self.describe(error)))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Self.encoder().encode(value).write(to: url, options: .atomic)
    }

    /// Renames a file we could not read, rather than deleting it. It may be the
    /// only copy of something, and a user who notices tomorrow should still be
    /// able to hand it to us.
    private func setAside(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = url
            .deletingPathExtension()
            .appendingPathExtension("damaged-\(stamp)")
            .appendingPathExtension("json")
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, _):
            "A required field (\(key.stringValue)) was missing."
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            context.debugDescription
        case let .dataCorrupted(context):
            context.debugDescription
        @unknown default:
            "The file could not be read."
        }
    }
}
