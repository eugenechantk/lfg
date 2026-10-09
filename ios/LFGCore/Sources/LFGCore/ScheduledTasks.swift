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
    public var label: String {
        switch kind {
        case "interval": return "Every \(everyMinutes ?? 0) minutes"
        case "cron": return expression ?? "Custom cron"
        default: return "One time"
        }
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
    public var statusLabel: String {
        if let currentRun { return currentRun.statusLabel }
        if cancelledAt != nil { return "Cancelled" }
        if !canResume { return lastRun?.statusLabel ?? "Completed" }
        return enabled ? "Scheduled" : "Paused"
    }
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
    public var expression = "0 9 * * 1-5"
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
        intervalMinutes = String(task.schedule.everyMinutes ?? 60); expression = task.schedule.expression ?? "0 9 * * 1-5"
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cwd.hasPrefix("/") && TimeZone(identifier: timezone) != nil && (kind != "interval" || (Int(intervalMinutes) ?? 0) > 0) && (kind != "cron" || expression.split(separator: " ").count == 5)
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

public struct ScheduledTasksClient: Sendable {
    public let host: ScheduledTaskHost
    public init(host: ScheduledTaskHost) { self.host = host }
    public func call<T: Decodable & Sendable>(_ path: String, body: Data? = nil, as: T.Type = T.self) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: host.request(path, body: body))
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
    public func save(_ draft: ScheduledTaskDraft, id: String? = nil) async throws { let _: ScheduledTaskMutation = try await call("/api/scheduled-tasks" + (id.map { "/\($0)" } ?? ""), body: JSONEncoder().encode(draft.payload)) }
    public func action(_ id: String, _ action: String, enabled: Bool? = nil) async throws {
        let data = try JSONEncoder().encode(ScheduledTaskToggle(enabled: enabled))
        let _: ScheduledTaskMutation = try await call("/api/scheduled-tasks/\(id)" + (action.isEmpty ? "" : "/\(action)"), body: data)
    }
    public func runs(_ id: String, offset: Int = 0) async throws -> ScheduledTaskRuns { try await call("/api/scheduled-tasks/\(id)/runs?offset=\(offset)") }
}
public struct ScheduledTaskList: Decodable, Sendable { public let tasks: [ScheduledTaskRecord] }
public struct ScheduledTaskRuns: Decodable, Sendable { public let runs: [ScheduledTaskRun]; public let total: Int }
public struct ScheduledTaskMutation: Decodable, Sendable { public let task: ScheduledTaskRecord?; public let run: ScheduledTaskRun? }
private struct ScheduledTaskToggle: Encodable { let enabled: Bool? }
private struct ScheduledTaskErrorBody: Decodable { let error: String? }
public struct ScheduledTaskClientError: LocalizedError, Sendable { public let message: String; public init(message: String) { self.message = message }; public var errorDescription: String? { message } }
