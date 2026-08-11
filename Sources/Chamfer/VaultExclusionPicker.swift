import AppKit
import ChamferCore
import Foundation
import UniformTypeIdentifiers

/// Native note selection for exact exclusions inside a connected vault.
@MainActor
enum VaultExclusionPicker {
    static func present(within vault: Vault) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = vault.url
        panel.prompt = "Exclude"
        panel.message = "Choose one or more Markdown or plain-text notes inside “\(vault.name)”. Chamfer will never process the selected notes."
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            .plainText
        ]

        guard panel.runModal() == .OK else { return [] }
        return relativeNotePaths(from: panel.urls, within: vault.url)
    }

    /// Pure boundary validation for selections returned by AppKit.
    nonisolated static func relativeNotePaths(
        from urls: [URL],
        within root: URL
    ) -> [String] {
        Array(
            Set(
                urls.compactMap { url in
                    guard let relative = NoteEligibility.relativePath(of: url, under: root),
                          NoteEligibility.isEligible(relativePath: relative, rules: [])
                    else { return nil }
                    return relative
                }
            )
        )
        .sorted()
    }
}
