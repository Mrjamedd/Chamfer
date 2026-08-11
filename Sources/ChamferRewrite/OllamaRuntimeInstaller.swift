import Foundation

/// Where the runtime install has got to.
public enum OllamaRuntimeStage: Equatable, Sendable {
    /// Asking whether anything needs doing at all.
    case checking
    case downloading
    case verifying
    case extracting
    /// The runtime is on disk; starting it and waiting for it to answer.
    case starting
}

public struct OllamaRuntimeProgress: Equatable, Sendable {
    public let stage: OllamaRuntimeStage
    /// 0…1 while downloading, nil for stages that have no measurable length.
    public let fraction: Double?
    public let completedBytes: UInt64
    public let totalBytes: UInt64?

    public init(
        stage: OllamaRuntimeStage,
        fraction: Double? = nil,
        completedBytes: UInt64 = 0,
        totalBytes: UInt64? = nil
    ) {
        self.stage = stage
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    /// What the interface says while this is happening.
    public var summary: String {
        switch stage {
        case .checking: "Checking the local runtime…"
        case .downloading: "Downloading the local runtime…"
        case .verifying: "Verifying the download…"
        case .extracting: "Unpacking the runtime…"
        case .starting: "Starting the local runtime…"
        }
    }
}

/// Which server Chamfer ended up talking to.
public enum OllamaRuntimeOutcome: Equatable, Sendable {
    /// An Ollama the user runs themselves was already answering. Chamfer
    /// borrowed it and installed nothing.
    case usingExistingInstallation(URL)
    /// Chamfer's own runtime was already on disk and was started.
    case started(URL)
    /// Downloaded, unpacked and started during this call.
    case installed(URL)
    case failed(String)

    public var baseURL: URL? {
        switch self {
        case let .usingExistingInstallation(url), let .started(url), let .installed(url):
            url
        case .failed:
            nil
        }
    }

    public var isReady: Bool { baseURL != nil }
}

/// Puts the Ollama *server* on the Mac, and nothing else.
///
/// Deliberately not `Ollama.app`. Installing a second application into
/// `/Applications` — with its own icon, menu bar item and daemon that outlives
/// Chamfer — is out of scope for a notes app. Ollama publishes a standalone
/// `ollama-darwin.tgz` containing the server, the CLI and the Metal runners
/// with no UI wrapper, and that is what this installs, into Chamfer's own
/// Application Support directory.
///
/// The consequences of that choice, all of them the point:
///
/// - Nothing appears in `/Applications`, the Dock, or the menu bar.
/// - The server is a **child process of Chamfer**. Quit Chamfer and it goes;
///   there is no daemon left behind.
/// - It listens on a private port, so it cannot collide with an Ollama the user
///   runs themselves — and if they run one, Chamfer uses theirs and installs
///   nothing at all.
/// - Models are stored under Chamfer, not in `~/.ollama`, so deleting Chamfer
///   and its Application Support really does remove everything.
///
/// Ollama is MIT licensed, so redistributing the binaries is fine; the licence
/// text ships alongside them.
///
/// Idempotent by the same three rules as `LocalModelInstaller`: ask what is
/// already there before fetching anything, coalesce concurrent callers onto one
/// install, and believe nothing until the server answers.
public actor OllamaRuntimeInstaller {
    public static let shared = OllamaRuntimeInstaller()

    /// The server without the application around it.
    public static let downloadURL = URL(
        string: "https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.tgz"
    )!
    /// Published beside it, so a download can be checked rather than trusted.
    public static let checksumURL = URL(
        string: "https://github.com/ollama/ollama/releases/latest/download/sha256sum.txt"
    )!
    static let archiveName = "ollama-darwin.tgz"

    private let session: URLSession
    private let client: OllamaClient
    private let fileManager: FileManager
    /// Chamfer's own storage. The runtime and the models both live under here.
    private let supportDirectory: URL
    private let sharedBaseURL: URL
    private let privateBaseURL: URL
    private let startupTimeout: Duration
    private let startupPoll: Duration
    /// Injected so a test never spawns a server.
    private let spawn: @Sendable (URL, URL, URL) async -> RuntimeProcess?

    private var inFlight: Task<OllamaRuntimeOutcome, Never>?
    /// Held for the life of the app so the server can be stopped on quit.
    private var running: RuntimeProcess?

    public init(
        session: URLSession = .shared,
        client: OllamaClient = OllamaClient(),
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil,
        sharedBaseURL: URL = OllamaAPI.sharedBaseURL,
        privateBaseURL: URL = OllamaAPI.privateBaseURL,
        startupTimeout: Duration = .seconds(120),
        startupPoll: Duration = .milliseconds(500),
        spawn: (@Sendable (URL, URL, URL) async -> RuntimeProcess?)? = nil
    ) {
        self.session = session
        self.client = client
        self.fileManager = fileManager
        self.supportDirectory = supportDirectory ?? Self.defaultSupportDirectory(
            fileManager: fileManager
        )
        self.sharedBaseURL = sharedBaseURL
        self.privateBaseURL = privateBaseURL
        self.startupTimeout = startupTimeout
        self.startupPoll = startupPoll
        self.spawn = spawn ?? { executable, models, baseURL in
            RuntimeProcess.launch(
                executable: executable,
                modelsDirectory: models,
                baseURL: baseURL
            )
        }
    }

    static func defaultSupportDirectory(fileManager: FileManager) -> URL {
        let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root.appendingPathComponent("Chamfer", isDirectory: true)
    }

    /// Where the unpacked runtime lives.
    public var runtimeDirectory: URL {
        supportDirectory.appendingPathComponent("Runtime", isDirectory: true)
    }

    public var executableURL: URL {
        runtimeDirectory.appendingPathComponent("ollama")
    }

    /// Written when Chamfer spawns the server, read when a later launch finds
    /// one already answering.
    var pidFileURL: URL {
        runtimeDirectory.appendingPathComponent("server.pid")
    }

    /// Chamfer's own model store, rather than `~/.ollama`.
    public var modelsDirectory: URL {
        supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    public var isInstalled: Bool {
        fileManager.isExecutableFile(atPath: executableURL.path)
    }

    /// Stops Chamfer's server. Called when the app quits.
    ///
    /// A no-op when Chamfer is borrowing somebody else's Ollama — that one is
    /// not ours to stop.
    public func shutDown() {
        LocalRuntimeSupervisor.terminate()
        running = nil
    }

    /// Makes a runtime available, doing as little as the situation allows.
    public func ensureAvailable(
        progress: (@Sendable (OllamaRuntimeProgress) -> Void)? = nil
    ) async -> OllamaRuntimeOutcome {
        if let inFlight { return await inFlight.value }

        let task = Task<OllamaRuntimeOutcome, Never> { [self] in
            await provision(progress: progress)
        }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }

    private func provision(
        progress: (@Sendable (OllamaRuntimeProgress) -> Void)?
    ) async -> OllamaRuntimeOutcome {
        progress?(OllamaRuntimeProgress(stage: .checking))

        // 1. Somebody's own Ollama is already running. Use it; install nothing.
        //    Respecting an existing install is both politer and faster than
        //    downloading 145 MB to duplicate it.
        if await client.addressing(sharedBaseURL).isAvailable() {
            return .usingExistingInstallation(sharedBaseURL)
        }

        // 2. Ours is already running — a second call this session, or an orphan
        //    left by a launch that was killed outright. Either way, adopt it:
        //    starting a second server on a taken port would fail, and leaving
        //    the orphan unowned would let it survive every future quit.
        if await client.addressing(privateBaseURL).isAvailable() {
            if let pid = recordedServerPID(), pid > 0, kill(pid, 0) == 0 {
                LocalRuntimeSupervisor.adopt(pid: pid)
            }
            return .started(privateBaseURL)
        }

        // 3. Ours is on disk but not running.
        if isInstalled {
            progress?(OllamaRuntimeProgress(stage: .starting))
            return await start()
        }

        // 4. Not here at all.
        let staging: URL
        do {
            staging = try makeStagingDirectory()
        } catch {
            return .failed(error.localizedDescription)
        }
        // A partial download must never survive to look like an install.
        defer { try? fileManager.removeItem(at: staging) }

        let archive = staging.appendingPathComponent(Self.archiveName)
        do {
            try await download(to: archive, progress: progress)
        } catch {
            return .failed("Couldn’t download the local runtime: \(error.localizedDescription)")
        }

        progress?(OllamaRuntimeProgress(stage: .verifying))
        if let expected = await publishedChecksum() {
            let actual = Self.sha256(ofFileAt: archive, fileManager: fileManager)
            guard actual == expected else {
                return .failed("The runtime download did not match its published checksum.")
            }
        }

        progress?(OllamaRuntimeProgress(stage: .extracting))
        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        do {
            try await extract(archive: archive, into: unpacked)
        } catch {
            return .failed("Couldn’t unpack the local runtime: \(error.localizedDescription)")
        }
        guard fileManager.isExecutableFile(
            atPath: unpacked.appendingPathComponent("ollama").path
        ) else {
            return .failed("The runtime download did not contain a server.")
        }

        do {
            // Moved into place whole, only once it is known good, so a
            // half-written runtime directory can never be found on a later
            // launch and mistaken for an install.
            try fileManager.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: runtimeDirectory.path) {
                try fileManager.removeItem(at: runtimeDirectory)
            }
            try fileManager.moveItem(at: unpacked, to: runtimeDirectory)
            try writeLicenceNotice()
        } catch {
            return .failed("Couldn’t install the local runtime: \(error.localizedDescription)")
        }

        progress?(OllamaRuntimeProgress(stage: .starting))
        guard case let .started(url) = await start() else {
            return .failed("The runtime was installed but did not start.")
        }
        return .installed(url)
    }

    // MARK: - Running it

    private func start() async -> OllamaRuntimeOutcome {
        do {
            try fileManager.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failed(error.localizedDescription)
        }

        guard let process = await spawn(
            executableURL,
            modelsDirectory,
            privateBaseURL
        ) else {
            return .failed("The local runtime would not start.")
        }
        running = process
        // Registered where a signal handler can reach it without an actor hop.
        LocalRuntimeSupervisor.adopt(process)
        recordServerPID(process.processIdentifier)

        // Verified, not assumed. A cold start discovers GPUs first and can take
        // ten seconds before it answers, which is why the timeout is generous.
        guard await waitForServer(at: privateBaseURL) else {
            LocalRuntimeSupervisor.terminate()
            running = nil
            return .failed("The local runtime started but did not answer.")
        }
        return .started(privateBaseURL)
    }

    private func recordServerPID(_ pid: pid_t) {
        try? Data(String(pid).utf8).write(to: pidFileURL, options: .atomic)
    }

    private func recordedServerPID() -> pid_t? {
        guard let text = try? String(contentsOf: pidFileURL, encoding: .utf8) else {
            return nil
        }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func waitForServer(at baseURL: URL) async -> Bool {
        let probe = client.addressing(baseURL)
        let deadline = ContinuousClock.now.advanced(by: startupTimeout)
        while ContinuousClock.now < deadline {
            if await probe.isAvailable() { return true }
            try? await Task.sleep(for: startupPoll)
        }
        return await probe.isAvailable()
    }

    // MARK: - Steps

    private func makeStagingDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "ChamferRuntimeInstall-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func download(
        to destination: URL,
        progress: (@Sendable (OllamaRuntimeProgress) -> Void)?
    ) async throws {
        let (bytes, response) = try await session.bytes(
            for: URLRequest(url: Self.downloadURL)
        )
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw ModelAccessError.rejected(
                status: http.statusCode,
                message: "The runtime download was refused."
            )
        }

        let total = response.expectedContentLength > 0
            ? UInt64(response.expectedContentLength)
            : nil

        fileManager.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var written: UInt64 = 0

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= (1 << 20) {
                try handle.write(contentsOf: buffer)
                written += UInt64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                // Reported per megabyte: a progress bar cannot show more steps
                // than it has pixels.
                progress?(
                    OllamaRuntimeProgress(
                        stage: .downloading,
                        fraction: total.map { Double(written) / Double($0) },
                        completedBytes: written,
                        totalBytes: total
                    )
                )
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += UInt64(buffer.count)
        }

        progress?(
            OllamaRuntimeProgress(
                stage: .downloading,
                fraction: total == nil ? nil : 1,
                completedBytes: written,
                totalBytes: total
            )
        )
    }

    /// The published SHA-256 for the archive, or nil when it cannot be read.
    ///
    /// A checksum that cannot be fetched does not block the install — the
    /// download was already over TLS from the vendor. It is a second lock, not
    /// the only one.
    private func publishedChecksum() async -> String? {
        guard let (data, _) = try? await session.data(
            from: Self.checksumURL
        ), let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") where line.hasSuffix(Self.archiveName) {
            if let digest = line.split(separator: " ").first {
                return String(digest).lowercased()
            }
        }
        return nil
    }

    /// Hashes data directly. Used by tests and by anything holding an archive
    /// in memory rather than on disk.
    static func sha256(ofData data: Data) -> String? {
        var hasher = SHA256Digest()
        hasher.update(data)
        return hasher.finalizedHex
    }

    static func sha256(ofFileAt url: URL, fileManager: FileManager) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256Digest()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(chunk)
        }
        return hasher.finalizedHex
    }

    private func extract(archive: URL, into destination: URL) async throws {
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        // The archive is flat — `ollama`, the runners and the dylibs side by
        // side — so it unpacks straight into the runtime directory.
        let status = try await Self.run(
            "/usr/bin/tar",
            ["-xzf", archive.path, "-C", destination.path]
        )
        guard status == 0 else {
            throw ModelAccessError.unavailable("tar exited with status \(status).")
        }
    }

    /// Ollama is MIT licensed. Redistributing its binaries is fine; saying so
    /// beside them is the condition.
    private func writeLicenceNotice() throws {
        let notice = """
            The files in this directory are the Ollama runtime
            (https://github.com/ollama/ollama), redistributed under the MIT
            licence. They are Chamfer's private copy of the server: Chamfer
            runs them as a child process on a private port and stops them when
            it quits. Nothing here is installed into /Applications and nothing
            is registered with macOS.

            Deleting this directory is safe. Chamfer will fetch it again.
            """
        try Data(notice.utf8).write(
            to: runtimeDirectory.appendingPathComponent("README-Chamfer.txt"),
            options: .atomic
        )
    }

    static func run(_ path: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// The one place that can stop the runtime, from any thread, without waiting.
///
/// Termination has to be callable from a signal handler and from
/// `applicationWillTerminate`, both of which run on the main queue while the
/// app is going away. Routing it through the installer actor meant hopping to
/// an executor that was never going to be serviced again — the app exited on a
/// timeout and left the server running. Verified by killing the app and finding
/// the child still answering.
///
/// So this is a plain lock and a plain `Process`: no actor, no `await`, nothing
/// that can fail to be scheduled.
public enum LocalRuntimeSupervisor {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: RuntimeProcess?
    /// A server this launch did not spawn but is now responsible for.
    ///
    /// Chamfer can be killed in ways nothing can intercept, which leaves the
    /// runtime orphaned. The next launch finds it answering and adopts it
    /// rather than starting a second — but adoption has to include the right to
    /// stop it, or the orphan would then survive every clean quit as well.
    nonisolated(unsafe) private static var adoptedPID: pid_t?

    public static func adopt(_ process: RuntimeProcess?) {
        lock.lock()
        current = process
        adoptedPID = nil
        lock.unlock()
    }

    public static func adopt(pid: pid_t) {
        lock.lock()
        current = nil
        adoptedPID = pid
        lock.unlock()
    }

    /// Stops the runtime and returns once it is gone. Safe to call twice, and
    /// safe to call when nothing is running.
    public static func terminate() {
        lock.lock()
        let process = current
        let orphan = adoptedPID
        current = nil
        adoptedPID = nil
        lock.unlock()

        if let process {
            process.stopAndWait()
            return
        }
        guard let orphan, orphan > 0 else { return }
        kill(orphan, SIGTERM)
        let deadline = Date().addingTimeInterval(2)
        while kill(orphan, 0) == 0, Date() < deadline {
            usleep(50_000)
        }
        if kill(orphan, 0) == 0 { kill(orphan, SIGKILL) }
    }
}

/// Chamfer's server, running as its child.
public final class RuntimeProcess: @unchecked Sendable {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    public var isRunning: Bool { process.isRunning }
    public var processIdentifier: pid_t { process.processIdentifier }

    public func terminate() {
        stopAndWait()
    }

    /// SIGTERM, then SIGKILL if it is still there.
    ///
    /// The second half is not paranoia: the promise is that quitting Chamfer
    /// leaves nothing behind, and a server that ignores a polite request would
    /// break it.
    func stopAndWait(timeout: TimeInterval = 2) {
        guard process.isRunning else { return }
        process.terminate()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// Starts `ollama serve` with Chamfer's own port and model directory.
    ///
    /// `terminationHandler` is deliberately unset: this process is meant to
    /// outlive the call and die with the app.
    static func launch(
        executable: URL,
        modelsDirectory: URL,
        baseURL: URL
    ) -> RuntimeProcess? {
        guard let host = baseURL.host, let port = baseURL.port else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "\(host):\(port)"
        environment["OLLAMA_MODELS"] = modelsDirectory.path
        // Long enough that consecutive notes reuse a loaded model, short enough
        // that a Mac left idle gets its memory back.
        environment["OLLAMA_KEEP_ALIVE"] = "10m"
        process.environment = environment

        do {
            try process.run()
        } catch {
            return nil
        }
        return RuntimeProcess(process: process)
    }
}

/// A minimal SHA-256, so verifying a download does not pull CryptoKit into a
/// target that otherwise only speaks HTTP.
struct SHA256Digest {
    private var state: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
        0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19
    ]
    private var buffer = [UInt8]()
    private var length: UInt64 = 0

    private static let k: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1,
        0x923f_82a4, 0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
        0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786,
        0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147,
        0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
        0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
        0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a,
        0x5b9c_ca4f, 0x682e_6ff3, 0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
        0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2
    ]

    mutating func update(_ data: Data) {
        length &+= UInt64(data.count) &* 8
        buffer.append(contentsOf: data)
        while buffer.count >= 64 {
            compress(Array(buffer.prefix(64)))
            buffer.removeFirst(64)
        }
    }

    var finalizedHex: String {
        var copy = self
        var tail = copy.buffer
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            tail.append(UInt8((copy.length >> UInt64(shift)) & 0xff))
        }
        for offset in stride(from: 0, to: tail.count, by: 64) {
            copy.compress(Array(tail[offset..<(offset + 64)]))
        }
        return copy.state.map { String(format: "%08x", $0) }.joined()
    }

    private mutating func compress(_ block: [UInt8]) {
        var w = [UInt32](repeating: 0, count: 64)
        for index in 0..<16 {
            let base = index * 4
            w[index] = (UInt32(block[base]) << 24)
                | (UInt32(block[base + 1]) << 16)
                | (UInt32(block[base + 2]) << 8)
                | UInt32(block[base + 3])
        }
        for index in 16..<64 {
            let s0 = rotate(w[index - 15], 7) ^ rotate(w[index - 15], 18) ^ (w[index - 15] >> 3)
            let s1 = rotate(w[index - 2], 17) ^ rotate(w[index - 2], 19) ^ (w[index - 2] >> 10)
            w[index] = w[index - 16] &+ s0 &+ w[index - 7] &+ s1
        }

        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]

        for index in 0..<64 {
            let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
            let ch = (e & f) ^ (~e & g)
            let temp1 = h &+ s1 &+ ch &+ Self.k[index] &+ w[index]
            let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj

            h = g; g = f; f = e; e = d &+ temp1
            d = c; c = b; b = a; a = temp1 &+ temp2
        }

        state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
    }

    private func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
