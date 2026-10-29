import Foundation
import Observation
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
        if !offline, chat.state == "working" { return "Working…" }
        if !offline, chat.state == "blocked" { return chat.error ?? "Paused" }
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
    private func data(_ path: String, body: Data? = nil, timeout: TimeInterval = 30) async throws -> Data {
        try await resource("/api/sessions" + path, body: body, timeout: timeout)
    }
    private func resource(_ path: String, body: Data? = nil, timeout: TimeInterval = 30) async throws -> Data {
        var request = host.request(path, body: body); request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ChatClientError(message: (try? JSONDecoder().decode(ChatFailure.self, from: data))?.error ?? "Chat is unavailable on \(host.name). Update its LFG host to use chat.", status: (response as? HTTPURLResponse)?.statusCode)
        }
        return data
    }
    public func models() async throws -> ModelCatalogResponse {
        try JSONDecoder().decode(ModelCatalogResponse.self, from: await resource("/api/models"))
    }
    public func list() async throws -> [ChatSessionRecord] { try JSONDecoder().decode(ChatList.self, from: await data("/chats", timeout: 8)).sessions }
    public func requireClientChatIDs() async throws {
        struct Capability: Decodable { let clientChatIDs: Bool }
        do {
            let capability = try JSONDecoder().decode(Capability.self, from: await data("/chats/capabilities", timeout: 8))
            guard capability.clientChatIDs else { throw ChatClientError(message: "Update this host to sync locally created chats.", status: 426) }
        } catch let error as ChatClientError where error.status == 404 {
            throw ChatClientError(message: "Update this host to sync locally created chats.", status: 426)
        }
    }
    public func create(name: String, instructions: String, memory: String, model: String = "", id: String? = nil) async throws -> ChatSessionRecord {
        if id != nil { try await requireClientChatIDs() }
        struct Input: Encodable { let name: String; let instructions: String; let memory: String; let model: String; let id: String? }
        return try JSONDecoder().decode(ChatReply.self, from: await data("/chats", body: JSONEncoder().encode(Input(name: name, instructions: instructions, memory: memory, model: model, id: id)))).session
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

/// Last successful lists, scoped to a configured host and origin. Connectivity
/// failures never act as authoritative empty lists.
public struct ChatListSnapshot: Codable, Sendable, Equatable {
    private var lists: [String: [ChatSessionRecord]] = [:]
    public init() {}
    static func key(_ host: ScheduledTaskHost) -> String {
        var origin = URLComponents(url: host.baseURL, resolvingAgainstBaseURL: true)
        origin?.user = nil; origin?.password = nil; origin?.query = nil; origin?.fragment = nil
        return host.id + "|" + (origin?.string ?? "")
    }
    public func records(on host: ScheduledTaskHost) -> [ChatSessionRecord] { lists[Self.key(host)] ?? [] }
    public mutating func replace(_ records: [ChatSessionRecord], on host: ScheduledTaskHost) { lists[Self.key(host)] = records }
    public mutating func upsert(_ record: ChatSessionRecord, on host: ScheduledTaskHost) {
        var rows = records(on: host).filter { $0.id != record.id }
        rows.append(record); replace(rows, on: host)
    }
    public mutating func retain(hosts: [ScheduledTaskHost]) {
        let keys = Set(hosts.map(Self.key)); lists = lists.filter { keys.contains($0.key) }
    }
}

public struct ChatListCache: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: Self {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return Self(url: root.appendingPathComponent("LFG/ChatCache/lists-v1.json"))
    }
    public func load() -> ChatListSnapshot {
        guard let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(ChatListSnapshot.self, from: data) else { return .init() }
        return snapshot
    }
    public func save(_ snapshot: ChatListSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(snapshot).write(to: url, options: options)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct ChatHostListUpdate: Sendable {
    public let host: ScheduledTaskHost
    /// nil means unreachable; an empty array means a successful empty list.
    public let sessions: [ChatSessionRecord]?
}
public enum ChatHostDiscovery {
    public static func availableHost(hosts: [ScheduledTaskHost], preferred: ScheduledTaskHost?, knownOffline: Set<String>,
        load: @escaping @Sendable (ScheduledTaskHost) async throws -> [ChatSessionRecord] = { try await ChatSessionsClient(host: $0).list() }
    ) async -> ScheduledTaskHost? {
        var tried: String?
        if let preferred, !knownOffline.contains(preferred.id) {
            tried = preferred.id
            if (try? await load(preferred)) != nil, !Task.isCancelled { return preferred }
        }
        guard !Task.isCancelled else { return nil }
        for await update in updates(hosts: hosts.filter { $0.id != tried }, load: load) {
            if update.sessions != nil, !Task.isCancelled { return update.host }
        }
        return nil
    }
    public static func updates(hosts: [ScheduledTaskHost],
        load: @escaping @Sendable (ScheduledTaskHost) async throws -> [ChatSessionRecord] = { try await ChatSessionsClient(host: $0).list() }
    ) -> AsyncStream<ChatHostListUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: ChatHostListUpdate.self) { group in
                    var seen = Set<String>()
                    for host in hosts where seen.insert(host.id).inserted {
                        group.addTask { ChatHostListUpdate(host: host, sessions: try? await load(host)) }
                    }
                    for await update in group {
                        guard !Task.isCancelled else { group.cancelAll(); break }
                        continuation.yield(update)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

public struct ChatQueueOwner: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let origin: URL
    public init(_ host: ScheduledTaskHost) {
        id = host.id; name = host.name
        var components = URLComponents(url: host.baseURL, resolvingAgainstBaseURL: true)!
        components.user = nil; components.password = nil; components.query = nil; components.fragment = nil
        origin = components.url!
    }
    func matches(_ host: ScheduledTaskHost) -> Bool { id == host.id && origin == ChatQueueOwner(host).origin }
}
public struct ChatQueuedMessage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let chatID: String
    public let text: String
    public let timestamp: Double
    public var failure: String?
}
private struct ChatQueuedCreation: Codable, Equatable {
    var record: ChatSessionRecord
    let preferredHostID: String?
    var registered = false
    var failure: String?
}
private struct ChatWorkspaceState: Codable, Equatable {
    var snapshot = ChatListSnapshot()
    var creations: [ChatQueuedCreation] = []
    var owners: [String: ChatQueueOwner] = [:]
    var history: [String: [ChatMessageRecord]] = [:]
    var outbox: [ChatQueuedMessage] = []
}
public struct ChatWorkspaceEntry: Sendable {
    public let host: ScheduledTaskHost
    public let session: ChatSessionRecord
}
public struct ChatDeliveryTransport: Sendable {
    public var available: @Sendable ([ScheduledTaskHost], String?) async -> ScheduledTaskHost?
    public var create: @Sendable (ScheduledTaskHost, ChatSessionRecord) async throws -> ChatSessionRecord
    public var send: @Sendable (ScheduledTaskHost, ChatQueuedMessage) async throws -> Void
    public init(available: @escaping @Sendable ([ScheduledTaskHost], String?) async -> ScheduledTaskHost?,
                create: @escaping @Sendable (ScheduledTaskHost, ChatSessionRecord) async throws -> ChatSessionRecord,
                send: @escaping @Sendable (ScheduledTaskHost, ChatQueuedMessage) async throws -> Void) {
        self.available = available; self.create = create; self.send = send
    }
    public static let live = Self(available: { hosts, preferred in
        await ChatHostDiscovery.availableHost(hosts: hosts, preferred: hosts.first { $0.id == preferred }, knownOffline: []) { host in
            let client = ChatSessionsClient(host: host)
            try await client.requireClientChatIDs()
            return try await client.list()
        }
    }, create: { host, record in
        let accepted = try await ChatSessionsClient(host: host).create(name: record.name, instructions: record.instructions,
            memory: record.memory, model: record.model ?? "", id: record.id)
        guard accepted.id == record.id else { throw ChatClientError(message: "The host did not preserve this chat’s identity. Update the host before retrying.", status: 426) }
        return accepted
    }, send: { host, message in
        try await ChatSessionsClient(host: host).send(message.chatID, text: message.text, requestID: message.id)
    })
}

/// Client-owned draft identities, cached history and a durable ordered outbox.
/// Offline changes commit to disk before the UI acknowledges them. Once a
/// create request can leave the device, its owner is pinned across retries.
@MainActor @Observable public final class ChatWorkspace {
    public static let localHost = ScheduledTaskHost(id: "chat-local", name: "This device", baseURL: URL(string: "https://local.invalid")!)
    public static let shared = ChatWorkspace(url: ChatListCache.standard.url.deletingLastPathComponent().appendingPathComponent("workspace-v1.json"), seed: ChatListCache.standard.load())
    private var state: ChatWorkspaceState
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var activeChats = Set<String>()
    @ObservationIgnored private var readFailure: String?
    public init(url: URL, seed: ChatListSnapshot = .init()) {
        self.url = url
        if let data = try? Data(contentsOf: url), let restored = try? JSONDecoder().decode(ChatWorkspaceState.self, from: data) { state = restored }
        else {
            state = .init(); state.snapshot = seed
            if FileManager.default.fileExists(atPath: url.path) { readFailure = "The saved chat queue could not be read. Its file has been preserved." }
        }
    }
    private func commit(_ change: (inout ChatWorkspaceState) -> Void) throws {
        if let readFailure { throw ChatClientError(message: readFailure) }
        var next = state; change(&next)
        guard next != state else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(next).write(to: url, options: options)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        state = next
    }
    public func entries(hosts: [ScheduledTaskHost]) -> [ChatWorkspaceEntry] {
        var byID: [String: ChatWorkspaceEntry] = [:]
        for host in hosts {
            for record in state.snapshot.records(on: host) { byID[record.id] = .init(host: host, session: record) }
        }
        for pending in state.creations {
            let owner = state.owners[pending.record.id]
            let host = owner.flatMap { owner in hosts.first { owner.matches($0) } }
                ?? hosts.first { $0.id == pending.preferredHostID } ?? hosts.first ?? Self.localHost
            // A pinned owner removed from Settings cannot silently route elsewhere.
            if let owner, !owner.matches(host) { continue }
            byID[pending.record.id] = .init(host: host, session: pending.record)
        }
        return byID.values.sorted {
            $0.session.lastActivityAt == $1.session.lastActivityAt ? $0.session.id < $1.session.id : $0.session.lastActivityAt > $1.session.lastActivityAt
        }
    }
    public func accept(_ records: [ChatSessionRecord], on host: ScheduledTaskHost, configured hosts: [ScheduledTaskHost]) {
        try? commit { state in
            state.snapshot.retain(hosts: hosts)
            state.snapshot.replace(records, on: host)
            for record in records where state.owners[record.id] == nil || state.owners[record.id]?.matches(host) == true { state.owners[record.id] = .init(host) }
            let ids = Set(records.map(\.id))
            state.creations.removeAll { $0.registered && ids.contains($0.record.id) && state.owners[$0.record.id]?.matches(host) == true }
        }
    }
    public func create(name: String, instructions: String, memory: String, model: String, preferredHostID: String?) throws -> ChatSessionRecord {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              instructions.count <= 24000, memory.count <= 24000, model.count <= 120 else { throw ChatClientError(message: "Check the name and the length of this chat’s instructions and memory.") }
        let now = Date().timeIntervalSince1970 * 1000
        let record = ChatSessionRecord(id: "chat-" + UUID().uuidString.lowercased(), kind: "chat", name: name.trimmingCharacters(in: .whitespacesAndNewlines), agent: "claude", model: model.isEmpty ? nil : model,
            instructions: instructions, memory: memory, summary: "", summaryThrough: 0, createdAt: now, lastActivityAt: now, revision: 1, state: "idle", error: nil, lastMessage: nil)
        try commit { $0.creations.append(.init(record: record, preferredHostID: preferredHostID)) }
        return record
    }
    public func record(_ id: String, fallback host: ScheduledTaskHost) -> ChatSessionRecord? {
        state.creations.first { $0.record.id == id }?.record ?? state.snapshot.records(on: host).first { $0.id == id }
    }
    public func host(for id: String, hosts: [ScheduledTaskHost], fallback: ScheduledTaskHost) -> ScheduledTaskHost {
        if let owner = state.owners[id] { return hosts.first { owner.matches($0) } ?? (owner.matches(fallback) ? fallback : Self.localHost) }
        return fallback
    }
    public func isLocal(_ id: String) -> Bool { state.creations.contains { $0.record.id == id && !$0.registered } }
    public func creationFailure(_ id: String) -> String? { state.creations.first { $0.record.id == id }?.failure }
    public func queued(for id: String) -> [ChatQueuedMessage] { state.outbox.filter { $0.chatID == id } }
    public func deliveryLabel(_ requestID: String) -> String? {
        state.outbox.first { $0.id == requestID }.map { $0.failure == nil ? "Queued" : "Retry" }
    }
    public func messages(_ id: String) -> [ChatMessageRecord] {
        var messages = state.history[id] ?? []
        let existing = Set(messages.filter { $0.role == "user" }.map(\.requestID))
        var sequence = messages.map(\.sequence).max() ?? 0
        for pending in queued(for: id) where !existing.contains(pending.id) {
            sequence += 1
            messages.append(.init(id: "local-" + pending.id, sequence: sequence, role: "user", text: pending.text, ts: pending.timestamp, requestID: pending.id))
        }
        return messages
    }
    public func remember(_ page: ChatHistoryPage, on host: ScheduledTaskHost) {
        try? commit { state in
            state.snapshot.upsert(page.session, on: host); state.owners[page.session.id] = .init(host)
            let echoed = Set(page.messages.filter { $0.role == "user" }.map(\.requestID))
            let old = (state.history[page.session.id] ?? []).filter { !$0.id.hasPrefix("local-") || !echoed.contains($0.requestID) }
            state.history[page.session.id] = ChatHistoryMerge.merge(old, page.messages)
            state.outbox.removeAll { $0.chatID == page.session.id && echoed.contains($0.id) }
            if let index = state.creations.firstIndex(where: { $0.record.id == page.session.id }) { state.creations[index].record = page.session }
        }
    }
    public func enqueue(_ id: String, text: String, on host: ScheduledTaskHost) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 32000 else { throw ChatClientError(message: "Messages must contain 1–32,000 characters.") }
        let message = ChatQueuedMessage(id: UUID().uuidString, chatID: id, text: text, timestamp: Date().timeIntervalSince1970 * 1000)
        try commit { state in
            if !state.creations.contains(where: { $0.record.id == id }), state.owners[id] == nil { state.owners[id] = .init(host) }
            state.outbox.append(message)
            if let index = state.creations.firstIndex(where: { $0.record.id == id }) {
                state.creations[index].record.lastMessage = .init(text: text, role: "user")
                state.creations[index].record.lastActivityAt = message.timestamp
            }
        }
    }
    public func retry(_ id: String) {
        try? commit { state in
            for i in state.outbox.indices where state.outbox[i].chatID == id { state.outbox[i].failure = nil }
            for i in state.creations.indices where state.creations[i].record.id == id { state.creations[i].failure = nil }
        }
    }
    private func permanent(_ error: Error) -> String? {
        guard let error = error as? ChatClientError, let status = error.status, (400..<500).contains(status), ![408,409,429].contains(status) else { return nil }
        return error.message
    }
    public func flush(hosts: [ScheduledTaskHost], only chatID: String? = nil, transport: ChatDeliveryTransport = .live) async {
        guard !Task.isCancelled else { return }
        let ids = Set(state.creations.filter { !$0.registered && $0.failure == nil }.map { $0.record.id } + state.outbox.map(\.chatID))
        await withTaskGroup(of: Void.self) { group in
            for id in ids where (chatID == nil || chatID == id) && activeChats.insert(id).inserted {
                group.addTask { await self.flushAndRelease(id, hosts: hosts, transport: transport) }
            }
        }
    }
    private func flushAndRelease(_ id: String, hosts: [ScheduledTaskHost], transport: ChatDeliveryTransport) async {
        defer { activeChats.remove(id) }
        await flushChat(id, hosts: hosts, transport: transport)
    }
    private func flushChat(_ chatID: String, hosts: [ScheduledTaskHost], transport: ChatDeliveryTransport) async {
        for pending in state.creations where pending.record.id == chatID && !pending.registered && pending.failure == nil {
            let id = pending.record.id
            do {
                let host: ScheduledTaskHost
                if let owner = state.owners[id] {
                    guard let configured = hosts.first(where: { owner.matches($0) }) else { continue }
                    host = configured
                } else {
                    guard let available = await transport.available(hosts, pending.preferredHostID), !Task.isCancelled else { continue }
                    host = available
                    try commit { $0.owners[id] = .init(host) }
                }
                guard !Task.isCancelled else { return }
                let accepted = try await transport.create(host, pending.record)
                try commit { state in
                    state.snapshot.upsert(accepted, on: host)
                    if let i = state.creations.firstIndex(where: { $0.record.id == id }) { state.creations[i].registered = true; state.creations[i].record = accepted }
                }
            } catch {
                if let failure = permanent(error) { try? commit { state in if let i = state.creations.firstIndex(where: { $0.record.id == id }) { state.creations[i].failure = failure } } }
            }
        }
        var blocked = Set<String>()
        for pending in state.outbox where pending.chatID == chatID {
            let id = pending.chatID
            if blocked.contains(id) { continue }
            guard pending.failure == nil, !isLocal(id), let owner = state.owners[id], let host = hosts.first(where: { owner.matches($0) }) else { blocked.insert(id); continue }
            guard !Task.isCancelled else { return }
            do {
                try await transport.send(host, pending)
                try commit { state in
                    let sequence = (state.history[id] ?? []).map(\.sequence).max() ?? 0
                    if !(state.history[id] ?? []).contains(where: { $0.role == "user" && $0.requestID == pending.id }) {
                        state.history[id, default: []].append(.init(id: "local-" + pending.id, sequence: sequence + 1, role: "user", text: pending.text, ts: pending.timestamp, requestID: pending.id))
                    }
                    state.outbox.removeAll { $0.id == pending.id }
                }
            } catch {
                blocked.insert(id)
                if let failure = permanent(error) { try? commit { state in if let i = state.outbox.firstIndex(where: { $0.id == pending.id }) { state.outbox[i].failure = failure } } }
            }
        }
    }
}
