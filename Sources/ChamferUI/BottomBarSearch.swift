import ChamferCore
import Foundation

public struct BottomBarSearchMatch: Identifiable, Equatable, Sendable {
    public enum Kind: Int, Equatable, Sendable {
        case titlePrefix
        case titleSubstring
        case content
    }

    public let document: NoteDocument
    public let title: String
    public let snippet: String
    public let kind: Kind

    public var id: URL { document.url }
}

public enum BottomBarSearchIndex {
    public static func matches(
        query: String,
        notes: [NoteDocument]
    ) -> [BottomBarSearchMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let needle = normalized(trimmedQuery)
        var bestMatchByURL: [URL: BottomBarSearchMatch] = [:]

        for document in notes {
            let title = document.url.deletingPathExtension().lastPathComponent
            let normalizedTitle = normalized(title)
            let kind: BottomBarSearchMatch.Kind

            if normalizedTitle.hasPrefix(needle) {
                kind = .titlePrefix
            } else if normalizedTitle.contains(needle) {
                kind = .titleSubstring
            } else if normalized(document.text).contains(needle) {
                kind = .content
            } else {
                continue
            }

            let candidate = BottomBarSearchMatch(
                document: document,
                title: title,
                snippet: snippet(
                    in: document.text,
                    matching: needle,
                    prefersMatch: kind == .content
                ),
                kind: kind
            )

            if
                let existing = bestMatchByURL[document.url],
                existing.kind.rawValue <= candidate.kind.rawValue
            {
                continue
            }
            bestMatchByURL[document.url] = candidate
        }

        return bestMatchByURL.values.sorted { left, right in
            if left.kind != right.kind {
                return left.kind.rawValue < right.kind.rawValue
            }
            let titleOrder = left.title.localizedCaseInsensitiveCompare(right.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return left.document.url.path < right.document.url.path
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }

    private static func snippet(
        in text: String,
        matching needle: String,
        prefersMatch: Bool
    ) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map {
                $0
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(
                        of: #"\s+"#,
                        with: " ",
                        options: .regularExpression
                    )
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        let selected = prefersMatch
            ? lines.first(where: { normalized($0).contains(needle) }) ?? lines.first
            : lines.first

        guard let selected else { return "Title match" }
        let limit = 96
        guard selected.count > limit else { return selected }
        return String(selected.prefix(limit - 1)) + "…"
    }
}
