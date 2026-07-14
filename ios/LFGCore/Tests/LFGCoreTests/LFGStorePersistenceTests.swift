import XCTest
@testable import LFGCore

/// Real-seam verification for Track B Phase 4b: data written to a file-backed
/// LFGStore must survive a full store teardown + reopen (the cold-launch
/// "SessionStore hydrates from LFGStore" promise). The rest of LFGStoreTests
/// runs entirely in-memory, so this is the only test that exercises on-disk
/// persistence across process/store lifetimes.
final class LFGStorePersistenceTests: XCTestCase {
    func testDataSurvivesStoreReopenOnDisk() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lfg-store-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("lfg.sqlite").path

        let host = LFGCore.Host(url: "http://mac.local:8766", hostId: "machine-1", name: "Mac.local", displayName: "Studio", isDefault: true)
        let session = Session(
            sessionId: "s1",
            title: "Build store",
            agent: "claude",
            model: "opus",
            cwd: "/repo",
            assignedUser: "eugene@example.com",
            lastActivityAt: 2000,
            busy: false,
            last: SessionMessage(id: "m2", role: "assistant", kind: "text", text: "Done", ts: 2000),
            closed: false
        )
        let messages = [
            SessionMessage(id: "m1", role: "user", kind: "text", text: "Do it", ts: 1000),
            SessionMessage(id: "m2", role: "assistant", kind: "text", text: "Done", ts: 2000),
        ]

        // First "launch": open on disk, write, then drop the store to force a close.
        do {
            let store = try LFGStore(path: dbPath)
            try await store.upsertHosts([host])
            try await store.upsertSessions([session], hostId: host.url)
            try await store.appendMessages(sessionId: "s1", messages)
            try await store.setCursor(hostId: host.url, seq: 42)
            try await store.markSeen(sessionId: "s1", lastSeenMessageId: "m2", openedAt: 3000)
        }

        // Second "launch": reopen the same file — nothing above is in memory anymore.
        let reopened = try LFGStore(path: dbPath)
        let hosts = try await reopened.hosts()
        let sessions = try await reopened.sessions()
        let storedMessages = try await reopened.messages(sessionId: "s1")
        let cursor = try await reopened.cursor(hostId: host.url)
        let readState = try await reopened.readState(sessionId: "s1")

        XCTAssertEqual(hosts.count, 1, "host should persist across reopen")
        XCTAssertEqual(sessions.map(\.sessionId), ["s1"], "session should persist across reopen")
        XCTAssertEqual(storedMessages.map(\.id), ["m1", "m2"], "transcript should persist across reopen")
        XCTAssertEqual(cursor, 42, "journal cursor should persist across reopen")
        XCTAssertNotNil(readState, "read-state should persist across reopen")
    }
}
