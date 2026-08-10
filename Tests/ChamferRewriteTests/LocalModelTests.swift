import ChamferCore
import Foundation
import Testing

@testable import ChamferRewrite

// MARK: - Device-to-model mapping

private func device(
    memoryGB: Int,
    appleSilicon: Bool = true,
    diskGB: Int? = 200
) -> DeviceProfile {
    DeviceProfile(
        physicalMemoryBytes: UInt64(memoryGB) * DeviceProfile.bytesPerGigabyte,
        performanceCoreCount: 8,
        totalCoreCount: 10,
        isAppleSilicon: appleSilicon,
        availableDiskBytes: diskGB.map {
            UInt64($0) * DeviceProfile.bytesPerGigabyte
        }
    )
}

@Test func everyMacGetsExactlyOneModelAndItRisesWithMemory() {
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 4)).id == "qwen3.5:0.8b")
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 8)).id == "qwen3.5:2b")
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 12)).id == "qwen3.5:2b")
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 16)).id == "qwen3.5:4b")
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 24)).id == "qwen3.5:9b")
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 36)).id == "qwen3.5:9b")
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 64)).id == "gpt-oss:20b")
    #expect(LocalModelSelection.recommended(for: device(memoryGB: 128)).id == "gpt-oss:20b")
}

/// Selection is total. There is no "unsupported Mac" state for the rest of the
/// app to carry, because a Mac too small for any tier still gets the floor.
@Test func aMacTooSmallForAnyTierStillGetsTheFloorModel() {
    let tiny = DeviceProfile(
        physicalMemoryBytes: 0,
        performanceCoreCount: 1,
        totalCoreCount: 1,
        isAppleSilicon: false
    )

    #expect(LocalModelSelection.recommended(for: tiny).id == LocalModelCatalog.floor.id)
}

/// Memory is not the only constraint. Without unified memory a large model
/// spends its time moving weights, so an Intel Mac is held to the small tiers
/// however much RAM it has.
@Test func anIntelMacIsCappedRegardlessOfItsMemory() {
    let intel = device(memoryGB: 128, appleSilicon: false)

    #expect(LocalModelSelection.recommended(for: intel).id == "qwen3.5:2b")
    #expect(
        LocalModelSelection.rationale(
            for: intel,
            model: LocalModelSelection.recommended(for: intel)
        ).contains("Intel")
    )
}

/// The same hardware always produces the same answer — this is what lets the
/// rest of the app treat the recommendation as the device's model rather than
/// as something to remember.
@Test func theSameDeviceAlwaysProducesTheSameModel() {
    let profile = device(memoryGB: 18)
    let answers = Set((0..<50).map { _ in
        LocalModelSelection.recommended(for: profile).id
    })

    #expect(answers.count == 1)
}

@Test func theLadderIsOrderedAndStartsAtTheFloor() {
    let thresholds = LocalModelCatalog.ladder.map(\.minimumMemoryGB)

    #expect(thresholds == thresholds.sorted())
    #expect(LocalModelCatalog.ladder.first?.id == LocalModelCatalog.floor.id)
    #expect(LocalModelCatalog.floor.minimumMemoryGB == 0)
    #expect(Set(LocalModelCatalog.ladder.map(\.id)).count == LocalModelCatalog.ladder.count)
}

@Test func aVolumeWithoutRoomForTheDownloadIsRecognised() {
    let cramped = device(memoryGB: 24, diskGB: 4)
    let roomy = device(memoryGB: 24, diskGB: 60)
    let model = LocalModelSelection.recommended(for: roomy)

    #expect(!LocalModelSelection.hasRoom(for: model, on: cramped))
    #expect(LocalModelSelection.hasRoom(for: model, on: roomy))
    // A volume that will not answer is treated as having room; the pull reports
    // its own failure rather than the app refusing pre-emptively.
    #expect(
        LocalModelSelection.hasRoom(
            for: model,
            on: device(memoryGB: 24, diskGB: nil)
        )
    )
}

// MARK: - Presence

@Test func presenceIgnoresHowATagHappensToBeWritten() {
    #expect(LocalModelIdentity.normalized("qwen3.5:4b") == "qwen3.5:4b")
    #expect(LocalModelIdentity.normalized("gpt-oss") == "gpt-oss:latest")
    #expect(LocalModelIdentity.normalized("  qwen3.5:4b  ") == "qwen3.5:4b")

    #expect(LocalModelIdentity.contains("gpt-oss", in: ["gpt-oss:latest"]))
    #expect(LocalModelIdentity.contains("gpt-oss:latest", in: ["gpt-oss"]))
    #expect(!LocalModelIdentity.contains("qwen3.5:4b", in: ["qwen3.5:9b"]))
}

/// Ollama can report the same model under both `name` and `model`. Normalising
/// on the way in is what stops one model being counted twice.
@Test func duplicateRegistrationsCollapseToOneModel() throws {
    let payload = Data("""
        {"models":[
          {"name":"qwen3.5:4b","model":"qwen3.5:4b"},
          {"name":"qwen3.5:4b"},
          {"model":"gpt-oss"}
        ]}
        """.utf8)

    let installed = try OllamaAPI.installedModelIDs(from: payload)

    #expect(installed == ["qwen3.5:4b", "gpt-oss:latest"])
}

// MARK: - Download progress

@Test func pullProgressIsReadWhenThereIsATotalAndHonestWhenThereIsNot() throws {
    let starting = try OllamaAPI.pullProgress(from: #"{"status":"pulling manifest"}"#)
    #expect(starting?.fraction == nil)
    #expect(starting?.stage == "pulling manifest")

    let midway = try OllamaAPI.pullProgress(
        from: #"{"status":"downloading","completed":50,"total":200}"#
    )
    #expect(midway?.fraction == 0.25)
    #expect(midway?.completedBytes == 50)

    let blank = try OllamaAPI.pullProgress(from: "   ")
    #expect(blank == nil)
}

@Test func aPullThatReportsAnErrorStopsRatherThanContinuing() {
    #expect(throws: ModelAccessError.self) {
        _ = try OllamaAPI.pullProgress(from: #"{"error":"model not found"}"#)
    }
}

// MARK: - Installation idempotency

/// A fake Ollama. Records every path asked for, so a test can assert what was
/// *not* requested — which is the whole point of an idempotent installer.
final class StubbedOllama: @unchecked Sendable {
    static let shared = StubbedOllama()

    private let lock = NSLock()
    private var recordedPaths: [String] = []
    private var installed: Set<String> = []
    private var installAfterPull = true
    private var pullFails = false
    private var pullDelay: Duration = .zero

    func reset(
        installed: Set<String> = [],
        installAfterPull: Bool = true,
        pullFails: Bool = false,
        pullDelay: Duration = .zero
    ) {
        lock.lock()
        defer { lock.unlock() }
        recordedPaths = []
        self.installed = installed
        self.installAfterPull = installAfterPull
        self.pullFails = pullFails
        self.pullDelay = pullDelay
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    var pullCount: Int {
        paths.filter { $0.hasSuffix("/api/pull") }.count
    }

    func respond(to request: URLRequest) -> (status: Int, body: Data) {
        let path = request.url?.path ?? ""
        lock.lock()
        recordedPaths.append(path)
        let currentlyInstalled = installed
        let willInstall = installAfterPull
        let fails = pullFails
        let delay = pullDelay
        lock.unlock()

        switch path {
        case "/api/version":
            return (200, Data(#"{"version":"0.5.0"}"#.utf8))
        case "/api/tags":
            let entries = currentlyInstalled
                .map { #"{"name":"\#($0)"}"# }
                .joined(separator: ",")
            return (200, Data(#"{"models":[\#(entries)]}"#.utf8))
        case "/api/pull":
            if delay > .zero { Thread.sleep(forTimeInterval: 0.05) }
            if fails { return (500, Data(#"{"error":"nope"}"#.utf8)) }
            if willInstall, let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let model = json["model"] as? String {
                lock.lock()
                installed.insert(LocalModelIdentity.normalized(model))
                lock.unlock()
            }
            return (
                200,
                Data("""
                    {"status":"pulling manifest"}
                    {"status":"downloading","completed":50,"total":100}
                    {"status":"success"}
                    """.utf8)
            )
        default:
            return (404, Data())
        }
    }
}

final class StubbedOllamaProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "127.0.0.1"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // `bytes(for:)` reads `httpBodyStream` rather than `httpBody`, so the
        // body has to be recovered before the stub can see which model was
        // asked for.
        var resolved = request
        if resolved.httpBody == nil, let stream = resolved.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(contentsOf: buffer[0..<read])
            }
            stream.close()
            resolved.httpBody = data
        }

        let (status, body) = StubbedOllama.shared.respond(to: resolved)
        let response = HTTPURLResponse(
            url: resolved.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedClient() -> OllamaClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubbedOllamaProtocol.self]
    return OllamaClient(session: URLSession(configuration: configuration))
}

private let testModel = LocalModelDescriptor(
    id: "qwen3.5:4b",
    displayName: "Qwen3.5",
    parameterLabel: "4B",
    downloadBytes: 3_650_722_201,
    minimumMemoryGB: 16,
    characterisation: "Test model."
)

@Suite(.serialized)
struct LocalModelInstallerTests {
    /// The most important property in the whole model system: a model that is
    /// already on disk is never fetched again, whatever the interface believes.
    @Test func anInstalledModelIsReusedAndNeverDownloadedAgain() async {
        StubbedOllama.shared.reset(installed: ["qwen3.5:4b"])
        let installer = LocalModelInstaller(client: stubbedClient())

        let outcome = await installer.ensureInstalled(
            testModel,
            device: device(memoryGB: 24)
        )

        #expect(outcome == .alreadyPresent)
        #expect(StubbedOllama.shared.pullCount == 0)
    }

    @Test func aMissingModelIsDownloadedOnceAndThenVerified() async {
        StubbedOllama.shared.reset()
        let installer = LocalModelInstaller(client: stubbedClient())

        let outcome = await installer.ensureInstalled(
            testModel,
            device: device(memoryGB: 24)
        )

        #expect(outcome == .downloaded)
        #expect(StubbedOllama.shared.pullCount == 1)
        #expect(await installer.isInstalled(testModel.id))
    }

    /// Repeated launches, a re-entered setup flow, restored state: whatever
    /// asks, the second call finds the model and costs nothing.
    @Test func repeatedInstallsDownloadExactlyOnce() async {
        StubbedOllama.shared.reset()
        let installer = LocalModelInstaller(client: stubbedClient())
        let profile = device(memoryGB: 24)

        let first = await installer.ensureInstalled(testModel, device: profile)
        let second = await installer.ensureInstalled(testModel, device: profile)
        let third = await installer.ensureInstalled(testModel, device: profile)

        #expect(first == .downloaded)
        #expect(second == .alreadyPresent)
        #expect(third == .alreadyPresent)
        #expect(StubbedOllama.shared.pullCount == 1)
    }

    /// Two callers arriving at once — a setup flow and a launch check — join
    /// one download rather than starting two of the same multi-gigabyte blob.
    @Test func concurrentInstallsShareASingleDownload() async {
        StubbedOllama.shared.reset(pullDelay: .milliseconds(50))
        let installer = LocalModelInstaller(client: stubbedClient())
        let profile = device(memoryGB: 24)

        async let first = installer.ensureInstalled(testModel, device: profile)
        async let second = installer.ensureInstalled(testModel, device: profile)
        async let third = installer.ensureInstalled(testModel, device: profile)
        let outcomes = await [first, second, third]
        let allInstalled = outcomes.allSatisfy { $0.isInstalled }

        #expect(allInstalled)
        #expect(StubbedOllama.shared.pullCount == 1)
    }

    /// An interrupted pull leaves nothing registered with Ollama. That has to
    /// read as *not installed* rather than as a model with nothing behind it.
    @Test func aPullThatLeavesNothingOnDiskIsAFailedInstall() async {
        StubbedOllama.shared.reset(installAfterPull: false)
        let installer = LocalModelInstaller(client: stubbedClient())

        let outcome = await installer.ensureInstalled(
            testModel,
            device: device(memoryGB: 24)
        )

        #expect(!outcome.isInstalled)
        #expect(await !installer.isInstalled(testModel.id))
    }

    @Test func aRefusedPullIsReportedWithItsReason() async {
        StubbedOllama.shared.reset(pullFails: true)
        let installer = LocalModelInstaller(client: stubbedClient())

        let outcome = await installer.ensureInstalled(
            testModel,
            device: device(memoryGB: 24)
        )

        guard case .failed = outcome else {
            Issue.record("Expected a failure, got \(outcome)")
            return
        }
    }

    /// Checked before a byte is fetched, so a full disk fails immediately
    /// rather than halfway through a download.
    @Test func anInstallWithoutRoomRefusesBeforeDownloading() async {
        StubbedOllama.shared.reset()
        let installer = LocalModelInstaller(client: stubbedClient())

        let outcome = await installer.ensureInstalled(
            testModel,
            device: device(memoryGB: 24, diskGB: 1)
        )

        #expect(!outcome.isInstalled)
        #expect(StubbedOllama.shared.pullCount == 0)
    }

    @Test func downloadProgressIsReportedWhileThePullRuns() async {
        StubbedOllama.shared.reset()
        let installer = LocalModelInstaller(client: stubbedClient())
        let recorder = ProgressRecorder()

        _ = await installer.ensureInstalled(
            testModel,
            device: device(memoryGB: 24),
            progress: { recorder.record($0) }
        )

        #expect(recorder.stages.contains("pulling manifest"))
        #expect(recorder.fractions.contains(0.5))
    }

    /// Nothing is reported for a model that was already here. A progress bar
    /// that completes instantly is a worse answer than no progress bar.
    @Test func noProgressIsReportedForAModelThatWasAlreadyPresent() async {
        StubbedOllama.shared.reset(installed: ["qwen3.5:4b"])
        let installer = LocalModelInstaller(client: stubbedClient())
        let recorder = ProgressRecorder()

        _ = await installer.ensureInstalled(
            testModel,
            device: device(memoryGB: 24),
            progress: { recorder.record($0) }
        )

        #expect(recorder.stages.isEmpty)
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [LocalModelDownloadProgress] = []

    func record(_ progress: LocalModelDownloadProgress) {
        lock.lock()
        recorded.append(progress)
        lock.unlock()
    }

    var stages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map(\.stage)
    }

    var fractions: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.compactMap(\.fraction)
    }
}
