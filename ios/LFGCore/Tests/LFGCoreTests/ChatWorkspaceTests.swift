import Foundation
import Testing
@testable import LFGCore

@MainActor @Suite struct ChatWorkspaceTests {
    private func host(_ id: String) -> ScheduledTaskHost {
        ScheduledTaskHost(id: id, name: id, baseURL: URL(string: "https://\(id).test")!, headers: ["Secret": "never-persist-this"])
    }
    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("workspace.json") }
    @Test func quickCreationUsesEmptyDefaultsAndPersistsWithoutHosts() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url)
        let first = try workspace.createDefault(hosts: []), second = try workspace.createDefault(hosts: [])
        #expect(ChatCreationDefaults.names.contains(first.session.name))
        #expect(first.session.name != second.session.name)
        #expect(first.session.model == nil)
        #expect(first.session.instructions.isEmpty && first.session.memory.isEmpty)
        #expect(first.host.id == ChatWorkspace.localHost.id)
        let restored = ChatWorkspace(url: url)
        #expect(restored.entries(hosts: []).count == 2)
        #expect(restored.record(first.session.id, fallback: first.host)?.name == first.session.name)
    }
    @Test func automaticNamesAvoidExistingNamesAndSurviveExhaustion() {
        let remaining = ChatCreationDefaults.names[0]
        #expect(ChatCreationDefaults.name(existing: Array(ChatCreationDefaults.names.dropFirst())) == remaining)
        let existing = ChatCreationDefaults.names.map { $0.uppercased() }
        #expect(!existing.contains(ChatCreationDefaults.name(existing: existing).uppercased()))
    }
    @Test func quickCreationPrefersConfiguredDefaultThenAnOnlineAlternative() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), pro = host("pro"), air = host("air")
        #expect(try workspace.createDefault(hosts: [air, pro], preferredHostID: pro.id).host.id == pro.id)
        #expect(try workspace.createDefault(hosts: [pro, air], preferredHostID: pro.id, knownOffline: [pro.id]).host.id == air.id)
        #expect(try workspace.createDefault(hosts: [air, pro], preferredHostID: pro.id, knownOffline: [air.id, pro.id]).host.id == pro.id)
    }
    @Test func richTranscriptSnapshotsReplacePartialRowsAndSurviveOfflineRestart() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), pro = host("pro")
        let record = try workspace.create(name: "Rich", instructions: "", memory: "Private", model: "", preferredHostID: nil)
        let legacy = [ChatMessageRecord(id: "user", sequence: 1, role: "user", text: "Check", ts: 1, requestID: "request"),
                      ChatMessageRecord(id: "assistant", sequence: 2, role: "assistant", text: "Concatenated old prose", ts: 2, requestID: "request")]
        var page = ChatHistoryPage(session: record, messages: legacy, hasMore: false)
        page.transcript = [.init(requestID: "request", sequence: 1, messages: [.init(id: "stream", text: "Checking")])]
        workspace.remember(page, on: pro)
        page.transcript = [.init(requestID: "request", sequence: 1, messages: [
            .init(id: "stream", text: "Checking files."),
            .init(id: "call", kind: "tool_use", text: "Read", toolUseId: "t", tool: .init(name: "Read", target: "/tmp/a")),
            .init(id: "result", role: "user", kind: "tool_result", text: "Found it", toolUseId: "t"),
            .init(id: "final", text: "Complete")], agents: [.init(id: "child", description: "Find callers", status: .running)],
            childTranscripts: ["child": [.init(id: "child-message", text: "Child progress")]])]
        workspace.remember(page, on: pro)
        try workspace.enqueue(record.id, text: "Queued follow-up", on: pro)
        let restored = ChatWorkspace(url: url), rows = restored.transcript(record.id)
        #expect(rows.map(\.text) == ["Check", "Checking files.", "Read", "Found it", "Complete", "Queued follow-up"])
        #expect(rows.filter { $0.id == "stream" }.count == 1)
        #expect(restored.childAgents(record.id).first?.status == .running)
        #expect(restored.childMessages(record.id, childID: "child").first?.text == "Child progress")
        #expect(restored.queued(for: record.id).count == 1)
    }
    @Test func preTranscriptCacheStillLoadsAndProjectsOrdinaryMessages() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url)
        let record = try workspace.create(name: "Old cache", instructions: "", memory: "", model: "", preferredHostID: nil)
        try workspace.enqueue(record.id, text: "Keep this", on: ChatWorkspace.localHost)
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json.removeValue(forKey: "transcript")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let restored = ChatWorkspace(url: url)
        #expect(restored.transcript(record.id).map(\.text) == ["Keep this"])
        #expect(restored.childAgents(record.id).isEmpty)
        try restored.enqueue(record.id, text: "Still works", on: ChatWorkspace.localHost)
        #expect(restored.queued(for: record.id).count == 2)
    }
    @Test func replacingLiveTurnPreservesOlderPagesAndRetiresRemovedPartialRows() {
        let old = ChatTranscriptTurn(requestID: "old", sequence: 1, messages: [.init(id: "old-row", text: "Older")])
        let partial = ChatTranscriptTurn(requestID: "new", sequence: 2, messages: [.init(id: "temporary", text: "Partial")])
        let complete = ChatTranscriptTurn(requestID: "new", sequence: 2, messages: [.init(id: "final", text: "Final")])
        let merged = ChatTranscriptProjection.merge([partial], [old, complete])
        #expect(merged.map(\.sequence) == [1, 2])
        #expect(merged.flatMap(\.messages).map(\.text) == ["Older", "Final"])
    }
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

extension ChatWorkspaceTests {
    @Test func enqueueKeepsACallersRequestIDOnce() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), pro = host("pro")
        let id = "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
        try workspace.enqueue(id, text: "shared link", on: pro, requestID: "share-1")
        try workspace.enqueue(id, text: "shared link", on: pro, requestID: "share-1")
        #expect(workspace.queued(for: id).map(\.id) == ["share-1"])
        #expect(workspace.deliveryLabel("share-1") == "Queued")
    }
}
