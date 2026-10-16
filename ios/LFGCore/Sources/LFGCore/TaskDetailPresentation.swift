import Foundation

// MARK: - Status card

/// The card at the top of the task view. One per state; the view only draws it.
public struct TaskStatusCardModel: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case next, paused, running, waiting, failed, closed }
    public enum Action: Sendable, Equatable { case runNow, pause, resume, retry, askToFix }

    public var kind: Kind
    /// Uppercase label at the top ("NEXT RUN", "LAST RUN FAILED").
    public var label: String
    public var main: String
    public var sub: String?
    /// "2nd in a row", only from the second failure in a row.
    public var streak: String?
    /// The line under the buttons ("Schedule still on. Next run: …").
    public var footnote: String?
    /// How long a run has waited for an answer ("12 min").
    public var waited: String?
    public var primary: Action?
    public var secondary: Action?
    /// A session the card links to ("Open session").
    public var sessionID: String?

    public static func make(task: ScheduledTaskRecord, now: Date = Date(), timeZone: TimeZone = .current, locale: Locale = .current) -> TaskStatusCardModel {
        let f = TaskTimeFormat(now: now, timeZone: timeZone, locale: locale)
        let sentence = TaskScheduleSummary.short(task.schedule, timeZone: timeZone, locale: locale)
        if let run = task.currentRun, run.status == "needs_input" {
            return .init(kind: .waiting, label: "Run is waiting for you", main: run.prompt?.question.nonEmpty ?? "The run is waiting for an answer",
                         sub: run.prompt?.context?.nonEmpty, waited: f.elapsed(from: run.needsInputAt ?? run.startedAt ?? now.ms),
                         sessionID: run.sessionId)
        }
        if let run = task.currentRun {
            let retrying = run.trigger == "manual" && task.consecutiveFailures > 0
            return .init(kind: .running, label: retrying ? "Retrying now" : "Running now",
                         main: "Started \(f.time(run.startedAt ?? now.ms))", sessionID: run.sessionId)
        }
        if task.cancelledAt != nil {
            return .init(kind: .closed, label: "Stopped", main: "Stopped by you",
                         sub: task.cancelledAt.map { f.dayAndTime($0) })
        }
        if task.isPaused {
            let resume = TaskScheduleSummary.resumePhrase(sentence)
            return .init(kind: .paused, label: "Paused", main: "No runs scheduled",
                         sub: task.schedule.kind == "once" && task.nextScheduledRun == nil
                            ? "Its run time has passed. Edit it to pick a new time."
                            : "Resume to run again \(task.schedule.kind == "once" ? "once" : resume)",
                         primary: .runNow, secondary: .resume)
        }
        if task.latestRunFailed, let run = task.lastRun {
            let footnote: String?
            if task.isScheduleActive, let next = task.nextScheduledRun { footnote = "Schedule still on. Next run: \(f.dayAndTime(next, lowercaseDay: true))" }
            else if task.schedule.kind == "once" { footnote = "One-time task. Retry runs it again." }
            else { footnote = nil }
            let verb = run.status == "interrupted" ? "Last run was interrupted" : "Last run failed"
            return .init(kind: .failed, label: verb,
                         main: f.dayAndTime(run.finishedAt ?? run.startedAt ?? run.scheduledFor ?? now.ms),
                         sub: RunErrorText.sentence(run.error, sessionStarted: run.sessionId != nil),
                         streak: task.consecutiveFailures >= 2 ? "\(TaskTimeFormat.ordinal(task.consecutiveFailures)) in a row" : nil,
                         footnote: footnote, primary: .retry, secondary: .askToFix, sessionID: run.sessionId)
        }
        if task.isScheduleActive, let next = task.nextScheduledRun {
            return .init(kind: .next, label: "Next run", main: f.dayAndTime(next),
                         sub: "\(f.fullDate(next)) · \(f.countdown(to: next))", primary: .runNow, secondary: .pause)
        }
        // Finished: a one-time task that ran, or a finite schedule that used all its runs.
        let ended = task.lastRun?.finishedAt ?? task.lastRunAt
        if task.schedule.kind == "once" {
            return .init(kind: .closed, label: "Done", main: "Ran once", sub: ended.map { f.dayAndTime($0) }, primary: .runNow)
        }
        let total = task.schedule.occurrences ?? task.schedule.maxRuns ?? task.scheduledRunCount ?? task.runCount
        return .init(kind: .closed, label: "Finished", main: "Ran all \(total) times", sub: ended.map { "Last run \(f.dayAndTime($0, lowercaseDay: true))" }, primary: .runNow)
    }
}

// MARK: - Runs timeline

public struct RunTimelineEntry: Sendable, Equatable, Identifiable {
    public enum Node: Sendable, Equatable { case upcoming, running, success, failure, warning }
    public var id: String
    public var node: Node
    public var head: String
    public var tail: String
    public var tailTone: TaskTone
    public var tailIsAction: Bool
    public var body: String?
    public var bodyTone: TaskTone
    public var sessionID: String?
    public var runID: String?

    /// Upcoming runs, then past runs, newest first throughout: the furthest run is on top and the
    /// next one sits just above the history. The grey node marks a run as upcoming, so it has no label.
    /// While a run is live the card owns the moment: no upcoming rows, and a waiting run stays in the card.
    public static func entries(task: ScheduledTaskRecord, runs: [ScheduledTaskRun], now: Date = Date(),
                               timeZone: TimeZone = .current, locale: Locale = .current) -> [RunTimelineEntry] {
        let f = TaskTimeFormat(now: now, timeZone: timeZone, locale: locale)
        var out: [RunTimelineEntry] = []
        let paused = task.isPaused
        if task.cancelledAt == nil {
            // After a failure the failed run matters more than the far future: show only the next run.
            let upcoming = task.currentRun != nil ? 0 : task.latestRunFailed ? 1 : task.upcomingRuns.count
            for (i, at) in task.upcomingRuns.prefix(upcoming).enumerated().reversed() {
                let skipped = paused && i == 0
                out.append(.init(id: "next-\(Int(at))", node: .upcoming,
                                 head: skipped ? "\(f.dayOnly(at)) · skipped while paused" : f.dayDotTime(at),
                                 tail: "", tailTone: .secondary, tailIsAction: false,
                                 body: nil, bodyTone: .secondary, sessionID: nil, runID: nil))
            }
        }
        // Retry is offered once, on the newest failed run that never got a session.
        var offeredRetry = task.cancelledAt != nil || task.currentRun != nil
        for run in runs {
            if run.status == "needs_input", run.id == task.currentRun?.id { continue }
            let at = run.startedAt ?? run.scheduledFor ?? 0
            let retry = run.trigger == "manual" ? " · retry" : ""
            var entry = RunTimelineEntry(id: run.id, node: .success, head: f.dayDotTime(at) + (run.trigger == "manual" && ["starting", "running"].contains(run.status ?? "") ? retry : ""),
                                         tail: "", tailTone: .secondary, tailIsAction: false, body: nil, bodyTone: .secondary,
                                         sessionID: run.sessionId, runID: run.id)
            switch run.status {
            case "starting", "running":
                entry.node = .running; entry.tail = "Running"; entry.tailTone = .success
            case "needs_input":
                entry.node = .warning; entry.tail = "Waiting"; entry.tailTone = .warning
                entry.body = run.prompt?.question.nonEmpty.map { "Asks: \($0)" }; entry.bodyTone = .warning
            case "succeeded":
                entry.node = .success
                entry.body = RunErrorText.firstLine(run.summary) ?? "Completed"
                entry.bodyTone = .soft
            case "interrupted":
                entry.node = .warning; entry.bodyTone = .warning
                entry.body = RunErrorText.firstLine(run.error) ?? "Interrupted"
            default: // failed
                entry.node = .failure; entry.bodyTone = .danger
                let reason = RunErrorText.short(run.error)
                let saysNoSession = reason.range(of: "no session", options: .caseInsensitive) != nil
                entry.body = "Failed · \(reason)" + (run.sessionId == nil && !saysNoSession ? " · no session started" : "")
            }
            if entry.tail.isEmpty {
                if run.sessionId != nil, let start = run.startedAt, let end = run.finishedAt {
                    entry.tail = "\(f.duration(from: start, to: end)) ›"
                } else if run.status == "failed", run.sessionId == nil, !offeredRetry {
                    offeredRetry = true
                    entry.tail = "Retry"; entry.tailTone = .accent; entry.tailIsAction = true
                } else if run.sessionId != nil {
                    entry.tail = "›"
                }
            }
            out.append(entry)
        }
        return out
    }

    /// "23 runs · 22 completed".
    public static func countLine(_ task: ScheduledTaskRecord) -> String {
        let runs = task.runCount == 1 ? "1 run" : "\(task.runCount) runs"
        guard let done = task.succeededCount else { return runs }
        return "\(runs) · \(done) completed"
    }
}

/// How one group of runs folds. Each group shows at most three rows; with more, it shows the two
/// nearest runs and a Show more row (above the upcoming runs, below the past ones).
public struct RunGroupFold: Sendable, Equatable {
    /// Runs to show.
    public var shown: Int
    /// Runs left out; the toggle row counts them.
    public var hidden: Int
    /// Whether the group has a Show more / Show less row.
    public var hasToggle: Bool
    public init(shown: Int, hidden: Int, hasToggle: Bool) { self.shown = shown; self.hidden = hidden; self.hasToggle = hasToggle }

    public static let maxRows = 3
    /// Past runs open ten at a time.
    public static let pastStep = 10

    /// The toggle reads Show more while runs are hidden, then Show less.
    public var opens: Bool { hidden > 0 }
    public var label: String { opens ? "Show more" : "Show less" }

    /// Upcoming runs open all at once (the host lists up to ten).
    public static func upcoming(count: Int, open: Bool) -> RunGroupFold {
        guard count > maxRows else { return .init(shown: count, hidden: 0, hasToggle: false) }
        return open ? .init(shown: count, hidden: 0, hasToggle: true)
                    : .init(shown: maxRows - 1, hidden: count - (maxRows - 1), hasToggle: true)
    }

    /// Past runs: `loaded` are on the client, `total` exist on the host (loaded ones included),
    /// `requested` is how many the viewer has opened.
    public static func past(loaded: Int, total: Int, requested: Int) -> RunGroupFold {
        let total = max(total, loaded)
        guard total > maxRows else { return .init(shown: loaded, hidden: 0, hasToggle: false) }
        let shown = min(loaded, max(maxRows - 1, requested))
        return .init(shown: shown, hidden: total - shown, hasToggle: true)
    }

    /// "8 later" above the upcoming runs, "21 earlier" below the past ones; nothing once open.
    public func count(upcoming: Bool) -> String {
        opens ? "\(hidden) \(upcoming ? "later" : "earlier")" : ""
    }
}

// MARK: - Text helpers

public extension RunErrorText {
    /// One sentence for the failure card: the first sentence of the error, ending in a period,
    /// and saying when no session started.
    static func sentence(_ error: String?, sessionStarted: Bool) -> String {
        guard let line = firstLine(error) else { return sessionStarted ? "The run stopped without a message." : "No session started." }
        var sentence = line.range(of: ". ").map { String(line[..<$0.lowerBound]) } ?? line
        if !sentence.hasSuffix(".") { sentence += "." }
        return sentence
    }
}

extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public extension TaskTimeFormat {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; c.locale = locale; return c }
    private func fmt(_ template: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = locale; f.timeZone = timeZone; f.setLocalizedDateFormatFromTemplate(template); return f
    }
    private func dayOffset(_ ms: Double) -> Int {
        let d = Date(timeIntervalSince1970: ms / 1000)
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
    }

    /// "Today, 9:00 AM", "Tomorrow, 9:00 AM", "Yesterday, 2:00 AM", "Monday, 9:00 AM", "Oct 27, 9:00 AM".
    func dayAndTime(_ ms: Double, lowercaseDay: Bool = false, joiner: String = ", ") -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let days = dayOffset(ms)
        var day: String
        switch days {
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        case -1: day = "Yesterday"
        case 2...6: day = fmt("EEEE").string(from: d)
        default: day = fmt("MMMd").string(from: d)
        }
        if lowercaseDay, (-1...1).contains(days) { day = day.lowercased() }
        return "\(day)\(joiner)\(time(ms))"
    }

    /// "Today · 9:00 AM", "Wed, Oct 14 · 9:00 AM" for the timeline.
    /// "Today" or "Fri, Oct 16".
    func dayOnly(_ ms: Double) -> String {
        dayOffset(ms) == 0 ? "Today" : fmt("EEEMMMd").string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    func dayDotTime(_ ms: Double) -> String {
        let days = dayOffset(ms)
        let day = days == 0 ? "Today" : fmt("EEEMMMd").string(from: Date(timeIntervalSince1970: ms / 1000))
        return "\(day) · \(time(ms))"
    }

    /// "Friday, Oct 16".
    func fullDate(_ ms: Double) -> String { fmt("EEEEMMMd").string(from: Date(timeIntervalSince1970: ms / 1000)) }

    /// "in 22 h 48 min", "in 12 min", "in 3 days".
    func countdown(to ms: Double) -> String {
        let minutes = Int(((ms - now.timeIntervalSince1970 * 1000) / 60_000).rounded(.up))
        if minutes <= 0 { return "due now" }
        if minutes < 60 { return "in \(minutes) min" }
        if minutes < 48 * 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
        }
        return "in \(minutes / 1440) days"
    }

    /// "6 min", "1 h 5 min", "40 s".
    func duration(from start: Double, to end: Double) -> String {
        let seconds = max(0, Int((end - start) / 1000))
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
