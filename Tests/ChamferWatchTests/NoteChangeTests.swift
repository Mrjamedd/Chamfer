import Foundation
import Testing

@testable import ChamferWatch

/// Scaffold-level check. Debounce, echo suppression and atomic-write tests
/// arrive with the watcher implementation.
@Test func changesCompareByURLAndTimestamp() {
    let url = URL(fileURLWithPath: "/tmp/note.md")
    let moment = Date(timeIntervalSince1970: 0)
    #expect(NoteChange(url: url, detectedAt: moment) == NoteChange(url: url, detectedAt: moment))
}
