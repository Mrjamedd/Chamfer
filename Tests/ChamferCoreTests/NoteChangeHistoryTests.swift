import Foundation
import Testing

@testable import ChamferCore

private let changeClock = Date(timeIntervalSince1970: 1_900_000_000)

private func changeSummary(_ url: URL) -> NoteSummary {
    NoteSummary(
        url: url,
        title: url.deletingPathExtension().lastPathComponent,
        wordCount: 8,
        modifiedAt: changeClock
    )
}

private func changeProposal(
    _ url: URL,
    createdAt: Date,
    state: ProposalState = .pending
) -> Proposal {
    Proposal(
        note: changeSummary(url),
        hunks: [Hunk(before: "teh", after: "the", startLine: 1)],
        createdAt: createdAt,
        state: state
    )
}

private func changeEntry(_ url: URL, occurredAt: Date) -> HistoryEntry {
    HistoryEntry(
        note: changeSummary(url),
        path: url,
        occurredAt: occurredAt,
        mode: .fullCleanup,
        modelID: "local.ollama",
        previousText: "teh",
        appliedText: "the",
        application: .review
    )
}

@Test func noteChangeHistoryCombinesOnlyActionableWorkForTheExactNote() {
    let noteURL = URL(filePath: "/Vault/Folder/../Note.md").standardizedFileURL
    let equivalentURL = URL(filePath: "/Vault/Note.md")
    let otherURL = URL(filePath: "/Vault/Other.md")
    let older = changeClock.addingTimeInterval(-60)

    let changes = NoteChangeHistory(
        noteURL: noteURL,
        proposals: [
            changeProposal(equivalentURL, createdAt: older),
            changeProposal(equivalentURL, createdAt: changeClock),
            changeProposal(equivalentURL, createdAt: changeClock, state: .accepted),
            changeProposal(otherURL, createdAt: changeClock)
        ],
        history: [
            changeEntry(equivalentURL, occurredAt: older),
            changeEntry(otherURL, occurredAt: changeClock),
            changeEntry(equivalentURL, occurredAt: changeClock)
        ]
    )

    #expect(changes.queued.map(\.createdAt) == [changeClock, older])
    #expect(changes.history.map(\.occurredAt) == [changeClock, older])
    #expect(changes.count == 4)
}

@Test func noteChangeHistoryCanBeEmptyWithoutLosingItsNoteIdentity() {
    let noteURL = URL(filePath: "/Vault/Quiet.md")
    let changes = NoteChangeHistory(noteURL: noteURL, proposals: [], history: [])

    #expect(changes.noteURL == noteURL.standardizedFileURL)
    #expect(changes.isEmpty)
    #expect(changes.count == 0)
}
