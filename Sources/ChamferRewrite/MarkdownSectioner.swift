import Foundation

/// Divides a note into bounded, byte-preserving regions for model calls.
/// Boundaries occur only before headings or after blank lines, and never
/// inside front matter or fenced code. Joining the result always recreates the
/// input exactly.
///
/// A heading is a *permitted* boundary, not a compulsory one. It used to be
/// compulsory, which quietly made `targetCharacterCount` meaningless: a 736
/// character note with four headings became five requests of 9, 66, 121, 223
/// and 243 characters, whatever budget the effort mode set, and no request
/// could see any of the others. The model was being asked to spell-check a
/// heading with the document it belongs to withheld. The size target is now the
/// thing that decides, and the heading only says *where* to cut once the target
/// says it is time.
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
            // `>= target` rather than `!current.isEmpty`. The unit planner asks
            // for a target of 1 when it wants every block separately, so that
            // caller is unchanged; every other caller now gets the size it
            // asked for.
            if isHeading, current.count >= max(1, targetCharacterCount) {
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
