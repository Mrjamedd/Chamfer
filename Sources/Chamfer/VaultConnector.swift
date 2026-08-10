import AppKit
import ChamferCore
import ChamferWatch
import Foundation

/// Pointing Chamfer at a folder of notes.
///
/// Lives in the app target rather than in `ChamferUI` because it needs
/// `NSOpenPanel` and a running application, and a view that assumed both could
/// never be rendered by the gallery or exercised by a test. The Vaults page
/// gets a closure; this is what the app puts behind it.
@MainActor
enum VaultConnector {
    @discardableResult
    static func present(reconnecting vaultID: UUID? = nil, into model: AppModel) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = vaultID == nil
        panel.canCreateDirectories = false
        panel.prompt = "Connect"
        panel.message = "Choose a folder of Markdown or plain-text notes. Chamfer watches everything inside it, including subfolders."

        guard panel.runModal() == .OK else { return false }
        var changed = false
        for url in panel.urls {
            changed = connect(url, reconnecting: vaultID, into: model) || changed
        }
        return changed
    }

    /// The bookmark is made here, immediately, while the panel's grant is still
    /// live. Deferring it until the first sweep would mean asking for access
    /// the user has already given and no longer remembers giving.
    private static func connect(
        _ url: URL,
        reconnecting vaultID: UUID?,
        into model: AppModel
    ) -> Bool {
        let standardized = url.standardizedFileURL

        // Connecting the same folder twice would give it two identities, two
        // sets of overrides, and two of every rewrite it produced.
        guard !model.dashboard.vaults.contains(where: {
            $0.id != vaultID && $0.url.standardizedFileURL == standardized
        }) else { return false }

        guard let bookmark = try? VaultBookmark.make(for: standardized) else {
            // Without a bookmark the folder would work until the next launch
            // and then silently stop, which is worse than not connecting it.
            report(
                "Chamfer couldn't keep access to “\(standardized.lastPathComponent)”.",
                detail: "macOS refused to issue a lasting permission for that folder, so it hasn't been connected. Try a folder inside your home directory."
            )
            return false
        }

        if let vaultID {
            return model.reconnectVault(vaultID, to: standardized, bookmark: bookmark)
        }
        return model.addVault(
            Vault(
                url: standardized,
                availability: .available,
                noteCount: 0,
                lastSweep: nil
            ),
            bookmark: bookmark
        )
    }

    private static func report(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}
