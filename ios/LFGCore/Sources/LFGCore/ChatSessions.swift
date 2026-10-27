import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ChatSessionRecord: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var kind: String
    public var name: String
    public var agent: String
    public var model: String?
    public var instructions: String
    public var memory: String
    public var summary: String
    public var summaryThrough: Int
    public var createdAt: Double
    public var lastActivityAt: Double
    public var revision: Int
    public var state: String
    public var error: String?
    public var lastMessage: ChatMessagePreview?
    public var canSend: Bool { state != "working" }
    public var statusLabel: String { state == "working" ? "Working" : state == "blocked" ? "Paused" : "Ready" }
}
public struct ChatMessagePreview: Codable, Sendable, Hashable {
    public var text: String
    public var role: String
}
public enum ChatPresentation {
    public static let states = ["blocked", "working", "idle"]
    public static func title(for state: String) -> String {
        state == "working" ? "Working" : state == "blocked" ? "Paused" : "Ready"
    }
    public static func modelLabel(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return "Claude · Default" }
        return "Claude · \(model)"
    }
    public static func preview(_ chat: ChatSessionRecord, offline: Bool = false) -> String {
        if offline { return "Host offline" }
        if chat.state == "working" { return "Working…" }
        if chat.state == "blocked" { return chat.error ?? "Paused" }
        let text = chat.lastMessage?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Ready for your message" : String(text.prefix(180))
    }
    public static func activityLabel(_ timestamp: Double, now: Date = .now) -> String {
        let minutes = max(1, Int(max(0, now.timeIntervalSince1970 - timestamp / 1000) / 60))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return "\(minutes / 60)h" }
        return "\(minutes / 1440)d"
    }
    public static func matches(_ chat: ChatSessionRecord, query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || chat.name.localizedCaseInsensitiveContains(term)
            || (chat.lastMessage?.text.localizedCaseInsensitiveContains(term) ?? false)
    }
}
public struct ChatMessageRecord: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var sequence: Int
    public var role: String
    public var text: String
    public var ts: Double
    public var requestID: String
    public init(id: String, sequence: Int, role: String, text: String, ts: Double, requestID: String) {
        self.id = id; self.sequence = sequence; self.role = role; self.text = text; self.ts = ts; self.requestID = requestID
    }
}
public struct ChatHistoryPage: Decodable, Sendable {
    public var session: ChatSessionRecord
    public var messages: [ChatMessageRecord]
    public var hasMore: Bool
}
private struct ChatList: Decodable, Sendable { var sessions: [ChatSessionRecord] }
private struct ChatReply: Decodable, Sendable { var session: ChatSessionRecord }
private struct ChatFailure: Decodable { var error: String }
public struct ChatClientError: LocalizedError, Sendable {
    public let message: String
    public var status: Int? = nil
    public var errorDescription: String? { message }
}
public enum ChatHistoryMerge {
    public static func merge(_ existing: [ChatMessageRecord], _ incoming: [ChatMessageRecord]) -> [ChatMessageRecord] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in incoming { byID[message.id] = message }
        return byID.values.sorted { $0.sequence < $1.sequence }
    }
}
public struct ChatSessionsClient: Sendable {
    public let host: ScheduledTaskHost
    private let session: URLSession
    public init(host: ScheduledTaskHost, session: URLSession = .shared) { self.host = host; self.session = session }
    private func data(_ path: String, body: Data? = nil) async throws -> Data {
        try await resource("/api/sessions" + path, body: body)
    }
    private func resource(_ path: String, body: Data? = nil) async throws -> Data {
        var request = host.request(path, body: body); request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ChatClientError(message: (try? JSONDecoder().decode(ChatFailure.self, from: data))?.error ?? "Chat is unavailable on \(host.name). Update its LFG host to use chat.", status: (response as? HTTPURLResponse)?.statusCode)
        }
        return data
    }
    public func models() async throws -> ModelCatalogResponse {
        try JSONDecoder().decode(ModelCatalogResponse.self, from: await resource("/api/models"))
    }
    public func list() async throws -> [ChatSessionRecord] { try JSONDecoder().decode(ChatList.self, from: await data("/chats")).sessions }
    public func create(name: String, instructions: String, memory: String, model: String = "") async throws -> ChatSessionRecord {
        struct Input: Encodable { let name: String; let instructions: String; let memory: String; let model: String }
        return try JSONDecoder().decode(ChatReply.self, from: await data("/chats", body: JSONEncoder().encode(Input(name: name, instructions: instructions, memory: memory, model: model)))).session
    }
    public func detail(_ id: String, before: Int? = nil) async throws -> ChatHistoryPage {
        try JSONDecoder().decode(ChatHistoryPage.self, from: await data("/\(id)?limit=50" + (before.map { "&before=\($0)" } ?? "")))
    }
    public func send(_ id: String, text: String, requestID: String) async throws {
        struct Input: Encodable { let text: String; let requestID: String }
        _ = try await data("/\(id)/send", body: JSONEncoder().encode(Input(text: text, requestID: requestID)))
    }
    public func interrupt(_ id: String) async throws { _ = try await data("/\(id)/interrupt", body: Data("{}".utf8)) }
    public func save(_ record: ChatSessionRecord, name: String, instructions: String, memory: String, model: String) async throws -> ChatSessionRecord {
        struct Input: Encodable { let revision: Int; let name: String; let instructions: String; let memory: String; let model: String }
        let body = try JSONEncoder().encode(Input(revision: record.revision, name: name, instructions: instructions, memory: memory, model: model))
        return try JSONDecoder().decode(ChatReply.self, from: await data("/\(record.id)/settings", body: body)).session
    }
}
