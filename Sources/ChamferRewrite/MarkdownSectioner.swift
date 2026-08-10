import Foundation

/// Divides a note into bounded, byte-preserving regions for model calls.
/// Boundaries occur only before headings or after blank lines, and never
/// inside front matter or fenced code. Joining the result always recreates the
/// input exactly.
enum MarkdownSectioner {
    static func sections(
        in text: String,
        targetCharacterCount: Int = 1_200
    ) -> [String] {
        guard !text.isEmpty else { return [] }

        let lines = retainedLines(in: text)
        var sections: [String] = []
        var current = ""
        var inFence: Character?
        var inFrontMatter = false
        var frontMatterFence: String?

        for (index, line) in lines.enumerated() {
            let body = line.trimmingCharacters(in: .newlines)
            let trimmed = body.trimmingCharacters(in: .whitespaces)

            if index == 0, trimmed == "---" || trimmed == "+++" {
                inFrontMatter = true
                frontMatterFence = trimmed
            } else if inFrontMatter, trimmed == frontMatterFence {
                inFrontMatter = false
            } else if !inFrontMatter, let marker = fenceMarker(in: trimmed) {
                if inFence == marker {
                    inFence = nil
                } else if inFence == nil {
                    inFence = marker
                }
            }

            let isHeading = !inFrontMatter && inFence == nil
                && trimmed.range(of: "^#{1,6}[ \\t]+", options: .regularExpression) != nil
            if isHeading, !current.isEmpty {
                sections.append(current)
                current = ""
            }

            current += line

            let isBlank = trimmed.isEmpty
            if isBlank, !inFrontMatter, inFence == nil,
               current.count >= max(1, targetCharacterCount) {
                sections.append(current)
                current = ""
            }
        }

        if !current.isEmpty { sections.append(current) }
        return sections
    }

    private static func retainedLines(in text: String) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            if let newline = text[start...].firstIndex(of: "\n") {
                let end = text.index(after: newline)
                result.append(String(text[start..<end]))
                start = end
            } else {
                result.append(String(text[start...]))
                break
            }
        }
        return result
    }

    private static func fenceMarker(in line: String) -> Character? {
        guard let first = line.first, first == "`" || first == "~" else {
            return nil
        }
        return line.prefix { $0 == first }.count >= 3 ? first : nil
    }
}
