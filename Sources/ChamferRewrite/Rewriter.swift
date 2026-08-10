import ChamferCore
import Foundation

/// One bounded edit request presented to a model.
///
/// Only `text` may be returned with edits. The surrounding context is supplied
/// to help grammar and clarity decisions, but is labelled read-only so a model
/// cannot legitimately echo it into the replacement.
public struct RewriteRequest: Sendable, Equatable {
    public let text: String
    public let documentTitle: String?
    public let headingPath: String?
    public let contextBefore: String?
    public let contextAfter: String?
    public let effort: ModelEffort
    /// The unguessable marker that fences this document off from its
    /// instructions. See `RewriteBoundary`.
    public let boundary: String
    /// Set by a stage that fences something other than one passage — the
    /// checking pass sends an original and a proposal together. `text` still
    /// carries the passage the answer is measured against, so the response
    /// budget and the guards need no special case.
    private let composedPrompt: String?

    public init(
        text: String,
        documentTitle: String? = nil,
        headingPath: String? = nil,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        effort: ModelEffort = .standard,
        boundary: String? = nil,
        composedPrompt: String? = nil
    ) {
        self.text = text
        self.documentTitle = documentTitle
        self.headingPath = headingPath
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.effort = effort
        self.boundary = boundary ?? RewriteBoundary.make(
            avoiding: [text, contextBefore ?? "", contextAfter ?? ""]
        )
        self.composedPrompt = composedPrompt
    }

    /// A ceiling that scales with the editable input rather than giving a model
    /// room to answer with an essay, refusal, or invented tool trace.
    ///
    /// The headroom above the input is generous — a formatting pass legitimately
    /// returns more characters than it was given — but the mode's own ceiling
    /// still caps it, which is one of the ways Base stays quick.
    public var maximumResponseTokens: Int {
        let scaled = Int(ceil(Double(text.utf8.count) / 3.0)) + 96
        return max(96, min(effort.profile.responseTokenCeiling, scaled))
    }

    /// The note is quoted inside an unguessable fence rather than sent as a
    /// naked command, and the requested output is named again immediately after
    /// the text, where a model is least likely to have lost it.
    public var prompt: String {
        if let composedPrompt { return composedPrompt }
        var lines: [String] = []
        if let documentTitle, !documentTitle.isEmpty {
            lines.append("Document: \(documentTitle)")
        }
        if let headingPath, !headingPath.isEmpty {
            lines.append("Section: \(headingPath)")
        }

        let hasContext = !(contextBefore ?? "").isEmpty
            || !(contextAfter ?? "").isEmpty
        if hasContext {
            lines.append(RewriteBoundary.contextOpen(boundary))
            if let contextBefore, !contextBefore.isEmpty {
                lines.append("[preceding text]")
                lines.append(contextBefore)
            }
            if let contextAfter, !contextAfter.isEmpty {
                lines.append("[following text]")
                lines.append(contextAfter)
            }
            lines.append(RewriteBoundary.contextClose(boundary))
        }

        lines.append(RewriteBoundary.editableOpen(boundary))
        lines.append(text)
        lines.append(RewriteBoundary.editableClose(boundary))
        lines.append(
            "Return the edited replacement for the text between "
                + "\(RewriteBoundary.editableOpen(boundary)) and "
                + "\(RewriteBoundary.editableClose(boundary)), and nothing else. "
                + "Do not repeat the markers."
        )
        return lines.joined(separator: "\n")
    }
}

/// The fence between a document and the instructions about it.
///
/// A fixed marker like `BEGIN EDITABLE TEXT` is a marker the document can
/// contain — and notes that are *about* prompting, or design bibles quoting
/// their own templates, routinely do. A note able to write the closing marker
/// can end the quoted region early and have the rest of itself read as
/// instructions. Randomising the marker per request makes that impossible to
/// write in advance, and the value is checked against the text it is about to
/// fence so it cannot collide by accident either.
public enum RewriteBoundary {
    public static func make(avoiding candidates: [String]) -> String {
        for _ in 0..<8 {
            let token = random()
            if !candidates.contains(where: { $0.contains(token) }) { return token }
        }
        return random()
    }

    public static func editableOpen(_ token: String) -> String { "<<<\(token):EDIT>>>" }
    public static func editableClose(_ token: String) -> String { "<<<\(token):END-EDIT>>>" }
    public static func contextOpen(_ token: String) -> String { "<<<\(token):CONTEXT>>>" }
    public static func contextClose(_ token: String) -> String { "<<<\(token):END-CONTEXT>>>" }

    /// Every marker a response might have echoed back, so the pipeline can
    /// strip them before the text is compared with the original.
    public static func markers(_ token: String) -> [String] {
        [
            editableOpen(token), editableClose(token),
            contextOpen(token), contextClose(token)
        ]
    }

    private static func random() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return "CHAMFER-" + String((0..<10).map { _ in
            alphabet[Int.random(in: 0..<alphabet.count)]
        })
    }
}

/// A language-model backend that improves a passage of prose.
///
/// The protocol is the seam that keeps the backend undecided. The downloaded
/// local model and the supported cloud providers both satisfy it, so the
/// cleanup pipeline does not handle credentials or HTTP.
public protocol Rewriter: Sendable {
    /// Whether this backend is usable right now — whether the runtime is up and
    /// the model it was asked for is actually on this Mac.
    var isAvailable: Bool { get async }

    /// Returns an improved version of `section`, preserving meaning.
    ///
    /// Callers pass one unit at a time with code, frontmatter and links already
    /// masked. Implementations must not be trusted to respect that on their own
    /// — the sanity gate in `ChamferCore` checks the result.
    ///
    /// `instructions` is what makes the five rewrite modes different from each
    /// other. It is a parameter rather than something each backend hardcodes
    /// because the mode is a property of the user's policy, and a backend that
    /// chose its own would make "spelling only" mean something different
    /// depending on which model happened to be selected.
    func rewrite(_ section: String, instructions: String) async throws -> String

    /// Rich request used by the pipeline. The default keeps simple test and
    /// third-party rewriters source-compatible; production backends override
    /// it so read-only context and explicit boundaries reach the model.
    func rewrite(_ request: RewriteRequest, instructions: String) async throws -> String
}

public extension Rewriter {
    func rewrite(_ request: RewriteRequest, instructions: String) async throws -> String {
        try await rewrite(request.text, instructions: instructions)
    }

    /// For callers with no mode in hand — a connectivity check, or a backend
    /// exercised directly. The pipeline always passes the mode's own.
    func rewrite(_ section: String) async throws -> String {
        try await rewrite(section, instructions: RewriteInstructions.standard)
    }
}
