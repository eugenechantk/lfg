import Foundation
import Testing
@testable import LFGCore

/// One case per row of the plan's variant table (plan-edit-variants), plus round trips:
/// every saved kind opens in the right mode and pick, and saves back unchanged.
@Suite struct ScheduleDraftTests {
    static let now = TaskPresentationTests.now // Thu 2026-10-15 10:12 HKT
    static let tz = "Asia/Hong_Kong"
    static let en = Locale(identifier: "en_US")
    static let friday9 = ISO8601DateFormatter().date(from: "2026-10-16T01:00:00Z")!

    private func draft(_ preset: ScheduleDraft.Preset, every: Int? = nil, ends: ScheduleDraft.Ends = .never, count: Int = 10) -> ScheduleDraft {
        var d = ScheduleDraft(now: Self.now, timezone: Self.tz)
        d.mode = .repeating; d.preset = preset; d.ends = ends; d.count = count
        d.start = Self.friday9
        if let every {
            switch preset { case .minutes: d.everyMinutes = every; case .hourly: d.everyHours = every; case .daily: d.everyDays = every; default: break }
        }
        return d
    }
    private func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }

    /// Next-run chips as the edit boards write them (same table on phone and desktop).
    @Test func nextRunChipsFollowTheBoards() {
        let ms = { (iso: String) in ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000 }
        let fri9 = ms("2026-10-16T01:00:00Z"), mon9 = ms("2026-10-19T01:00:00Z"), tue9 = ms("2026-10-20T01:00:00Z"), wed9 = ms("2026-10-21T01:00:00Z")
        let chips = { (d: ScheduleDraft, runs: [Double]) in d.chips(runs, now: Self.now, locale: Self.en).map(self.plain) }
        #expect(chips(draft(.weekdays), [fri9, mon9, tue9, wed9]) == ["Fri 9:00", "Mon 9:00", "Tue 9:00"])
        var daily = draft(.daily, every: 1); daily.hour = 9; daily.minute = 0
        #expect(chips(daily, [fri9]) == ["Fri 9:00"])
        #expect(chips(draft(.daily, every: 3), [fri9, mon9, ms("2026-10-22T01:00:00Z"), ms("2026-10-25T01:00:00Z"), ms("2026-10-28T01:00:00Z")]).count == 4)
        let nov1 = ms("2026-11-01T01:00:00Z"), dec1 = ms("2026-12-01T01:00:00Z")
        #expect(chips(draft(.monthly), [nov1, dec1]) == ["Nov 1 · 9:00", "Dec 1 · 9:00"])
        let t1015 = ms("2026-10-15T02:15:00Z"), t1020 = ms("2026-10-15T02:20:00Z")
        #expect(chips(draft(.minutes, every: 5), [t1015, t1020]) == ["10:15", "10:20"])
        #expect(chips(draft(.minutes, every: 7), [fri9]) == ["Fri 9:00 AM"])
    }

    @Test func every5MinutesIsCron() {
        let s = draft(.minutes, every: 5).schedule
        #expect(s.kind == "cron"); #expect(s.expression == "*/5 * * * *")
        #expect(draft(.minutes, every: 5).subline(now: Self.now, locale: Self.en) == "Runs at fixed clock times")
    }

    @Test func every7MinutesIsAnExactGapFromStarts() {
        let d = draft(.minutes, every: 7)
        let s = d.schedule
        #expect(s.kind == "interval"); #expect(s.everyMinutes == 7); #expect(s.at == "2026-10-16T09:00:00+08:00")
        #expect(plain(d.subline(now: Self.now, locale: Self.en)) == "Exact gap from Fri, Oct 16 at 9:00 AM")
    }

    @Test func everyHourAndEvery5Hours() {
        var hourly = draft(.hourly, every: 1); hourly.minute = 0
        #expect(hourly.schedule.expression == "0 * * * *")
        var six = draft(.hourly, every: 6); six.minute = 15
        #expect(six.schedule.expression == "15 */6 * * *")
        let five = draft(.hourly, every: 5).schedule
        #expect(five.kind == "interval"); #expect(five.everyMinutes == 300)
    }

    @Test func everyDayIsCronEvery3DaysIsAGap() {
        let daily = draft(.daily, every: 1).schedule
        #expect(daily.kind == "cron"); #expect(daily.expression == "0 9 * * *")
        let three = draft(.daily, every: 3).schedule
        #expect(three.kind == "interval"); #expect(three.everyMinutes == 4320); #expect(three.at == "2026-10-16T09:00:00+08:00")
    }

    @Test func weekdaysWeeklyMonthlyCustom() {
        #expect(draft(.weekdays).schedule.expression == "0 9 * * 1-5")
        var weekly = draft(.weekly); weekly.days = [1, 3, 5]
        #expect(weekly.schedule.expression == "0 9 * * 1,3,5")
        #expect(plain(weekly.sentence(locale: Self.en)) == "Every Mon, Wed and Fri at 9:00 AM")
        var monthly = draft(.monthly); monthly.dayOfMonth = 1
        #expect(monthly.schedule.expression == "0 9 1 * *")
        #expect(plain(monthly.sentence(locale: Self.en)) == "On the 1st of every month at 9:00 AM")
        var custom = draft(.custom); custom.customExpression = "30 8 1,15  *  *"
        #expect(custom.schedule.expression == "30 8 1,15 * *")
        #expect(plain(custom.sentence(locale: Self.en)) == "At 8:30 AM on the 1st and 15th of every month")
    }

    /// What the chat saves ("Tue–Fri at 8:00 AM" as `0 8 * * 2-5`) opens as Weekly with those days, and an
    /// edit to the days writes a plain list.
    @Test func dayRangesOpenAsWeekly() {
        var d = ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "0 8 * * 2-5"))
        #expect(d.preset == .weekly); #expect(d.days == [2, 3, 4, 5]); #expect(d.hour == 8)
        #expect(d.schedule.expression == "0 8 * * 2-5")
        d.days.insert(1)
        #expect(d.schedule.expression == "0 8 * * 1,2,3,4,5")
        #expect(ScheduleDraft.weekdays(in: "1-3,5") == [1, 2, 3, 5]); #expect(ScheduleDraft.weekdays(in: "5-2") == nil)
    }

    @Test func endsAfterAndOnDate() {
        let cronAfter = draft(.weekdays, ends: .after, count: 10).schedule
        #expect(cronAfter.kind == "cron"); #expect(cronAfter.maxRuns == 10); #expect(cronAfter.endsAt == nil)
        let gapAfter = draft(.daily, every: 3, ends: .after, count: 5).schedule
        #expect(gapAfter.kind == "repeat"); #expect(gapAfter.occurrences == 5); #expect(gapAfter.everyMinutes == 4320)
        var onDate = draft(.weekdays, ends: .onDate)
        onDate.endDate = ISO8601DateFormatter().date(from: "2026-12-31T04:00:00Z")!
        #expect(onDate.schedule.endsAt == "2026-12-31T23:59:59+08:00"); #expect(onDate.schedule.maxRuns == nil)
        var gapOnDate = draft(.minutes, every: 7, ends: .onDate); gapOnDate.endDate = onDate.endDate
        #expect(gapOnDate.schedule.kind == "interval"); #expect(gapOnDate.schedule.endsAt == "2026-12-31T23:59:59+08:00")
        #expect(plain(draft(.weekdays, ends: .after, count: 10).sentence(locale: Self.en)) == "Every weekday at 9:00 AM, 10 times")
    }

    @Test func once() {
        var d = ScheduleDraft(now: Self.now, timezone: Self.tz)
        d.mode = .once; d.start = Self.friday9
        #expect(d.schedule.kind == "once"); #expect(d.schedule.at == "2026-10-16T09:00:00+08:00")
        #expect(plain(d.sentence(locale: Self.en)) == "Once, Fri, Oct 16 at 9:00 AM")
        #expect(d.subline(now: Self.now, locale: Self.en) == "In 22 h 48 min")
    }

    @Test func newDraftDefaultsToOnceTomorrowAtNine() {
        let d = ScheduleDraft(now: Self.now, timezone: Self.tz)
        #expect(d.mode == .once); #expect(d.start == Self.friday9)
    }

    @Test(arguments: [
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "*/5 * * * *"),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "0 * * * *"),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "15 */6 * * *"),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "0 9 * * *"),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "0 9 * * 1-5", maxRuns: 10),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "0 9 * * 1,3,5"),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "0 8 * * 2-5"),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "0 9 1 * *", endsAt: "2026-12-31T23:59:59+08:00"),
        ScheduledTaskSchedule(kind: "cron", timezone: tz, expression: "30 8 1,15 * *"),
        ScheduledTaskSchedule(kind: "interval", timezone: tz, at: "2026-10-16T09:00:00+08:00", everyMinutes: 7),
        ScheduledTaskSchedule(kind: "interval", timezone: tz, at: "2026-10-16T09:00:00+08:00", everyMinutes: 300),
        ScheduledTaskSchedule(kind: "repeat", timezone: tz, at: "2026-10-16T09:00:00+08:00", everyMinutes: 4320, occurrences: 5),
        // Exact gaps that happen to fit the clock stay exact gaps (cron would restart the count).
        ScheduledTaskSchedule(kind: "repeat", timezone: tz, at: "2026-10-13T08:30:00+08:00", everyMinutes: 1440, occurrences: 5),
        ScheduledTaskSchedule(kind: "interval", timezone: tz, at: "2026-10-16T09:00:00+08:00", everyMinutes: 60),
        ScheduledTaskSchedule(kind: "interval", timezone: tz, everyMinutes: 360),
        ScheduledTaskSchedule(kind: "once", timezone: tz, at: "2026-10-16T09:00:00+08:00"),
    ])
    func savedSchedulesOpenInTheirPickAndSaveBackUnchanged(_ saved: ScheduledTaskSchedule) {
        let d = ScheduleDraft(schedule: saved, now: Self.now)
        #expect(d.schedule == saved, "\(saved.kind) \(saved.expression ?? "") opened as \(d.mode) \(d.preset)")
    }

    @Test func aNewPickReplacesASavedExactGap() {
        var d = ScheduleDraft(schedule: .init(kind: "repeat", timezone: Self.tz, at: "2026-10-13T08:30:00+08:00", everyMinutes: 1440, occurrences: 5), now: Self.now)
        #expect(d.preset == .daily); #expect(!d.isClockAligned)
        d.preset = .weekdays
        #expect(d.schedule.kind == "cron")
        d.preset = .daily
        #expect(d.schedule.kind == "cron"); #expect(d.schedule.expression == "30 8 * * *")
    }

    @Test func olderIntervalWithoutStartShowsTheNextRunAndSavesWithoutOne() {
        let next = Self.friday9.timeIntervalSince1970 * 1000
        var d = ScheduleDraft(schedule: .init(kind: "interval", timezone: Self.tz, everyMinutes: 360), now: Self.now, nextRunAt: next)
        #expect(d.start == Self.friday9); #expect(d.schedule.at == nil)
        d.start = Self.friday9.addingTimeInterval(3600)
        #expect(d.schedule.at == "2026-10-16T10:00:00+08:00")
    }

    @Test func picksForSavedCron() {
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "*/5 * * * *")).preset == .minutes)
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "0 * * * *")).preset == .hourly)
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "0 9 * * *")).preset == .daily)
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "0 9 * * 1-5")).preset == .weekdays)
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "0 9 * * 1,3,5")).preset == .weekly)
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "0 9 1 * *")).preset == .monthly)
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "30 8 1,15 * *")).preset == .custom)
        #expect(ScheduleDraft(schedule: .init(kind: "cron", timezone: Self.tz, expression: "0 9 * * MON")).preset == .custom)
    }

    @Test func problemsBlockSave() {
        var weekly = draft(.weekly); weekly.days = []
        #expect(weekly.problem(now: Self.now) == "Pick at least one day.")
        #expect(draft(.minutes, every: 0).problem(now: Self.now) == "Every must be 1 to 1440 minutes.")
        #expect(draft(.weekdays, ends: .after, count: 0).problem(now: Self.now) == "Number of runs must be 1 to 1,000.")
        var past = ScheduleDraft(now: Self.now, timezone: Self.tz); past.start = Self.now.addingTimeInterval(-60)
        #expect(past.problem(now: Self.now) == "Choose a time in the future.")
        #expect(draft(.weekdays).problem(now: Self.now) == nil)
    }
}
