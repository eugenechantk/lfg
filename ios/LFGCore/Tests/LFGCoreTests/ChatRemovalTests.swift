import Foundation
import Testing
@testable import LFGCore

@MainActor @Suite struct ChatRemovalTests {
    private func host(_ id: String) -> ScheduledTaskHost {
        .init(id: id, name: id, baseURL: URL(string: "https://\(id).test")!)
    }
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("workspace.json")
    }
    @Test func hidingPersistsWithoutRemovingHistoryOrQueuedMessages() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url)
        let chat = try workspace.createDefault(hosts: [])
        try workspace.enqueue(chat.session.id, text: "Keep this queued", on: chat.host)
        try workspace.setHidden(chat.session.id, true)
        let restored = ChatWorkspace(url: url)
        #expect(restored.entries(hosts: []).isEmpty)
        #expect(restored.entries(hosts: [], includeHidden: true).map(\.session.id) == [chat.session.id])
        #expect(restored.queued(for: chat.session.id).map(\.text) == ["Keep this queued"])
        try restored.setHidden(chat.session.id, false)
        #expect(restored.entries(hosts: []).count == 1)
    }
    @Test func deletionPurgesPrivateCacheAndCannotBeUndoneByAnOldResponse() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), owner = host("pro")
        let chat = try workspace.create(name: "Private", instructions: "Private instructions", memory: "Private memory", model: "", preferredHostID: owner.id)
        let page = ChatHistoryPage(session: chat, messages: [.init(id: "message", sequence: 1, role: "user", text: "Private history", ts: 1, requestID: "r")], hasMore: false)
        workspace.remember(page, on: owner)
        try workspace.enqueue(chat.id, text: "Private queued message", on: owner)
        try workspace.setHidden(chat.id, true)
        try workspace.forgetDeleted(chat.id)
        workspace.remember(page, on: owner)
        workspace.accept([chat], on: owner, configured: [owner])
        let restored = ChatWorkspace(url: url)
        #expect(restored.isDeleted(chat.id))
        #expect(restored.entries(hosts: [owner], includeHidden: true).isEmpty)
        #expect(restored.messages(chat.id).isEmpty)
        #expect(restored.queued(for: chat.id).isEmpty)
        #expect(restored.record(chat.id, fallback: owner) == nil)
        #expect(throws: ChatClientError.self) { try restored.enqueue(chat.id, text: "Do not resurrect", on: owner) }
        let bytes = try String(contentsOf: url, encoding: .utf8)
        #expect(!bytes.contains("Private"))
    }
    @Test func onlyTheOwningHostCanReconcileADeletion() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), owner = host("pro"), other = host("air")
        let chat = try workspace.createDefault(hosts: [owner])
        workspace.remember(.init(session: chat.session, messages: [], hasMore: false), on: owner)
        workspace.remember(.init(session: chat.session, messages: [], hasMore: false), on: other)
        #expect(workspace.host(for: chat.session.id, hosts: [owner, other], fallback: other).id == owner.id)
        workspace.accept([chat.session], on: other, configured: [owner, other])
        workspace.accept([], on: other, configured: [owner, other], deletedIDs: [chat.session.id])
        #expect(!workspace.isDeleted(chat.session.id))
        workspace.accept([], on: owner, configured: [owner, other], deletedIDs: [chat.session.id])
        #expect(workspace.isDeleted(chat.session.id))
        #expect(workspace.entries(hosts: [owner, other]).isEmpty)
    }
    @Test func onlyUnattemptedDraftsCanBeDeletedWithoutAHost() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), owner = host("pro")
        let chat = try workspace.createDefault(hosts: [owner])
        #expect(workspace.canDeleteLocally(chat.session.id))
        await workspace.flush(hosts: [owner], transport: .init(available: { hosts, _ in hosts.first }, create: { _, _ in throw URLError(.cannotConnectToHost) }, send: { _, _ in }))
        #expect(!workspace.canDeleteLocally(chat.session.id))
    }
    @Test func fullHistoryRejectsANonOwningHost() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), owner = host("pro"), other = host("air")
        let chat = try workspace.createDefault(hosts: [owner]).session
        workspace.remember(.init(session: chat, messages: [], hasMore: false), on: owner)
        do {
            try await workspace.loadAllHistory(chat.id, on: other) { _ in
                Issue.record("A non-owner must not be contacted")
                return .init(session: chat, messages: [], hasMore: false)
            }
            Issue.record("Expected ownership rejection")
        } catch { #expect((error as? ChatClientError)?.status == 409) }
    }
    @Test func resourceHistoryLoadsEveryPageAndRetainsOlderFilesAndLinks() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), owner = host("pro")
        let chat = try workspace.createDefault(hosts: [owner]).session
        try await workspace.loadAllHistory(chat.id, on: owner) { before in
            if before == nil {
                return .init(session: chat, messages: [.init(id: "new", sequence: 4, role: "assistant", text: "[Latest report](/tmp/latest.pdf)", ts: 4, requestID: "new")], hasMore: true)
            }
            #expect(before == 4)
            return .init(session: chat, messages: [.init(id: "old", sequence: 2, role: "assistant", text: "[Earlier report](/tmp/earlier.pdf) and [Reference](https://example.com/reference)", ts: 2, requestID: "old")], hasMore: false)
        }
        let resources = TranscriptResourceIndex.collect(from: workspace.transcript(chat.id))
        #expect(resources.files.count == 2)
        #expect(resources.links.count == 1)
    }
    @Test func brokenPagingFailsWithoutDiscardingCachedResources() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let workspace = ChatWorkspace(url: url), owner = host("pro")
        let chat = try workspace.createDefault(hosts: [owner]).session
        do {
            try await workspace.loadAllHistory(chat.id, on: owner) { _ in
                .init(session: chat, messages: [.init(id: "same", sequence: 2, role: "assistant", text: "[Saved](/tmp/saved.pdf)", ts: 2, requestID: "same")], hasMore: true)
            }
            Issue.record("Expected a repeated cursor to fail")
        } catch { #expect(error is ChatClientError) }
        #expect(TranscriptResourceIndex.collect(from: workspace.transcript(chat.id)).files.count == 1)
    }
    @Test func listingRemainsCompatibleWithOlderHosts() throws {
        let listing = try JSONDecoder().decode(ChatSessionListing.self, from: Data(#"{"sessions":[]}"#.utf8))
        #expect(listing.sessions.isEmpty)
        #expect(listing.deletedIDs == nil)
    }
    @Test func deletionAlsoRemovesTheLegacyListCache() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let owner = host("pro"), cache = ChatListCache(url: url.deletingLastPathComponent().appendingPathComponent("legacy.json"))
        let workspace = ChatWorkspace(url: url, legacyCache: cache)
        let chat = try workspace.createDefault(hosts: [owner]).session
        var snapshot = ChatListSnapshot(); snapshot.replace([chat], on: owner); try cache.save(snapshot)
        try workspace.forgetDeleted(chat.id)
        #expect(cache.load().records(on: owner).isEmpty)
    }
}
