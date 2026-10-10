import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTaskScheduleDescriptionTests {
    private let locale = Locale(identifier: "en_US")
    private let hongKong = TimeZone(identifier: "Asia/Hong_Kong")!

    private func label(_ expression: String) -> String {
        ScheduledTaskSchedule(kind: "cron", expression: expression)
            .description(locale: locale, displayTimeZone: hongKong)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test(arguments: [
        ("0 9 * * *", "Every day at 9:00 AM"),
        ("30 18 * * MON-FRI", "Every weekday at 6:30 PM"),
        ("0 9 * * 0,6", "Every weekend at 9:00 AM"),
        ("0 9 * * 7", "Every Sunday at 9:00 AM"),
        ("0 9 * * 1", "Every Monday at 9:00 AM"),
        ("0 9 1 * *", "On day 1 of every month at 9:00 AM"),
        ("0 9 1 JAN *", "On day 1 of January at 9:00 AM"),
        ("*/15 * * * *", "Every 15 minutes"),
        ("* * * * *", "Every minute"),
        ("0 * * * *", "Every hour"),
        ("30 * * * *", "Every hour at minute 30"),
        ("0 */6 * * *", "Every 6 hours"),
        ("0 9,17 * * *", "Every day at 9:00 AM and 5:00 PM"),
        ("0 9 * * 1,3,5", "Every Monday, Wednesday, and Friday at 9:00 AM"),
        ("  0\t9  * * ?  ", "Every day at 9:00 AM")
    ]) func recurringSchedulesAreReadable(expression: String, expected: String) {
        #expect(label(expression) == expected)
    }

    @Test(arguments: ["0 9 L * *", "0 9 * * MON#2", "0 9 1 * MON", "0 9 1 * +MON", "*/0 * * * *", "0 25 * * *", "0 9 * *", "0 9 * * 8", "0 9 * * 5-1"])
    func unfamiliarOrInvalidCronIsNotMistranslated(_ expression: String) {
        #expect(label(expression) == "Custom schedule")
    }

    @Test func customScheduleShowsItsNextExactOccurrence() {
        let schedule = ScheduledTaskSchedule(kind: "cron", expression: "0 9 L * *")
        let result = schedule.description(nextRunAt: 1791594000000, locale: locale, displayTimeZone: hongKong)
        #expect(result.hasPrefix("Custom schedule · Next: "))
        #expect(result.contains("Oct 10, 2026"))
        #expect(result.contains("9:00"))
    }

    @Test func oneTimeDateRemainsExactWithoutANextRun() {
        let schedule = ScheduledTaskSchedule(at: "2026-10-10T01:00:00.000Z")
        let result = schedule.description(locale: locale, displayTimeZone: hongKong)
        #expect(result.contains("Oct 10, 2026"))
        #expect(result.contains("9:00"))
        #expect(!result.contains("Hong Kong"))
        #expect(!result.contains("One time"))
    }

    @Test func oneTimeScheduleConvertsToLocalDateAndTime() {
        let schedule = ScheduledTaskSchedule(timezone: "Asia/Hong_Kong", at: "2026-10-10T09:00:00+08:00")
        let result = schedule.description(locale: locale, displayTimeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(result.contains("Oct 9, 2026"))
        #expect(result.contains("6:00"))
        #expect(!result.contains("Hong Kong"))
    }

    @Test func cronUsesLocalTimeAndUsersClockFormat() {
        let schedule = ScheduledTaskSchedule(kind: "cron", timezone: "America/New_York", expression: "30 18 * * *")
        let result = schedule.description(nextRunAt: timestamp("2026-10-10T22:30:00Z"), locale: Locale(identifier: "en_GB"), displayTimeZone: hongKong)
        #expect(result == "Every day at 06:30")
    }

    private func timestamp(_ value: String) -> Double {
        ISO8601DateFormatter().date(from: value)!.timeIntervalSince1970 * 1000
    }

    @Test(arguments: [
        ("2026-10-10T13:00:00Z", "Every day at 21:00"),
        ("2026-11-10T14:00:00Z", "Every day at 22:00")
    ]) func nextRunControlsDaylightSavingOffset(nextRun: String, expected: String) {
        let schedule = ScheduledTaskSchedule(kind: "cron", timezone: "America/New_York", expression: "0 9 * * *")
        #expect(schedule.description(nextRunAt: timestamp(nextRun), locale: Locale(identifier: "en_GB"), displayTimeZone: hongKong) == expected)
    }

    @Test(arguments: [
        ("30 18 * * MON", "America/New_York", "Asia/Hong_Kong", "Every Tuesday at 06:30"),
        ("0 9 * * MON", "Asia/Hong_Kong", "America/Los_Angeles", "Every Sunday at 18:00"),
        ("30 18 * * MON-FRI", "America/New_York", "Asia/Hong_Kong", "Every Tuesday, Wednesday, Thursday, Friday and Saturday at 06:30"),
        ("0 9 * * *", "UTC", "Asia/Kathmandu", "Every day at 14:45"),
        ("0 * * * *", "UTC", "Asia/Kolkata", "Every hour at minute 30"),
        ("0 9,17 * * *", "UTC", "Asia/Hong_Kong", "Every day at 01:00 and 17:00"),
        ("0 9 1 * *", "UTC", "Asia/Hong_Kong", "On day 1 of every month at 17:00")
    ]) func recurrenceConvertsCalendarAndClock(expression: String, source: String, local: String, expected: String) {
        let schedule = ScheduledTaskSchedule(kind: "cron", timezone: source, expression: expression)
        #expect(schedule.description(nextRunAt: timestamp("2026-10-12T22:30:00Z"), locale: Locale(identifier: "en_GB"), displayTimeZone: TimeZone(identifier: local)!) == expected)
    }

    @Test func monthlyBoundaryUsesExactLocalNextRun() {
        let schedule = ScheduledTaskSchedule(kind: "cron", timezone: "Asia/Hong_Kong", expression: "0 1 1 * *")
        let result = schedule.description(nextRunAt: timestamp("2026-10-31T17:00:00Z"), locale: locale, displayTimeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(result.hasPrefix("Custom schedule · Next: "))
        #expect(result.contains("Oct 31, 2026"))
        #expect(result.contains("10:00"))
    }

    @Test func mixedWeekdayTimesDoNotInventExtraRuns() {
        let schedule = ScheduledTaskSchedule(kind: "cron", timezone: "UTC", expression: "0 9,17 * * MON")
        let result = schedule.description(nextRunAt: timestamp("2026-10-12T09:00:00Z"), locale: locale, displayTimeZone: hongKong)
        #expect(result.hasPrefix("Custom schedule · Next: "))
        #expect(result.contains("5:00"))
    }

    @Test(arguments: [(1, "Every minute"), (30, "Every 30 minutes"), (60, "Every hour"), (120, "Every 2 hours"), (1440, "Every 24 hours"), (0, "Interval schedule")])
    func elapsedIntervalsDoNotImplyCalendarDays(minutes: Int, expected: String) {
        let schedule = ScheduledTaskSchedule(kind: "interval", everyMinutes: minutes)
        #expect(schedule.description(locale: locale, displayTimeZone: hongKong) == expected)
    }

    @Test func missingAndInvalidDatesStayHonest() {
        #expect(ScheduledTaskSchedule(at: "broken").description(locale: locale, displayTimeZone: hongKong) == "One-time schedule")
        let result = ScheduledTaskSchedule(timezone: "invalid", at: "2026-10-10T01:00:00Z")
            .description(locale: locale, displayTimeZone: hongKong)
        #expect(result.contains("9:00"))
        #expect(!result.contains("UTC"))
    }
}
