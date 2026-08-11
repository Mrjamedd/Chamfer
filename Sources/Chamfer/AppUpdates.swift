import Foundation
import Sparkle
import SwiftUI

/// How Chamfer updates itself once it is installed on somebody's Mac.
///
/// Chamfer is distributed outside the App Store, so nothing updates it unless
/// the app does. Sparkle is the standard answer: it reads a signed feed, checks
/// the signature of what it downloads against a key compiled into this build,
/// and replaces the app in place.
///
/// Two rules the pipeline around this enforces, and the reason they matter:
///
/// 1. **Tags ship, pushes do not.** The release workflow runs on `v*` tags
///    only. Ordinary commits build and test and stop there, so an afternoon's
///    unfinished work cannot reach anybody's Mac by being pushed.
/// 2. **A build nobody signed cannot update anybody.** The feed URL and the
///    public key both live in `Info.plist`, written by `Scripts/package.sh`.
///    A locally built `.app` has neither, and Sparkle simply does nothing —
///    which is what should happen when you run the thing you are working on.
@MainActor
final class AppUpdates {
    static let shared = AppUpdates()

    /// Nil when this build has no feed — a `swift build` run from the source
    /// directory, or any bundle assembled without the release keys.
    private let controller: SPUStandardUpdaterController?

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard let feed, !feed.isEmpty, let key, !key.isEmpty else {
            controller = nil
            return
        }
        // `startingUpdater: true` schedules the background check Sparkle is
        // configured for in Info.plist. The first run asks permission; there is
        // no version of this that checks silently before being allowed to.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Whether this build can update itself at all. The menu item reflects it
    /// rather than offering a check that cannot happen.
    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// What the About/Help surfaces show, and what a bug report needs.
    static var versionDescription: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return switch (short, build) {
        case let (version?, build?): "Version \(version) (\(build))"
        case let (version?, nil): "Version \(version)"
        default: "Development build"
        }
    }
}

/// The menu item, which is deliberately not a `SparkleUpdaterView` or any other
/// component that assumes a window: Chamfer's only scenes are its window and
/// its settings, and an update check has to work from the menu bar with both
/// closed.
struct CheckForUpdatesCommand: View {
    private let updates = AppUpdates.shared

    var body: some View {
        Button("Check for Updates…") {
            updates.checkForUpdates()
        }
        .disabled(!updates.isAvailable)
    }
}
