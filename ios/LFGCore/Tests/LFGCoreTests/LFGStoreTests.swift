import XCTest
@testable import LFGCore

final class LFGStoreTests: XCTestCase {
    func testMigrationCreatesV1TablesOnFreshDatabase() async throws {
        let store = try LFGStore.inMemory()
        let tables = try await store.tableNames()

        XCTAssertTrue(tables.isSuperset(of: [
            "hosts",
            "sessions",
            "messages",
            "outbox",
            "cursors",
            "readState",
        ]))
    }

    func testUpsertsAreIdempotent() async throws {
        let store = try LFGStore.inMemory()
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

        try await ingest(host: host, session: session, messages: messages, into: store)
        let first = try await Snapshot(store)

        try await ingest(host: host, session: session, messages: messages, into: store)
        let second = try await Snapshot(store)

        XCTAssertEqual(first, second)
    }

    func testPartialSessionUpdateDoesNotNullExistingColumns() async throws {
        let store = try LFGStore.inMemory()
        let full = Session(
            sessionId: "s1",
            title: "Original title",
            agent: "claude",
            model: "opus",
            cwd: "/repo",
            assignedUser: "eugene@example.com",
            lastActivityAt: 1000,
            busy: false,
            last: SessionMessage(id: "m1", role: "assistant", kind: "text", text: "Original preview", ts: 1000),
            closed: true
        )
        try await store.upsertSessions([full], hostId: "http://old-host")

        let partialJSON = #"{"sessionId":"s1","busy":true}"#.data(using: .utf8)!
        let partial = try JSONDecoder().decode(Session.self, from: partialJSON)
        try await store.upsertSessions([partial], hostId: "http://new-host")

        let sessions = try await store.sessions()
        let stored = try XCTUnwrap(sessions.first)
        XCTAssertEqual(stored.hostId, "http://new-host")
        XCTAssertEqual(stored.title, "Original title")
        XCTAssertEqual(stored.agent, "claude")
        XCTAssertEqual(stored.model, "opus")
        XCTAssertEqual(stored.cwd, "/repo")
        XCTAssertEqual(stored.assignedUser, "eugene@example.com")
        XCTAssertEqual(stored.lastActivityAt, 1000)
        XCTAssertEqual(stored.lastMessageId, "m1")
        XCTAssertEqual(stored.lastMessagePreview, "Original preview")
        XCTAssertEqual(stored.lastMessageRole, "assistant")
        XCTAssertTrue(stored.closed)
        XCTAssertEqual(stored.busy, true)
    }

    func testMessagesAreBoundedPerSessionAtCap() async throws {
        let store = try LFGStore.inMemory()
        try await store.upsertSessions([Session(sessionId: "s1", title: "One"), Session(sessionId: "s2", title: "Two")], hostId: "host")

        let overflow = (0..<(LFGStore.messageLimit + 5)).map { i in
            SessionMessage(id: "m\(i)", role: "assistant", kind: "text", text: "message \(i)", ts: Double(i))
        }
        try await store.appendMessages(sessionId: "s1", overflow)
        try await store.appendMessages(sessionId: "s2", [
            SessionMessage(id: "a", role: "user", kind: "text", text: "kept", ts: 1),
        ])

        let s1Messages = try await store.messages(sessionId: "s1")
        let s2Messages = try await store.messages(sessionId: "s2")

        XCTAssertEqual(s1Messages.count, LFGStore.messageLimit)
        XCTAssertEqual(s1Messages.first?.id, "m5")
        XCTAssertEqual(s1Messages.last?.id, "m204")
        XCTAssertEqual(s2Messages.map(\.id), ["a"])
    }

    func testCursorOnlyMovesForward() async throws {
        let store = try LFGStore.inMemory()

        try await store.setCursor(hostId: "host", seq: 10)
        try await store.setCursor(hostId: "host", seq: 8)
        try await store.setCursor(hostId: "host", seq: 15)

        let finalCursor = try await store.cursor(hostId: "host")
        XCTAssertEqual(finalCursor, 15)
    }

    func testReadStateRoundTrip() async throws {
        let store = try LFGStore.inMemory()

        try await store.markSeen(sessionId: "s1", lastSeenMessageId: "m9", openedAt: 1234)

        let readState = try await store.readState(sessionId: "s1")
        XCTAssertEqual(readState, LFGReadStateSnapshot(sessionId: "s1", lastSeenMessageId: "m9", openedAt: 1234))
    }

    func testOutboxRoundTripAndTerminalStates() async throws {
        let store = try LFGStore.inMemory()

        try await store.enqueueOutbox(clientId: "c1", sessionId: "s1", hostId: "h1", text: "hello")
        var pending = try await store.pendingOutbox()
        XCTAssertEqual(pending.map(\.clientId), ["c1"])
        XCTAssertEqual(pending[0].sessionId, "s1")
        XCTAssertEqual(pending[0].hostId, "h1")
        XCTAssertEqual(pending[0].text, "hello")
        XCTAssertEqual(pending[0].state, "pending")

        try await store.markOutbox(clientId: "c1", state: "sent")
        pending = try await store.pendingOutbox()
        XCTAssertEqual(pending.map(\.state), ["sent"])

        try await store.markOutbox(clientId: "c1", state: "failed")
        let failedPending = try await store.pendingOutbox()
        let failedRow = try await store.outbox(clientId: "c1")
        XCTAssertTrue(failedPending.isEmpty)
        XCTAssertEqual(failedRow?.state, "failed")

        try await store.enqueueOutbox(clientId: "c1", sessionId: "s1", hostId: "h1", text: "retry")
        let retryPending = try await store.pendingOutbox()
        XCTAssertEqual(retryPending.map(\.text), ["retry"])

        try await store.markOutbox(clientId: "c1", state: "delivered")
        let deliveredRow = try await store.outbox(clientId: "c1")
        XCTAssertNil(deliveredRow)
    }

    /// `failed` must not be a black hole. `pendingOutbox` hides those rows on
    /// purpose, but the replay paths read `retryableOutbox` so a host coming back
    /// can re-attempt them — and so a relaunch still restores the bubble instead
    /// of losing the message with no trace in the UI.
    func testRetryableOutboxIncludesFailedButNotDelivered() async throws {
        let store = try LFGStore.inMemory()

        try await store.enqueueOutbox(clientId: "c1", sessionId: "s1", hostId: "h1", text: "queued")
        try await store.enqueueOutbox(clientId: "c2", sessionId: "s1", hostId: "h1", text: "burned")
        try await store.enqueueOutbox(clientId: "c3", sessionId: "s1", hostId: "h1", text: "gone")

        try await store.markOutbox(clientId: "c2", state: "failed")
        try await store.markOutbox(clientId: "c3", state: "delivered")

        let stillPending = try await store.pendingOutbox()
        XCTAssertEqual(stillPending.map(\.clientId), ["c1"])

        let retryable = try await store.retryableOutbox()
        XCTAssertEqual(retryable.map(\.clientId), ["c1", "c2"])
        XCTAssertEqual(retryable.first { $0.clientId == "c2" }?.state, "failed")
        XCTAssertEqual(retryable.first { $0.clientId == "c2" }?.text, "burned")
    }

    func testDeleteOutbox() async throws {
        let store = try LFGStore.inMemory()

        try await store.enqueueOutbox(clientId: "c1", sessionId: "s1", hostId: "h1", text: "hello")
        try await store.deleteOutbox(clientId: "c1")

        let pending = try await store.pendingOutbox()
        let row = try await store.outbox(clientId: "c1")
        XCTAssertTrue(pending.isEmpty)
        XCTAssertNil(row)
    }

    func testObservationsEmitOnRelevantWrites() async throws {
        let store = try LFGStore.inMemory()
        let sessionProbe = StreamProbe(store.observeSessions())
        let messageProbe = StreamProbe(store.observeMessages(sessionId: "s1"))

        let initialSessions = try await sessionProbe.nextValue()
        XCTAssertEqual(initialSessions.count, 0)
        let initialMessages = try await messageProbe.nextValue()
        XCTAssertEqual(initialMessages.count, 0)

        try await store.upsertSessions([
            Session(sessionId: "s1", title: "Observed", agent: "codex", lastActivityAt: 1),
        ], hostId: "host")
        let observedSessions = try await sessionProbe.nextValue()
        XCTAssertEqual(observedSessions.map(\.sessionId), ["s1"])

        try await store.appendMessages(sessionId: "s1", [
            SessionMessage(id: "m1", role: "assistant", kind: "text", text: "hello", ts: 1),
        ])
        let observedMessages = try await messageProbe.nextValue()
        XCTAssertEqual(observedMessages.map(\.id), ["m1"])
    }

    /// A host fetch is a complete snapshot of that host's live sessions, so a
    /// session the snapshot omits has ended and must not survive in the store.
    ///
    /// Left to accumulate, these rows are what `hydrateFromStore` seeds
    /// `lastSessionsByHost` from at a cold launch, and when the owning host is
    /// unreachable no live fetch ever overwrites that seed — so every session the
    /// host has ever had comes back onto the list, some of them frozen at
    /// `busy: true`. See
    /// `.claude/diagnosis-offline-host-resurrects-dead-sessions-20260811.md`.
    func testReplaceSessionsDropsSessionsMissingFromTheSnapshot() async throws {
        let store = try LFGStore.inMemory()
        try await store.replaceSessions([
            Session(sessionId: "old", title: "Ended weeks ago", lastActivityAt: 1, busy: true),
            Session(sessionId: "live", title: "Still running", lastActivityAt: 2, busy: true),
        ], hostId: "air")

        try await store.replaceSessions([
            Session(sessionId: "live", title: "Still running", lastActivityAt: 3, busy: true),
        ], hostId: "air")

        let sessions = try await store.sessions()
        XCTAssertEqual(sessions.map(\.sessionId), ["live"])
    }

    /// The delete is scoped to the fetching host. `~/.claude/projects` is synced,
    /// so two hosts can report the same session id and the row's `hostId` follows
    /// whichever fetch landed last — one host's snapshot must never evict another
    /// host's sessions.
    func testReplaceSessionsOnlyEvictsWithinTheSameHost() async throws {
        let store = try LFGStore.inMemory()
        try await store.replaceSessions([Session(sessionId: "onPro", title: "Pro", lastActivityAt: 1)], hostId: "pro")
        try await store.replaceSessions([Session(sessionId: "onAir", title: "Air", lastActivityAt: 2)], hostId: "air")

        try await store.replaceSessions([], hostId: "air")

        let sessions = try await store.sessions()
        XCTAssertEqual(sessions.map(\.sessionId), ["onPro"])
    }

    /// Dropping a session must not take its cached transcript or read mark with
    /// it: the session may well come back on the host's next poll, and re-fetching
    /// history it already had (or re-showing messages already read) is a
    /// regression the user would see immediately.
    func testReplaceSessionsKeepsTranscriptAndReadStateForEvictedSessions() async throws {
        let store = try LFGStore.inMemory()
        try await store.replaceSessions([Session(sessionId: "s1", title: "One", lastActivityAt: 1)], hostId: "air")
        try await store.appendMessages(sessionId: "s1", [
            SessionMessage(id: "m1", role: "assistant", kind: "text", text: "hello", ts: 1),
        ])
        try await store.markSeen(sessionId: "s1", lastSeenMessageId: "m1", openedAt: 10)

        try await store.replaceSessions([], hostId: "air")

        let sessions = try await store.sessions()
        let messages = try await store.messages(sessionId: "s1")
        let read = try await store.readState(sessionId: "s1")
        XCTAssertEqual(sessions.count, 0)
        XCTAssertEqual(messages.map(\.id), ["m1"])
        XCTAssertEqual(read?.lastSeenMessageId, "m1")
    }
}

private extension LFGStoreTests {
    func ingest(host: LFGCore.Host, session: Session, messages: [SessionMessage], into store: LFGStore) async throws {
        try await store.upsertHosts([host])
        try await store.upsertSessions([session], hostId: host.url)
        try await store.appendMessages(sessionId: "s1", messages)
        try await store.setCursor(hostId: host.url, seq: 42)
        try await store.markSeen(sessionId: "s1", lastSeenMessageId: "m2", openedAt: 3000)
    }

    struct Snapshot: Hashable {
        var hosts: [LFGStoredHost]
        var sessions: [LFGStoredSession]
        var messages: [LFGStoredMessage]
        var cursor: Int64?
        var readState: LFGReadStateSnapshot?

        init(_ store: LFGStore) async throws {
            hosts = try await store.hosts()
            sessions = try await store.sessions()
            messages = try await store.messages(sessionId: "s1")
            cursor = try await store.cursor(hostId: "http://mac.local:8766")
            readState = try await store.readState(sessionId: "s1")
        }
    }

    actor StreamProbe<Element: Sendable> {
        private var values: [Element] = []
        private var streamError: Error?
        private var finished = false
        private var readIndex = 0

        init(_ stream: AsyncThrowingStream<Element, Error>) {
            Task { await self.consume(stream) }
        }

        private func consume(_ stream: AsyncThrowingStream<Element, Error>) async {
            do {
                for try await value in stream { values.append(value) }
            } catch {
                streamError = error
            }
            finished = true
        }

        func nextValue(timeout seconds: TimeInterval = 2) async throws -> Element {
            let deadline = Date().addingTimeInterval(seconds)
            while true {
                if readIndex < values.count {
                    let value = values[readIndex]
                    readIndex += 1
                    return value
                }
                if let streamError { throw streamError }
                if finished { throw ObservationEnded() }
                if Date() > deadline { throw ObservationTimedOut() }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    struct ObservationTimedOut: Error, Sendable {}
    struct ObservationEnded: Error, Sendable {}
}
