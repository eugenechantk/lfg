import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The chat UI uses the same records and client transport as the Tasks tab.
public typealias ChatJobRun = ScheduledTaskRun
public typealias ChatJobRecord = ScheduledTaskRecord
extension ScheduledTaskRecord {
    public var instructions: String { prompt }
    public var canPauseOrResume: Bool {
        cancelledAt == nil && (enabled || pausedAt != nil || (currentRun ?? lastRun)?.status == "queued")
    }
    public var deliveryLabel: String? {
        switch notificationState {
        case "pending": "Notification pending"
        case "accepted": "Notification sent"
        case "failed": "Notification failed"
        case "cancelled": "Notification cancelled"
        default: nil
        }
    }
}
public struct ChatJobDraft: Sendable {
    public var name = ""
    public var instructions = ""
    public var action = "notify"
    public var firstRun = Date().addingTimeInterval(3600)
    public var repeats = false
    public var everyMinutes = 60
    public var timezone = TimeZone.current.identifier
    public var notification = "requested"
    public var stopOnNotify = false
    public var requestID = UUID().uuidString
    public init() {}
    public init(job: ChatJobRecord) {
        name = job.name; instructions = job.instructions; action = job.action == "chat" ? "run" : job.action
        repeats = job.schedule.kind != "once"; everyMinutes = job.schedule.everyMinutes ?? 60
        timezone = job.schedule.timezone; notification = job.notification; stopOnNotify = job.stopOnNotify
        if let at = job.nextRunAt { firstRun = Date(timeIntervalSince1970: at / 1000) }
    }
    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && everyMinutes >= 1 && firstRun > Date() }
    public var schedule: ScheduledTaskSchedule { .init(kind: repeats ? "interval" : "once", timezone: timezone, at: ISO8601DateFormatter().string(from: firstRun), everyMinutes: repeats ? everyMinutes : nil) }
}
public struct ChatJobsClient: Sendable {
    public let host: ScheduledTaskHost
    private let client: ScheduledTasksClient
    public init(host: ScheduledTaskHost, session: URLSession = .shared) { self.host = host; client = .init(host: host, session: session) }
    public func list(chatId: String) async throws -> [ScheduledTaskRecord] { try await client.list(chatId: chatId) }
    public func create(chatId: String, draft: ChatJobDraft) async throws {
        struct Input: Encodable { let chatId: String; let name: String; let prompt: String; let action: String; let schedule: ScheduledTaskSchedule; let notification: String; let stopOnNotify: Bool; let requestID: String }
        let _: ScheduledTaskMutation = try await client.call("/api/scheduled-tasks", body: JSONEncoder().encode(Input(chatId: chatId, name: draft.name, prompt: draft.instructions, action: draft.action == "run" ? "chat" : draft.action, schedule: draft.schedule, notification: draft.notification, stopOnNotify: draft.stopOnNotify, requestID: draft.requestID)))
    }
    public func save(_ job: ScheduledTaskRecord, draft: ChatJobDraft, scheduleChanged: Bool) async throws {
        struct Input: Encodable { let revision: Int; let name: String; let prompt: String; let schedule: ScheduledTaskSchedule?; let notification: String; let stopOnNotify: Bool }
        let _: ScheduledTaskMutation = try await client.call("/api/scheduled-tasks/\(job.id)", body: JSONEncoder().encode(Input(revision: job.revision, name: draft.name, prompt: draft.instructions, schedule: scheduleChanged ? draft.schedule : nil, notification: draft.notification, stopOnNotify: draft.stopOnNotify)))
    }
    public func setEnabled(_ job: ScheduledTaskRecord, enabled: Bool) async throws { try await client.action(job.id, "", enabled: enabled, revision: job.revision) }
    public func cancel(_ id: String) async throws { try await client.action(id, "cancel") }
}
