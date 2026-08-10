import ChamferCore
import CoreServices
import Foundation

/// FSEvents, wrapped so the rest of the app never sees a C callback.
///
/// Two things make this more than a thin wrapper, and both are correctness
/// rather than convenience:
///
/// **Settling.** FSEvents fires while a file is still being written, and an
/// editor saving a note can produce several events in a few hundred
/// milliseconds. A note is only reported once it has been quiet for
/// `settleInterval`, so the pipeline downstream sees one change per save rather
/// than one per write syscall.
///
/// **Echo suppression.** Chamfer writes to the same folders it watches. Without
/// suppression, applying a rewrite produces a change event, which makes the
/// note eligible again, which produces another rewrite — forever. Every write
/// the app makes is announced here first, and events for that path are ignored
/// for a moment afterwards.
public final class FolderObserver: FolderObserving, @unchecked Sendable {
    /// How long a note must be quiet before it counts as saved.
    public static let settleInterval: TimeInterval = 1.0
    /// How long our own writes stay invisible. Generous relative to the write
    /// itself, because the event can arrive well after the bytes have landed.
    public static let echoWindow: TimeInterval = 3.0

    private let roots: [URL]
    private let queue = DispatchQueue(
        label: "app.chamfer.folder-observer",
        qos: .utility
    )

    /// Guards everything below it. The FSEvents callback runs on `queue` and
    /// the app announces its own writes from wherever it happens to be.
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var handler: (@Sendable (NoteChange) -> Void)?
    private var pending: [String: DispatchWorkItem] = [:]
    private var suppressedUntil: [String: Date] = [:]
    private var accessGrants: [URL: Bool] = [:]

    public init(roots: [URL]) {
        self.roots = roots.map(\.standardizedFileURL)
    }

    deinit {
        tearDown()
    }

    // MARK: - FolderObserving

    public func start(onChange: @escaping @Sendable (NoteChange) -> Void) throws {
        stop()

        lock.lock()
        handler = onChange
        lock.unlock()

        guard !roots.isEmpty else { return }

        // Held for as long as the stream is: FSEvents reads the folder on its
        // own schedule, so the scope cannot be opened and closed around a
        // single call the way a scan can.
        for root in roots {
            accessGrants[root] = root.startAccessingSecurityScopedResource()
        }

        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.initialize(
            to: FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
        )
        defer {
            context.deinitialize(count: 1)
            context.deallocate()
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagIgnoreSelf
        )

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            observerCallback,
            context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            // FSEvents' own coalescing window. Deliberately shorter than
            // `settleInterval`: this one trims the storm, and the settle timer
            // decides when the note is actually finished.
            0.3,
            flags
        ) else {
            throw ObserverFailure.streamUnavailable
        }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            throw ObserverFailure.streamUnavailable
        }

        lock.lock()
        stream = created
        lock.unlock()
    }

    public func stop() {
        tearDown()
    }

    public enum ObserverFailure: Error, Sendable {
        case streamUnavailable
    }

    // MARK: - Echo suppression

    /// Announce a write Chamfer is about to make, so its own event is ignored.
    ///
    /// Called before the write rather than after: the event can beat the return
    /// of the write call, and a suppression that arrives second suppresses
    /// nothing.
    public func expectOwnWrite(to url: URL) {
        let key = url.standardizedFileURL.path
        lock.lock()
        suppressedUntil[key] = Date().addingTimeInterval(Self.echoWindow)
        lock.unlock()
    }

    public func cancelExpectedOwnWrite(to url: URL) {
        let key = url.standardizedFileURL.path
        lock.lock()
        suppressedUntil[key] = nil
        lock.unlock()
    }

    // MARK: - Internals

    private func tearDown() {
        lock.lock()
        let existing = stream
        stream = nil
        handler = nil
        let work = pending
        pending.removeAll()
        lock.unlock()

        work.values.forEach { $0.cancel() }

        if let existing {
            FSEventStreamStop(existing)
            FSEventStreamInvalidate(existing)
            FSEventStreamRelease(existing)
        }

        for (url, granted) in accessGrants where granted {
            url.stopAccessingSecurityScopedResource()
        }
        accessGrants.removeAll()
    }

    fileprivate func handle(
        paths: [String],
        flags: [FSEventStreamEventFlags]
    ) {
        let now = Date()
        for (index, path) in paths.enumerated() {
            let url = URL(fileURLWithPath: path)
            let eventFlags = index < flags.count ? flags[index] : 0
            let requiresRescan = Self.requiresReconciliation(for: eventFlags)
            guard requiresRescan
                    || NoteEligibility.isSupportedFile(url.lastPathComponent)
            else {
                continue
            }
            // Vault rules are not applied here. The observer reports what moved
            // on disk; deciding whether a given vault's rules permit acting on
            // it belongs with the vault, which this object does not know about.
            guard requiresRescan || !isSuppressed(path, now: now) else { continue }
            scheduleSettle(for: url, path: path, requiresRescan: requiresRescan)
        }
    }

    static func requiresReconciliation(for flags: FSEventStreamEventFlags) -> Bool {
        let incomplete = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )
        if flags & incomplete != 0 { return true }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            return true
        }
        let isDirectory = flags
            & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
        let structural = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
        )
        return isDirectory && flags & structural != 0
    }

    private func isSuppressed(_ path: String, now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = suppressedUntil[path] else { return false }
        guard until > now else {
            suppressedUntil[path] = nil
            return false
        }
        return true
    }

    /// Restarts the note's quiet timer. Each new event pushes the report
    /// further out, so a file being written continuously is never reported
    /// until the writing stops.
    private func scheduleSettle(
        for url: URL,
        path: String,
        requiresRescan: Bool
    ) {
        lock.lock()
        pending[path]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            lock.lock()
            pending[path] = nil
            let handler = handler
            let stillSuppressed = suppressedUntil[path].map { $0 > Date() } ?? false
            lock.unlock()

            guard let handler, !stillSuppressed else { return }
            handler(
                NoteChange(
                    url: url,
                    detectedAt: Date(),
                    requiresRescan: requiresRescan
                )
            )
        }
        pending[path] = work
        lock.unlock()

        queue.asyncAfter(deadline: .now() + Self.settleInterval, execute: work)
    }
}

/// The C callback, kept at file scope because a closure cannot be one.
private let observerCallback: FSEventStreamCallback = {
    _, info, count, eventPaths, eventFlags, _ in
    guard let info,
          let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String]
    else { return }
    let observer = Unmanaged<FolderObserver>.fromOpaque(info)
        .takeUnretainedValue()
    observer.handle(
        paths: Array(paths.prefix(count)),
        flags: Array(UnsafeBufferPointer(start: eventFlags, count: count))
    )
}
