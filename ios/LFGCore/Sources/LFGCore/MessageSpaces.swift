import Foundation

public struct MessageSpace: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var spaceID: String?
    public var agent: String
    public var runID: String?
    public var powerState: String
    public var messages: [SpaceUserMessage]
    public var pending: String?
    public var error: String?
    public var createdAt: Double
    public var canSend: Bool { spaceID != nil && pending == nil && !["stopped", "suspended", "unavailable"].contains(powerState) }
}
public struct SpaceUserMessage: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var text: String
    public var date: Double
}
public struct SpaceAgentEvent: Codable, Identifiable, Sendable, Hashable {
    public var seq: Int
    public var kind: String
    public var text: String?
    public var summary: String?
    public var ts_ms: Double?
    public var category: String?
    public var id: Int { seq }
    public var displayText: String { text ?? summary ?? kind.replacingOccurrences(of: "_", with: " ") }
    public var isVisible: Bool { category != "hidden" && kind != "thought" && !displayText.isEmpty }
}
public struct MessageSpaceList: Decodable, Sendable { public var spaces: [MessageSpace] }
public struct MessageSpaceReply: Decodable, Sendable {
    public var space: MessageSpace
    public var events: [SpaceAgentEvent]?
    public var cursor: Int?
    public var status: String?
}
public struct SpaceBrowserReply: Decodable, Sendable {
    public var imageBase64: String?
    public var mimeType: String?
    public var text: String?
}
public struct MessageSpaceError: LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private struct MessageSpaceFailure: Decodable { let error: String }

public struct MessageSpacesClient: Sendable {
    public let host: ScheduledTaskHost
    private let session: URLSession
    public init(host: ScheduledTaskHost, session: URLSession = .shared) { self.host = host; self.session = session }
    public func call<T: Decodable & Sendable>(_ path: String, body: Data? = nil, as: T.Type = T.self) async throws -> T {
        var request = host.request("/api/message" + path, body: body)
        request.timeoutInterval = body == nil ? 60 : 700
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(MessageSpaceFailure.self, from: data))?.error
                ?? "Message is unavailable on this host. Start a host that supports Cua Spaces."
            throw MessageSpaceError(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    public func list() async throws -> [MessageSpace] { try await call("/spaces", as: MessageSpaceList.self).spaces }
    public func create(name: String, agent: String) async throws -> MessageSpace {
        struct Payload: Encodable { let name: String; let agent: String }
        return try await call("/spaces", body: JSONEncoder().encode(Payload(name: name, agent: agent)), as: MessageSpaceReply.self).space
    }
    public func detail(_ id: String, cursor: Int) async throws -> MessageSpaceReply {
        try await call("/spaces/\(id)?cursor=\(cursor)")
    }
    public func send(_ id: String, text: String, requestID: String) async throws -> MessageSpace {
        struct Payload: Encodable { let text: String; let requestID: String }
        return try await call("/spaces/\(id)/messages", body: JSONEncoder().encode(Payload(text: text, requestID: requestID)), as: MessageSpaceReply.self).space
    }
    public func power(_ id: String, action: String) async throws -> MessageSpace {
        struct Payload: Encodable { let action: String }
        return try await call("/spaces/\(id)/power", body: JSONEncoder().encode(Payload(action: action)), as: MessageSpaceReply.self).space
    }
    public func interrupt(_ id: String) async throws {
        struct Result: Decodable, Sendable {}
        let _: Result = try await call("/spaces/\(id)/interrupt", body: Data("{}".utf8))
    }
    public func browser(_ id: String, action: String, values: [String: String] = [:]) async throws -> SpaceBrowserReply {
        var payload = values; payload["action"] = action
        return try await call("/spaces/\(id)/browser", body: JSONEncoder().encode(payload))
    }
}

public struct SpaceTranscriptRow: Identifiable, Sendable, Equatable {
    public var id: String
    public var text: String
    public var date: Double
    public var user: Bool
    public var activity: Bool
}

public enum MessageSpaceTranscript {
    /// ACP emits text deltas. Join them into messages and keep raw tool results
    /// out of the conversation: they can contain entire accessibility trees.
    public static func rows(messages: [SpaceUserMessage], events: [SpaceAgentEvent]) -> [SpaceTranscriptRow] {
        var rows: [SpaceTranscriptRow] = []
        var chunk: SpaceTranscriptRow?
        func flush() {
            if let chunk, !chunk.text.isEmpty { rows.append(chunk) }
            chunk = nil
        }
        for event in events.sorted(by: { $0.seq < $1.seq }) {
            switch event.kind {
            case "message":
                guard event.category != "hidden", let text = event.text, !text.isEmpty else { continue }
                if chunk != nil { chunk?.text += text }
                else { chunk = SpaceTranscriptRow(id: "event-\(event.seq)", text: text, date: event.ts_ms ?? 0, user: false, activity: false) }
            case "tool_call":
                flush()
                let title = (event.summary ?? event.text ?? "").lowercased()
                let label: String
                if title.contains("launch") { label = "Opening an app" }
                else if title.contains("click") { label = "Clicking" }
                else if title.contains("type") || title.contains("key") { label = "Using the keyboard" }
                else if title.contains("bash") || title.contains("shell") { label = "Running a command" }
                else if title.contains("browser") || title.contains("window") || title.contains("accessibility") { label = "Inspecting the browser" }
                else { label = "Using tools" }
                rows.append(SpaceTranscriptRow(id: "event-\(event.seq)", text: label, date: event.ts_ms ?? 0, user: false, activity: true))
            case "error":
                flush()
                rows.append(SpaceTranscriptRow(id: "event-\(event.seq)", text: String(event.displayText.prefix(2000)), date: event.ts_ms ?? 0, user: false, activity: true))
            case "turn_started", "turn_ended": flush()
            default: break
            }
        }
        flush()
        rows += messages.map { SpaceTranscriptRow(id: $0.id, text: $0.text, date: $0.date, user: true, activity: false) }
        return rows.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
