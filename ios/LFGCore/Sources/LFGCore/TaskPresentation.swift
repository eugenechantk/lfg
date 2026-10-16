import Foundation

// MARK: - List sections

/// The four groups of the Tasks list. Each task appears in exactly one.
public enum TaskListSection: String, CaseIterable, Sendable, Identifiable {
    case needsInput, active, paused, closed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .needsInput: "Needs input"
        case .active: "Active"
        case .paused: "Paused"
        case .closed: "Closed"
        }
    }
    /// Shown at the right of the section header while it is expanded.
    public var hint: String? { self == .active ? "by next run" : nil }
}

public extension ScheduledTaskRecord {
    var isRunInProgress: Bool { ["starting", "running", "needs_input"].contains(currentRun?.status ?? "") }
    var isWaitingForInput: Bool { currentRun?.status == "needs_input" }
    /// The newest run failed or was interrupted and nothing is running now.
    var latestRunFailed: Bool { currentRun == nil && ["failed", "interrupted"].contains(lastRun?.status ?? "") }
    /// Switched off by the user, and able to resume.
    var isPaused: Bool { cancelledAt == nil && !enabled && canResume }

    /// Precedence: stopped → waiting for an answer → running → paused by the user →
    /// a failed latest run → scheduled → finished.
    var listSection: TaskListSection {
        if cancelledAt != nil { return .closed }
        if isWaitingForInput { return .needsInput }
        if isRunInProgress { return .active }
        if isPaused { return .paused }
        if latestRunFailed { return .needsInput }
        if isScheduleActive { return .active }
        return .closed
    }

    /// The next time this task will (or, when paused, would) run.
    var nextScheduledRun: Double? { upcomingRuns.first ?? (enabled ? nextRunAt : nil) }

    /// When the task last asked for attention, for ordering the Needs input group.
    fileprivate var attentionAt: Double {
        currentRun?.needsInputAt ?? currentRun?.startedAt ?? lastRun?.finishedAt ?? lastRun?.startedAt ?? 0
    }
    /// When a closed task ended.
    var endedAt: Double? { cancelledAt ?? lastRun?.finishedAt ?? lastRunAt ?? updatedAt }
}

public enum TaskListGrouping {
    /// Non-empty sections in display order, each sorted for that section.
    public static func sections<Item>(_ items: [Item], task: (Item) -> ScheduledTaskRecord) -> [(section: TaskListSection, items: [Item])] {
        var buckets: [TaskListSection: [Item]] = [:]
        for item in items { buckets[task(item).listSection, default: []].append(item) }
        return TaskListSection.allCases.compactMap { section in
            guard var bucket = buckets[section], !bucket.isEmpty else { return nil }
            bucket.sort { lhs, rhs in
                let a = task(lhs), b = task(rhs)
                switch section {
                case .needsInput:
                    if a.attentionAt != b.attentionAt { return a.attentionAt > b.attentionAt }
                case .active:
                    if a.isRunInProgress != b.isRunInProgress { return a.isRunInProgress }
                    let x = a.nextScheduledRun ?? .greatestFiniteMagnitude, y = b.nextScheduledRun ?? .greatestFiniteMagnitude
                    if x != y { return x < y }
                case .paused:
                    let x = a.nextScheduledRun ?? .greatestFiniteMagnitude, y = b.nextScheduledRun ?? .greatestFiniteMagnitude
                    if x != y { return x < y }
                case .closed:
                    let x = a.endedAt ?? 0, y = b.endedAt ?? 0
                    if x != y { return x > y }
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return (section, bucket)
        }
    }

    /// The Tasks tab badge.
    public static func needsInputCount(_ tasks: [ScheduledTaskRecord]) -> Int {
        tasks.filter { $0.listSection == .needsInput }.count
    }
}

// MARK: - Row model

/// `accent` is link blue; `soft` is body text a step quieter than primary.
public enum TaskTone: Sendable, Equatable { case primary, secondary, warning, danger, success, accent, soft }
public enum TaskResultGlyph: Sendable, Equatable { case none, success, failure, question, running, paused }

/// Everything a Tasks list row shows. Pure, so the phone and the Mac render the same words.
public struct TaskRowModel: Sendable, Equatable {
    public var time: String
    public var timeDetail: String
    public var timeTone: TaskTone
    public var title: String
    public var when: String
    public var glyph: TaskResultGlyph
    public var result: String
    public var resultTone: TaskTone

    public static func make(task: ScheduledTaskRecord, hostName: String, now: Date = Date(),
                            timeZone: TimeZone = .current, locale: Locale = .current) -> TaskRowModel {
        let f = TaskTimeFormat(now: now, timeZone: timeZone, locale: locale)
        var row = TaskRowModel(time: "", timeDetail: "", timeTone: .primary, title: task.name,
                               when: TaskScheduleSummary.whenLine(task, hostName: hostName, timeZone: timeZone, locale: locale),
                               glyph: .none, result: "", resultTone: .secondary)
        switch task.listSection {
        case .needsInput:
            if task.isWaitingForInput, let run = task.currentRun {
                (row.time, row.timeDetail) = f.clock(run.needsInputAt ?? run.startedAt ?? now.ms)
                row.timeTone = .warning
                row.glyph = .question; row.resultTone = .warning
                let question = run.prompt?.question.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                row.result = question.isEmpty ? "Waiting for your answer" : "Asks: \(question)"
            } else if let run = task.lastRun {
                (row.time, row.timeDetail) = f.clock(run.finishedAt ?? run.startedAt ?? run.scheduledFor ?? now.ms)
                row.timeTone = .danger
                row.glyph = .failure; row.resultTone = .danger
                let verb = run.status == "interrupted" ? "Interrupted" : "Failed"
                let streak = task.consecutiveFailures >= 2 ? " \(TaskTimeFormat.ordinal(task.consecutiveFailures)) time" : ""
                row.result = "\(verb)\(streak) · \(RunErrorText.short(run.error))"
            }
        case .active:
            if let run = task.currentRun {
                let started = run.startedAt ?? now.ms
                row.time = "Now"; row.timeDetail = f.elapsed(from: started, compact: true); row.timeTone = .success
                row.glyph = .running; row.resultTone = .success
                row.result = "Running · started \(f.time(started))"
            } else {
                if let next = task.nextScheduledRun { (row.time, row.timeDetail) = f.clock(next) }
                applyLastResult(task, format: f, to: &row)
            }
        case .paused:
            if let next = task.nextScheduledRun { (row.time, row.timeDetail) = f.clock(next) }
            row.timeTone = .secondary
            row.glyph = .paused
            var text = task.pausedAt.map { "Paused by you · \(f.shortDate($0))" } ?? "Paused"
            if task.schedule.kind == "once", task.nextScheduledRun == nil { text += " · its run time has passed" }
            row.result = text
        case .closed:
            row.timeTone = .secondary
            if let ended = task.endedAt { row.time = f.shortDate(ended) }
            if task.cancelledAt != nil {
                row.timeDetail = "Stopped"; row.result = "Stopped by you"
            } else if task.schedule.isFinite, task.schedule.kind != "once" {
                let total = task.schedule.occurrences ?? task.schedule.maxRuns ?? task.scheduledRunCount ?? task.runCount
                let done = task.schedule.kind == "repeat" ? total : (task.scheduledRunCount ?? total)
                row.timeDetail = "\(done) of \(total)"
                row.glyph = .success; row.result = "Finished all \(total) runs"
            } else {
                row.timeDetail = "Done"
                applyLastResult(task, format: f, to: &row, relativeDay: false)
            }
        }
        return row
    }

    private static func applyLastResult(_ task: ScheduledTaskRecord, format f: TaskTimeFormat, to row: inout TaskRowModel, relativeDay: Bool = true) {
        guard let run = task.lastRun else { row.result = "No runs yet"; return }
        let summary = RunErrorText.firstLine(run.summary)
        switch run.status {
        case "succeeded":
            row.glyph = .success
            let day = (run.finishedAt ?? run.startedAt).map { f.relativeDay($0) }
            row.result = [relativeDay ? day : nil, summary ?? "Completed"].compactMap { $0 }.joined(separator: " · ")
        case "failed", "interrupted":
            row.glyph = .failure; row.resultTone = .danger
            row.result = "\(run.status == "failed" ? "Failed" : "Interrupted") · \(RunErrorText.short(run.error))"
        default:
            row.result = run.statusLabel
        }
    }
}

// MARK: - Text helpers

/// Short, plain wording for the schedule part of a row.
public enum TaskScheduleSummary {
    public static func short(_ schedule: ScheduledTaskSchedule, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        switch schedule.kind {
        case "once": return "Once"
        case "interval", "repeat":
            guard let minutes = schedule.everyMinutes, minutes > 0 else { return "Repeats" }
            return everyPhrase(minutes)
        default:
            return listPhrase(schedule.description(locale: locale, displayTimeZone: timeZone), locale: locale)
        }
    }

    /// The boards' wording for day-of-week schedules: "Every weekday at 9:00 AM" → "Weekdays at 9:00 AM",
    /// "Every Monday and Friday at 8:00 AM" → "Mondays and Fridays at 8:00 AM". English only; other text is unchanged.
    static func listPhrase(_ text: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "en", text.hasPrefix("Every ") else { return text }
        let rest = text.dropFirst("Every ".count)
        if rest.hasPrefix("weekday at ") { return "Weekdays" + rest.dropFirst("weekday".count) }
        if rest.hasPrefix("weekend at ") { return "Weekends" + rest.dropFirst("weekend".count) }
        guard let at = rest.range(of: " at ") else { return text }
        let days = String(rest[..<at.lowerBound])
        let symbols = DateFormatter(); symbols.locale = locale
        let names = Set(symbols.weekdaySymbols)
        let words = days.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty && $0 != "and" }
        guard !words.isEmpty, words.allSatisfy(names.contains) else { return text }
        let plural = words.reduce(days) { $0.replacingOccurrences(of: $1, with: $1 + "s") }
        return plural + rest[at.lowerBound...]
    }

    /// The schedule as the end of "Resume to run again …": "on weekdays at 9:00 AM", "every day at 9:00 AM".
    public static func resumePhrase(_ phrase: String) -> String {
        let first = phrase.prefix(while: { $0 != " " })
        let symbols = DateFormatter(); symbols.locale = Locale(identifier: "en_US")
        if first == "Weekdays" || first == "Weekends" { return "on " + phrase.prefix(1).lowercased() + phrase.dropFirst() }
        if first.hasSuffix("s"), symbols.weekdaySymbols.contains(String(first.dropLast())) { return "on " + phrase }
        return phrase.prefix(1).lowercased() + phrase.dropFirst()
    }

    /// "Daily", "Every 3 days", "Every hour", "Every 7 minutes".
    public static func everyPhrase(_ minutes: Int) -> String {
        if minutes.isMultiple(of: 1440) { return minutes == 1440 ? "Daily" : "Every \(minutes / 1440) days" }
        if minutes.isMultiple(of: 60) { return minutes == 60 ? "Every hour" : "Every \(minutes / 60) hours" }
        return minutes == 1 ? "Every minute" : "Every \(minutes) minutes"
    }

    /// Run number of the next scheduled run for a finite schedule ("run 4 of 5"), when known.
    public static func runProgress(_ task: ScheduledTaskRecord) -> String? {
        let s = task.schedule
        guard task.listSection == .active, task.currentRun == nil else { return nil }
        if s.kind == "repeat", let total = s.occurrences, let minutes = s.everyMinutes, minutes > 0,
           let at = s.at.flatMap(ISODate.parse), let next = task.nextScheduledRun {
            let index = Int(((next / 1000 - at.timeIntervalSince1970) / Double(minutes * 60)).rounded()) + 1
            return (1...total).contains(index) ? "run \(index) of \(total)" : nil
        }
        if let total = s.maxRuns { return "run \(min(total, (task.scheduledRunCount ?? 0) + 1)) of \(total)" }
        return nil
    }

    /// The schedule line under a task's title: the sentence plus how it ends.
    /// "Every weekday at 9:00 AM, 10 times", "Once · today at 10:00 AM".
    public static func detailLine(_ schedule: ScheduledTaskSchedule, now: Date = Date(), timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let f = TaskTimeFormat(now: now, timeZone: timeZone, locale: locale)
        if schedule.kind == "once", let at = schedule.at.flatMap(ISODate.parse) {
            return "Once · \(f.dayAndTime(at.ms, lowercaseDay: true, joiner: " at "))"
        }
        return sentence(schedule, timeZone: timeZone, locale: locale) + ending(schedule, f)
    }

    /// The task view's sentence form, unlike the list's short form: "Every weekday at 9:00 AM", "Every day".
    public static func sentence(_ schedule: ScheduledTaskSchedule, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        switch schedule.kind {
        case "once": return "Once"
        case "interval", "repeat":
            guard let minutes = schedule.everyMinutes, minutes > 0 else { return "Repeats" }
            return minutes == 1440 ? "Every day" : everyPhrase(minutes)
        default:
            return schedule.description(locale: locale, displayTimeZone: timeZone)
        }
    }

    /// A schedule as the chat's change card writes it: the sentence form, with three or more
    /// days in a row as a range. "Every weekday at 9:00 AM" → "Tue–Fri at 8:00 AM".
    public static func changeLine(_ schedule: ScheduledTaskSchedule, now: Date = Date(), timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard schedule.kind == "cron" else { return detailLine(schedule, now: now, timeZone: timeZone, locale: locale) }
        let f = TaskTimeFormat(now: now, timeZone: timeZone, locale: locale)
        return rangePhrase(schedule.description(locale: locale, displayTimeZone: timeZone), locale: locale) + ending(schedule, f)
    }

    private static func ending(_ schedule: ScheduledTaskSchedule, _ f: TaskTimeFormat) -> String {
        if let count = schedule.kind == "repeat" ? schedule.occurrences : schedule.maxRuns { return ", \(count) times" }
        if let end = schedule.endsAt.flatMap(ISODate.parse) { return ", until \(f.shortDate(end.ms))" }
        return ""
    }

    static func rangePhrase(_ text: String, locale: Locale) -> String {
        guard text.hasPrefix("Every "), let at = text.range(of: " at ") else { return text }
        let symbols = DateFormatter(); symbols.locale = locale
        let days = text[text.index(text.startIndex, offsetBy: 6)..<at.lowerBound]
            .components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty && $0 != "and" }
        let indices = days.compactMap { symbols.weekdaySymbols.firstIndex(of: $0) }
        guard indices.count == days.count, indices.count >= 3,
              zip(indices, indices.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return text }
        let short = symbols.shortWeekdaySymbols!
        return "\(short[indices.first!])–\(short[indices.last!])" + text[at.lowerBound...]
    }

    public static func whenLine(_ task: ScheduledTaskRecord, hostName: String, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var parts = [short(task.schedule, timeZone: timeZone, locale: locale)]
        if let progress = runProgress(task) { parts.append(progress) }
        else if task.listSection == .closed, task.cancelledAt == nil,
                let total = task.schedule.kind == "repeat" ? task.schedule.occurrences : task.schedule.maxRuns {
            parts.append(total == 1 ? "1 run" : "\(total) runs")
        }
        parts.append(hostName)
        if task.agent == "codex" { parts.append("Codex") }
        return parts.joined(separator: " · ")
    }
}

public enum RunErrorText {
    /// One short clause for a list row: the first sentence, without a trailing period.
    public static func short(_ error: String?) -> String {
        guard let line = firstLine(error) else { return "no details" }
        // A sentence ends at ". " or a final "." — not inside "5.5" or a path.
        var sentence = line.range(of: ". ").map { String(line[..<$0.lowerBound]) } ?? line
        if sentence.hasSuffix(".") { sentence.removeLast() }
        sentence = sentence.trimmingCharacters(in: .whitespaces)
        if sentence.count > 60 { sentence = String(sentence.prefix(59)) + "…" }
        return sentence
    }

    public static func firstLine(_ text: String?) -> String? {
        let line = text?.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
    }
}

enum ISODate {
    static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ISO8601DateFormatter().date(from: text) ?? fractional.date(from: text)
    }
}

extension Date { var ms: Double { timeIntervalSince1970 * 1000 } }

/// Times as the Tasks screens write them: "9:00" over "AM Fri", "12 min", "Today", "Oct 12".
public struct TaskTimeFormat: Sendable {
    public let now: Date
    public let timeZone: TimeZone
    public let locale: Locale
    public init(now: Date, timeZone: TimeZone, locale: Locale) { self.now = now; self.timeZone = timeZone; self.locale = locale }

    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; c.locale = locale; return c }
    private func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = locale; f.timeZone = timeZone; f.setLocalizedDateFormatFromTemplate(template); return f
    }
    private func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    /// ("9:00", "AM") today, ("9:00", "AM Fri") within a week, ("9:00", "AM Oct 27") later.
    public func clock(_ ms: Double) -> (String, String) {
        let d = date(ms)
        // "jmm" follows the user's 12/24-hour setting; split off AM/PM so it can sit under the time.
        let f = formatter("jmm")
        let full = f.string(from: d)
        var clockText = full, period = ""
        for symbol in [f.amSymbol, f.pmSymbol].compactMap({ $0 }) where !symbol.isEmpty && full.contains(symbol) {
            period = symbol
            clockText = full.replacingOccurrences(of: symbol, with: "").trimmingCharacters(in: .whitespaces)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 0
        // A weekday only for the coming week; any earlier day gets its date, so "Fri" never
        // leaves the reader guessing whether it means last Friday or the next one.
        let day: String
        if days == 0 { day = "" }
        else if (1...6).contains(days) { day = formatter("EEE").string(from: d) }
        else { day = formatter("MMMd").string(from: d) }
        return (clockText, [period, day].filter { !$0.isEmpty }.joined(separator: " "))
    }

    public func time(_ ms: Double) -> String { formatter("jmm").string(from: date(ms)) }

    public func shortDate(_ ms: Double) -> String { formatter("MMMd").string(from: date(ms)) }

    /// "Today", "Yesterday", "Mon", or "Oct 3".
    public func relativeDay(_ ms: Double) -> String {
        let d = date(ms)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return formatter("EEE").string(from: d)
        default: return shortDate(ms)
        }
    }

    /// "12 min", "1 h 5 min", "<1 min". `compact` fits the list's time column: "4 h", "2 d".
    public func elapsed(from ms: Double, compact: Bool = false) -> String {
        let minutes = max(0, Int((now.ms - ms) / 60_000))
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        if compact { return h < 48 ? "\(Int((Double(minutes) / 60).rounded())) h" : "\(h / 24) d" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    public static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
