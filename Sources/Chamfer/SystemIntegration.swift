import ChamferCore
import Foundation
import ServiceManagement
import UserNotifications

/// Whether this process is a real application as far as macOS is concerned.
///
/// A SwiftPM executable is not: it has no bundle and no bundle identifier. Most
/// of AppKit shrugs at that — the app target already works around it for the
/// activation policy and for Command-comma — but the two system services below
/// do not. `UNUserNotificationCenter.current()` *raises* rather than returning
/// nil, which killed the app at launch before this check existed.
///
/// Checked once. The answer cannot change while the process is alive.
enum SystemBundle {
    static let exists = Bundle.main.bundleIdentifier != nil
}

/// Stable identifiers shared by registration and response routing.
///
/// They are deliberately independent of button copy: changing “Open Models”
/// should not strand notifications already delivered by an earlier build.
enum NotificationAction {
    static let review = "chamfer.notification.review"
    static let undo = "chamfer.notification.undo"
    static let models = "chamfer.notification.models"
    static let vaults = "chamfer.notification.vaults"
}

/// The four things a delivered notification can ask the app to do.
enum NotificationRoute: Equatable, Sendable {
    case review
    case undo(UUID)
    case models
    case vaults
}

/// Turns an AppKit/UserNotifications response into an app decision.
///
/// Kept pure so routing can be proved in a source build, where touching
/// `UNUserNotificationCenter.current()` would raise before a test could run.
enum NotificationRouter {
    static let historyEntryKey = "historyEntryID"

    static func route(
        actionIdentifier: String,
        categoryIdentifier: String? = nil,
        userInfo: [AnyHashable: Any]
    ) -> NotificationRoute? {
        switch actionIdentifier {
        case NotificationAction.review:
            return .review
        case NotificationAction.undo:
            guard let value = userInfo[historyEntryKey] as? String,
                  let historyEntryID = UUID(uuidString: value)
            else { return nil }
            return .undo(historyEntryID)
        case NotificationAction.models:
            return .models
        case NotificationAction.vaults:
            return .vaults
        case UNNotificationDefaultActionIdentifier:
            return defaultRoute(for: categoryIdentifier)
        default:
            return nil
        }
    }

    private static func defaultRoute(for identifier: String?) -> NotificationRoute? {
        guard let identifier,
              let category = NotificationCategory(rawValue: identifier)
        else { return nil }

        return switch category {
        case .rewriteReady, .automaticApplied, .rewriteFailed, .periodicSummary:
            .review
        case .folderUnavailable:
            .vaults
        case .modelUnavailable:
            .models
        }
    }
}

/// Opening at login.
///
/// A thin wrapper over `SMAppService`, which throws for reasons the user can do
/// something about — the item being disabled in System Settings, most often —
/// and reasons they cannot, such as running from a build directory with no
/// bundle. Both are reported rather than swallowed, because a toggle that
/// silently does nothing is worse than one that says why.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        guard SystemBundle.exists else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// - Returns: an explanation when the change could not be made.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        guard SystemBundle.exists else {
            return "Opening at login needs Chamfer to be a real app bundle. This is a source build, so the setting has nothing to register."
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            if SMAppService.mainApp.status == .requiresApproval {
                return "macOS needs you to allow Chamfer in System Settings › General › Login Items."
            }
            return error.localizedDescription
        }
    }
}

/// What Chamfer tells the user about while they are somewhere else.
///
/// Every category is checked against `AppPreferences` at the moment of posting
/// rather than at registration, so switching one off in Settings takes effect
/// immediately rather than at the next launch.
@MainActor
final class NotificationCentre {
    private var hasAskedForPermission = false

    /// Resolved on use rather than held.
    ///
    /// `UNUserNotificationCenter.current()` raises an exception in a process
    /// with no bundle, so it must not be touched — not even to store it — until
    /// something is actually being posted, and not at all in a source build.
    private var centre: UNUserNotificationCenter? {
        SystemBundle.exists ? .current() : nil
    }

    /// Whether Chamfer can notify at all in this build.
    var isAvailable: Bool { SystemBundle.exists }

    /// Installs every category and the one delegate that receives its actions.
    ///
    /// Registration is as guarded as delivery. Even asking the system centre
    /// for a source build is fatal, so the guard must precede the lookup rather
    /// than merely making the resulting categories inert.
    func configureResponses(delegate: any UNUserNotificationCenterDelegate) {
        guard SystemBundle.exists else { return }
        let centre = UNUserNotificationCenter.current()
        centre.delegate = delegate
        centre.setNotificationCategories(Self.categories)
    }

    private static var categories: Set<UNNotificationCategory> {
        let review = UNNotificationAction(
            identifier: NotificationAction.review,
            title: "Review",
            options: [.foreground]
        )
        let undo = UNNotificationAction(
            identifier: NotificationAction.undo,
            title: "Undo",
            options: []
        )
        let models = UNNotificationAction(
            identifier: NotificationAction.models,
            title: "Open Models",
            options: [.foreground]
        )
        let vaults = UNNotificationAction(
            identifier: NotificationAction.vaults,
            title: "Open Vaults",
            options: [.foreground]
        )

        return Set([
            UNNotificationCategory(
                identifier: NotificationCategory.rewriteReady.rawValue,
                actions: [review],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.automaticApplied.rawValue,
                actions: [undo],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.rewriteFailed.rawValue,
                actions: [review],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.folderUnavailable.rawValue,
                actions: [vaults],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.modelUnavailable.rawValue,
                actions: [models],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.periodicSummary.rawValue,
                actions: [review],
                intentIdentifiers: []
            )
        ])
    }

    /// Asked for once, and only when there is something to say.
    ///
    /// Prompting at launch — before the user has connected a vault or seen a
    /// rewrite — asks permission for something they have no reason to want yet,
    /// and a refusal then is much harder to undo than one made later.
    private func ensurePermission(_ centre: UNUserNotificationCenter) async -> Bool {
        let settings = await centre.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            guard !hasAskedForPermission else { return false }
            hasAskedForPermission = true
            return (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    func post(
        _ category: NotificationCategory,
        title: String,
        body: String,
        userInfo: [String: String] = [:],
        preferences: AppPreferences
    ) {
        guard preferences.notifies(about: category) else { return }
        // A source build posts nothing. There is no app for macOS to attribute
        // an alert to, and everything else about Chamfer still works.
        guard let centre else { return }

        Task { [weak self] in
            guard let self, await ensurePermission(centre) else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil
            content.categoryIdentifier = category.rawValue
            content.userInfo = userInfo

            try? await centre.add(
                UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    // No trigger means "now", which is the only timing any of
                    // these want.
                    trigger: nil
                )
            )
        }
    }

    // MARK: - The six categories

    func rewriteReady(noteTitle: String, preferences: AppPreferences) {
        post(
            .rewriteReady,
            title: "A rewrite is ready",
            body: "“\(noteTitle)” is waiting for you in Review.",
            preferences: preferences
        )
    }

    func automaticApplied(
        noteTitle: String,
        historyEntryID: UUID,
        preferences: AppPreferences
    ) {
        post(
            .automaticApplied,
            title: "Chamfer cleaned a note",
            body: "“\(noteTitle)” was rewritten automatically. It can be undone from Review.",
            userInfo: [NotificationRouter.historyEntryKey: historyEntryID.uuidString],
            preferences: preferences
        )
    }

    func rewriteFailed(
        noteTitle: String,
        failure: RewriteFailure,
        preferences: AppPreferences
    ) {
        post(
            .rewriteFailed,
            title: failure.title,
            body: "“\(noteTitle)” was left unchanged. \(failure.detail)",
            preferences: preferences
        )
    }

    func folderUnavailable(vaultName: String, preferences: AppPreferences) {
        post(
            .folderUnavailable,
            title: "A vault isn't available",
            body: "Chamfer can't reach “\(vaultName)”, so nothing in it is being watched.",
            preferences: preferences
        )
    }

    func modelUnavailable(modelID: String, preferences: AppPreferences) {
        post(
            .modelUnavailable,
            title: "The selected model isn't available",
            body: "\(modelID) didn't respond. Rules keep running; rewrites are waiting.",
            preferences: preferences
        )
    }

    func summary(pending: Int, applied: Int, preferences: AppPreferences) {
        guard pending + applied > 0 else { return }
        var parts: [String] = []
        if applied > 0 { parts.append("\(applied) applied") }
        if pending > 0 { parts.append("\(pending) waiting for you") }

        post(
            .periodicSummary,
            title: "Chamfer so far",
            body: parts.joined(separator: ", ") + ".",
            preferences: preferences
        )
    }
}
