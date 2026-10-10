import Foundation

public struct ScheduledTaskSchedule: Codable, Hashable, Sendable {
    public var kind = "once"
    public var timezone = "Asia/Hong_Kong"
    public var at: String?
    public var everyMinutes: Int?
    public var expression: String?
    public init(kind: String = "once", timezone: String = "Asia/Hong_Kong", at: String? = nil, everyMinutes: Int? = nil, expression: String? = nil) {
        self.kind = kind; self.timezone = timezone; self.at = at; self.everyMinutes = everyMinutes; self.expression = expression
    }
    public var label: String { description() }

    /// Presentation only. The host remains the authority for cron execution.
    public func description(nextRunAt: Double? = nil, locale: Locale = .current,
                            displayTimeZone: TimeZone = .current) -> String {
        let nextRun = nextRunAt.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        let formatter = TaskScheduleDescription(locale: locale, timezone: timezone,
            displayTimeZone: displayTimeZone, referenceDate: nextRun ?? Date())
        switch kind {
        case "interval":
            guard let minutes = everyMinutes, minutes > 0 else { return "Interval schedule" }
            if minutes == 1 { return "Every minute" }
            if minutes == 60 { return "Every hour" }
            return minutes.isMultiple(of: 60) ? "Every \(minutes / 60) hours" : "Every \(minutes) minutes"
        case "cron":
            if TimeZone(identifier: timezone) != nil,
               let readable = formatter.cron(expression ?? "") {
                return readable
            }
            if let nextRunAt, nextRunAt.isFinite {
                return "Custom schedule · Next: " + formatter.date(Date(timeIntervalSince1970: nextRunAt / 1000))
            }
            return "Custom schedule"
        default:
            if let at {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: at) ?? ISO8601DateFormatter().date(from: at) {
                    return formatter.date(date)
                }
            }
            if let nextRunAt, nextRunAt.isFinite { return formatter.date(Date(timeIntervalSince1970: nextRunAt / 1000)) }
            return "One-time schedule"
        }
    }
}

private struct TaskScheduleDescription {
    let locale: Locale
    let timezone: String
    let displayTimeZone: TimeZone
    let referenceDate: Date
    private var zone: TimeZone { TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)! }

    func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = displayTimeZone
        formatter.dateStyle = .medium
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = displayTimeZone
        formatter.timeStyle = calendar.component(.second, from: value) == 0 ? .short : .medium
        return formatter.string(from: value)
    }

    private func time(hour: Int, minute: Int) -> String {
        // The fields have already been converted to local wall-clock time.
        // UTC here prevents the formatter from applying the timezone twice.
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: Date(timeIntervalSince1970: Double(hour * 3600 + minute * 60)))
    }

    private func joined(_ values: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    func cron(_ expression: String) -> String? {
        let fields = expression.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5,
              let sourceMinutes = values(fields[0], range: 0...59),
              let sourceHours = values(fields[1], range: 0...23),
              let days = values(fields[2], range: 1...31),
              let months = values(fields[3], range: 1...12, names: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]),
              let rawWeekdays = values(fields[4], range: 0...7, names: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"])
        else { return nil }
        let sourceWeekdays = Set(rawWeekdays.map { $0 == 7 ? 0 : $0 })
        let anyDay = fields[2] == "*" || fields[2] == "?"
        let anyWeekday = fields[4] == "*" || fields[4] == "?"
        // Croner combines restricted day-of-month and weekday fields with OR.
        // Avoid silently describing them as an AND recurrence.
        guard anyDay || anyWeekday else { return nil }

        // Anchor conversion to the actual next run, including its DST offset.
        let offset = displayTimeZone.secondsFromGMT(for: referenceDate) - zone.secondsFromGMT(for: referenceDate)
        guard offset.isMultiple(of: 60) else { return nil }
        var localSlots = Set<Int>()
        var localWeekSlots = Set<Int>()
        for hour in sourceHours {
            for minute in sourceMinutes {
                let shifted = hour * 60 + minute + offset / 60
                let dayShift = Int(floor(Double(shifted) / 1440))
                let localMinute = shifted - dayShift * 1440
                // Month boundaries vary by month and leap year. Keep the exact
                // next-run fallback rather than inventing a fixed calendar rule.
                guard dayShift == 0 || (anyDay && months.count == 12) else { return nil }
                localSlots.insert(localMinute)
                for weekday in sourceWeekdays {
                    let localDay = ((weekday + dayShift) % 7 + 7) % 7
                    localWeekSlots.insert(localDay * 1440 + localMinute)
                }
            }
        }
        let weekdays = Set(localWeekSlots.map { $0 / 1440 }).sorted()
        // A rule like Monday morning + Tuesday evening must not become both
        // times on both days after conversion.
        guard localWeekSlots.count == weekdays.count * localSlots.count else { return nil }
        let hours = Set(localSlots.map { $0 / 60 }).sorted()
        let minutes = Set(localSlots.map { $0 % 60 }).sorted()
        let independentClockFields = hours.count * minutes.count == localSlots.count

        let symbols = DateFormatter()
        symbols.locale = locale
        var calendarRule = "Every day"
        var restriction = ""
        if !anyDay {
            let dayPhrase = "day\(days.count == 1 ? "" : "s") \(joined(days.map(String.init)))"
            let monthPhrase = months.count == 12 ? "every month" : joined(months.map { symbols.monthSymbols[$0 - 1] })
            calendarRule = "On \(dayPhrase) of \(monthPhrase)"
            restriction = " on \(dayPhrase) of \(monthPhrase)"
        } else {
            if weekdays == [1, 2, 3, 4, 5] {
                calendarRule = "Every weekday"; restriction = " on weekdays"
            } else if weekdays == [0, 6] {
                calendarRule = "Every weekend"; restriction = " on weekends"
            } else if weekdays.count != 7 {
                let names = joined(weekdays.map { symbols.weekdaySymbols[$0] })
                calendarRule = "Every \(names)"; restriction = " on \(names)"
            }
            if months.count != 12 {
                let monthPhrase = " in \(joined(months.map { symbols.monthSymbols[$0 - 1] }))"
                calendarRule += monthPhrase; restriction += monthPhrase
            }
        }

        if independentClockFields, hours.count == 24 {
            if minutes.count == 60 { return "Every minute" + restriction }
            if let step = regularStep(minutes, cycle: 60) { return "Every \(step) minutes" + restriction }
            if minutes == [0] { return "Every hour" + restriction }
            if minutes.count == 1 { return "Every hour at minute \(minutes[0])" + restriction }
        }
        if minutes == [0], let step = regularStep(hours, cycle: 24) {
            return "Every \(step) hours" + restriction
        }
        // Keep large or advanced schedules honest and concise with the next-run fallback.
        guard localSlots.count <= 6 else { return nil }
        let times = localSlots.sorted().map { time(hour: $0 / 60, minute: $0 % 60) }
        return calendarRule + " at " + joined(times)
    }

    private func regularStep(_ values: [Int], cycle: Int) -> Int? {
        guard values.count > 1, values[0] == 0 else { return nil }
        let step = values[1]
        guard step > 1, cycle.isMultiple(of: step), values == Array(stride(from: 0, to: cycle, by: step)) else { return nil }
        return step
    }

    /// Supports standard fields only. Special operators remain custom schedules.
    private func values(_ field: String, range: ClosedRange<Int>, names: [String] = []) -> [Int]? {
        func number(_ text: String) -> Int? {
            if let index = names.firstIndex(of: text) { return index + range.lowerBound }
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(text), range.contains(value) else { return nil }
            return value
        }
        var result = Set<Int>()
        for part in field.split(separator: ",", omittingEmptySubsequences: false) {
            let stepped = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard (1...2).contains(stepped.count) else { return nil }
            let step: Int
            if stepped.count == 2 {
                guard let value = Int(stepped[1]), value > 0, value <= range.count else { return nil }
                step = value
            } else { step = 1 }
            let bounds: ClosedRange<Int>
            if stepped[0] == "*" || stepped[0] == "?" { bounds = range }
            else {
                let endpoints = stepped[0].split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard let first = endpoints.first.flatMap(number) else { return nil }
                if endpoints.count == 1 {
                    // A stepped single value can differ between cron dialects.
                    guard stepped.count == 1 else { return nil }
                    bounds = first...first
                } else {
                    guard endpoints.count == 2, let last = number(endpoints[1]), first <= last else { return nil }
                    bounds = first...last
                }
            }
            result.formUnion(stride(from: bounds.lowerBound, through: bounds.upperBound, by: step))
        }
        return result.isEmpty ? nil : result.sorted()
    }
}

public struct ScheduledTaskRun: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var taskId: String?
    public var taskName: String?
    public var trigger: String?
    public var scheduledFor: Double?
    public var startedAt: Double?
    public var finishedAt: Double?
    public var status: String?
    public var sessionId: String?
    public var summary: String?
    public var error: String?
    public var statusLabel: String {
        switch status {
        case "starting": "Starting"
        case "running": "Running"
        case "needs_input": "Needs input"
        case "succeeded": "Completed"
        case "failed": "Failed"
        case "interrupted": "Interrupted"
        default: "Unknown"
        }
    }
}

public struct ScheduledTaskRecord: Decodable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    public var cwd: String
    public var agent: String
    public var model: String?
    public var schedule: ScheduledTaskSchedule
    public var enabled: Bool
    public var nextRunAt: Double?
    public var lastRunAt: Double?
    public var cancelledAt: Double?
    public var currentRun: ScheduledTaskRun?
    public var lastRun: ScheduledTaskRun?
    public var recentRuns: [ScheduledTaskRun]
    public var runCount: Int
    enum CodingKeys: String, CodingKey { case id, name, prompt, cwd, agent, model, schedule, enabled, nextRunAt, lastRunAt, cancelledAt, currentRun, lastRun, recentRuns, runCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled task"
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? "claude"
        model = try c.decodeIfPresent(String.self, forKey: .model)
        schedule = try c.decodeIfPresent(ScheduledTaskSchedule.self, forKey: .schedule) ?? .init()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        nextRunAt = try c.decodeIfPresent(Double.self, forKey: .nextRunAt)
        lastRunAt = try c.decodeIfPresent(Double.self, forKey: .lastRunAt)
        cancelledAt = try c.decodeIfPresent(Double.self, forKey: .cancelledAt)
        currentRun = try c.decodeIfPresent(ScheduledTaskRun.self, forKey: .currentRun)
        lastRun = try c.decodeIfPresent(ScheduledTaskRun.self, forKey: .lastRun)
        recentRuns = try c.decodeIfPresent([ScheduledTaskRun].self, forKey: .recentRuns) ?? lastRun.map { [$0] } ?? []
        runCount = try c.decodeIfPresent(Int.self, forKey: .runCount) ?? recentRuns.count
    }
    public var modelLabel: String {
        let chosen = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return chosen.isEmpty ? "\(agent == "codex" ? "Codex" : "Claude") default" : chosen
    }
    public var canResume: Bool { cancelledAt == nil && !(schedule.kind == "once" && lastRunAt != nil && nextRunAt == nil) }
    public var isScheduleActive: Bool { enabled && canResume }
    public var listGroup: ScheduledTaskGroup {
        let running = ["starting", "running", "needs_input"].contains(currentRun?.status ?? "")
        return running || canResume ? .pending : .completed
    }
    public var statusLabel: String {
        if let currentRun { return currentRun.statusLabel }
        if cancelledAt != nil { return "Cancelled" }
        if !canResume { return lastRun?.statusLabel ?? "Completed" }
        return enabled ? "Scheduled" : "Paused"
    }
}

public enum ScheduledTaskGroup: String, CaseIterable, Sendable {
    case pending, completed
    public var title: String { self == .pending ? "Pending" : "Completed" }
}

public struct HostedScheduledTask: Identifiable, Sendable {
    public let task: ScheduledTaskRecord
    public let host: ScheduledTaskHost
    public var id: String { "\(host.id):\(task.id)" }
    public init(task: ScheduledTaskRecord, host: ScheduledTaskHost) { self.task = task; self.host = host }
}

public struct ScheduledTaskPayload: Encodable, Sendable {
    public var name: String
    public var prompt: String
    public var cwd: String
    public var agent: String
    public var model: String?
    public var schedule: ScheduledTaskSchedule
    public var enabled: Bool
    enum CodingKeys: String, CodingKey { case name, prompt, cwd, agent, model, schedule, enabled }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(prompt, forKey: .prompt)
        try c.encode(cwd, forKey: .cwd); try c.encode(agent, forKey: .agent)
        // Explicit null clears a previously selected model when editing.
        try c.encode(model, forKey: .model)
        try c.encode(schedule, forKey: .schedule); try c.encode(enabled, forKey: .enabled)
    }
}

public enum ScheduledTaskCronField: Int, CaseIterable, Identifiable, Sendable {
    case minute, hour, day, month, weekday
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .minute: "Minute"
        case .hour: "Hour"
        case .day: "Day of month"
        case .month: "Month"
        case .weekday: "Day of week"
        }
    }
    public var range: ClosedRange<Int> {
        switch self {
        case .minute: 0...59
        case .hour: 0...23
        case .day: 1...31
        case .month: 1...12
        case .weekday: 0...7
        }
    }
    public func accepts(_ value: String) -> Bool {
        value == "*" || (!value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
            && Int(value).map { range.contains($0) } == true)
    }
}

public struct ScheduledTaskDraft: Sendable {
    public var name = ""
    public var prompt = ""
    public var cwd = ""
    public var agent = "claude"
    public var model = ""
    public var kind = "once"
    public var timezone = TimeZone.current.identifier
    public var date = Date().addingTimeInterval(3600)
    public var intervalMinutes = "60"
    private var cronValues = ["0", "9", "*", "*", "*"]
    public var expression: String {
        get { cronValues.joined(separator: " ") }
        set { cronValues = newValue.components(separatedBy: " ") }
    }
    private var savedCronValues: [String] = []
    public var enabled = true
    public init(task: ScheduledTaskRecord? = nil) {
        guard let task else { return }
        name = task.name; prompt = task.prompt; cwd = task.cwd; agent = task.agent; model = task.model ?? ""
        kind = task.schedule.kind; timezone = task.schedule.timezone; enabled = task.enabled
        if let at = task.schedule.at {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = ISO8601DateFormatter().date(from: at) ?? fractional.date(from: at) ?? Date(timeIntervalSince1970: (task.nextRunAt ?? 0) / 1000)
        }
        intervalMinutes = String(task.schedule.everyMinutes ?? 60)
        expression = (task.schedule.expression ?? expression).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        savedCronValues = expression.components(separatedBy: " ")
    }
    public func cronValue(for field: ScheduledTaskCronField) -> String {
        cronValues.indices.contains(field.rawValue) ? cronValues[field.rawValue] : ""
    }
    public mutating func setCronValue(_ value: String, for field: ScheduledTaskCronField) {
        while cronValues.count < 5 { cronValues.append("") }
        cronValues[field.rawValue] = value
    }
    public func isCronFieldValid(_ field: ScheduledTaskCronField) -> Bool {
        let value = cronValue(for: field)
        // The host already validated saved ranges, steps, and named values.
        // Editing metadata or a different field must not destroy that schedule.
        return field.accepts(value) || (savedCronValues.indices.contains(field.rawValue)
            && !value.isEmpty && value == savedCronValues[field.rawValue])
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cwd.hasPrefix("/") && TimeZone(identifier: timezone) != nil && (kind != "interval" || (Int(intervalMinutes) ?? 0) > 0) && (kind != "cron" || (cronValues.count == 5 && ScheduledTaskCronField.allCases.allSatisfy(isCronFieldValid)))
    }
    public var payload: ScheduledTaskPayload {
        .init(name: name, prompt: prompt, cwd: cwd, agent: agent, model: model.isEmpty ? nil : model,
              schedule: .init(kind: kind, timezone: timezone, at: kind == "once" ? ISO8601DateFormatter().string(from: date) : nil, everyMinutes: kind == "interval" ? Int(intervalMinutes) : nil, expression: kind == "cron" ? expression : nil), enabled: enabled)
    }
}

public struct ScheduledTaskHost: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: URL
    private let headers: [String: String]
    public init(id: String, name: String, baseURL: URL, headers: [String: String] = [:]) { self.id = id; self.name = name; self.baseURL = baseURL; self.headers = headers }
    public func request(_ path: String, body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: path, relativeTo: baseURL)!.absoluteURL)
        r.allHTTPHeaderFields = headers; r.timeoutInterval = body == nil ? 20 : 120
        if let body { r.httpMethod = "POST"; r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }
}

public struct ScheduledTaskChatContext: Sendable {
    public let taskID: String?
    public init(taskID: String? = nil) { self.taskID = taskID }
    public var endpoint: String {
        "/api/scheduled-tasks" + (taskID.map { "/\($0)" } ?? "") + "/chat"
    }
    public func savedSessionKey(hostID: String) -> String {
        "lfg.taskAuthoring.\(hostID)" + (taskID.map { ".task.\($0)" } ?? "")
    }
    public static func displayedMessage(_ text: String) -> String {
        let authoring = text.hasPrefix("Help the user create an LFG scheduled task")
            || text.hasPrefix("Help the user edit an existing LFG scheduled task")
        guard authoring, let range = text.range(of: "The user's request follows:\n") else { return text }
        return String(text[range.upperBound...])
    }
}

public struct ScheduledTasksClient: Sendable {
    public let host: ScheduledTaskHost
    private let session: URLSession
    public init(host: ScheduledTaskHost, session: URLSession = .shared) {
        self.host = host; self.session = session
    }
    public func call<T: Decodable & Sendable>(_ path: String, body: Data? = nil, as: T.Type = T.self) async throws -> T {
        let (data, response) = try await session.data(for: host.request(path, body: body))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 404, path == "/api/scheduled-tasks" {
                throw ScheduledTaskClientError(message: "Scheduled Tasks is unavailable on this host. Update and restart the host to use it.")
            }
            let message = (try? JSONDecoder().decode(ScheduledTaskErrorBody.self, from: data))?.error ?? "This host could not complete the request. Update the host if Scheduled Tasks is unavailable."
            throw ScheduledTaskClientError(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    public func list() async throws -> [ScheduledTaskRecord] { try await call("/api/scheduled-tasks", as: ScheduledTaskList.self).tasks }
    public func task(_ id: String) async throws -> ScheduledTaskRecord {
        let result: ScheduledTaskMutation = try await call("/api/scheduled-tasks/\(id)")
        guard let task = result.task else { throw ScheduledTaskClientError(message: "Task not found.") }
        return task
    }
    public func save(_ draft: ScheduledTaskDraft, id: String? = nil) async throws { let _: ScheduledTaskMutation = try await call("/api/scheduled-tasks" + (id.map { "/\($0)" } ?? ""), body: JSONEncoder().encode(draft.payload)) }
    public func action(_ id: String, _ action: String, enabled: Bool? = nil) async throws {
        let data = try JSONEncoder().encode(ScheduledTaskToggle(enabled: enabled))
        let _: ScheduledTaskMutation = try await call("/api/scheduled-tasks/\(id)" + (action.isEmpty ? "" : "/\(action)"), body: data)
    }
    public func runs(_ id: String, offset: Int = 0) async throws -> ScheduledTaskRuns { try await call("/api/scheduled-tasks/\(id)/runs?offset=\(offset)") }
    public func startEditingChat(_ id: String) async throws -> String {
        let body = try JSONEncoder().encode([
            "prompt": "I want to edit this task. Ask me what I would like to change before making any updates."
        ])
        let result: ScheduledTaskChatSession = try await call(ScheduledTaskChatContext(taskID: id).endpoint, body: body)
        guard let sessionID = result.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty else {
            throw ScheduledTaskClientError(message: "The conversation started without an ID. Check Sessions before starting again.")
        }
        return sessionID
    }
}
private struct ScheduledTaskChatSession: Decodable, Sendable { let sessionId: String? }
public struct ScheduledTaskList: Decodable, Sendable { public let tasks: [ScheduledTaskRecord] }
public struct ScheduledTaskRuns: Decodable, Sendable { public let runs: [ScheduledTaskRun]; public let total: Int }
public struct ScheduledTaskMutation: Decodable, Sendable { public let task: ScheduledTaskRecord?; public let run: ScheduledTaskRun? }
private struct ScheduledTaskToggle: Encodable { let enabled: Bool? }
private struct ScheduledTaskErrorBody: Decodable { let error: String? }
public struct ScheduledTaskClientError: LocalizedError, Sendable { public let message: String; public init(message: String) { self.message = message }; public var errorDescription: String? { message } }
