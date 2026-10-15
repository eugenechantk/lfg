import Foundation

/// The edit form's schedule: Once, or a Repeat pick with an Ends rule. It decides the saved kind,
/// so the user never chooses between cron, interval and repeat:
/// - Clock-aligned picks (N minutes where N divides 60, N hours where N divides 24, every day,
///   weekdays, weekly, monthly, custom) save as `cron`; Ends adds `maxRuns` or `endsAt`.
/// - Any other gap saves as an exact gap from Starts: `repeat` with After N, otherwise `interval`
///   (with `endsAt` for On date).
public struct ScheduleDraft: Equatable, Sendable {
    public enum Mode: String, Sendable, CaseIterable { case once, repeating }
    public enum Preset: String, Sendable, CaseIterable, Identifiable {
        case minutes, hourly, daily, weekdays, weekly, monthly, custom
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .minutes: "Minutes"
            case .hourly: "Hourly"
            case .daily: "Daily"
            case .weekdays: "Weekdays"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .custom: "Custom"
            }
        }
        /// The unit of "Every N", for the presets that have one.
        public var everyUnit: (singular: String, plural: String, limit: Int)? {
            switch self {
            case .minutes: ("minute", "minutes", 1440)
            case .hourly: ("hour", "hours", 168)
            case .daily: ("day", "days", 365)
            default: nil
            }
        }
    }
    public enum Ends: String, Sendable, CaseIterable, Identifiable {
        case never, after, onDate
        public var id: String { rawValue }
        public var title: String { self == .never ? "Never" : self == .after ? "After N" : "On date" }
    }

    public var mode: Mode = .once
    public var preset: Preset = .weekdays {
        // A new pick is the user's choice; stop preserving the saved exact gap.
        didSet { if oldValue != preset { keepsExactGap = false } }
    }
    /// Set when the task was saved as an exact gap (repeat or interval). Saving it again must not
    /// turn "every day from Tuesday 8:30" into cron, which would restart its run count.
    public private(set) var keepsExactGap = false
    /// Set for an older interval saved without a start; saving keeps it that way until Starts changes.
    public private(set) var omitsStart = false
    public var everyMinutes = 5
    public var everyHours = 1
    public var everyDays = 1
    /// Weekdays the task runs on, 0 = Sunday.
    public var days: Set<Int> = [1, 2, 3, 4, 5]
    public var hour = 9
    public var minute = 0
    public var dayOfMonth = 1
    /// Once: when it runs. Exact gap: when the gap starts.
    public var start: Date {
        didSet { if oldValue != start { omitsStart = false } }
    }
    public var customExpression = "0 9 * * 1-5"
    public var ends: Ends = .never
    public var count = 10
    public var endDate: Date
    public var timezone: String

    /// `nextRunAt` (ms) stands in for the start of an older interval saved without one.
    public init(schedule: ScheduledTaskSchedule? = nil, now: Date = Date(), timezone: String = TimeZone.current.identifier, nextRunAt: Double? = nil) {
        self.timezone = schedule?.timezone ?? timezone
        let zone = TimeZone(identifier: self.timezone) ?? .current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        // A new task starts tomorrow at 9:00.
        let tomorrow9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: now)!)!
        start = tomorrow9
        endDate = cal.date(byAdding: .month, value: 1, to: tomorrow9)!
        guard let s = schedule else { return }
        switch s.kind {
        case "once":
            mode = .once
            if let at = s.at.flatMap(ISODate.parse) { start = at }
        case "repeat", "interval":
            mode = .repeating
            keepsExactGap = true
            if let at = s.at.flatMap(ISODate.parse) { start = at }
            else if let next = nextRunAt { start = Date(timeIntervalSince1970: next / 1000); omitsStart = true }
            else { omitsStart = true }
            let m = max(1, s.everyMinutes ?? 60)
            if m.isMultiple(of: 1440) { preset = .daily; everyDays = m / 1440 }
            else if m.isMultiple(of: 60) { preset = .hourly; everyHours = m / 60 }
            else { preset = .minutes; everyMinutes = m }
            let c = cal.dateComponents([.hour, .minute], from: start); hour = c.hour ?? 9; minute = c.minute ?? 0
            if s.kind == "repeat" { ends = .after; count = s.occurrences ?? 10 }
            else if let end = s.endsAt.flatMap(ISODate.parse) { ends = .onDate; endDate = end }
        default:
            mode = .repeating
            readCron(s.expression ?? "")
            if let n = s.maxRuns { ends = .after; count = n }
            else if let end = s.endsAt.flatMap(ISODate.parse) { ends = .onDate; endDate = end }
        }
    }

    private var zone: TimeZone { TimeZone(identifier: timezone) ?? .current }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c }

    /// Maps a saved cron expression to the pick that would produce it, or Custom.
    /// The day-of-week field a saved Weekly schedule was written with ("2-5"), so saving the same
    /// days writes the same text and the host does not see a schedule change.
    private var savedDayField: String?

    /// Days named by a cron day-of-week field of numbers, lists and ranges. 7 means Sunday.
    static func weekdays(in field: String) -> Set<Int>? {
        var out = Set<Int>()
        for part in field.split(separator: ",") {
            let ends = part.split(separator: "-").map { Int($0) }
            guard !ends.isEmpty, ends.count <= 2, ends.allSatisfy({ $0 != nil && (0...7).contains($0!) }) else { return nil }
            let lo = ends[0]!, hi = ends.count == 2 ? ends[1]! : lo
            guard lo <= hi else { return nil }
            for d in lo...hi { out.insert(d == 7 ? 0 : d) }
        }
        return out.isEmpty ? nil : out
    }

    private mutating func readCron(_ expression: String) {
        customExpression = expression.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let f = customExpression.split(separator: " ").map(String.init)
        preset = .custom
        guard f.count == 5 else { return }
        let int = { (s: String) -> Int? in s.allSatisfy(\.isNumber) ? Int(s) : nil }
        let step = { (s: String) -> Int? in s == "*" ? 1 : (s.hasPrefix("*/") ? Int(s.dropFirst(2)) : nil) }
        if f[2] == "*", f[3] == "*", f[4] == "*" {
            // "*/N * * * *" (and "* * * * *") is Minutes; "M */N * * *" (and "M * * * *") is Hourly.
            if f[1] == "*", let n = step(f[0]), n > 0, 60 % n == 0 { preset = .minutes; everyMinutes = n; return }
            if let m = int(f[0]), (0...59).contains(m), let n = step(f[1]), n > 0, 24 % n == 0 {
                preset = .hourly; everyHours = n; minute = m; return
            }
        }
        guard let m = int(f[0]), let h = int(f[1]), (0...59).contains(m), (0...23).contains(h), f[3] == "*" else { return }
        if f[2] == "*", f[4] == "*" { preset = .daily; everyDays = 1; hour = h; minute = m; return }
        if f[2] == "*", f[4] == "1-5" { preset = .weekdays; days = [1, 2, 3, 4, 5]; hour = h; minute = m; return }
        if f[2] == "*", let values = Self.weekdays(in: f[4]) {
            // Lists and ranges ("1,3,5", "2-5") open as Weekly; the saved text is kept for an unchanged save.
            preset = .weekly; days = values; savedDayField = f[4]; hour = h; minute = m; return
        }
        if f[4] == "*", let d = int(f[2]), (1...31).contains(d) { preset = .monthly; dayOfMonth = d; hour = h; minute = m }
    }

    /// The gap in minutes for Minutes / Hourly / Daily.
    public var gapMinutes: Int? {
        switch preset {
        case .minutes: everyMinutes
        case .hourly: everyHours * 60
        case .daily: everyDays * 1440
        default: nil
        }
    }

    /// True when the pick fits the clock, so it saves as cron.
    public var isClockAligned: Bool {
        if keepsExactGap, gapMinutes != nil { return false }
        switch preset {
        case .minutes: return 60 % max(1, everyMinutes) == 0
        case .hourly: return 24 % max(1, everyHours) == 0
        case .daily: return everyDays == 1
        default: return true
        }
    }

    public var cronExpression: String? {
        guard mode == .repeating, isClockAligned else { return nil }
        switch preset {
        case .minutes: return everyMinutes == 1 ? "* * * * *" : "*/\(everyMinutes) * * * *"
        case .hourly: return "\(minute) \(everyHours == 1 ? "*" : "*/\(everyHours)") * * *"
        case .daily: return "\(minute) \(hour) * * *"
        case .weekdays: return "\(minute) \(hour) * * 1-5"
        case .weekly:
            if let savedDayField, Self.weekdays(in: savedDayField) == days { return "\(minute) \(hour) * * \(savedDayField)" }
            return "\(minute) \(hour) * * \(days.sorted().map(String.init).joined(separator: ","))"
        case .monthly: return "\(minute) \(hour) \(dayOfMonth) * *"
        case .custom: return customExpression.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = zone; f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// The last moment of the chosen end day, in the task's timezone.
    public var endsAtValue: Date {
        let day = calendar.startOfDay(for: endDate)
        return calendar.date(byAdding: .second, value: 86_399, to: day)!
    }

    /// The exact-gap start, with Daily's time of day applied to the start date.
    private var gapStart: Date {
        guard preset == .daily else { return start }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
    }

    /// What Save sends.
    public var schedule: ScheduledTaskSchedule {
        if mode == .once { return .init(kind: "once", timezone: timezone, at: iso(start)) }
        if let expression = cronExpression {
            return .init(kind: "cron", timezone: timezone, expression: expression,
                         maxRuns: ends == .after ? count : nil, endsAt: ends == .onDate ? iso(endsAtValue) : nil)
        }
        let gap = gapMinutes ?? 60
        if ends == .after {
            return .init(kind: "repeat", timezone: timezone, at: iso(gapStart), everyMinutes: gap, occurrences: count)
        }
        return .init(kind: "interval", timezone: timezone, at: omitsStart ? nil : iso(gapStart), everyMinutes: gap,
                     endsAt: ends == .onDate ? iso(endsAtValue) : nil)
    }

    /// Why Save is unavailable, in plain words; nil when the draft can be saved.
    public func problem(now: Date = Date()) -> String? {
        if mode == .once { return start > now ? nil : "Choose a time in the future." }
        if let unit = preset.everyUnit, let n = [Preset.minutes: everyMinutes, .hourly: everyHours, .daily: everyDays][preset],
           !(1...unit.limit).contains(n) { return "Every must be 1 to \(unit.limit) \(unit.plural)." }
        if preset == .weekly, days.isEmpty { return "Pick at least one day." }
        if preset == .custom, customExpression.split(whereSeparator: \.isWhitespace).count != 5 { return "A cron expression has five fields." }
        if ends == .after, !(1...1000).contains(count) { return "Number of runs must be 1 to 1,000." }
        if ends == .onDate, endsAtValue <= now { return "Choose an end date in the future." }
        return nil
    }

    // MARK: Words

    /// "Mon, Wed and Fri", as the boards write lists (no comma before "and").
    static func joined(_ items: [String]) -> String {
        items.count < 2 ? (items.first ?? "") : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    /// "At 8:30 AM on the 1st and 15th of every month" for a custom cron that names days of the month.
    func monthDaysSentence(locale: Locale) -> String? {
        let f = customExpression.split(separator: " ").map(String.init)
        guard f.count == 5, let m = Int(f[0]), let h = Int(f[1]), f[3] == "*", f[4] == "*", (0..<60).contains(m), (0..<24).contains(h) else { return nil }
        let days = f[2].split(separator: ",").compactMap { Int($0) }
        guard !days.isEmpty, days.count == f[2].split(separator: ",").count, days.allSatisfy({ (1...31).contains($0) }) else { return nil }
        return "At \(clock(hour: h, minute: m, locale: locale)) on the \(Self.joined(days.map(TaskTimeFormat.ordinal))) of every month"
    }

    public func sentence(locale: Locale = .current) -> String {
        let t = clock(hour: hour, minute: minute, locale: locale)
        let base: String
        if mode == .once {
            let f = DateFormatter(); f.locale = locale; f.timeZone = zone; f.setLocalizedDateFormatFromTemplate("EEEMMMd")
            return "Once, \(f.string(from: start)) at \(time(start, locale: locale))"
        }
        switch preset {
        case .minutes: base = everyMinutes == 1 ? "Every minute" : "Every \(everyMinutes) minutes"
        case .hourly: base = everyHours == 1 ? "Every hour" : "Every \(everyHours) hours"
        case .daily: base = everyDays == 1 ? "Every day at \(t)" : "Every \(everyDays) days at \(t)"
        case .weekdays: base = "Every weekday at \(t)"
        case .weekly:
            let f = DateFormatter(); f.locale = locale
            let names = [1, 2, 3, 4, 5, 6, 0].filter(days.contains).map { f.shortWeekdaySymbols[$0] }
            base = names.isEmpty ? "Weekly" : "Every \(Self.joined(names)) at \(t)"
        case .monthly: base = "On the \(TaskTimeFormat.ordinal(dayOfMonth)) of every month at \(t)"
        case .custom:
            base = monthDaysSentence(locale: locale)
                ?? ScheduledTaskSchedule(kind: "cron", timezone: timezone, expression: cronExpression)
                    .description(locale: locale, displayTimeZone: zone)
        }
        switch ends {
        case .never: return base
        case .after: return "\(base), \(count) \(count == 1 ? "time" : "times")"
        case .onDate:
            let f = DateFormatter(); f.locale = locale; f.timeZone = zone; f.setLocalizedDateFormatFromTemplate("MMMd")
            return "\(base), until \(f.string(from: endDate))"
        }
    }

    /// The line under the sentence: how it runs, or for Once how far away it is.
    public func subline(now: Date = Date(), locale: Locale = .current) -> String {
        if mode == .once {
            let f = TaskTimeFormat(now: now, timeZone: zone, locale: locale)
            let c = f.countdown(to: start.timeIntervalSince1970 * 1000)
            return c.prefix(1).uppercased() + c.dropFirst()
        }
        if isClockAligned { return "Runs at fixed clock times" }
        let f = DateFormatter(); f.locale = locale; f.timeZone = zone; f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return "Exact gap from \(f.string(from: gapStart)) at \(time(gapStart, locale: locale))"
    }

    /// The next-run chips as the boards write them: four for a clock-aligned minute or a
    /// days gap, three otherwise.
    public func chips(_ runs: [Double], now: Date = Date(), locale: Locale = .current) -> [String] {
        let four = (preset == .minutes && isClockAligned) || (preset == .daily && !isClockAligned)
        return runs.prefix(four ? 4 : 3).map { chip($0, now: now, locale: locale) }
    }

    /// A short label for one next-run chip, picked for the schedule's scale.
    /// Day-level schedules drop AM/PM ("Fri 9:00"); monthly ones lead with the date ("Nov 1 · 9:00").
    public func chip(_ ms: Double, now: Date = Date(), locale: Locale = .current) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let sameDay = calendar.isDate(d, inSameDayAs: now)
        func format(_ template: String, period: Bool = true) -> String {
            let f = DateFormatter(); f.locale = locale; f.timeZone = zone
            f.setLocalizedDateFormatFromTemplate(template)
            if !period {
                f.dateFormat = f.dateFormat.replacingOccurrences(of: "a", with: "")
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: "\u{202F}")))
            }
            return f.string(from: d)
        }
        switch preset {
        case .minutes where mode == .repeating && isClockAligned: return format(sameDay ? "hmm" : "EEEhmm", period: false)
        case .minutes, .hourly: return format(sameDay ? "jmm" : "EEEjmm")
        case .daily where !isClockAligned: return format("MMMd")
        case .monthly: return "\(format("MMMd")) · \(format("hmm", period: false))"
        case .custom where !sameDay: return "\(format("MMMd")) · \(format("hmm", period: false))"
        default: return format(sameDay ? "hmm" : "EEEhmm", period: false)
        }
    }

    /// "Thu, Oct 29 at 9:00 AM".
    public func dayAndTime(_ ms: Double, locale: Locale = .current) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter(); f.locale = locale; f.timeZone = zone; f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return "\(f.string(from: d)) at \(time(d, locale: locale))"
    }

    private func time(_ date: Date, locale: Locale) -> String {
        let f = DateFormatter(); f.locale = locale; f.timeZone = zone; f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }
    private func clock(hour: Int, minute: Int, locale: Locale) -> String {
        let d = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: start)) ?? start
        return time(d, locale: locale)
    }
}

// MARK: - Preview from the host

/// `POST /api/scheduled-tasks/preview`: the host's next runs for a schedule, and its last run if it ends.
public struct SchedulePreview: Decodable, Sendable, Equatable {
    public var nextRuns: [Double]
    public var lastRun: Double?
    public var error: String?
    enum CodingKeys: String, CodingKey { case nextRuns, lastRun, error }
    public init(nextRuns: [Double] = [], lastRun: Double? = nil, error: String? = nil) { self.nextRuns = nextRuns; self.lastRun = lastRun; self.error = error }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextRuns = try c.decodeIfPresent([Double].self, forKey: .nextRuns) ?? []
        lastRun = try c.decodeIfPresent(Double.self, forKey: .lastRun)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

public extension ScheduledTasksClient {
    func preview(_ schedule: ScheduledTaskSchedule) async throws -> SchedulePreview {
        struct Body: Encodable { let schedule: ScheduledTaskSchedule }
        return try await call("/api/scheduled-tasks/preview", body: JSONEncoder().encode(Body(schedule: schedule)))
    }
}
