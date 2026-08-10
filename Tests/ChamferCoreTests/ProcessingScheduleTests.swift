import Foundation
import Testing

@testable import ChamferCore

// MARK: - Helpers

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func moment(
    day: Int = 14,
    hour: Int,
    minute: Int = 0
) -> Date {
    calendar.date(
        from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
    )!
}

// MARK: - Inactivity

@Test func aNoteIsEligibleOnceItHasBeenQuietForTheConfiguredDelay() {
    let changed = moment(hour: 9)

    #expect(
        !ProcessingSchedule.hasSettled(
            lastChanged: changed,
            delay: 600,
            now: moment(hour: 9, minute: 9)
        )
    )
    // Inclusive: ten minutes means ten minutes, not a tick later.
    #expect(
        ProcessingSchedule.hasSettled(
            lastChanged: changed,
            delay: 600,
            now: moment(hour: 9, minute: 10)
        )
    )
    #expect(
        ProcessingSchedule.hasSettled(
            lastChanged: changed,
            delay: 600,
            now: moment(hour: 11)
        )
    )
}

// MARK: - Never

@Test func neverMeansTheClockTriggersNothingEvenOnAVaultNeverSwept() {
    // A "first sweep" here would be the app overruling the user's explicit
    // instruction that nothing should run on a schedule.
    #expect(
        !ProcessingSchedule.isSweepDue(
            .never,
            lastSweep: nil,
            now: moment(hour: 12),
            calendar: calendar
        )
    )
    #expect(ProcessingSchedule.nextSweep(.never, lastSweep: nil, now: moment(hour: 12)) == nil)
}

// MARK: - Interval sweeps

@Test func anIntervalSweepIsDueOnceTheIntervalHasElapsed() {
    let last = moment(hour: 6)

    #expect(
        !ProcessingSchedule.isSweepDue(
            .everyHours(6),
            lastSweep: last,
            now: moment(hour: 11),
            calendar: calendar
        )
    )
    #expect(
        ProcessingSchedule.isSweepDue(
            .everyHours(6),
            lastSweep: last,
            now: moment(hour: 12),
            calendar: calendar
        )
    )
}

@Test func aVaultNeverSweptIsDueImmediatelyOnAnInterval() {
    #expect(
        ProcessingSchedule.isSweepDue(
            .everyHours(24),
            lastSweep: nil,
            now: moment(hour: 12),
            calendar: calendar
        )
    )
}

// MARK: - Daily sweeps

@Test func aDailySweepIsDueOnceTheClockHasPassedItsHour() {
    // Swept yesterday evening; the 3am appointment has since come round.
    #expect(
        ProcessingSchedule.isSweepDue(
            .dailyAt(hour: 3),
            lastSweep: moment(day: 13, hour: 20),
            now: moment(day: 14, hour: 9),
            calendar: calendar
        )
    )
}

@Test func aDailySweepIsNotDueTwiceInTheSameDay() {
    #expect(
        !ProcessingSchedule.isSweepDue(
            .dailyAt(hour: 3),
            lastSweep: moment(day: 14, hour: 3, minute: 1),
            now: moment(day: 14, hour: 22),
            calendar: calendar
        )
    )
}

@Test func aSweepJustBeforeTheHourDoesNotSatisfyIt() {
    // Ran at 02:59. The 03:00 sweep is still owed, and comparing against a
    // rolling 24 hours instead of the appointment would push it to tomorrow.
    #expect(
        ProcessingSchedule.isSweepDue(
            .dailyAt(hour: 3),
            lastSweep: moment(day: 14, hour: 2, minute: 59),
            now: moment(day: 14, hour: 3, minute: 30),
            calendar: calendar
        )
    )
}

@Test func beforeTheHourTheRelevantAppointmentIsYesterdays() {
    // It is 1am. The last appointment was 3am yesterday, and a sweep since
    // then means nothing is owed.
    #expect(
        !ProcessingSchedule.isSweepDue(
            .dailyAt(hour: 3),
            lastSweep: moment(day: 13, hour: 8),
            now: moment(day: 14, hour: 1),
            calendar: calendar
        )
    )
    // No sweep since yesterday's appointment, so one is owed.
    #expect(
        ProcessingSchedule.isSweepDue(
            .dailyAt(hour: 3),
            lastSweep: moment(day: 13, hour: 1),
            now: moment(day: 14, hour: 1),
            calendar: calendar
        )
    )
}

@Test func everyScheduleTheInterfaceOffersBehavesSensibly() {
    // The picker's choices, none of which may trap or crash.
    for schedule in SweepSchedule.choices {
        _ = ProcessingSchedule.isSweepDue(
            schedule,
            lastSweep: nil,
            now: moment(hour: 12),
            calendar: calendar
        )
        _ = ProcessingSchedule.nextSweep(
            schedule,
            lastSweep: moment(hour: 6),
            now: moment(hour: 12),
            calendar: calendar
        )
    }
}

// MARK: - Next due

@Test func theNextIntervalSweepIsOneIntervalAfterTheLast() {
    #expect(
        ProcessingSchedule.nextSweep(
            .everyHours(6),
            lastSweep: moment(hour: 6),
            now: moment(hour: 8),
            calendar: calendar
        ) == moment(hour: 12)
    )
}

@Test func anOverdueSweepIsReportedAsDueNow() {
    let now = moment(hour: 20)
    #expect(
        ProcessingSchedule.nextSweep(
            .everyHours(6),
            lastSweep: moment(hour: 6),
            now: now,
            calendar: calendar
        ) == now
    )
}
