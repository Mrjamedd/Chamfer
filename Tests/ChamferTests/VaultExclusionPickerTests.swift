import Foundation
import Testing

@testable import Chamfer

@Test func exclusionPickerAcceptsOnlySupportedNotesInsideTheVault() {
    let root = URL(filePath: "/Users/example/Vault", directoryHint: .isDirectory)
    let urls = [
        root.appending(path: "Roadmap.md"),
        root.appending(path: "Notes/Idea.txt"),
        root.appending(path: "Image.png"),
        URL(filePath: "/Users/example/Elsewhere/Private.md"),
        root.appending(path: "Roadmap.md")
    ]

    #expect(VaultExclusionPicker.relativeNotePaths(from: urls, within: root) == [
        "Notes/Idea.txt",
        "Roadmap.md"
    ])
}
