import CoreGraphics

public enum ModelsBackendID: String, CaseIterable, Hashable, Sendable {
    case apple
    case ollama
    case mlx
}

public enum ModelsConnectionState: Equatable, Sendable {
    case connected
    case testing
    case failed
}

public enum ModelsInstallationState: Equatable, Sendable {
    case notInstalled
    case downloading
    case installed
}

public struct ModelsLandscapeState: Equatable, Sendable {
    public var active: ModelsBackendID
    public var selected: ModelsBackendID
    public var expanded: ModelsBackendID?
    public var connection: ModelsConnectionState
    public var installation: ModelsInstallationState

    public init(
        active: ModelsBackendID = .apple,
        selected: ModelsBackendID = .apple,
        expanded: ModelsBackendID? = nil,
        connection: ModelsConnectionState = .connected,
        installation: ModelsInstallationState = .notInstalled
    ) {
        self.active = active
        self.selected = selected
        self.expanded = expanded
        self.connection = connection
        self.installation = installation
    }

    public mutating func select(_ backend: ModelsBackendID) {
        selected = backend
        expanded = backend
    }

    public mutating func closeConfiguration() {
        selected = active
        expanded = nil
    }

    public mutating func activateSelected() {
        active = selected
        expanded = nil
    }

    public mutating func beginConnectionTest() {
        connection = .testing
    }

    public mutating func finishConnectionTest(connected: Bool) {
        connection = connected ? .connected : .failed
    }

    public mutating func beginDownload() {
        installation = .downloading
    }

    public mutating func finishDownload() {
        installation = .installed
    }

    public func status(
        for backend: ModelsBackendID,
        appleAvailable: Bool
    ) -> String {
        if backend == active {
            if backend == .apple, !appleAvailable { return "UNAVAILABLE" }
            return "ACTIVE"
        }

        switch backend {
        case .apple:
            return appleAvailable ? "AVAILABLE" : "UNAVAILABLE"
        case .ollama:
            return "NOT CONFIGURED"
        case .mlx:
            return installation == .installed ? "READY" : "NOT INSTALLED"
        }
    }
}

public struct ModelsLandscapePlacement: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let opacity: Double
    public let scale: CGFloat

    public init(x: CGFloat, y: CGFloat, opacity: Double, scale: CGFloat) {
        self.x = x
        self.y = y
        self.opacity = opacity
        self.scale = scale
    }
}

public enum ModelsLandscapeLayout {
    public static func placement(
        for backend: ModelsBackendID,
        state: ModelsLandscapeState
    ) -> ModelsLandscapePlacement {
        let base = basePlacement(for: backend)
        guard let expanded = state.expanded else { return base }

        if backend == expanded {
            return ModelsLandscapePlacement(
                x: base.x,
                y: backend == .mlx ? 0.29 : base.y,
                opacity: 1,
                scale: 1.045
            )
        }

        switch backend {
        case .apple:
            return ModelsLandscapePlacement(
                x: base.x - 0.055,
                y: base.y - 0.015,
                opacity: 0.28,
                scale: 0.96
            )
        case .ollama:
            return ModelsLandscapePlacement(
                x: base.x + 0.055,
                y: base.y - 0.015,
                opacity: 0.28,
                scale: 0.96
            )
        case .mlx:
            return ModelsLandscapePlacement(
                x: base.x,
                y: base.y + 0.045,
                opacity: 0.28,
                scale: 0.96
            )
        }
    }

    public static func sheetCenterX(for backend: ModelsBackendID) -> CGFloat {
        switch backend {
        case .apple: 0.39
        case .ollama: 0.61
        case .mlx: 0.50
        }
    }

    private static func basePlacement(
        for backend: ModelsBackendID
    ) -> ModelsLandscapePlacement {
        switch backend {
        case .apple:
            ModelsLandscapePlacement(x: 0.24, y: 0.34, opacity: 1, scale: 1)
        case .ollama:
            ModelsLandscapePlacement(x: 0.76, y: 0.35, opacity: 1, scale: 1)
        case .mlx:
            ModelsLandscapePlacement(x: 0.50, y: 0.66, opacity: 1, scale: 1)
        }
    }
}
