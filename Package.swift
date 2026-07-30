// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Chamfer",
    defaultLocalization: "en",
    platforms: [
        // FoundationModels ships with macOS 26, and it is the first rewrite
        // backend, so the whole package targets 26 rather than gating every
        // call site behind availability checks.
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Chamfer", targets: ["Chamfer"]),
        .library(name: "ChamferCore", targets: ["ChamferCore"])
    ],
    targets: [
        .executableTarget(
            // Menu bar shell, review window, settings.
            name: "Chamfer",
            dependencies: ["ChamferCore", "ChamferWatch", "ChamferRewrite"],
            path: "Sources/Chamfer"
        ),
        .target(
            // Pure logic: document model, rule engine, diffing, masking.
            // No file I/O, no network, no UI, so it stays fully testable.
            name: "ChamferCore",
            path: "Sources/ChamferCore"
        ),
        .target(
            // FSEvents watching, debounce, atomic writes, snapshot history.
            name: "ChamferWatch",
            dependencies: ["ChamferCore"],
            path: "Sources/ChamferWatch"
        ),
        .target(
            // Rewriter protocol and its local-model implementations.
            name: "ChamferRewrite",
            dependencies: ["ChamferCore"],
            path: "Sources/ChamferRewrite"
        ),
        .testTarget(
            name: "ChamferCoreTests",
            dependencies: ["ChamferCore"],
            path: "Tests/ChamferCoreTests"
        ),
        .testTarget(
            name: "ChamferWatchTests",
            dependencies: ["ChamferWatch"],
            path: "Tests/ChamferWatchTests"
        ),
        .testTarget(
            name: "ChamferRewriteTests",
            dependencies: ["ChamferRewrite"],
            path: "Tests/ChamferRewriteTests"
        )
    ]
)
