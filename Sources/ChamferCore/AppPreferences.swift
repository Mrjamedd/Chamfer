import Foundation

/// The notification categories of version 1.0.
///
/// Each is independently switchable, so this is a set rather than a level:
/// someone who wants to know about failures and nothing else is a normal
/// person, not an edge case.
public enum NotificationCategory: String, Sendable, Codable, CaseIterable, Identifiable {
    case rewriteReady
    case automaticApplied
    case rewriteFailed
    case folderUnavailable
    case modelUnavailable
    case periodicSummary

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rewriteReady: "A rewrite is ready to review"
        case .automaticApplied: "A rewrite was applied automatically"
        case .rewriteFailed: "A rewrite failed"
        case .folderUnavailable: "A connected folder isn't available"
        case .modelUnavailable: "The selected model isn't available"
        case .periodicSummary: "A summary of what's done and waiting"
        }
    }

    public var detail: String {
        switch self {
        case .rewriteReady: "Only when the rewrite is queued rather than applied."
        case .automaticApplied: "Tells you a note changed without being asked."
        case .rewriteFailed: "Includes the reason, and the note is always left alone."
        case .folderUnavailable: "An unplugged disk, or access that has been withdrawn."
        case .modelUnavailable: "Rules keep running; rewrites wait."
        case .periodicSummary: "One notification rather than one per note."
        }
    }

    /// What a fresh install notifies about.
    ///
    /// The two that mean something happened to a file, and the one that means
    /// something stopped working. The rest are opt-in, because a notification
    /// for every queued rewrite would train the user to dismiss all of them.
    public static let standard: Set<NotificationCategory> = [
        .automaticApplied, .rewriteFailed, .folderUnavailable
    ]
}

/// Settings that belong to the app rather than to any vault.
public struct AppPreferences: Sendable, Equatable, Codable {
    public var notifications: Set<NotificationCategory>
    public var launchAtLogin: Bool
    /// Keeps every model on this machine, whatever a vault or folder asks for.
    ///
    /// A single switch that outranks the hierarchy, because "never send my
    /// notes anywhere" is a promise the app makes, not a default a folder
    /// should be able to quietly overturn.
    public var localProcessingOnly: Bool

    public init(
        notifications: Set<NotificationCategory> = NotificationCategory.standard,
        launchAtLogin: Bool = false,
        localProcessingOnly: Bool = false
    ) {
        self.notifications = notifications
        self.launchAtLogin = launchAtLogin
        self.localProcessingOnly = localProcessingOnly
    }

    public static let standard = AppPreferences()

    public func notifies(about category: NotificationCategory) -> Bool {
        notifications.contains(category)
    }

    public mutating func setNotification(_ category: NotificationCategory, enabled: Bool) {
        if enabled {
            notifications.insert(category)
        } else {
            notifications.remove(category)
        }
    }
}

/// Whether a policy may run at all, given the app-wide privacy switch.
public enum ProcessingGuard {
    /// Cloud models are named by their prefix, the same way `ChamferRewrite`
    /// registers them.
    public static func isCloud(_ modelID: String) -> Bool {
        modelID.hasPrefix("cloud.")
    }

    /// The model that will actually be used, after the local-only switch has
    /// had its say.
    ///
    /// Returns nil when the user's settings rule out every option, which is a
    /// state the interface must report rather than paper over: silently
    /// falling back to the cloud here is precisely what the scope forbids.
    public static func permittedModel(
        for policy: RewritePolicy,
        preferences: AppPreferences
    ) -> String? {
        guard preferences.localProcessingOnly else { return policy.modelID }
        if !isCloud(policy.modelID) { return policy.modelID }
        if let fallback = policy.fallbackModelID, !isCloud(fallback) { return fallback }
        return nil
    }

    /// Whether falling back from this model to that one would move the user's
    /// notes off the device.
    public static func fallbackLeavesDevice(from: String, to: String) -> Bool {
        !isCloud(from) && isCloud(to)
    }
}
