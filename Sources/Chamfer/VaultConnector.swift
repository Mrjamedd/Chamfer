import AppKit
import ChamferCore
import ChamferWatch
import Foundation

/// Everything the caller needs after one folder picker closes.
///
/// `didChange` is kept independently from the failure because a multi-folder
/// choice can legitimately contain both. Treating the last attempt as the
/// whole result used to lose successful additions whenever a later bookmark
/// was refused.
struct VaultConnectionResult: Equatable, Sendable {
    private(set) var didChange: Bool
    private var refusedFolderNames: [String]

    static let unchanged = Self(didChange: false, refusedFolderNames: [])
    static let connected = Self(didChange: true, refusedFolderNames: [])

    static func lastingAccessRefused(folderName: String) -> Self {
        Self(didChange: false, refusedFolderNames: [folderName])
    }

    mutating func merge(_ next: Self) {
        didChange = didChange || next.didChange
        refusedFolderNames.append(contentsOf: next.refusedFolderNames)
    }

    var notice: String? {
        guard let first = refusedFolderNames.first else { return nil }
        let subject = refusedFolderNames.count == 1
            ? "“\(first)”"
            : "\(refusedFolderNames.count.formatted()) selected folders"
        return "Chamfer couldn’t keep access to \(subject). macOS refused to issue a lasting permission for that folder, so it hasn’t been connected. Try a folder inside your home directory."
    }
}

/// Pointing Chamfer at a folder of notes.
///
/// Lives in the app target rather than in `ChamferUI` because it needs
/// `NSOpenPanel` and a running application, and a view that assumed both could
/// never be rendered by the gallery or exercised by a test. The Vaults page
/// gets a closure; this is what the app puts behind it.
@MainActor
enum VaultConnector {
    @discardableResult
    static func present(
        reconnecting vaultID: UUID? = nil,
        into model: AppModel
    ) -> VaultConnectionResult {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = vaultID == nil
        panel.canCreateDirectories = false
        panel.prompt = "Connect"
        panel.message = "Choose a folder of Markdown or plain-text notes. Chamfer watches everything inside it, including subfolders."

        guard panel.runModal() == .OK else { return .unchanged }
        var result = VaultConnectionResult.unchanged
        for url in panel.urls {
            result.merge(connect(url, reconnecting: vaultID, into: model))
        }
        return result
    }

    /// The bookmark is made here, immediately, while the panel's grant is still
    /// live. Deferring it until the first sweep would mean asking for access
    /// the user has already given and no longer remembers giving.
    private static func connect(
        _ url: URL,
        reconnecting vaultID: UUID?,
        into model: AppModel
    ) -> VaultConnectionResult {
        let standardized = url.standardizedFileURL

        // Connecting the same folder twice would give it two identities, two
        // sets of overrides, and two of every rewrite it produced.
        guard !model.dashboard.vaults.contains(where: {
            $0.id != vaultID && $0.url.standardizedFileURL == standardized
        }) else { return .unchanged }

        guard let bookmark = try? VaultBookmark.make(for: standardized) else {
            // Without a bookmark the folder would work until the next launch
            // and then silently stop, which is worse than not connecting it.
            return .lastingAccessRefused(
                folderName: standardized.lastPathComponent
            )
        }

        if let vaultID {
            return model.reconnectVault(
                vaultID,
                to: standardized,
                bookmark: bookmark
            ) ? .connected : .unchanged
        }
        return model.addVault(
            Vault(
                url: standardized,
                availability: .available,
                noteCount: 0,
                lastSweep: nil
            ),
            bookmark: bookmark
        ) ? .connected : .unchanged
    }
}
