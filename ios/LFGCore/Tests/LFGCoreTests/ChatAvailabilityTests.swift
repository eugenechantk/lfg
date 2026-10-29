import Foundation
import Testing
@testable import LFGCore

@Suite struct ChatAvailabilityTests {
    private func host(_ id: String, origin: String? = nil) -> ScheduledTaskHost {
        ScheduledTaskHost(id: id, name: id, baseURL: URL(string: origin ?? "https://\(id).test")!, headers: ["Secret": "must-not-be-cached"])
    }
    private func chat(_ id: String) throws -> ChatSessionRecord {
        try JSONDecoder().decode(ChatSessionRecord.self, from: Data("""
        {"id":"\(id)","kind":"chat","name":"Scout","agent":"claude","instructions":"Be concise","memory":"Pip","summary":"","summaryThrough":0,"createdAt":1,"lastActivityAt":2,"revision":1,"state":"idle"}
        """.utf8))
    }
    @Test func cachedListsSurviveRelaunchAndOnlySuccessfulResponsesReplaceThem() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ChatListCache(url: dir.appendingPathComponent("chats.json"))
        let pro = host("pro"), air = host("air")
        var snapshot = ChatListSnapshot()
        snapshot.replace(try [chat("chat-pro")], on: pro)
        snapshot.replace(try [chat("chat-air")], on: air)
        try cache.save(snapshot)
        var restored = cache.load()
        #expect(restored.records(on: pro).map(\.id) == ["chat-pro"])
        #expect(restored.records(on: air).map(\.id) == ["chat-air"])
        // A failed response has no replacement. A successful empty response is authoritative.
        restored.replace([], on: pro)
        try cache.save(restored)
        #expect(cache.load().records(on: pro).isEmpty)
        #expect(cache.load().records(on: air).count == 1)
        let bytes = try String(contentsOf: cache.url, encoding: .utf8)
        #expect(!bytes.contains("must-not-be-cached"))
        #expect(!bytes.contains("Secret"))
    }
    @Test func removedAndReplacedHostsCannotExposeOldCachedRows() throws {
        let pro = host("pro"), air = host("air")
        var snapshot = ChatListSnapshot()
        snapshot.replace(try [chat("chat-pro")], on: pro)
        snapshot.replace(try [chat("chat-air")], on: air)
        #expect(snapshot.records(on: host("pro", origin: "https://different.test")).isEmpty)
        snapshot.retain(hosts: [pro])
        #expect(snapshot.records(on: air).isEmpty)
        #expect(snapshot.records(on: pro).count == 1)
    }
    @Test func upsertCreatedChatKeepsOtherRowsWithoutDuplicates() throws {
        let pro = host("pro")
        var snapshot = ChatListSnapshot()
        snapshot.replace(try [chat("old")], on: pro)
        snapshot.upsert(try chat("new"), on: pro)
        snapshot.upsert(try chat("new"), on: pro)
        #expect(Set(snapshot.records(on: pro).map(\.id)) == ["old", "new"])
        #expect(snapshot.records(on: pro).count == 2)
    }
    @Test func corruptCacheFallsBackToAnEmptyList() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cache = ChatListCache(url: dir.appendingPathComponent("chats.json"))
        try Data("broken".utf8).write(to: cache.url)
        #expect(cache.load().records(on: host("pro")).isEmpty)
    }
    @Test func healthyHostArrivesBeforeAnUnavailableSlowHost() async throws {
        let gate = DiscoveryGate()
        let pro = host("pro"), air = host("air")
        let record = try chat("chat-pro")
        let updates = ChatHostDiscovery.updates(hosts: [air, pro, pro]) { host in
            if host.id == "air" { await gate.wait(); throw URLError(.notConnectedToInternet) }
            return [record]
        }
        var iterator = updates.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.host.id == "pro")
        #expect(first?.sessions?.map(\.id) == ["chat-pro"])
        await gate.release()
        let second = await iterator.next()
        #expect(second?.host.id == "air")
        #expect(second?.sessions == nil)
        #expect(await iterator.next() == nil)
    }
    @Test func creationSelectsHealthyHostsAndRechecksRecoveredHosts() async {
        let pro = host("pro"), air = host("air")
        let chosen = await ChatHostDiscovery.availableHost(hosts: [air, pro], preferred: air, knownOffline: []) { host in
            if host.id == "air" { throw URLError(.cannotConnectToHost) }; return []
        }
        #expect(chosen?.id == "pro")
        let recovered = await ChatHostDiscovery.availableHost(hosts: [air], preferred: air, knownOffline: ["air"], load: { _ in [] })
        #expect(recovered?.id == "air")
        let unavailable = await ChatHostDiscovery.availableHost(hosts: [air, pro], preferred: air, knownOffline: []) { _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(unavailable == nil)
    }
    @Test func allOfflineAndEmptyFleetsFinishNormally() async {
        var failures = 0
        for await update in ChatHostDiscovery.updates(hosts: [host("pro"), host("air")], load: { _ in throw URLError(.notConnectedToInternet) }) {
            #expect(update.sessions == nil)
            failures += 1
        }
        #expect(failures == 2)
        var count = 0
        for await _ in ChatHostDiscovery.updates(hosts: [], load: { _ in [] }) { count += 1 }
        #expect(count == 0)
    }
}
private actor DiscoveryGate {
    private var open = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { if !open { await withCheckedContinuation { continuation = $0 } } }
    func release() { open = true; continuation?.resume(); continuation = nil }
}
