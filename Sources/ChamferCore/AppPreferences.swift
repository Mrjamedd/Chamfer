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

}

/// Settings that belong to the app rather than to any vault.
public struct AppPreferences: Sendable, Equatable, Codable {
    public private(set) var notifications: Set<NotificationCategory>
    /// Categories for which the user has deliberately chosen on or off.
    /// Absence here is different from an explicit choice stored in
    /// `notifications`.
    public private(set) var configuredNotifications: Set<NotificationCategory>
    public var launchAtLogin: Bool?
    /// Keeps every model on this machine, whatever model is active.
    ///
    /// A single switch that outranks model selection, because "never send my
    /// notes anywhere" is a promise the app makes.
    public var localProcessingOnly: Bool?

    public init(
        launchAtLogin: Bool? = nil,
        localProcessingOnly: Bool? = nil
    ) {
        self.notifications = []
        self.configuredNotifications = []
        self.launchAtLogin = launchAtLogin
        self.localProcessingOnly = localProcessingOnly
    }

    /// Convenience for tests and migrations that intentionally specify every
    /// notification category at once. An empty set means deliberately off,
    /// not unconfigured.
    public init(
        notifications: Set<NotificationCategory>,
        launchAtLogin: Bool? = nil,
        localProcessingOnly: Bool? = nil
    ) {
        self.notifications = notifications
        configuredNotifications = Set(NotificationCategory.allCases)
        self.launchAtLogin = launchAtLogin
        self.localProcessingOnly = localProcessingOnly
    }

    public static let unconfigured = AppPreferences()

    public func notifies(about category: NotificationCategory) -> Bool {
        notificationChoice(for: category) == true
    }

    public func notificationChoice(for category: NotificationCategory) -> Bool? {
        guard configuredNotifications.contains(category) else { return nil }
        return notifications.contains(category)
    }

    public mutating func setNotification(_ category: NotificationCategory, enabled: Bool) {
        configuredNotifications.insert(category)
        if enabled {
            notifications.insert(category)
        } else {
            notifications.remove(category)
        }
    }

    public mutating func clearNotificationChoice(_ category: NotificationCategory) {
        configuredNotifications.remove(category)
        notifications.remove(category)
    }

    private enum CodingKeys: String, CodingKey {
        case notifications
        case configuredNotifications
        case launchAtLogin
        case localProcessingOnly
    }

    /// Old state files had no intent markers. When an old key is present its
    /// value is preserved as an existing choice; a genuinely fresh state has
    /// no file and therefore uses `unconfigured` instead.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try values.decodeIfPresent(
            Set<NotificationCategory>.self,
            forKey: .notifications
        ) ?? []
        configuredNotifications = try values.decodeIfPresent(
            Set<NotificationCategory>.self,
            forKey: .configuredNotifications
        ) ?? (values.contains(.notifications) ? Set(NotificationCategory.allCases) : [])
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
        localProcessingOnly = try values.decodeIfPresent(
            Bool.self,
            forKey: .localProcessingOnly
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(notifications, forKey: .notifications)
        try values.encode(configuredNotifications, forKey: .configuredNotifications)
        try values.encodeIfPresent(launchAtLogin, forKey: .launchAtLogin)
        try values.encodeIfPresent(localProcessingOnly, forKey: .localProcessingOnly)
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
    /// Returns nil when the user's settings rule out the vault's model, which
    /// is a state the interface must report rather than paper over. There is
    /// deliberately nothing to substitute: quietly running a different model
    /// than the one on screen is precisely what the scope forbids, and the
    /// local model needs no substitute because it is already the default path.
    public static func permittedModel(
        for policy: RewritePolicy,
        preferences: AppPreferences
    ) -> String? {
        guard preferences.localProcessingOnly == true else { return policy.modelID }
        return isCloud(policy.modelID) ? nil : policy.modelID
    }
}
