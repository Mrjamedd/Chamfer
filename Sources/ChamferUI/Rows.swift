import ChamferCore
import SwiftUI

public struct FolderRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.chamferSurface) private var surface

    private let folder: WatchedFolder

    public init(_ folder: WatchedFolder) {
        self.folder = folder
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: folder.isReachable ? "folder" : "folder.badge.questionmark")
                .font(.system(size: 12))
                .foregroundStyle(folder.isReachable ? surface.textFaint : surface.danger)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(folder.url.lastPathComponent)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(surface.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(folder.isReachable ? surface.textFaint : surface.danger)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var detail: String {
        guard folder.isReachable else { return "Unreachable — reconnect the disk to resume" }
        let notes = "\(folder.noteCount.formatted()) notes"
        guard let sweep = folder.lastSweep else { return "\(notes) · sweeping now" }
        return "\(notes) · swept \(RelativeTime.string(sweep, since: now))"
    }
}

public struct CleanupRow: View {
    @Environment(\.chamferNow) private var now
    @Environment(\.chamferSurface) private var surface

    private let record: CleanupRecord

    public init(_ record: CleanupRecord) {
        self.record = record
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Chamfer.Space.snug) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(surface.positive)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: Chamfer.Space.hair) {
                Text(record.note.title)
                    .font(Chamfer.TypeScale.bodyStrong)
                    .foregroundStyle(surface.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(record.rules.count) rule\(record.rules.count == 1 ? "" : "s") · \(RelativeTime.string(record.appliedAt, since: now))")
                    .font(Chamfer.TypeScale.caption)
                    .foregroundStyle(surface.textFaint)
            }
            Spacer(minLength: 0)
        }
    }
}
