import ChamferCore
import Foundation
import Testing

@testable import ChamferRewrite

/// Serves the Ollama download and the server's health check, and records what
/// was asked for — so a test can assert what was *not* downloaded.
final class StubbedRuntimeHost: @unchecked Sendable {
    static let shared = StubbedRuntimeHost()

    private let lock = NSLock()
    private var recordedPaths: [String] = []
    private var serverRunning = false
    private var archive = Data()
    private var downloadFails = false
    private var corrupt = false

    func reset(
        serverRunning: Bool = false,
        archive: Data = Data(),
        downloadFails: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }
        recordedPaths = []
        self.serverRunning = serverRunning
        self.archive = archive
        self.downloadFails = downloadFails
        corrupt = false
    }

    /// Serves a body that does not match the checksum it also serves.
    func corruptDownload() {
        lock.lock()
        corrupt = true
        lock.unlock()
    }

    /// Lets a test make the server start answering once it has been "launched".
    func startServer() {
        lock.lock()
        serverRunning = true
        lock.unlock()
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    var downloadCount: Int {
        paths.filter { $0.contains("ollama-darwin.tgz") }.count
    }

    func respond(to request: URLRequest) -> (status: Int, body: Data) {
        let path = request.url?.path ?? ""
        lock.lock()
        recordedPaths.append(path)
        let running = serverRunning
        let payload = archive
        let fails = downloadFails
        let tampered = corrupt
        lock.unlock()

        if path.contains("ollama-darwin.tgz") {
            if fails { return (500, Data()) }
            return (200, tampered ? payload + Data([0x00]) : payload)
        }
        if path.contains("sha256sum.txt") {
            let digest = OllamaRuntimeInstaller.sha256(
                ofData: payload
            ) ?? ""
            return (200, Data("\(digest)  ./ollama-darwin.tgz\n".utf8))
        }
        if path == "/api/version" {
            return running ? (200, Data(#"{"version":"0.5.0"}"#.utf8)) : (503, Data())
        }
        return (404, Data())
    }
}

final class StubbedRuntimeProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        let host = request.url?.host
        return host == "127.0.0.1" || host == "ollama.com" || host == "github.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let (status, body) = StubbedRuntimeHost.shared.respond(to: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(body.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A real gzipped tar with a real executable `ollama` at its root, so the
/// installer's own extraction and executable check are exercised rather than
/// mocked. Mirrors the shape of the published `ollama-darwin.tgz`, which is
/// flat: the binary, its runners and its dylibs side by side.
private func makeArchive() throws -> Data {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ChamferArchive-\(UUID().uuidString)", isDirectory: true)
    let payload = root.appendingPathComponent("payload", isDirectory: true)
    try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let binary = payload.appendingPathComponent("ollama")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: binary.path
    )
    try Data("runner".utf8).write(
        to: payload.appendingPathComponent("libggml-base.dylib")
    )

    let archive = root.appendingPathComponent("ollama-darwin.tgz")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-czf", archive.path, "-C", payload.path, "."]
    try process.run()
    process.waitUntilExit()
    return try Data(contentsOf: archive)
}

private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubbedRuntimeProtocol.self]
    return URLSession(configuration: configuration)
}

@Suite(.serialized)
struct OllamaRuntimeInstallerTests {
    private static let shared = URL(string: "http://127.0.0.1:11434")!
    private static let priv = URL(string: "http://127.0.0.1:11913")!

    private func sandbox() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChamferSupport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func installer(
        support: URL,
        launches: LaunchRecorder
    ) -> OllamaRuntimeInstaller {
        let session = stubbedSession()
        return OllamaRuntimeInstaller(
            session: session,
            client: OllamaClient(session: session, baseURL: Self.shared),
            supportDirectory: support,
            sharedBaseURL: Self.shared,
            privateBaseURL: Self.priv,
            startupTimeout: .seconds(3),
            startupPoll: .milliseconds(20),
            spawn: { executable, models, _ in
                launches.record(executable, models: models)
                // Starting the server is what makes it answer, as in life.
                StubbedRuntimeHost.shared.startServer()
                return RuntimeProcess(process: Process())
            }
        )
    }

    private func runtimeBinary(in support: URL) -> URL {
        support.appendingPathComponent("Runtime/ollama")
    }

    /// The point of the whole feature: a Mac with no Ollama gets a working
    /// server, and nothing lands in /Applications.
    @Test func aMacWithoutOllamaGetsTheServerAndNothingElse() async throws {
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()

        let outcome = await installer(support: support, launches: launches)
            .ensureAvailable()

        #expect(outcome == .installed(Self.priv))
        #expect(FileManager.default.isExecutableFile(atPath: runtimeBinary(in: support).path))
        #expect(launches.count == 1)
        #expect(StubbedRuntimeHost.shared.downloadCount == 1)
    }

    /// Everything lives under Chamfer: the runtime and the models both. Deleting
    /// Chamfer's Application Support really does remove all of it.
    @Test func theRuntimeAndItsModelsLiveUnderChamfer() async throws {
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()

        _ = await installer(support: support, launches: launches).ensureAvailable()

        #expect(launches.lastModels?.path.hasPrefix(support.path) == true)
        #expect(launches.lastExecutable?.path.hasPrefix(support.path) == true)
        // The licence notice ships beside the binaries it applies to.
        #expect(
            FileManager.default.fileExists(
                atPath: support.appendingPathComponent("Runtime/README-Chamfer.txt").path
            )
        )
    }

    /// Somebody who already runs Ollama keeps running theirs. Chamfer borrows
    /// it and downloads nothing.
    @Test func anExistingInstallationIsBorrowedRatherThanDuplicated() async throws {
        StubbedRuntimeHost.shared.reset(serverRunning: true, archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()

        let outcome = await installer(support: support, launches: launches)
            .ensureAvailable()

        #expect(outcome == .usingExistingInstallation(Self.shared))
        #expect(StubbedRuntimeHost.shared.downloadCount == 0)
        #expect(launches.count == 0)
        #expect(!FileManager.default.fileExists(atPath: runtimeBinary(in: support).path))
    }

    /// On every launch after the first the runtime is on disk but not running.
    /// It must be started, not fetched again.
    @Test func anInstalledRuntimeIsStartedRatherThanDownloadedAgain() async throws {
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()
        let subject = installer(support: support, launches: launches)

        let first = await subject.ensureAvailable()
        #expect(first == .installed(Self.priv))

        // A fresh installer over the same directory: a new launch.
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let relaunched = LaunchRecorder()
        let second = await installer(support: support, launches: relaunched)
            .ensureAvailable()

        #expect(second == .started(Self.priv))
        #expect(StubbedRuntimeHost.shared.downloadCount == 0)
        #expect(relaunched.count == 1)
    }

    @Test func repeatedCallsInOneSessionDownloadAndStartExactlyOnce() async throws {
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()
        let subject = installer(support: support, launches: launches)

        _ = await subject.ensureAvailable()
        _ = await subject.ensureAvailable()
        _ = await subject.ensureAvailable()

        #expect(StubbedRuntimeHost.shared.downloadCount == 1)
        #expect(launches.count == 1)
    }

    /// Two callers at once join one install rather than each fetching 145 MB.
    @Test func concurrentCallersShareOneInstall() async throws {
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()
        let subject = installer(support: support, launches: launches)

        async let first = subject.ensureAvailable()
        async let second = subject.ensureAvailable()
        async let third = subject.ensureAvailable()
        let outcomes = await [first, second, third]
        let allReady = outcomes.allSatisfy { $0.isReady }

        #expect(allReady)
        #expect(StubbedRuntimeHost.shared.downloadCount == 1)
    }

    /// A download that does not match its published checksum is discarded. This
    /// is executable code being fetched over the network; a second lock is
    /// worth having.
    @Test func aDownloadThatFailsItsChecksumIsRefused() async throws {
        // The stub serves the checksum of the *real* archive while serving a
        // different body, so the two cannot agree.
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()
        StubbedRuntimeHost.shared.corruptDownload()

        let outcome = await installer(support: support, launches: launches)
            .ensureAvailable()

        #expect(!outcome.isReady)
        #expect(!FileManager.default.fileExists(atPath: runtimeBinary(in: support).path))
        #expect(launches.count == 0)
    }

    @Test func aFailedDownloadInstallsNothing() async throws {
        StubbedRuntimeHost.shared.reset(downloadFails: true)
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()

        let outcome = await installer(support: support, launches: launches)
            .ensureAvailable()

        #expect(!outcome.isReady)
        #expect(!FileManager.default.fileExists(atPath: runtimeBinary(in: support).path))
        #expect(launches.count == 0)
    }

    /// An archive without a server in it is a failure, not a half-install.
    @Test func anArchiveWithoutAServerIsRejected() async throws {
        StubbedRuntimeHost.shared.reset(archive: Data("not an archive".utf8))
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let launches = LaunchRecorder()

        let outcome = await installer(support: support, launches: launches)
            .ensureAvailable()

        #expect(!outcome.isReady)
        #expect(!FileManager.default.fileExists(atPath: runtimeBinary(in: support).path))
    }

    /// The pid is written down so a launch that finds an orphan can adopt *and*
    /// stop it. Without the file, an orphan left by a killed Chamfer would
    /// survive every clean quit afterwards.
    @Test func spawningRecordsThePidSoAnOrphanCanBeCollectedLater() async throws {
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }

        _ = await installer(support: support, launches: LaunchRecorder())
            .ensureAvailable()

        let pidFile = support.appendingPathComponent("Runtime/server.pid")
        #expect(FileManager.default.fileExists(atPath: pidFile.path))
    }

    /// Called on every quit, including quits where nothing was ever started.
    @Test func stoppingWhenNothingIsRunningIsHarmless() {
        LocalRuntimeSupervisor.adopt(nil)
        LocalRuntimeSupervisor.terminate()
        LocalRuntimeSupervisor.terminate()
    }

    @Test func everyStageReportsSomethingTheInterfaceCanSay() async throws {
        StubbedRuntimeHost.shared.reset(archive: try makeArchive())
        let support = try sandbox()
        defer { try? FileManager.default.removeItem(at: support) }
        let stages = StageRecorder()

        _ = await installer(support: support, launches: LaunchRecorder())
            .ensureAvailable { stages.record($0) }

        let seen = stages.stages
        #expect(seen.contains(.checking))
        #expect(seen.contains(.downloading))
        #expect(seen.contains(.verifying))
        #expect(seen.contains(.extracting))
        #expect(seen.contains(.starting))
        #expect(stages.summaries.allSatisfy { !$0.isEmpty })
    }
}

final class LaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var launched: [(executable: URL, models: URL)] = []

    func record(_ executable: URL, models: URL) {
        lock.lock()
        launched.append((executable, models))
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return launched.count
    }

    var lastExecutable: URL? {
        lock.lock()
        defer { lock.unlock() }
        return launched.last?.executable
    }

    var lastModels: URL? {
        lock.lock()
        defer { lock.unlock() }
        return launched.last?.models
    }
}

final class StageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [OllamaRuntimeProgress] = []

    func record(_ progress: OllamaRuntimeProgress) {
        lock.lock()
        recorded.append(progress)
        lock.unlock()
    }

    var stages: [OllamaRuntimeStage] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map(\.stage)
    }

    var summaries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map(\.summary)
    }
}
