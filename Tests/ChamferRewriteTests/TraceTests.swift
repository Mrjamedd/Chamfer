import ChamferCore
import Foundation
import Testing

@testable import ChamferRewrite

/// Every model call of one real note, written down.
///
/// Chamfer keeps no log of what it sent or what came back — a failed rewrite
/// reports a sentence and nothing else — so this reruns the note through the
/// real pipeline with a rewriter that records both sides of every request.
private final class TracingRewriter: Rewriter, @unchecked Sendable {
    private let inner: OllamaRewriter
    private let lock = NSLock()
    private(set) var log: [[String: String]] = []

    init(model: String, client: OllamaClient) {
        inner = OllamaRewriter(model: model, client: client)
    }

    var isAvailable: Bool { get async { await inner.isAvailable } }

    func rewrite(_ section: String, instructions: String) async throws -> String {
        try await rewrite(RewriteRequest(text: section), instructions: instructions)
    }

    func rewrite(_ request: RewriteRequest, instructions: String) async throws -> String {
        let answer: String
        do {
            answer = try await inner.rewrite(request, instructions: instructions)
        } catch {
            record(request, instructions, "«THREW: \(error)»")
            throw error
        }
        record(request, instructions, answer)
        return answer
    }

    private func record(_ request: RewriteRequest, _ instructions: String, _ answer: String) {
        lock.lock()
        log.append([
            "stage": request.prompt.contains(":PROPOSED>>>") ? "checking" : "editing",
            "system": instructions,
            "user": request.prompt,
            "raw": answer,
            "sanitized": RewritePipeline.sanitize(answer),
            "budget": String(request.maximumResponseTokens)
        ])
        lock.unlock()
    }
}

@Test(.tags(.live))
func traceOneNote() async throws {
    OllamaEndpoint.shared.current = OllamaAPI.privateBaseURL
    let client = OllamaClient(baseURL: OllamaAPI.privateBaseURL)
    guard await client.isAvailable(),
          let installed = try? await client.installedModelIDs(),
          let modelID = installed.sorted().first else {
        Issue.record("No runtime on 11913")
        return
    }

    let url = URL(filePath: tracedNote)
    let text = try String(contentsOf: url, encoding: .utf8)
    let tracer = TracingRewriter(model: modelID, client: client)

    // The vault's own settings, as persisted.
    let policy = RewritePolicy(
        mode: .spelling,
        application: .review,
        runTrigger: .inactivity,
        inactivityDelay: 60,
        sweep: .never,
        preserved: MarkdownStructure(rawValue: 508),
        modelID: RewritePolicy.localModelIdentifier
    )

    // What the note looks like after masking, before any request is built.
    let effective = MarkdownStructure(rawValue: 508).union(.all)
    let segments = MarkdownSectioner.sections(
        in: text,
        targetCharacterCount: ModelEffort.balanced.profile.segmentTargetCharacters
    )

    var report: [String] = [
        "MODEL \(modelID) · MODE spelling · EFFORT balanced",
        "PRESERVED raw 508 → effective \(effective.rawValue) (spelling forces .all)",
        "SEGMENTS \(segments.count)"
    ]

    for (index, segment) in segments.enumerated() {
        let masked = MarkdownMask.apply(to: segment, preserving: effective)
        report.append("""

            ══════ SEGMENT \(index + 1) — MASKED (\(masked.replacements.count) placeholders) ══════
            \(masked.masked)
            ── what each placeholder stands for ──
            \(masked.replacements.sorted { $0.key < $1.key }
                .map { "\($0.key) = \($0.value.debugDescription)" }
                .joined(separator: "\n"))
            """)
    }

    let outcome = await RewritePipeline.run(
        text: text,
        documentTitle: "Project Atlas",
        policy: policy,
        model: NamedRewriter(modelID: modelID, rewriter: tracer),
        effort: .balanced
    )

    for (index, call) in tracer.log.enumerated() {
        report.append("""

            ══════ REQUEST \(index + 1) — \(call["stage"]!.uppercased()) ══════
            ── budget: num_predict \(call["budget"]!) ──
            ── SYSTEM MESSAGE ──
            \(call["system"]!)
            ── USER MESSAGE ──
            \(call["user"]!)
            ── RAW ANSWER ──
            \(call["raw"]!)
            ── AFTER SANITISING ──
            \(call["sanitized"]!)
            """)
    }

    switch outcome {
    case .unchanged:
        report.append("\n══════ OUTCOME ══════\nUNCHANGED — no diff to show anyone.")
    case let .failed(failure):
        report.append("\n══════ OUTCOME ══════\nFAILED — \(failure.title): \(failure.detail)")
    case let .proposed(product):
        report.append("\n══════ OUTCOME ══════\nPROPOSED — \(product.hunks.count) change(s)")
        for hunk in product.hunks {
            report.append("  - \(hunk.before.debugDescription)")
            report.append("  + \(hunk.after.debugDescription)")
        }
    }

    print(report.joined(separator: "\n"))
}

/// The note to trace. Point it at whichever one is misbehaving.
private let tracedNote =
    "/Users/anthonymurphy/Documents/Chamfer Test Vault/19 Project Atlas.md"

/// How the note is actually divided, per effort mode. Pure functions, no model.
@Test(.tags(.live))
func traceSegmentation() throws {
    let text = try String(contentsOf: URL(filePath: tracedNote), encoding: .utf8)
    var lines = ["NOTE \(text.count) chars\n"]

    for effort in ModelEffort.allCases {
        let profile = effort.profile
        let segments = MarkdownSectioner.sections(
            in: text,
            targetCharacterCount: profile.segmentTargetCharacters
        )
        var units = 0
        var withContext = 0
        var sizes: [Int] = []

        for segment in segments {
            let masked = MarkdownMask.apply(to: segment, preserving: .all)
            let planned = RewriteUnitPlanner.units(
                in: masked.masked,
                mode: .spelling,
                profile: profile
            )
            units += planned.count
            withContext += planned.count {
                $0.contextBefore != nil || $0.contextAfter != nil
            }
            sizes.append(contentsOf: planned.map(\.text.count))
        }

        lines.append("""
            \(effort.rawValue.uppercased())
              segment target \(profile.segmentTargetCharacters) chars → \(segments.count) segments
              unit target    \(profile.unitTargetCharacters) chars → \(units) units
              unit sizes     \(sizes.sorted().map(String.init).joined(separator: ", "))
              neighbour context promised \(profile.includesNeighbourContext), attached to \(withContext) of \(units)
              model calls    \(units * profile.requestsPerUnit)
            """)
    }

    print(lines.joined(separator: "\n"))
}
