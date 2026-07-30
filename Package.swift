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
        .executable(name: "ChamferGallery", targets: ["ChamferGallery"]),
        .library(name: "ChamferCore", targets: ["ChamferCore"]),
        .library(name: "ChamferUI", targets: ["ChamferUI"])
    ],
    targets: [
        .executableTarget(
            // Menu bar shell, review window, settings.
            name: "Chamfer",
            dependencies: ["ChamferCore", "ChamferUI", "ChamferWatch", "ChamferRewrite"],
            path: "Sources/Chamfer"
        ),
        .executableTarget(
            // Stands in for the Xcode preview canvas: every component in every
            // state, driven by fixtures. This is the design iteration loop.
            name: "ChamferGallery",
            dependencies: ["ChamferUI", "ChamferFixtures"],
            path: "Sources/ChamferGallery"
        ),
        .target(
            // Pure logic: document model, rule engine, diffing, masking.
            // No file I/O, no network, no UI, so it stays fully testable.
            name: "ChamferCore",
            path: "Sources/ChamferCore"
        ),
        .target(
            // The design system: tokens, primitives, components, and views
            // composed from them. Depends only on ChamferCore, so it cannot
            // reach for app state and stays reusable by construction.
            name: "ChamferUI",
            dependencies: ["ChamferCore"],
            path: "Sources/ChamferUI"
        ),
        .target(
            // The fake data layer. Real shapes, deliberately hostile values.
            // Kept out of ChamferCore so none of it can ship in the app.
            name: "ChamferFixtures",
            dependencies: ["ChamferCore"],
            path: "Sources/ChamferFixtures"
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
