import ChamferCore
import Foundation

/// What became of a stored bookmark when we tried to use it.
public struct VaultResolution: Sendable {
    public let url: URL?
    public let availability: VaultAvailability
    /// Set when the system reported the bookmark stale and handed us a fresh
    /// one. Storing it back is what stops a vault that has merely been moved
    /// from degrading a little more on every launch.
    public let refreshedBookmark: Data?

    public init(
        url: URL?,
        availability: VaultAvailability,
        refreshedBookmark: Data? = nil
    ) {
        self.url = url
        self.availability = availability
        self.refreshedBookmark = refreshedBookmark
    }
}

/// Turning a folder the user picked into something that still works next week.
///
/// A path is a guess. A security-scoped bookmark survives the folder being
/// renamed, moved, or living on a disk that comes and goes — which is the whole
/// difference between "connect a vault once" and "re-pick your notes folder
/// every time you restart".
public enum VaultBookmark {
    /// Made at the moment the user picks the folder, while the open panel's
    /// grant is still live.
    ///
    /// Falls back to a plain bookmark when the security-scoped one is refused.
    /// A SwiftPM build has no bundle and no entitlements, so the scoped variant
    /// is not always available; the plain one still survives a move, which is
    /// most of the value, and the sandboxed build gets the stronger promise.
    public static func make(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    /// Resolves a stored bookmark and works out what the user can do about it.
    ///
    /// The four availabilities are not decoration: they are four different next
    /// moves. Plug the disk in, grant access again, find the folder, or nothing
    /// at all. Collapsing them into "unavailable" would make all four read as
    /// the same shrug, which is exactly what `VaultAvailability` exists to
    /// avoid.
    public static func resolve(_ bookmark: Data) -> VaultResolution {
        var isStale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            // A scoped resolve fails on a build without the entitlement, so a
            // plain resolve is tried before concluding the folder is gone.
            guard let plain = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return VaultResolution(url: nil, availability: .missing)
            }
            return VaultResolution(
                url: plain,
                availability: availability(of: plain),
                refreshedBookmark: isStale ? try? make(for: plain) : nil
            )
        }

        return VaultResolution(
            url: resolved,
            availability: availability(of: resolved),
            refreshedBookmark: isStale ? try? make(for: resolved) : nil
        )
    }

    /// Runs `work` with the folder's security scope held open.
    ///
    /// Balanced by construction — the stop is in a `defer` — because an
    /// unbalanced start leaks the grant for the life of the process and there
    /// is a hard limit on how many of those a process may hold.
    @discardableResult
    public static func withAccess<T>(
        to url: URL,
        perform work: () throws -> T
    ) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        return try work()
    }

    private static func availability(of url: URL) -> VaultAvailability {
        withAccess(to: url) {
            let manager = FileManager.default
            var isDirectory: ObjCBool = false

            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                // Nothing at the path. Either the folder was deleted, or the
                // disk it lived on is not mounted — and those want opposite
                // advice, so it is worth the extra look.
                return isOnMountedVolume(url) ? .missing : .offline
            }
            guard isDirectory.boolValue else { return .missing }
            guard manager.isReadableFile(atPath: url.path) else {
                return .permissionDenied
            }
            return .available
        }
    }

    /// Whether the volume this URL sits on is currently mounted.
    ///
    /// Compared by path prefix against the mounted volumes rather than by
    /// asking the URL for its volume, because the URL does not exist — which is
    /// the case being diagnosed.
    private static func isOnMountedVolume(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let mounts = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []

        // Longest match wins: "/" is a prefix of everything, so checking it
        // first would report every unplugged disk as merely missing.
        let best = mounts
            .map { $0.path(percentEncoded: false) }
            .filter { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .max { $0.count < $1.count }

        guard let best else { return false }
        // The root volume is always mounted, so anything under it that is
        // absent is genuinely absent rather than offline.
        return best == "/" || FileManager.default.fileExists(atPath: best)
    }
}
