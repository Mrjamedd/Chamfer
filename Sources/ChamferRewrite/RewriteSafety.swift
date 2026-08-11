import ChamferCore
import Foundation

enum RewriteSafety {
    static func reviewRecommendation(
        original: String,
        candidate: String,
        mode: RewriteMode
    ) -> RewriteReviewRecommendation? {
        guard original != candidate else { return nil }

        let suspicious = switch mode {
        case .spelling:
            spellingLooksBroad(original: original, candidate: candidate)
        case .grammar:
            grammarLooksBroad(original: original, candidate: candidate)
        case .formatting:
            words(in: original) != words(in: candidate)
        case .clarity:
            lengthRatio(candidate, to: original) < 0.70
                || lengthRatio(candidate, to: original) > 1.35
        case .fullCleanup:
            lengthRatio(candidate, to: original) < 0.65
                || lengthRatio(candidate, to: original) > 1.50
        }
        return suspicious ? .broaderThanExpectedForMode : nil
    }

    private static func spellingLooksBroad(original: String, candidate: String) -> Bool {
        let source = lexicalParts(original)
        let result = lexicalParts(candidate)
        guard source.separators == result.separators,
              source.words.count == result.words.count else { return true }

        let pairs = zip(source.words, result.words).filter { $0 != $1 }
        guard pairs.count <= max(4, source.words.count / 3) else { return true }
        return pairs.contains { before, after in
            damerauLevenshtein(before.lowercased(), after.lowercased())
                > max(2, before.count / 2)
        }
    }

    private static func grammarLooksBroad(original: String, candidate: String) -> Bool {
        guard newlinePattern(original) == newlinePattern(candidate) else { return true }
        let ratio = lengthRatio(candidate, to: original)
        guard ratio >= 0.75, ratio <= 1.25 else { return true }
        let sourceWords = words(in: original)
        let resultWords = words(in: candidate)
        guard !sourceWords.isEmpty else { return false }
        let delta = abs(sourceWords.count - resultWords.count)
        return Double(delta) / Double(sourceWords.count) > 0.25
    }

    private static func lengthRatio(_ candidate: String, to original: String) -> Double {
        guard !original.isEmpty else { return candidate.isEmpty ? 1 : .infinity }
        return Double(candidate.count) / Double(original.count)
    }

    private static func newlinePattern(_ text: String) -> [Int] {
        text.enumerated().compactMap { $0.element == "\n" ? $0.offset : nil }
    }

    private static func words(in text: String) -> [String] {
        lexicalParts(text).words
    }

    private static func lexicalParts(_ text: String) -> (words: [String], separators: [String]) {
        var words: [String] = []
        var separators: [String] = []
        var word = ""
        var separator = ""

        for character in text {
            if character.isLetter {
                if !separator.isEmpty {
                    separators.append(separator)
                    separator = ""
                }
                word.append(character)
            } else {
                if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
                separator.append(character)
            }
        }
        if !word.isEmpty { words.append(word) }
        if !separator.isEmpty { separators.append(separator) }
        return (words, separators)
    }

    /// Adjacent transpositions are one edit, which is the difference between
    /// recognizing "teh" as a typo and treating it as a broad rewrite.
    private static func damerauLevenshtein(_ left: String, _ right: String) -> Int {
        let a = Array(left)
        let b = Array(right)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var distance = Array(
            repeating: Array(repeating: 0, count: b.count + 1),
            count: a.count + 1
        )
        for index in 0...a.count { distance[index][0] = index }
        for index in 0...b.count { distance[0][index] = index }

        for i in 1...a.count {
            for j in 1...b.count {
                let substitution = a[i - 1] == b[j - 1] ? 0 : 1
                distance[i][j] = min(
                    distance[i - 1][j] + 1,
                    min(
                        distance[i][j - 1] + 1,
                        distance[i - 1][j - 1] + substitution
                    )
                )
                if i > 1, j > 1,
                   a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    distance[i][j] = min(distance[i][j], distance[i - 2][j - 2] + 1)
                }
            }
        }
        return distance[a.count][b.count]
    }
}
