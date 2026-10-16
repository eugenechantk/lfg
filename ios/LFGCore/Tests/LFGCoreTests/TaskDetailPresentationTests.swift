import Foundation
import Testing
@testable import LFGCore

/// The task view: which status card shows, its words and buttons, and the runs timeline.
@Suite struct TaskDetailPresentationTests {
    static let now = TaskPresentationTests.now
    static let hk = TaskPresentationTests.hk
    static let en = TaskPresentationTests.en
    static func ms(_ iso: String) -> Double { TaskPresentationTests.ms(iso) }

    private func task(_ fields: String, schedule: String = #"{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 9 * * 1-5"}"#) throws -> ScheduledTaskRecord {
        let json = #"{"id":"t","name":"Daily repo review","prompt":"p","cwd":"/tmp","agent":"claude","schedule":\#(schedule),\#(fields)}"#
        return try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
    }
    private func card(_ t: ScheduledTaskRecord) -> TaskStatusCardModel { .make(task: t, now: Self.now, timeZone: Self.hk, locale: Self.en) }
    private func plain(_ s: String?) -> String? { s?.replacingOccurrences(of: "\u{202F}", with: " ") }

    @Test func nextRunCard() throws {
        let t = try task(#""enabled":true,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-16T01:00:00Z"))]"#)
        let c = card(t)
        #expect(c.kind == .next); #expect(c.label == "Next run")
        #expect(plain(c.main) == "Tomorrow, 9:00 AM")
        #expect(c.sub == "Friday, Oct 16 · in 22 h 48 min")
        #expect(c.primary == .runNow); #expect(c.secondary == .pause)
    }

    @Test func pausedCardSaysNoRunsAndOffersResume() throws {
        let t = try task(#""enabled":false,"pausedAt":1,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-16T01:00:00Z"))]"#)
        let c = card(t)
        #expect(c.kind == .paused); #expect(c.main == "No runs scheduled")
        #expect(plain(c.sub) == "Resume to run again on weekdays at 9:00 AM")
        #expect(c.primary == .runNow); #expect(c.secondary == .resume)
    }

    @Test func resumePhraseFollowsTheBoards() {
        #expect(TaskScheduleSummary.resumePhrase("Weekdays at 9:00 AM") == "on weekdays at 9:00 AM")
        #expect(TaskScheduleSummary.resumePhrase("Mondays at 8:00 AM") == "on Mondays at 8:00 AM")
        #expect(TaskScheduleSummary.resumePhrase("Every day at 9:00 AM") == "every day at 9:00 AM")
        #expect(TaskScheduleSummary.resumePhrase("Daily") == "daily")
    }

    /// A live run owns the card: no upcoming rows, no waiting row, and no Retry on older failures.
    @Test func liveRunHidesUpcomingAndTheWaitingRow() throws {
        let failed = #"{"id":"f","status":"failed","startedAt":\#(Self.ms("2026-10-14T01:00:00Z")),"error":"Model unavailable. No session started."}"#
        let waiting = #"{"id":"w","status":"needs_input","sessionId":"s","startedAt":\#(Self.ms("2026-10-15T01:58:00Z"))}"#
        let t = try task(#""enabled":true,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-16T01:00:00Z"))],"currentRun":\#(waiting)"#)
        let runs = try JSONDecoder().decode([ScheduledTaskRun].self, from: Data("[\(waiting),\(failed)]".utf8))
        let entries = RunTimelineEntry.entries(task: t, runs: runs, now: Self.now, timeZone: Self.hk, locale: Self.en)
        #expect(entries.map(\.id) == ["f"])
        #expect(entries[0].tail == "")
        let retrying = #"{"id":"m","status":"running","trigger":"manual","sessionId":"s2","startedAt":\#(Self.ms("2026-10-15T02:14:00Z"))}"#
        var r = t; r.currentRun = try JSONDecoder().decode(ScheduledTaskRun.self, from: Data(retrying.utf8))
        let rRuns = try JSONDecoder().decode([ScheduledTaskRun].self, from: Data("[\(retrying),\(failed)]".utf8))
        let rEntries = RunTimelineEntry.entries(task: r, runs: rRuns, now: Self.now, timeZone: Self.hk, locale: Self.en)
        #expect(rEntries.map(\.id) == ["m", "f"])
        #expect(plain(rEntries[0].head) == "Today · 10:14 AM · retry")
    }

    /// Retry sits on the newest failed run without a session, even after a later success; the reason is not repeated.
    @Test func retryOnTheNewestFailureAndNoDuplicateReason() throws {
        let ok = #"{"id":"ok","status":"succeeded","sessionId":"s","startedAt":\#(Self.ms("2026-10-15T01:00:00Z")),"finishedAt":\#(Self.ms("2026-10-15T01:06:00Z")),"summary":"Fine"}"#
        let f1 = #"{"id":"f1","status":"failed","startedAt":\#(Self.ms("2026-10-13T01:00:00Z")),"error":"Opus 5.5 was unavailable, so no session started."}"#
        let f2 = #"{"id":"f2","status":"failed","startedAt":\#(Self.ms("2026-10-12T01:00:00Z")),"error":"Model unavailable. No session started."}"#
        let t = try task(#""enabled":true,"nextRunAt":\#(Self.ms("2026-10-16T01:00:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-16T01:00:00Z"))]"#)
        let runs = try JSONDecoder().decode([ScheduledTaskRun].self, from: Data("[\(ok),\(f1),\(f2)]".utf8))
        let entries = RunTimelineEntry.entries(task: t, runs: runs, now: Self.now, timeZone: Self.hk, locale: Self.en)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        #expect(byID["f1"]?.tail == "Retry"); #expect(byID["f2"]?.tail == "")
        #expect(byID["f1"]?.body == "Failed · Opus 5.5 was unavailable, so no session started")
        #expect(byID["f2"]?.body == "Failed · Model unavailable · no session started")
    }

    @Test func failedCardOnFirstFailureWithStreakFromTheSecond() throws {
        let t = try task(#""enabled":true,"consecutiveFailures":1,"nextRunAt":\#(Self.ms("2026-10-15T18:00:00Z")),"upcomingRuns":[\#(Self.ms("2026-10-15T18:00:00Z"))],"lastRun":{"id":"r","status":"failed","finishedAt":\#(Self.ms("2026-10-14T18:00:00Z")),"error":"Opus 5.5 was unavailable, so no session started. Details follow."}"#,
                         schedule: #"{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 2 * * *"}"#)
        let c = card(t)
        #expect(c.kind == .failed); #expect(c.label == "Last run failed")
        #expect(plain(c.main) == "Today, 2:00 AM")
        #expect(c.sub == "Opus 5.5 was unavailable, so no session started.")
        #expect(c.streak == nil)
        #expect(plain(c.footnote) == "Schedule still on. Next run: tomorrow, 2:00 AM")
        #expect(c.primary == .retry); #expect(c.secondary == .askToFix)
        var second = t; second.consecutiveFailures = 2
        #expect(card(second).streak == "2nd in a row")
    }

    @Test func runningAndRetryingCards() throws {
        let running = try task(#""enabled":true,"currentRun":{"id":"r","status":"running","trigger":"scheduled","startedAt":\#(Self.ms("2026-10-15T02:00:00Z")),"sessionId":"s"}"#)
        #expect(card(running).kind == .running); #expect(card(running).label == "Running now")
        #expect(plain(card(running).main) == "Started 10:00 AM"); #expect(card(running).sessionID == "s")
        var retry = running; retry.currentRun?.trigger = "manual"; retry.consecutiveFailures = 1
        #expect(card(retry).label == "Retrying now")
    }

    @Test func waitingCardCarriesTheQuestion() throws {
        let t = try task(#""enabled":false,"currentRun":{"id":"r","status":"needs_input","sessionId":"s","needsInputAt":\#(Self.ms("2026-10-15T02:00:00Z")),"prompt":{"question":"Which build should I verify?","context":"Two builds today.","options":[{"index":1,"label":"1.3.1"},{"index":2,"label":"1.3.0"}]}}"#)
        let c = card(t)
        #expect(c.kind == .waiting); #expect(c.label == "Run is waiting for you")
        #expect(c.main == "Which build should I verify?"); #expect(c.sub == "Two builds today."); #expect(c.waited == "12 min")
        #expect(c.sessionID == "s")
    }

    @Test func closedCards() throws {
        let stopped = try task(#""enabled":false,"cancelledAt":\#(Self.ms("2026-10-03T02:00:00Z"))"#)
        #expect(card(stopped).kind == .closed); #expect(card(stopped).main == "Stopped by you"); #expect(card(stopped).primary == nil)
        let finished = try task(#""enabled":false,"lastRun":{"id":"r","status":"succeeded","finishedAt":\#(Self.ms("2026-10-09T01:00:00Z"))}"#,
                                schedule: #"{"kind":"repeat","timezone":"Asia/Hong_Kong","at":"2026-10-05T09:00:00+08:00","everyMinutes":1440,"occurrences":5}"#)
        #expect(card(finished).main == "Ran all 5 times"); #expect(card(finished).primary == .runNow)
    }

    @Test func timelineShowsUpcomingThenPastRuns() throws {
        let t = try task(#""enabled":true,"upcomingRuns":[\#(Self.ms("2026-10-16T01:00:00Z")),\#(Self.ms("2026-10-19T01:00:00Z")),\#(Self.ms("2026-10-20T01:00:00Z"))],"lastRun":{"id":"f","status":"failed"}"#)
        let runs = [
            ScheduledTaskRun(id: "a", trigger: "scheduled", startedAt: Self.ms("2026-10-15T01:00:00Z"), finishedAt: Self.ms("2026-10-15T01:06:00Z"), status: "succeeded", sessionId: "s1", summary: "Reviewed 14 commits\nmore"),
            ScheduledTaskRun(id: "f", trigger: "scheduled", startedAt: Self.ms("2026-10-13T01:00:00Z"), finishedAt: Self.ms("2026-10-13T01:00:00Z"), status: "failed", error: "Model unavailable."),
        ]
        let e = RunTimelineEntry.entries(task: t, runs: runs, now: Self.now, timeZone: Self.hk, locale: Self.en)
        // The latest run failed, so only the next run is listed ahead of the history.
        #expect(e.count == 3)
        #expect(e[0].node == .upcoming); #expect(plain(e[0].head) == "Fri, Oct 16 · 9:00 AM"); #expect(e[0].tail.isEmpty)
        #expect(plain(e[1].head) == "Today · 9:00 AM"); #expect(e[1].tail == "6 min ›"); #expect(e[1].body == "Reviewed 14 commits")
        #expect(e[2].node == .failure); #expect(e[2].tail == "Retry"); #expect(e[2].tailIsAction)
        #expect(e[2].body == "Failed · Model unavailable · no session started")
        var healthy = t; healthy.lastRun = runs[0]
        let h = RunTimelineEntry.entries(task: healthy, runs: [], now: Self.now, timeZone: Self.hk, locale: Self.en)
        // Healthy: every upcoming run the host sent, furthest first, so the next run sits above the history.
        #expect(h.map { plain($0.head) } == ["Tue, Oct 20 · 9:00 AM", "Mon, Oct 19 · 9:00 AM", "Fri, Oct 16 · 9:00 AM"])
        #expect(h.allSatisfy { $0.node == .upcoming && $0.tail.isEmpty })
    }

    /// Upcoming: up to three show; past three, the nearest two and "Show more · 8 later", then all at once.
    @Test func upcomingRunsFoldToTwoAndOpenAllAtOnce() {
        #expect(RunGroupFold.upcoming(count: 3, open: false) == RunGroupFold(shown: 3, hidden: 0, hasToggle: false))
        let closed = RunGroupFold.upcoming(count: 10, open: false)
        #expect(closed == RunGroupFold(shown: 2, hidden: 8, hasToggle: true))
        #expect(closed.label == "Show more"); #expect(closed.count(upcoming: true) == "8 later")
        let open = RunGroupFold.upcoming(count: 10, open: true)
        #expect(open == RunGroupFold(shown: 10, hidden: 0, hasToggle: true))
        #expect(open.label == "Show less"); #expect(open.count(upcoming: true) == "")
    }

    /// Past: two and "Show more · 21 earlier"; each tap adds ten, counting runs the host has not sent yet.
    @Test func pastRunsOpenTenAtATime() {
        #expect(RunGroupFold.past(loaded: 3, total: 3, requested: 2) == RunGroupFold(shown: 3, hidden: 0, hasToggle: false))
        let first = RunGroupFold.past(loaded: 20, total: 23, requested: 2)
        #expect(first == RunGroupFold(shown: 2, hidden: 21, hasToggle: true)); #expect(first.count(upcoming: false) == "21 earlier")
        #expect(RunGroupFold.past(loaded: 20, total: 23, requested: 12).hidden == 11)
        // Asked for more than the client holds: show what is loaded until the next page arrives.
        #expect(RunGroupFold.past(loaded: 20, total: 23, requested: 22) == RunGroupFold(shown: 20, hidden: 3, hasToggle: true))
        let all = RunGroupFold.past(loaded: 23, total: 23, requested: 32)
        #expect(all == RunGroupFold(shown: 23, hidden: 0, hasToggle: true)); #expect(all.label == "Show less")
    }

    @Test func pausedTimelineMarksTheSkippedRun() throws {
        let t = try task(#""enabled":false,"pausedAt":1,"upcomingRuns":[\#(Self.ms("2026-10-16T01:00:00Z")),\#(Self.ms("2026-10-19T01:00:00Z"))]"#)
        let e = RunTimelineEntry.entries(task: t, runs: [], now: Self.now, timeZone: Self.hk, locale: Self.en)
        #expect(plain(e[1].head) == "Fri, Oct 16 · skipped while paused"); #expect(e[1].tail.isEmpty)
        #expect(plain(e[0].head) == "Mon, Oct 19 · 9:00 AM")
    }

    @Test func countLine() throws {
        let t = try task(#""enabled":true,"runCount":23,"succeededCount":22"#)
        #expect(RunTimelineEntry.countLine(t) == "23 runs · 22 completed")
    }
}
