import Foundation
import Testing
@testable import LFGCore

/// The Tasks list: which section a task lands in, its order, and the words on its row.
@Suite struct TaskPresentationTests {
    // Thu 2026-10-15 10:12 in Hong Kong.
    static let now = Date(timeIntervalSince1970: 1_792_030_320)
    static let hk = TimeZone(identifier: "Asia/Hong_Kong")!
    static let en = Locale(identifier: "en_US")
    static func ms(_ iso: String) -> Double { ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000 }

    private func task(_ fields: String, schedule: String = #"{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 9 * * 1-5"}"#,
                      name: String = "Task") throws -> ScheduledTaskRecord {
        let json = #"{"id":"t-\#(name)","name":"\#(name)","prompt":"p","cwd":"/tmp","agent":"claude","schedule":\#(schedule)\#(fields.isEmpty ? "" : ",")\#(fields)}"#
        return try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
    }
    private func row(_ t: ScheduledTaskRecord, host: String = "Pro") -> TaskRowModel {
        TaskRowModel.make(task: t, hostName: host, now: Self.now, timeZone: Self.hk, locale: Self.en)
    }
    private func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }

    // MARK: sections

    @Test func waitingRunIsNeedsInputEvenWhenPaused() throws {
        let t = try task(#""enabled":false,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"currentRun":{"id":"r","status":"needs_input","startedAt":\#(Self.ms("2026-10-15T02:00:00Z"))}"#)
        #expect(t.listSection == .needsInput)
    }

    @Test func failedLatestRunIsNeedsInputButPausedWins() throws {
        let failed = try task(#""enabled":true,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"lastRun":{"id":"r","status":"failed","error":"Model unavailable."}"#)
        #expect(failed.listSection == .needsInput)
        let pausedFailed = try task(#""enabled":false,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"lastRun":{"id":"r","status":"failed"}"#)
        #expect(pausedFailed.listSection == .paused)
        // A one-time task whose only run failed stays in Needs input so Retry is one tap away.
        let onceFailed = try task(#""enabled":false,"lastRunAt":1,"lastRun":{"id":"r","status":"interrupted"}"#,
                                  schedule: #"{"kind":"once","timezone":"UTC","at":"2026-10-15T00:00:00Z"}"#)
        #expect(onceFailed.listSection == .needsInput)
    }

    @Test func runningScheduledPausedAndFinished() throws {
        #expect(try task(#""enabled":true,"currentRun":{"id":"r","status":"running"}"#).listSection == .active)
        #expect(try task(#""enabled":true,"nextRunAt":5"#).listSection == .active)
        #expect(try task(#""enabled":false,"nextRunAt":5,"pausedAt":1"#).listSection == .paused)
        #expect(try task(#""enabled":false,"nextRunAt":5,"cancelledAt":3"#).listSection == .closed)
        let doneOnce = try task(#""enabled":false,"lastRunAt":2,"lastRun":{"id":"r","status":"succeeded"}"#,
                                schedule: #"{"kind":"once","timezone":"UTC","at":"2026-10-12T00:00:00Z"}"#)
        #expect(doneOnce.listSection == .closed)
        let doneCron = try task(#""enabled":false,"scheduledRunCount":10,"lastRun":{"id":"r","status":"succeeded"}"#,
                                schedule: #"{"kind":"cron","timezone":"UTC","expression":"0 9 * * *","maxRuns":10}"#)
        #expect(doneCron.listSection == .closed)
    }

    @Test func sectionsAreOrderedAndSortedPerSection() throws {
        let items = [
            try task(#""enabled":true,"nextRunAt":300,"upcomingRuns":[300]"#, name: "Later"),
            try task(#""enabled":true,"nextRunAt":200,"upcomingRuns":[200]"#, name: "Sooner"),
            try task(#""enabled":true,"currentRun":{"id":"r","status":"running","startedAt":1}"#, name: "Running"),
            try task(#""enabled":true,"lastRun":{"id":"a","status":"failed","finishedAt":10}"#, name: "OldFail"),
            try task(#""enabled":true,"currentRun":{"id":"b","status":"needs_input","needsInputAt":20}"#, name: "Question"),
            try task(#""enabled":false,"pausedAt":1,"upcomingRuns":[]"#, name: "PausedBlank"),
            try task(#""enabled":false,"pausedAt":1,"upcomingRuns":[100]"#, name: "PausedSoon"),
            try task(#""enabled":false,"cancelledAt":50"#, name: "StoppedLate"),
            try task(#""enabled":false,"cancelledAt":40"#, name: "StoppedEarly"),
        ]
        let sections = TaskListGrouping.sections(items) { $0 }
        #expect(sections.map(\.section) == [.needsInput, .active, .paused, .closed])
        #expect(sections[0].items.map(\.name) == ["Question", "OldFail"])
        #expect(sections[1].items.map(\.name) == ["Running", "Sooner", "Later"])
        #expect(sections[2].items.map(\.name) == ["PausedSoon", "PausedBlank"])
        #expect(sections[3].items.map(\.name) == ["StoppedLate", "StoppedEarly"])
        #expect(TaskListGrouping.needsInputCount(items) == 2)
    }

    @Test func emptySectionsAreLeftOut() throws {
        let sections = TaskListGrouping.sections([try task(#""enabled":true,"nextRunAt":5"#)]) { $0 }
        #expect(sections.map(\.section) == [.active])
    }

    // MARK: rows

    @Test func questionRow() throws {
        let t = try task(#""enabled":false,"currentRun":{"id":"r","status":"needs_input","startedAt":\#(Self.ms("2026-10-15T01:58:00Z")),"needsInputAt":\#(Self.ms("2026-10-15T02:00:00Z")),"prompt":{"question":"Verify build 1.3.0 or 1.3.1?","options":[]}}"#,
                         schedule: #"{"kind":"once","timezone":"Asia/Hong_Kong","at":"2026-10-15T09:58:00+08:00"}"#, name: "Release verification")
        let r = row(t, host: "Air")
        #expect(r.time == "10:00"); #expect(r.timeDetail == "AM"); #expect(r.timeTone == .warning)
        #expect(r.when == "Once · Air")
        #expect(r.glyph == .question); #expect(r.result == "Asks: Verify build 1.3.0 or 1.3.1?"); #expect(r.resultTone == .warning)
    }

    @Test func failedRowCountsTheStreakFromTheSecondFailure() throws {
        let first = try task(#""enabled":true,"nextRunAt":\#(Self.ms("2026-10-15T18:00:00Z")),"consecutiveFailures":1,"lastRun":{"id":"r","status":"failed","finishedAt":\#(Self.ms("2026-10-14T18:00:00Z")),"error":"Model unavailable. Try another model."}"#,
                             schedule: #"{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 2 * * *"}"#)
        let r = row(first)
        #expect(r.time == "2:00"); #expect(r.timeDetail == "AM"); #expect(r.timeTone == .danger)
        #expect(plain(r.when) == "Every day at 2:00 AM · Pro")
        #expect(r.glyph == .failure); #expect(r.result == "Failed · Model unavailable")
        var second = first; second.consecutiveFailures = 2
        #expect(row(second).result == "Failed 2nd time · Model unavailable")
    }

    @Test func runningRow() throws {
        var t = try task(#""enabled":true,"currentRun":{"id":"r","status":"running","startedAt":\#(Self.ms("2026-10-15T02:00:00Z"))}"#,
                         schedule: #"{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 * * * *"}"#)
        t.agent = "codex"
        let r = row(t)
        #expect(r.time == "Now"); #expect(r.timeDetail == "12 min"); #expect(r.timeTone == .success)
        #expect(r.when == "Every hour · Pro · Codex")
        #expect(r.glyph == .running); #expect(plain(r.result) == "Running · started 10:00 AM")
    }

    @Test func scheduledRowShowsNextRunAndLastResult() throws {
        let t = try task(#""enabled":true,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-16T01:00:00Z"))],"lastRun":{"id":"r","status":"succeeded","finishedAt":\#(Self.ms("2026-10-15T01:06:00Z")),"summary":"**Reviewed 14 commits**, 1 regression\nMore"}"#)
        let r = row(t)
        #expect(r.time == "9:00"); #expect(r.timeDetail == "AM Fri"); #expect(r.timeTone == .primary)
        #expect(plain(r.when) == "Weekdays at 9:00 AM · Pro")
        #expect(r.glyph == .success); #expect(r.result == "Today · Reviewed 14 commits, 1 regression")
    }

    @Test func finiteRepeatShowsRunProgress() throws {
        let t = try task(#""enabled":true,"nextRunAt":\#(Self.ms("2026-10-16T00:30:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-16T00:30:00Z"))]"#,
                         schedule: #"{"kind":"repeat","timezone":"Asia/Hong_Kong","at":"2026-10-13T08:30:00+08:00","everyMinutes":1440,"occurrences":5}"#)
        #expect(row(t).when == "Daily · run 4 of 5 · Pro")
    }

    /// The boards' wording: plural day names, "Weekdays", and a finished finite schedule's run total.
    @Test func listWordingFollowsTheBoards() throws {
        let s = { (expr: String) in TaskScheduleSummary.short(.init(kind: "cron", timezone: "Asia/Hong_Kong", expression: expr), timeZone: Self.hk, locale: Self.en) }
        #expect(plain(s("0 17 * * 5")) == "Fridays at 5:00 PM")
        #expect(plain(s("0 8 * * 1,3")) == "Mondays and Wednesdays at 8:00 AM")
        #expect(plain(s("0 9 * * 1-5")) == "Weekdays at 9:00 AM")
        #expect(plain(s("0 2 * * *")) == "Every day at 2:00 AM")
        let finished = try task(#""enabled":false,"scheduledRunCount":5"#,
                                schedule: #"{"kind":"repeat","timezone":"Asia/Hong_Kong","at":"2026-10-05T09:00:00+08:00","everyMinutes":1440,"occurrences":5}"#)
        #expect(row(finished).when == "Daily · 5 runs · Pro")
    }

    /// The task view keeps the sentence form; only list rows use the short one.
    @Test func taskViewLineUsesTheSentenceForm() {
        let weekdays = ScheduledTaskSchedule(kind: "cron", timezone: "Asia/Hong_Kong", expression: "0 9 * * 1-5")
        #expect(plain(TaskScheduleSummary.detailLine(weekdays, now: Self.now, timeZone: Self.hk, locale: Self.en)) == "Every weekday at 9:00 AM")
        let daily = ScheduledTaskSchedule(kind: "repeat", timezone: "Asia/Hong_Kong", at: "2026-10-05T09:00:00+08:00", everyMinutes: 1440, occurrences: 5)
        #expect(TaskScheduleSummary.detailLine(daily, now: Self.now, timeZone: Self.hk, locale: Self.en) == "Every day, 5 times")
    }

    @Test func pausedRowsShowNextScheduledRunOrNothing() throws {
        let weekly = try task(#""enabled":false,"pausedAt":\#(Self.ms("2026-10-12T03:00:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-19T00:00:00Z"))]"#,
                              schedule: #"{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 8 * * 1"}"#)
        let r = row(weekly, host: "Air")
        #expect(r.time == "8:00"); #expect(r.timeDetail == "AM Mon"); #expect(r.timeTone == .secondary)
        #expect(r.glyph == .paused); #expect(r.result == "Paused by you · Oct 12")
        let passed = try task(#""enabled":false,"pausedAt":\#(Self.ms("2026-10-08T03:00:00Z")),"upcomingRuns":[]"#,
                              schedule: #"{"kind":"once","timezone":"Asia/Hong_Kong","at":"2026-10-09T09:00:00+08:00"}"#)
        let p = row(passed)
        #expect(p.time.isEmpty); #expect(p.timeDetail.isEmpty)
        #expect(p.result == "Paused by you · Oct 8 · its run time has passed")
    }

    @Test func closedRows() throws {
        let once = try task(#""enabled":false,"lastRunAt":\#(Self.ms("2026-10-12T02:00:00Z")),"lastRun":{"id":"r","status":"succeeded","finishedAt":\#(Self.ms("2026-10-12T02:04:00Z")),"summary":"Schema matches; no migration needed"}"#,
                            schedule: #"{"kind":"once","timezone":"Asia/Hong_Kong","at":"2026-10-12T10:00:00+08:00"}"#)
        let o = row(once)
        #expect(o.time == "Oct 12"); #expect(o.timeDetail == "Done"); #expect(o.glyph == .success)
        #expect(o.result == "Schema matches; no migration needed")
        let repeatDone = try task(#""enabled":false,"lastRun":{"id":"r","status":"succeeded","finishedAt":\#(Self.ms("2026-10-09T01:00:00Z"))}"#,
                                  schedule: #"{"kind":"repeat","timezone":"Asia/Hong_Kong","at":"2026-10-05T09:00:00+08:00","everyMinutes":1440,"occurrences":5}"#)
        let rd = row(repeatDone)
        #expect(rd.time == "Oct 9"); #expect(rd.timeDetail == "5 of 5"); #expect(rd.result == "Finished all 5 runs")
        let stopped = try task(#""enabled":false,"cancelledAt":\#(Self.ms("2026-10-03T02:00:00Z"))"#)
        let s = row(stopped)
        #expect(s.time == "Oct 3"); #expect(s.timeDetail == "Stopped"); #expect(s.glyph == .none); #expect(s.result == "Stopped by you")
    }

    @Test func clockUsesWeekdaysAheadAndDatesBehind() {
        let f = TaskTimeFormat(now: Self.now, timeZone: Self.hk, locale: Self.en)
        #expect(f.clock(Self.ms("2026-10-15T01:00:00Z")).1 == "AM")            // today
        #expect(f.clock(Self.ms("2026-10-16T01:00:00Z")).1 == "AM Fri")        // tomorrow
        #expect(f.clock(Self.ms("2026-10-09T06:24:00Z")).1 == "PM Oct 9")      // last Friday
        #expect(f.clock(Self.ms("2026-10-27T01:00:00Z")).1 == "AM Oct 27")     // beyond a week
    }

    @Test func olderDecodesStillWork() throws {
        // A host without the new fields: upcoming runs fall back to nextRunAt.
        let t = try task(#""enabled":true,"nextRunAt":42"#)
        #expect(t.upcomingRuns == [42]); #expect(t.consecutiveFailures == 0); #expect(t.pausedAt == nil)
    }

    @Test func errorTextIsOneShortClause() {
        #expect(RunErrorText.short("Opus 5.5 was unavailable, so no session started.\nTrace…") == "Opus 5.5 was unavailable, so no session started")
        #expect(RunErrorText.short(nil) == "no details")
        #expect(RunErrorText.short("The session is no longer running. Open its conversation.") == "The session is no longer running")
    }
}
