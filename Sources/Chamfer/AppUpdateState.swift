import AppKit
import Foundation

struct AppUpdateConfiguration: Equatable {
    let feedURL: String
    let publicKey: String

    init?(infoDictionary: [String: Any]?) {
        let feed = infoDictionary?["SUFeedURL"] as? String
        let key = infoDictionary?["SUPublicEDKey"] as? String
        guard let feed, !feed.isEmpty, let key, !key.isEmpty else { return nil }
        feedURL = feed
        publicKey = key
    }
}

struct AppUpdateReleaseNotes: Equatable, Sendable {
    struct Block: Equatable, Sendable {
        enum Style: Equatable, Sendable {
            case heading
            case paragraph
            case listItem
        }

        let style: Style
        let text: String
    }

    let blocks: [Block]

    var plainText: String {
        blocks.map(\.text).joined(separator: "\n")
    }

    static func plain(_ text: String) -> AppUpdateReleaseNotes {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppUpdateReleaseNotes(
            blocks: [
                Block(
                    style: .paragraph,
                    text: cleaned.isEmpty ? unreadableFallback : cleaned
                )
            ]
        )
    }

    /// This is deliberately a release-notes converter, not a general HTML
    /// renderer. Chamfer's appcast uses headings, paragraphs, and lists; the
    /// system importer safely turns those into attributed text and everything
    /// else is reduced to the readable text it contains.
    static func html(
        _ data: Data,
        textEncodingName: String? = nil
    ) -> AppUpdateReleaseNotes {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html
        ]
        if let encoding = stringEncoding(named: textEncodingName) {
            options[.characterEncoding] = encoding.rawValue
        }

        if let imported = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) {
            let blocks = semanticBlocks(from: imported)
            if !blocks.isEmpty { return AppUpdateReleaseNotes(blocks: blocks) }
        }

        let decoded = decodedText(from: data, encodingName: textEncodingName)
        let fallbackBlocks = structuralFallbackBlocks(from: decoded)
        if !fallbackBlocks.isEmpty {
            return AppUpdateReleaseNotes(blocks: fallbackBlocks)
        }
        return plain(fallbackPlainText(from: decoded))
    }

    private static let unreadableFallback =
        "Release notes could not be read, but this update can still be installed."

    private static func semanticBlocks(from imported: NSAttributedString) -> [Block] {
        let source = imported.string as NSString
        guard source.length > 0 else { return [] }

        var result: [Block] = []
        var location = 0
        while location < source.length {
            let paragraphRange = source.paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            let raw = source.substring(with: paragraphRange)
            let text = normalizedLine(raw)
            if !text.isEmpty {
                let attributeLocation = min(paragraphRange.location, imported.length - 1)
                let attributes = imported.attributes(
                    at: attributeLocation,
                    effectiveRange: nil
                )
                let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
                let font = attributes[.font] as? NSFont
                let style: Block.Style
                if paragraph?.textLists.isEmpty == false || looksLikeListItem(raw) {
                    style = .listItem
                } else if let font, font.pointSize >= 15 {
                    style = .heading
                } else {
                    style = .paragraph
                }
                result.append(Block(style: style, text: text))
            }
            location = NSMaxRange(paragraphRange)
        }
        return result
    }

    /// The leading marker on a list item, as ICU sees it.
    ///
    /// Deliberately not a raw string. Swift resolves `\u{2022}` into a bullet
    /// only in an ordinary literal; inside `#"…"#` the six characters reach the
    /// regex engine untouched, and ICU has no `\u{…}` escape to make sense of
    /// them. The pattern then matched nothing, every bullet survived
    /// `normalizedLine`, and the panel showed "• Warm paper surfaces" under a
    /// bullet the list style had already drawn.
    ///
    /// The hyphen sits last in the class so it is a literal rather than a range.
    private static let listMarker = "[\u{2022}\u{25E6}\u{25AA}*-]|\\d+[.)]"

    private static func normalizedLine(_ source: String) -> String {
        source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "^(?:\(listMarker))\\s*",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeListItem(_ source: String) -> Bool {
        source.range(
            of: "^\\s*(?:\(listMarker))\\s+",
            options: .regularExpression
        ) != nil
    }

    private static func structuralFallbackBlocks(from source: String) -> [Block] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<(h[1-6]|p|li)\b[^>]*>(.*?)</\1>"#
        ) else { return [] }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: source),
                  let contentRange = Range(match.range(at: 2), in: source)
            else { return nil }
            let tag = source[tagRange].lowercased()
            let text = fallbackPlainText(from: String(source[contentRange]))
            guard text != unreadableFallback else { return nil }
            let style: Block.Style
            if tag == "li" {
                style = .listItem
            } else if tag.hasPrefix("h") {
                style = .heading
            } else {
                style = .paragraph
            }
            return Block(style: style, text: text)
        }
    }

    private static func decodedText(
        from data: Data,
        encodingName: String?
    ) -> String {
        let encoding = stringEncoding(named: encodingName) ?? .utf8
        return String(data: data, encoding: encoding)
            ?? String(decoding: data, as: UTF8.self)
    }

    private static func fallbackPlainText(from source: String) -> String {
        let withBreaks = source.replacingOccurrences(
            of: #"(?i)</?(?:p|h[1-6]|li|ul|ol|br)[^>]*>"#,
            with: "\n",
            options: .regularExpression
        )
        let withoutTags = withBreaks.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        let unescaped = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let lines = unescaped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? unreadableFallback : lines.joined(separator: "\n")
    }

    private static func stringEncoding(named name: String?) -> String.Encoding? {
        guard let name else { return nil }
        let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)
        )
    }
}

enum AppUpdateStage: Equatable, Sendable {
    case notDownloaded
    case downloaded
    case installing
}

struct AppUpdateDetails: Equatable, Sendable {
    var version: String
    var releaseNotes: AppUpdateReleaseNotes
    var informationURL: URL?
    var isInformationOnly: Bool
    var isCritical: Bool
    var stage: AppUpdateStage

    static let unknown = AppUpdateDetails(
        version: "a new version",
        releaseNotes: .plain("Release notes are not available for this update."),
        informationURL: nil,
        isInformationOnly: false,
        isCritical: false,
        stage: .notDownloaded
    )
}

struct AppUpdateProgress: Equatable, Sendable {
    var completedBytes: UInt64
    var totalBytes: UInt64?

    init(completedBytes: UInt64 = 0, totalBytes: UInt64? = nil) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(Double(completedBytes) / Double(totalBytes), 1)
    }
}

struct AppUpdateMessage: Equatable, Sendable {
    let title: String
    let detail: String
}

enum AppUpdatePresentationState: Equatable, Sendable {
    case idle
    case permission
    case checking
    case available(AppUpdateDetails)
    case downloading(AppUpdateDetails, AppUpdateProgress)
    case extracting(AppUpdateDetails, fraction: Double?)
    case readyToInstall(AppUpdateDetails)
    case installing(AppUpdateDetails, applicationTerminated: Bool)
    case installed
    case upToDate(AppUpdateMessage)
    case error(AppUpdateMessage)
}

struct AppUpdateStateMachine: Sendable {
    enum Event: Equatable, Sendable {
        case permissionRequested
        case userInitiatedCheckStarted
        case updateFound(AppUpdateDetails)
        case releaseNotesLoaded(AppUpdateReleaseNotes)
        case downloadStarted
        case downloadExpectedLength(UInt64)
        case downloadReceived(bytes: UInt64)
        case extractionStarted
        case extractionProgress(Double)
        case readyToInstall
        case installing(applicationTerminated: Bool)
        case installed(relaunched: Bool)
        case noUpdate(AppUpdateMessage, isCurrentVersion: Bool)
        case failed(AppUpdateMessage)
        case dismissed
    }

    private(set) var state: AppUpdatePresentationState = .idle
    private var activeUpdate: AppUpdateDetails?
    private var completedBytes: UInt64 = 0
    private var totalBytes: UInt64?

    var progress: AppUpdateProgress? {
        guard case let .downloading(_, progress) = state else { return nil }
        return progress
    }

    mutating func receive(_ event: Event) {
        switch event {
        case .permissionRequested:
            state = .permission

        case .userInitiatedCheckStarted:
            state = .checking

        case let .updateFound(details):
            activeUpdate = details
            completedBytes = 0
            totalBytes = nil
            state = .available(details)

        case let .releaseNotesLoaded(releaseNotes):
            guard var update = activeUpdate else { return }
            update.releaseNotes = releaseNotes
            activeUpdate = update
            replaceUpdateDetails(with: update)

        case .downloadStarted:
            completedBytes = 0
            totalBytes = nil
            state = .downloading(currentUpdate, currentProgress)

        case let .downloadExpectedLength(length):
            totalBytes = length > 0 ? length : nil
            state = .downloading(currentUpdate, currentProgress)

        case let .downloadReceived(length):
            let (sum, overflow) = completedBytes.addingReportingOverflow(length)
            completedBytes = overflow ? UInt64.max : sum
            state = .downloading(currentUpdate, currentProgress)

        case .extractionStarted:
            state = .extracting(currentUpdate, fraction: nil)

        case let .extractionProgress(progress):
            let fraction = progress.isFinite ? min(max(progress, 0), 1) : nil
            state = .extracting(currentUpdate, fraction: fraction)

        case .readyToInstall:
            state = .readyToInstall(currentUpdate)

        case let .installing(applicationTerminated):
            state = .installing(
                currentUpdate,
                applicationTerminated: applicationTerminated
            )

        case let .installed(relaunched):
            state = relaunched ? .idle : .installed

        case let .noUpdate(message, isCurrentVersion):
            state = isCurrentVersion ? .upToDate(message) : .error(message)

        case let .failed(message):
            state = .error(message)

        case .dismissed:
            reset()
        }
    }

    private var currentUpdate: AppUpdateDetails {
        activeUpdate ?? .unknown
    }

    private var currentProgress: AppUpdateProgress {
        AppUpdateProgress(completedBytes: completedBytes, totalBytes: totalBytes)
    }

    private mutating func replaceUpdateDetails(with update: AppUpdateDetails) {
        switch state {
        case .available:
            state = .available(update)
        case let .downloading(_, progress):
            state = .downloading(update, progress)
        case let .extracting(_, fraction):
            state = .extracting(update, fraction: fraction)
        case .readyToInstall:
            state = .readyToInstall(update)
        case let .installing(_, applicationTerminated):
            state = .installing(
                update,
                applicationTerminated: applicationTerminated
            )
        case .idle, .permission, .checking, .installed, .upToDate, .error:
            break
        }
    }

    private mutating func reset() {
        state = .idle
        activeUpdate = nil
        completedBytes = 0
        totalBytes = nil
    }
}
