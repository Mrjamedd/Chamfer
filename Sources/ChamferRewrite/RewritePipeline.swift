import ChamferCore
import Foundation

/// What a rewrite attempt came to.
public enum RewriteOutcome: Sendable {
    /// The model found nothing to change. Not a failure, and not something to
    /// put in the queue — a rewrite that changes nothing is not a decision the
    /// user should be asked to make.
    case unchanged
    case proposed(RewriteProduct)
    case failed(RewriteFailure)
}

/// A rewrite that survived every check, and the story of how it was produced.
public struct RewriteProduct: Sendable {
    public let hunks: [Hunk]
    /// The complete rewritten text, kept so applying does not have to replay
    /// the hunks against a file that may have moved on.
    public let text: String
    /// Which model did the work.
    public let modelID: String
    /// The mode it ran at, so history can say why a note took as long as it did.
    public let effort: ModelEffort
    public let reviewRecommendation: RewriteReviewRecommendation?

    public init(
        hunks: [Hunk],
        text: String,
        modelID: String,
        effort: ModelEffort = .standard,
        reviewRecommendation: RewriteReviewRecommendation? = nil
    ) {
        self.hunks = hunks
        self.text = text
        self.modelID = modelID
        self.effort = effort
        self.reviewRecommendation = reviewRecommendation
    }
}

/// A model, named, so a failure can say which one failed.
public struct NamedRewriter: Sendable {
    public let modelID: String
    public let rewriter: any Rewriter

    public init(modelID: String, rewriter: any Rewriter) {
        self.modelID = modelID
        self.rewriter = rewriter
    }
}

/// The whole journey from a note on disk to a rewrite in the queue.
///
/// Segment, mask, plan, ask, check, review, reassemble, diff. Each stage can
/// refuse, and a refusal at any point leaves the note exactly as it was — the
/// pipeline never returns something half-applied, because there is no such
/// thing as half-applying a rewrite to someone's file.
///
/// There is one model. When it cannot run, that is reported; nothing is
/// silently retried somewhere else, and in particular nothing is retried in the
/// cloud. Every stage below survives because it earns its keep on determinism
/// or on damage control, not because the model could not hold a document:
///
/// - **Segmentation** keeps reassembly byte-exact and gives each request a
///   heading path. It is not a context workaround.
/// - **Masking** is the only reason a link or a code block cannot be rewritten.
/// - **Unit planning** bounds the blast radius of one bad answer.
/// - **The response guard** is deterministic and unbribable.
/// - **The checking pass** is the one stage that is genuinely optional, which
///   is why it is what Base gives up and Max doubles.
public enum RewritePipeline {
    public static func run(
        text: String,
        documentTitle: String? = nil,
        policy: RewritePolicy,
        model: NamedRewriter,
        effort: ModelEffort = .standard
    ) async -> RewriteOutcome {
        let profile = effort.profile

        guard await model.rewriter.isAvailable else {
            return .failed(.modelUnavailable(model: model.modelID))
        }

        var rewritten = ""
        var headings: [Int: String] = [:]
        var keptOriginal = false
        let segments = MarkdownSectioner.sections(
            in: text,
            targetCharacterCount: profile.segmentTargetCharacters
        )

        for segment in segments {
            let headingPath = updateHeadingPath(from: segment, headings: &headings)
            switch await attemptSegment(
                segment,
                documentTitle: documentTitle,
                headingPath: headingPath,
                policy: policy,
                profile: profile,
                using: model
            ) {
            case let .success(candidate):
                rewritten += candidate
            case let .keptOriginal(candidate):
                rewritten += candidate
                keptOriginal = true
            case let .refused(failure):
                // A refusal now only ever means the model was never reached, so
                // there is no answer to salvage and nothing to show anybody.
                return .failed(failure)
            }
        }

        return finish(
            original: text,
            candidate: rewritten,
            modelID: model.modelID,
            effort: effort,
            policy: policy,
            keptOriginal: keptOriginal
        )
    }

    // MARK: - One segment

    private enum Attempt {
        case success(String)
        /// Usable text, but some of it is the original rather than a rewrite.
        case keptOriginal(String)
        case refused(RewriteFailure)
    }

    private static func attemptSegment(
        _ segment: String,
        documentTitle: String?,
        headingPath: String?,
        policy: RewritePolicy,
        profile: ModelEffortProfile,
        using model: NamedRewriter
    ) async -> Attempt {
        // A unit whose answer is rejected contributes the text it was given.
        // That is always safe — the original satisfies every check by
        // construction — and it is what lets one bad passage cost a paragraph
        // instead of the whole note.
        let envelope = SectionEnvelope(segment)
        guard !envelope.body.isEmpty else { return .success(segment) }

        let masked = MarkdownMask.apply(
            to: envelope.body,
            preserving: effectivePreservation(for: policy)
        )

        var rewritten = ""
        var keptOriginal = false
        let protectedTokens = Set(masked.replacements.keys)
        let units = RewriteUnitPlanner.units(
            in: masked.masked,
            mode: policy.mode,
            profile: profile
        )

        for unit in units {
            let editableTokens = protectedTokens.filter { unit.text.contains($0) }
            let cleaned: String

            if protectedTokens.contains(unit.text) {
                // The whole unit is one masked region. There is no prose here
                // to edit, so there is no reason to spend a request on it.
                cleaned = unit.text
            } else {
                switch await attemptUnit(
                    unit,
                    documentTitle: documentTitle,
                    headingPath: headingPath,
                    editableTokens: Array(editableTokens),
                    policy: policy,
                    profile: profile,
                    using: model
                ) {
                case let .success(candidate):
                    cleaned = candidate
                case let .keptOriginal(candidate):
                    cleaned = candidate
                    keptOriginal = true
                case let .refused(failure):
                    return .refused(failure)
                }
            }

            rewritten += unit.leading + cleaned + unit.trailing
        }

        // The placeholders are checked before anything is put back, so the
        // failure names the real problem rather than surfacing as a mangled
        // note further down.
        // Reassembly is the one place that cannot be made partial: if the
        // placeholders no longer line up, this segment's text goes back exactly
        // as it arrived. The note keeps whatever the other segments achieved.
        guard masked.brokenTokens(in: rewritten).isEmpty,
              let restored = masked.unmask(rewritten) else {
            return .keptOriginal(segment)
        }

        return keptOriginal
            ? .keptOriginal(envelope.leading + restored + envelope.trailing)
            : .success(envelope.leading + restored + envelope.trailing)
    }

    // MARK: - One unit, and its checking passes

    private static func attemptUnit(
        _ unit: RewriteUnit,
        documentTitle: String?,
        headingPath: String?,
        editableTokens: [String],
        policy: RewritePolicy,
        profile: ModelEffortProfile,
        using model: NamedRewriter
    ) async -> Attempt {
        let request = RewriteRequest(
            text: unit.text,
            documentTitle: documentTitle,
            headingPath: headingPath,
            contextBefore: unit.contextBefore,
            contextAfter: unit.contextAfter,
            effort: profile.effort
        )

        let raw: String
        do {
            raw = try await model.rewriter.rewrite(
                request,
                instructions: RewriteInstructions.forMode(
                    policy.mode,
                    effort: profile.effort,
                    protectedTokens: editableTokens,
                    fixesCapitalisation: policy.fixesCapitalisation
                )
            )
        } catch let error as ModelAccessError {
            return .refused(failure(from: error, modelID: model.modelID))
        } catch {
            return .refused(
                ProcessingGuard.isCloud(model.modelID)
                    ? .cloudRequestFailed(detail: error.localizedDescription)
                    : .localModelFailed(detail: error.localizedDescription)
            )
        }

        // An answer the guard will not accept is not a reason to abandon the
        // note. This passage keeps the text it already had — which passes every
        // check by construction — and the rest of the note carries on. What the
        // user loses is a fix in one paragraph; what they would have lost
        // before is every fix in the note, with nothing shown to them at all.
        var candidate = sanitize(raw, original: unit.text)
        if RewriteResponseGuard.inspect(
            original: unit.text,
            candidate: candidate
        ) != nil {
            return .keptOriginal(unit.text)
        }

        // The checking passes. A pass that fails its own guard is discarded and
        // the passage it was checking is kept: a rejected *check* is not a
        // reason to abandon a rewrite that already passed every check of its
        // own, and letting one turn the note into a failure would make Max less
        // reliable than Base, which is the opposite of what it promises.
        for _ in 0..<profile.reviewPasses {
            guard let reviewed = await review(
                original: unit.text,
                proposal: candidate,
                editableTokens: editableTokens,
                policy: policy,
                profile: profile,
                using: model
            ) else { break }
            candidate = reviewed
        }

        return .success(candidate)
    }

    private static func review(
        original: String,
        proposal: String,
        editableTokens: [String],
        policy: RewritePolicy,
        profile: ModelEffortProfile,
        using model: NamedRewriter
    ) async -> String? {
        let boundary = RewriteBoundary.make(avoiding: [original, proposal])
        let request = RewriteRequest(
            text: proposal,
            effort: profile.effort,
            boundary: boundary,
            composedPrompt: RewriteReviewInstructions.prompt(
                original: original,
                proposal: proposal,
                boundary: boundary
            )
        )

        guard let raw = try? await model.rewriter.rewrite(
            request,
            instructions: RewriteReviewInstructions.forMode(
                policy.mode,
                effort: profile.effort,
                protectedTokens: editableTokens,
                fixesCapitalisation: policy.fixesCapitalisation
            )
        ) else { return nil }

        let reviewed = sanitize(raw, original: original)
        guard !reviewed.isEmpty else { return nil }
        // Measured against the original, not against the proposal: the check
        // exists to catch a proposal that drifted, so its own answer has to
        // satisfy the same rule the proposal did.
        guard RewriteResponseGuard.inspect(
            original: original,
            candidate: reviewed
        ) == nil else { return nil }
        guard RewriteResponseGuard.isComposed(
            reviewed,
            of: [original, proposal]
        ) else { return nil }
        // The check may put a change back. That is the whole of what it may do:
        // every position in its answer has to hold either the original's word
        // or the proposal's. Anything else — a new correction, a different one,
        // half of one — is a check writing rather than checking, and is not
        // believed.
        guard RewriteResponseGuard.onlyReverts(
            reviewed,
            from: proposal,
            towards: original
        ) else { return nil }
        // A check may narrow a rewrite. It may not delete one.
        //
        // Handing the original back whole is the answer a small model reaches
        // for when it is unsure, and it is the most expensive answer available:
        // the note silently reports as unchanged and the corrections the user
        // asked for are gone, with nothing shown and nothing to reject. Measured
        // on the model this app ships — a clean `teh → the` reverted, and the
        // whole pass scoring lower with checking on than off.
        //
        // Keeping an overstepped rewrite costs far less, because Chamfer never
        // applies one silently: it goes to the review queue, where a person
        // reads it and presses Reject. Between a bad edit somebody can refuse
        // and a good edit nobody is offered, this app is built around the first.
        guard reviewed != original else { return nil }
        return reviewed
    }

    private static func effectivePreservation(for policy: RewritePolicy) -> MarkdownStructure {
        switch policy.mode {
        case .spelling, .grammar:
            policy.preserved.union(.all)
        case .formatting, .clarity, .fullCleanup:
            policy.preserved
        }
    }

    private static func updateHeadingPath(
        from section: String,
        headings: inout [Int: String]
    ) -> String? {
        guard let line = section.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return headings.isEmpty ? nil : headings.keys.sorted().compactMap { headings[$0] }
                .joined(separator: " > ")
        }

        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        let marker = trimmed.prefix { $0 == "#" }
        if !marker.isEmpty, marker.count <= 6,
           trimmed.dropFirst(marker.count).first?.isWhitespace == true {
            let level = marker.count
            headings.keys.filter { $0 >= level }.forEach { headings.removeValue(forKey: $0) }
            headings[level] = trimmed.dropFirst(level)
                .trimmingCharacters(in: .whitespaces)
        }

        let path = headings.keys.sorted().compactMap { headings[$0] }
        return path.isEmpty ? nil : path.joined(separator: " > ")
    }

    /// Newline separators belong to the document, not to the prose a model is
    /// invited to rewrite. Keeping them outside the request means a provider
    /// that trims its response cannot collapse headings or paragraphs when the
    /// independently rewritten sections are reassembled.
    private struct SectionEnvelope {
        let leading: String
        let body: String
        let trailing: String

        init(_ section: String) {
            let leadingEnd = section.firstIndex { !$0.isWhitespace } ?? section.endIndex
            let trailingStart = section[..<section.endIndex].lastIndex { !$0.isWhitespace }
                .map { section.index(after: $0) } ?? leadingEnd
            leading = String(section[..<leadingEnd])
            body = String(section[leadingEnd..<trailingStart])
            trailing = String(section[trailingStart...])
        }
    }

    /// Turns the reassembled text into an outcome.
    ///
    /// The gate no longer discards. A rewrite that trips it is shown rather
    /// than thrown away, carrying the reason it is being shown — the user gets
    /// a diff they can read and refuse instead of a sentence about a note they
    /// cannot see. The one thing a tripped gate still costs is the right to
    /// apply itself: `RewriteApplicationDecision` sends anything with a
    /// recommendation to the queue however the vault is configured.
    private static func finish(
        original: String,
        candidate: String,
        modelID: String,
        effort: ModelEffort,
        policy: RewritePolicy,
        keptOriginal: Bool = false
    ) -> RewriteOutcome {
        let gateFailure = RewriteGate.inspect(
            original: original,
            candidate: candidate,
            preserved: effectivePreservation(for: policy)
        )
        // An empty answer is the exception: there is no diff in it to judge.
        if let gateFailure, candidate.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return .failed(gateFailure)
        }

        let hunks = TextDiff.hunks(from: original, to: candidate)
        guard !hunks.isEmpty else { return .unchanged }

        let recommendation: RewriteReviewRecommendation? = if gateFailure != nil {
            .structureChangedUnexpectedly
        } else if keptOriginal {
            .partOfTheNoteWasKeptAsItWas
        } else {
            RewriteSafety.reviewRecommendation(
                original: original,
                candidate: candidate,
                mode: policy.mode
            )
        }

        return .proposed(
            RewriteProduct(
                hunks: hunks,
                text: candidate,
                modelID: modelID,
                effort: effort,
                reviewRecommendation: recommendation
            )
        )
    }

    // MARK: - Tidying what came back

    /// Everything a raw answer has to survive before it is compared with its
    /// original: a wrapping code fence, and any fence marker echoed back on a
    /// line of its own.
    static func sanitize(_ raw: String, original: String = "") -> String {
        RewriteResponseGuard.removingBoundaryMarkers(
            from: strippingOrphanFence(from: stripFencing(from: raw), original: original)
        )
    }

    /// Removes a lone closing fence the model added to a passage that never had
    /// one.
    ///
    /// `stripFencing` only handles a response wrapped in a fence top and
    /// bottom. This is the other half: an answer that ends in ``` with nothing
    /// opening it. Real code blocks are masked into placeholders before the
    /// model sees anything, so a fence in an answer whose passage contained
    /// none is always the model's own punctuation — and appending it to the
    /// note turns the rest of the file into a code block.
    private static func strippingOrphanFence(
        from text: String,
        original: String
    ) -> String {
        guard !original.contains("```"), text.contains("```") else { return text }
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last,
              last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes the code fence models wrap whole documents in.
    ///
    /// Asked for "only the revised note", a model will still sometimes return
    /// it inside ```` ```markdown ```` — and applying that would add three
    /// backticks to the top of the user's note. Only stripped when the fence
    /// wraps the entire response, so a note that legitimately *is* one code
    /// block survives.
    static func stripFencing(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: "\n")
        guard lines.count >= 2,
              let last = lines.last?.trimmingCharacters(in: .whitespaces),
              last == "```" || last.hasPrefix("```")
        else { return trimmed }

        // A fence in the middle means the response is a document containing
        // code blocks rather than a document wrapped in one.
        let interiorFences = lines.dropFirst().dropLast().filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        }
        guard interiorFences.isEmpty else { return trimmed }

        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    private static func failure(
        from error: ModelAccessError,
        modelID: String
    ) -> RewriteFailure {
        switch error {
        case .unavailable:
            .modelUnavailable(model: modelID)
        case let .rejected(status, message):
            ProcessingGuard.isCloud(modelID)
                ? .cloudRequestFailed(
                    detail: message.isEmpty
                        ? "The provider rejected the request (HTTP \(status))."
                        : message
                )
                : .localModelFailed(detail: message)
        case .invalidRequest, .invalidResponse, .emptyResponse:
            ProcessingGuard.isCloud(modelID)
                ? .cloudRequestFailed(
                    detail: error.errorDescription ?? "The provider's response could not be read."
                )
                : .localModelFailed(
                    detail: error.errorDescription ?? "The model's response could not be read."
                )
        }
    }
}
