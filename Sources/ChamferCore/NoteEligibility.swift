import Foundation

/// Which files Chamfer is allowed to touch.
///
/// Pure and path-based, with no filesystem access at all, because "is this file
/// excluded" is the single most consequential question the app asks: getting it
/// wrong means rewriting something the user told us not to. A rule that can be
/// exercised with a string is a rule that can be exhaustively tested.
public enum NoteEligibility {
    /// The only two formats version 1.0 processes.
    ///
    /// Anything else is left strictly alone rather than best-effort handled —
    /// an `.rtf` opened as UTF-8 and written back is a corrupted file, and the
    /// scope lists corruption as unacceptable for release.
    public static let supportedExtensions: Set<String> = ["md", "txt"]

    /// Directory names that belong to an application rather than to the user.
    ///
    /// These hold indexes, caches and workspace state. They are inside note
    /// vaults constantly — every Obsidian vault has a `.obsidian` — and a
    /// rewrite pass let loose in one would corrupt the host app's own data
    /// while producing nothing the user would ever read.
    public static let excludedDirectoryNames: Set<String> = [
        ".obsidian",
        ".trash",
        ".git",
        ".svn",
        ".hg",
        ".stfolder",
        ".stversions",
        ".smart-connections",
        ".makemd",
        ".space",
        "node_modules",
        "__pycache__",
        ".venv",
        ".build",
        "Library",
        ".Spotlight-V100",
        ".fseventsd",
        ".TemporaryItems",
        ".DocumentRevisions-V100"
    ]

    /// Whether a path component is one Chamfer never descends into.
    ///
    /// Hidden by convention counts: a leading dot is how macOS and every note
    /// app say "this is not content". The user's own notes are not hidden.
    public static func isExcludedDirectory(_ name: String) -> Bool {
        if excludedDirectoryNames.contains(name) { return true }
        return name.hasPrefix(".")
    }

    /// Whether a file is one of the two supported kinds and not itself hidden.
    public static func isSupportedFile(_ name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Whether this note may be processed, given its vault's rules.
    ///
    /// `relativePath` is measured from the vault root and uses `/` separators,
    /// so a rule survives the vault itself being moved or renamed.
    ///
    /// Include-only wins the tie by being evaluated first as a gate: when the
    /// user has narrowed a vault to two folders, everything outside them is out
    /// regardless of what else is said. Exclusions then carve out of what
    /// remains, so "only Projects, but not Projects/Archive" means what it
    /// reads like.
    public static func isEligible(
        relativePath: String,
        rules: [VaultRule]
    ) -> Bool {
        let path = normalise(relativePath)
        guard !path.isEmpty else { return false }

        // Any hidden or application-owned component anywhere in the path takes
        // the file out, however permissive the rules are. This is not something
        // a rule may override: the scope requires it unconditionally.
        let components = path.split(separator: "/").map(String.init)
        guard let fileName = components.last else { return false }
        for directory in components.dropLast() where isExcludedDirectory(directory) {
            return false
        }
        guard isSupportedFile(fileName) else { return false }

        let includeOnly = rules.filter { $0.kind == .includeOnly }
        if !includeOnly.isEmpty {
            let permitted = includeOnly.contains { isUnder($0.path, path: path) }
            guard permitted else { return false }
        }

        let excluded = rules
            .filter { $0.kind == .exclude }
            .contains { isUnder($0.path, path: path) }
        return !excluded
    }

    /// Whether `path` sits at or beneath `rulePath`.
    ///
    /// Compared component-wise rather than with `hasPrefix`, so a rule for
    /// `Work` does not silently swallow `Workshop`.
    public static func isUnder(_ rulePath: String, path: String) -> Bool {
        let rule = normalise(rulePath)
        guard !rule.isEmpty else { return true }
        let ruleComponents = rule.split(separator: "/")
        let pathComponents = path.split(separator: "/")
        guard pathComponents.count >= ruleComponents.count else { return false }
        return Array(pathComponents.prefix(ruleComponents.count)) == Array(ruleComponents)
    }

    /// The path of `url` relative to `root`, or nil when it is not inside it.
    public static func relativePath(of url: URL, under root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// Strips leading and trailing slashes and collapses the empty components a
    /// hand-typed rule tends to arrive with.
    private static func normalise(_ path: String) -> String {
        path
            .split(separator: "/")
            .filter { !$0.isEmpty && $0 != "." }
            .joined(separator: "/")
    }
}
