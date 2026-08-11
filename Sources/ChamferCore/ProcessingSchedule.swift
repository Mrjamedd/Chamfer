import Foundation

/// When a note becomes eligible to be worked on.
///
/// Two independent routes, exactly as the scope describes: a note that has gone
/// quiet, and a sweep that runs on the clock. Both are pure functions over a
/// supplied `now`, so the behaviour at three in the morning on a Sunday is
/// something that can be tested rather than waited for.
public enum ProcessingSchedule {
    /// Whether a note that last changed at `lastChanged` has been quiet long
    /// enough.
    ///
    /// The comparison is inclusive: a delay of exactly ten minutes means a note
    /// is eligible ten minutes after the last keystroke, not a tick later.
    public static func hasSettled(
        lastChanged: Date,
        delay: TimeInterval,
        now: Date
    ) -> Bool {
        now.timeIntervalSince(lastChanged) >= delay
    }

    /// Whether a vault is due a sweep.
    ///
    /// A vault that has never been swept is always due, whatever the schedule —
    /// except under `.never`, where the user has said the clock is not to
    /// trigger anything at all and a "first sweep" would be the app deciding
    /// otherwise on their behalf.
    public static func isSweepDue(
        _ schedule: SweepSchedule,
        lastSweep: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        switch schedule {
        case .never:
            return false

        case let .everyHours(hours):
            guard let lastSweep else { return true }
            return now.timeIntervalSince(lastSweep) >= Double(hours) * 3_600

        case let .dailyAt(hour):
            guard let lastSweep else { return true }
            guard let occurrence = mostRecentOccurrence(
                ofHour: hour,
                before: now,
                calendar: calendar
            ) else { return false }
            // Due when the clock has passed the appointed hour since the last
            // sweep. Comparing against the occurrence rather than against a
            // 24-hour interval is what stops a sweep that ran at 02:59 from
            // pushing the 03:00 one to the following day.
            return lastSweep < occurrence
        }
    }

    /// When the next sweep would fall, for anything that wants to say so.
    public static func nextSweep(
        _ schedule: SweepSchedule,
        lastSweep: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch schedule {
        case .never:
            return nil

        case let .everyHours(hours):
            guard let lastSweep else { return now }
            let next = lastSweep.addingTimeInterval(Double(hours) * 3_600)
            return next > now ? next : now

        case let .dailyAt(hour):
            guard let occurrence = mostRecentOccurrence(
                ofHour: hour,
                before: now,
                calendar: calendar
            ) else { return nil }
            if lastSweep == nil { return now }
            if let lastSweep, lastSweep < occurrence { return now }
            return calendar.date(byAdding: .day, value: 1, to: occurrence)
        }
    }

    /// The last time the clock passed `hour`, which is today if it already has
    /// and yesterday if it has not.
    private static func mostRecentOccurrence(
        ofHour hour: Int,
        before now: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = ((hour % 24) + 24) % 24
        components.minute = 0
        components.second = 0

        guard let today = calendar.date(from: components) else { return nil }
        guard today > now else { return today }
        return calendar.date(byAdding: .day, value: -1, to: today)
    }
}
