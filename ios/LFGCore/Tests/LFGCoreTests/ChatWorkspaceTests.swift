import Foundation
import Testing
@testable import LFGCore

@MainActor @Suite struct ChatWorkspaceTests {
    private func host(_ id: String) -> ScheduledTaskHost {
        ScheduledTaskHost(id: id, name: id, baseURL: URL(string: "https://\(id).test")!, headers: ["Secret": "never-persist-this"])
    }
    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("workspace.json") }
    @Test func offlineCreationAndSeveralMessagesSurviveRestartWithoutAnyHost() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url)
        let record = try workspace.create(name: "Offline", instructions: "Be concise", memory: "Pip", model: "opus", preferredHostID: nil)
        try workspace.enqueue(record.id, text: "First", on: ChatWorkspace.localHost)
        try workspace.enqueue(record.id, text: "Second", on: ChatWorkspace.localHost)
        let restored = ChatWorkspace(url: url)
        #expect(restored.entries(hosts: []).first?.session.id == record.id)
        #expect(restored.record(record.id, fallback: ChatWorkspace.localHost)?.memory == "Pip")
        #expect(restored.messages(record.id).map(\.text) == ["First", "Second"])
        #expect(restored.queued(for: record.id).count == 2)
        #expect(restored.isLocal(record.id))
    }
    @Test func reconnectRegistersSameChatThenDeliversInOrderAndReconcilesEchoes() async throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), air = host("air")
        let record = try workspace.create(name: "Offline", instructions: "Short", memory: "Seven", model: "", preferredHostID: "pro")
        try workspace.enqueue(record.id, text: "First", on: air)
        try workspace.enqueue(record.id, text: "Second", on: air)
        let receipts = DeliveryReceipts()
        await workspace.flush(hosts: [air], transport: receipts.transport)
        let calls = await receipts.calls
        #expect(calls.map(\.0) == ["create", "First", "Second"])
        #expect(calls.allSatisfy { $0.1 == "air" && $0.2 == record.id })
        #expect(workspace.queued(for: record.id).isEmpty)
        #expect(workspace.messages(record.id).map(\.text) == ["First", "Second"])
        let sent = await receipts.sent
        let page = ChatHistoryPage(session: record, messages: [ChatMessageRecord(id: "server-user", sequence: 1, role: "user", text: "First", ts: 1, requestID: sent[0].id)], hasMore: false)
        workspace.remember(page, on: air)
        #expect(workspace.messages(record.id).filter { $0.requestID == sent[0].id }.count == 1)
        #expect(!workspace.isLocal(record.id))
        let bytes = try String(contentsOf: url, encoding: .utf8)
        #expect(!bytes.contains("never-persist-this"))
    }
    @Test func lostCreateAndSendResponsesPinOwnerAndKeepStableReceipts() async throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), pro = host("pro"), air = host("air")
        let record = try workspace.create(name: "Stable", instructions: "", memory: "", model: "", preferredHostID: "pro")
        try workspace.enqueue(record.id, text: "Hello", on: pro)
        let receipts = DeliveryReceipts(); await receipts.setFailures(create: true, send: true)
        await workspace.flush(hosts: [pro, air], transport: receipts.transport)
        let restored = ChatWorkspace(url: url)
        await restored.flush(hosts: [air], transport: receipts.transport)
        #expect(await receipts.calls.count == 1) // Never retry this uncertain create on Air.
        await receipts.setFailures(create: false, send: true)
        await restored.flush(hosts: [pro, air], transport: receipts.transport)
        let firstRequest = restored.queued(for: record.id).first?.id
        await receipts.setFailures(create: false, send: false)
        await restored.flush(hosts: [pro, air], transport: receipts.transport)
        let sent = await receipts.sent
        #expect(sent.count == 2)
        #expect(Set(sent.map(\.id)) == [firstRequest!])
        #expect(await receipts.calls.allSatisfy { $0.1 == "pro" && $0.2 == record.id })
    }
    @Test func permanentFailureKeepsMessageEditableAndRetryable() async throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), pro = host("pro")
        let record = try workspace.create(name: "Retry", instructions: "", memory: "", model: "", preferredHostID: "pro")
        let receipts = DeliveryReceipts()
        await workspace.flush(hosts: [pro], transport: receipts.transport)
        try workspace.enqueue(record.id, text: "Keep this text", on: pro)
        await receipts.setPermanent(true)
        await workspace.flush(hosts: [pro], transport: receipts.transport)
        let id = workspace.queued(for: record.id)[0].id
        #expect(workspace.deliveryLabel(id) == "Retry")
        try workspace.enqueue(record.id, text: "Keep composing", on: pro)
        #expect(workspace.messages(record.id).map(\.text) == ["Keep this text", "Keep composing"])
        workspace.retry(record.id); await receipts.setPermanent(false)
        await workspace.flush(hosts: [pro], transport: receipts.transport)
        #expect(workspace.queued(for: record.id).isEmpty)
    }
    @Test func canonicalEchoBeforeSendResponseDoesNotDuplicateHistory() async throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), pro = host("pro")
        let record = try workspace.create(name: "Echo", instructions: "", memory: "", model: "", preferredHostID: "pro")
        try workspace.enqueue(record.id, text: "Once", on: pro)
        let transport = ChatDeliveryTransport(available: { hosts, _ in hosts.first }, create: { _, record in record }, send: { _, message in
            await MainActor.run {
                workspace.remember(.init(session: record, messages: [.init(id: "canonical", sequence: 1, role: "user", text: message.text, ts: 1, requestID: message.id)], hasMore: false), on: pro)
            }
        })
        await workspace.flush(hosts: [pro], transport: transport)
        #expect(workspace.messages(record.id).map(\.id) == ["canonical"])
    }
    @Test func corruptQueueIsPreservedInsteadOfOverwritten() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("incomplete but valuable".utf8); try original.write(to: url)
        let workspace = ChatWorkspace(url: url)
        #expect(throws: ChatClientError.self) {
            _ = try workspace.create(name: "New", instructions: "", memory: "", model: "", preferredHostID: nil)
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(workspace.entries(hosts: []).isEmpty)
    }
    @Test func stalledChatDoesNotBlockOtherChatsOrDuplicateConcurrentFlushes() async throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), pro = host("pro")
        let blocked = try workspace.create(name: "Blocked", instructions: "", memory: "", model: "", preferredHostID: "pro")
        let healthy = try workspace.create(name: "Healthy", instructions: "", memory: "", model: "", preferredHostID: "pro")
        try workspace.enqueue(blocked.id, text: "Blocked message", on: pro)
        try workspace.enqueue(healthy.id, text: "Healthy message", on: pro)
        let gate = DeliveryGate(blockedID: blocked.id)
        let transport = ChatDeliveryTransport(available: { hosts, _ in hosts.first }, create: { _, record in
            await gate.create(record)
        }, send: { _, message in await gate.send(message) })
        let first = Task { await workspace.flush(hosts: [pro], transport: transport) }
        // Wait for both independent transports. This would deadlock under global serialization.
        for _ in 0..<500 where !(await gate.healthySent) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await gate.healthySent)
        await workspace.flush(hosts: [pro], transport: transport)
        #expect(await gate.created.filter { $0 == blocked.id }.count == 1)
        await gate.release(); await first.value
        #expect(workspace.queued(for: blocked.id).isEmpty)
        #expect(await gate.sent.count == 2)
    }

}
private actor DeliveryReceipts {
    var calls: [(String, String, String)] = []
    var sent: [ChatQueuedMessage] = []
    var failCreate = false, failSend = false, permanent = false
    nonisolated var transport: ChatDeliveryTransport {
        .init(available: { hosts, preferred in hosts.first { $0.id == preferred } ?? hosts.first }, create: { host, record in try await self.create(host, record) }, send: { host, message in try await self.send(host, message) })
    }
    func setFailures(create: Bool, send: Bool) { failCreate = create; failSend = send }
    func setPermanent(_ value: Bool) { permanent = value }
    func create(_ host: ScheduledTaskHost, _ record: ChatSessionRecord) throws -> ChatSessionRecord {
        calls.append(("create", host.id, record.id))
        if failCreate { throw URLError(.timedOut) }
        return record
    }
    func send(_ host: ScheduledTaskHost, _ message: ChatQueuedMessage) throws {
        calls.append((message.text, host.id, message.chatID)); sent.append(message)
        if permanent { throw ChatClientError(message: "Rejected by host", status: 400) }
        if failSend { throw URLError(.networkConnectionLost) }
    }
}

private actor DeliveryGate {
    let blockedID: String
    var created: [String] = []
    var sent: [String] = []
    var continuation: CheckedContinuation<Void, Never>?
    var healthySent: Bool { !sent.isEmpty }
    init(blockedID: String) { self.blockedID = blockedID }
    func create(_ record: ChatSessionRecord) async -> ChatSessionRecord {
        created.append(record.id)
        if record.id == blockedID { await withCheckedContinuation { continuation = $0 } }
        return record
    }
    func send(_ message: ChatQueuedMessage) { sent.append(message.id) }
    func release() { continuation?.resume(); continuation = nil }
}
