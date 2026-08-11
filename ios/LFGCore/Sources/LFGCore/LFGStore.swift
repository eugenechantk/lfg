import Foundation
@preconcurrency import GRDB

/// Durable client-side storage for hosts, sessions, bounded transcript messages,
/// journal cursors, read-state, and the future outbox.
public final class LFGStore: @unchecked Sendable {
    /// Supported SQLite backing locations.
    public enum Location: Sendable {
        /// An in-memory database, intended for tests and previews.
        case inMemory
        /// A file-backed database at a filesystem path.
        case path(String)
        /// A file-backed database at a file URL.
        case url(URL)
    }

    /// The per-session transcript cache limit.
    public static let messageLimit = 200

    private let dbQueue: DatabaseQueue

    /// Opens a store at the requested location and migrates it to the latest schema.
    public init(_ location: Location) throws {
        switch location {
        case .inMemory:
            dbQueue = try DatabaseQueue()
        case .path(let path):
            dbQueue = try DatabaseQueue(path: path)
        case .url(let url):
            dbQueue = try DatabaseQueue(path: url.path)
        }
        try Self.migrator.migrate(dbQueue)
    }

    /// Opens a file-backed store and migrates it to the latest schema.
    public convenience init(path: String) throws {
        try self.init(.path(path))
    }

    /// Opens an in-memory store and migrates it to the latest schema.
    public static func inMemory() throws -> LFGStore {
        try LFGStore(.inMemory)
    }

    /// Inserts or updates configured hosts by URL.
    public func upsertHosts(_ hosts: [Host]) async throws {
        try await dbQueue.write { db in
            for host in hosts {
                guard LFGStoreRecordHelpers.nonEmpty(host.url) != nil else { continue }
                try HostRecord(host).upsert(db)
            }
        }
    }

    /// Inserts or updates sessions by stable session id for the configured host URL.
    ///
    /// Optional absent fields preserve the existing row values, so partial events
    /// can enrich liveness state without wiping REST-derived metadata.
    public func upsertSessions(_ sessions: [Session], hostId: String) async throws {
        try await dbQueue.write { db in
            for session in sessions {
                guard let record = SessionUpsertRecord(session, hostId: hostId) else { continue }
                try db.execute(sql: Self.upsertSessionSQL, arguments: Self.sessionArguments(record))
            }
        }
    }

    /// Replaces a host's stored sessions with `sessions`, which must be that
    /// host's **complete** live list — rows the snapshot omits are deleted.
    ///
    /// This is the write to use for a `GET /api/sessions` result, and the reason
    /// it exists is that `upsertSessions` never forgets. Left to merge, this table
    /// accumulates every session a host has ever reported; `hydrateFromStore`
    /// seeds `lastSessionsByHost` from it at a cold launch, and while the owning
    /// host is unreachable no live fetch ever overwrites that seed — so the list
    /// fills with long-dead sessions, some frozen at `busy: true`, that are
    /// invisible whenever the host is actually up. See
    /// `.claude/diagnosis-offline-host-resurrects-dead-sessions-20260811.md`.
    ///
    /// The delete is scoped to `hostId` so one host's snapshot cannot evict
    /// another's: `~/.claude/projects` is synced, two hosts can report the same
    /// session id, and the row's `hostId` follows whichever fetch landed last.
    ///
    /// `messages` and `readState` are deliberately left alone (the v1 schema
    /// declares no foreign keys, so nothing cascades). A session that ends and is
    /// later resumed keeps its cached transcript and its read mark.
    public func replaceSessions(_ sessions: [Session], hostId: String) async throws {
        try await dbQueue.write { db in
            var keep: [String] = []
            for session in sessions {
                guard let record = SessionUpsertRecord(session, hostId: hostId) else { continue }
                try db.execute(sql: Self.upsertSessionSQL, arguments: Self.sessionArguments(record))
                keep.append(record.sessionId)
            }
            // Built by hand rather than with a `NOT IN (...)` list because the
            // empty case has to delete everything, and `NOT IN ()` is a syntax
            // error. An unreachable host legitimately reports zero sessions.
            let placeholders = keep.isEmpty ? "" : " AND sessionId NOT IN (\(databaseQuestionMarks(count: keep.count)))"
            try db.execute(
                sql: "DELETE FROM sessions WHERE hostId = ?\(placeholders)",
                arguments: StatementArguments([hostId] + keep)
            )
        }
    }

    /// Appends transcript messages and keeps only the newest `messageLimit` rows for that session.
    public func appendMessages(sessionId: String, _ messages: [Message]) async throws {
        guard LFGStoreRecordHelpers.nonEmpty(sessionId) != nil else { return }
        try await dbQueue.write { db in
            for message in messages {
                let record = MessageRecord(sessionId: sessionId, message: message)
                try db.execute(sql: Self.upsertMessageSQL, arguments: Self.messageArguments(record))
            }

            try db.execute(
                sql: """
                DELETE FROM messages
                WHERE sessionId = :sessionId
                  AND id NOT IN (
                    SELECT id
                    FROM messages
                    WHERE sessionId = :sessionId
                    ORDER BY COALESCE(ts, 0) DESC, id DESC
                    LIMIT :limit
                  )
                """,
                arguments: ["sessionId": sessionId, "limit": Self.messageLimit]
            )

            if let latest = try MessageRecord.fetchOne(
                db,
                sql: """
                SELECT id, sessionId, role, kind, text, ts, json
                FROM messages
                WHERE sessionId = ?
                ORDER BY COALESCE(ts, 0) DESC, id DESC
                LIMIT 1
                """,
                arguments: [sessionId]
            ) {
                try db.execute(
                    sql: """
                    UPDATE sessions
                    SET lastActivityAt = COALESCE(:lastActivityAt, lastActivityAt),
                        lastMessageId = :lastMessageId,
                        lastMessagePreview = :lastMessagePreview,
                        lastMessageRole = :lastMessageRole
                    WHERE sessionId = :sessionId
                    """,
                    arguments: [
                        "sessionId": sessionId,
                        "lastActivityAt": latest.ts,
                        "lastMessageId": latest.id,
                        "lastMessagePreview": latest.text,
                        "lastMessageRole": latest.role,
                    ]
                )
            }
        }
    }

    /// Advances a host journal cursor without ever allowing it to move backward.
    public func setCursor(hostId: String, seq: Int64) async throws {
        guard LFGStoreRecordHelpers.nonEmpty(hostId) != nil else { return }
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO cursors (hostId, seq)
                VALUES (?, ?)
                ON CONFLICT(hostId) DO UPDATE SET
                    seq = MAX(cursors.seq, excluded.seq)
                """,
                arguments: [hostId, seq]
            )
        }
    }

    /// Fetches the last applied journal cursor for a configured host URL.
    public func cursor(hostId: String) async throws -> Int64? {
        try await dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT seq FROM cursors WHERE hostId = ?", arguments: [hostId])
        }
    }

    /// Marks a session as opened through a specific last-seen message identity.
    public func markSeen(
        sessionId: String,
        lastSeenMessageId: String?,
        openedAt: Double = Date().timeIntervalSince1970 * 1000
    ) async throws {
        guard LFGStoreRecordHelpers.nonEmpty(sessionId) != nil else { return }
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO readState (sessionId, lastSeenMessageId, openedAt)
                VALUES (:sessionId, :lastSeenMessageId, :openedAt)
                ON CONFLICT(sessionId) DO UPDATE SET
                    lastSeenMessageId = excluded.lastSeenMessageId,
                    openedAt = excluded.openedAt
                """,
                arguments: [
                    "sessionId": sessionId,
                    "lastSeenMessageId": lastSeenMessageId,
                    "openedAt": openedAt,
                ]
            )
        }
    }

    /// Fetches local read-state for one session.
    public func readState(sessionId: String) async throws -> LFGReadStateSnapshot? {
        try await dbQueue.read { db in
            try ReadStateRecord
                .fetchOne(db, sql: "SELECT sessionId, lastSeenMessageId, openedAt FROM readState WHERE sessionId = ?", arguments: [sessionId])?
                .stored
        }
    }

    /// Inserts or refreshes an unresolved send before transport starts.
    public func enqueueOutbox(clientId: String, sessionId: String, hostId: String, text: String) async throws {
        guard LFGStoreRecordHelpers.nonEmpty(clientId) != nil,
              LFGStoreRecordHelpers.nonEmpty(sessionId) != nil,
              LFGStoreRecordHelpers.nonEmpty(hostId) != nil else { return }
        let now = Self.nowMs()
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO outbox (clientId, sessionId, hostId, text, state, createdAt, updatedAt)
                VALUES (:clientId, :sessionId, :hostId, :text, 'pending', :createdAt, :updatedAt)
                ON CONFLICT(clientId) DO UPDATE SET
                    sessionId = excluded.sessionId,
                    hostId = excluded.hostId,
                    text = excluded.text,
                    state = 'pending',
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    "clientId": clientId,
                    "sessionId": sessionId,
                    "hostId": hostId,
                    "text": text,
                    "createdAt": now,
                    "updatedAt": now,
                ]
            )
        }
    }

    /// Marks an outbox row. Delivered rows are terminal and removed immediately.
    public func markOutbox(clientId: String, state: String) async throws {
        guard LFGStoreRecordHelpers.nonEmpty(clientId) != nil else { return }
        if state == "delivered" {
            try await deleteOutbox(clientId: clientId)
            return
        }
        let now = Self.nowMs()
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE outbox
                SET state = :state,
                    updatedAt = :updatedAt
                WHERE clientId = :clientId
                """,
                arguments: [
                    "clientId": clientId,
                    "state": state,
                    "updatedAt": now,
                ]
            )
        }
    }

    /// Fetches unresolved outbox rows. Failed rows persist for retry UI but are terminal for auto-replay.
    public func pendingOutbox() async throws -> [LFGOutboxRow] {
        try await dbQueue.read { db in
            try OutboxRecord
                .fetchAll(
                    db,
                    sql: """
                    SELECT clientId, sessionId, hostId, text, state, createdAt, updatedAt
                    FROM outbox
                    WHERE state IS NULL OR state NOT IN ('delivered', 'failed')
                    ORDER BY COALESCE(createdAt, 0) ASC, clientId ASC
                    """
                )
                .map(\.stored)
        }
    }

    /// Fetches every outbox row auto-replay may still retry — including rows a
    /// previous attempt marked `failed`.
    ///
    /// `pendingOutbox()` deliberately excludes `failed`, and for a long time it
    /// was the only reader, which made `failed` terminal in the worst possible
    /// way: the host-recovery drain could no longer see the row, AND a relaunch
    /// no longer restored its bubble, so a message the user watched sit in
    /// "Queued" simply vanished. `failed` is set on ANY transport error — most
    /// often just "the host is still down" — so reaching it is routine, not
    /// exceptional. Retry eligibility is a decision for the caller (which knows
    /// the 24h cap and whether the host is up), not for the query.
    public func retryableOutbox() async throws -> [LFGOutboxRow] {
        try await dbQueue.read { db in
            try OutboxRecord
                .fetchAll(
                    db,
                    sql: """
                    SELECT clientId, sessionId, hostId, text, state, createdAt, updatedAt
                    FROM outbox
                    WHERE state IS NULL OR state <> 'delivered'
                    ORDER BY COALESCE(createdAt, 0) ASC, clientId ASC
                    """
                )
                .map(\.stored)
        }
    }

    /// Deletes an outbox row after a delivered ack or explicit local cleanup.
    public func deleteOutbox(clientId: String) async throws {
        guard LFGStoreRecordHelpers.nonEmpty(clientId) != nil else { return }
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM outbox WHERE clientId = ?", arguments: [clientId])
        }
    }

    /// Fetches all stored hosts ordered by URL.
    public func hosts() async throws -> [LFGStoredHost] {
        try await dbQueue.read { db in
            try HostRecord
                .fetchAll(db, sql: "SELECT id, hostId, name, displayName, isDefault FROM hosts ORDER BY id")
                .map(\.stored)
        }
    }

    /// Fetches the session list joined with read-state and ordered by recent activity.
    public func sessions() async throws -> [LFGStoredSession] {
        try await dbQueue.read { db in
            try Self.fetchSessions(db)
        }
    }

    /// Fetches one session transcript ordered oldest to newest.
    public func messages(sessionId: String) async throws -> [LFGStoredMessage] {
        try await dbQueue.read { db in
            try Self.fetchMessages(db, sessionId: sessionId)
        }
    }

    /// Observes the session list using GRDB `ValueObservation`.
    ///
    /// Values are scheduled through the main queue before entering the async
    /// stream, making the sequence suitable for future SwiftUI consumption.
    public func observeSessions() -> AsyncThrowingStream<[LFGStoredSession], Error> {
        let observation = ValueObservation.tracking { db in
            try Self.fetchSessions(db)
        }
        return AsyncThrowingStream { continuation in
            let token = LFGObservationToken()
            do {
                let cancellable = try observation.start(
                    in: dbQueue,
                    scheduling: .async(onQueue: DispatchQueue.main),
                    onError: { error in
                        Task { @MainActor in continuation.finish(throwing: error) }
                    },
                    onChange: { value in
                        Task { @MainActor in continuation.yield(value) }
                    }
                )
                token.set(cancellable)
            } catch {
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { @Sendable _ in token.cancel() }
        }
    }

    /// Observes one session transcript using GRDB `ValueObservation`.
    ///
    /// Values are scheduled through the main queue before entering the async
    /// stream, making the sequence suitable for future SwiftUI consumption.
    public func observeMessages(sessionId: String) -> AsyncThrowingStream<[LFGStoredMessage], Error> {
        let observation = ValueObservation.tracking { db in
            try Self.fetchMessages(db, sessionId: sessionId)
        }
        return AsyncThrowingStream { continuation in
            let token = LFGObservationToken()
            do {
                let cancellable = try observation.start(
                    in: dbQueue,
                    scheduling: .async(onQueue: DispatchQueue.main),
                    onError: { error in
                        Task { @MainActor in continuation.finish(throwing: error) }
                    },
                    onChange: { value in
                        Task { @MainActor in continuation.yield(value) }
                    }
                )
                token.set(cancellable)
            } catch {
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { @Sendable _ in token.cancel() }
        }
    }

    func tableNames() async throws -> Set<String> {
        try await dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }

    func outbox(clientId: String) async throws -> LFGOutboxRow? {
        try await dbQueue.read { db in
            try OutboxRecord
                .fetchOne(
                    db,
                    sql: """
                    SELECT clientId, sessionId, hostId, text, state, createdAt, updatedAt
                    FROM outbox
                    WHERE clientId = ?
                    """,
                    arguments: [clientId]
                )?
                .stored
        }
    }
}

private extension LFGStore {
    static func nowMs() -> Double {
        Date().timeIntervalSince1970 * 1000
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "hosts") { table in
                table.column("id", .text).primaryKey()
                table.column("hostId", .text)
                table.column("name", .text)
                table.column("displayName", .text)
                table.column("isDefault", .boolean)
            }

            try db.create(table: "sessions") { table in
                table.column("sessionId", .text).primaryKey()
                table.column("hostId", .text)
                table.column("title", .text)
                table.column("cwd", .text)
                table.column("agent", .text)
                table.column("model", .text)
                table.column("closed", .boolean)
                table.column("busy", .boolean)
                table.column("assignedUser", .text)
                table.column("lastActivityAt", .double)
                table.column("lastMessageId", .text)
                table.column("lastMessagePreview", .text)
                table.column("lastMessageRole", .text)
            }

            try db.create(table: "messages") { table in
                table.column("id", .text).notNull()
                table.column("sessionId", .text).notNull()
                table.column("role", .text)
                table.column("kind", .text)
                table.column("text", .text)
                table.column("ts", .double)
                table.column("json", .text)
                table.primaryKey(["sessionId", "id"])
            }

            try db.create(table: "outbox") { table in
                table.column("clientId", .text).primaryKey()
                table.column("sessionId", .text)
                table.column("hostId", .text)
                table.column("text", .text)
                table.column("state", .text)
                table.column("createdAt", .double)
                table.column("updatedAt", .double)
            }

            try db.create(table: "cursors") { table in
                table.column("hostId", .text).primaryKey()
                table.column("seq", .integer)
            }

            try db.create(table: "readState") { table in
                table.column("sessionId", .text).primaryKey()
                table.column("lastSeenMessageId", .text)
                table.column("openedAt", .double)
            }

            try db.create(index: "messages_session_ts", on: "messages", columns: ["sessionId", "ts"])
            try db.create(index: "sessions_last_activity", on: "sessions", columns: ["lastActivityAt"])
        }
        return migrator
    }

    static let sessionListSQL = """
        SELECT
            s.sessionId,
            s.hostId,
            s.title,
            s.cwd,
            s.agent,
            s.model,
            COALESCE(s.closed, 0) AS closed,
            s.busy,
            s.assignedUser,
            s.lastActivityAt,
            s.lastMessageId,
            s.lastMessagePreview,
            s.lastMessageRole,
            rs.lastSeenMessageId,
            rs.openedAt
        FROM sessions s
        LEFT JOIN readState rs ON rs.sessionId = s.sessionId
        ORDER BY COALESCE(s.lastActivityAt, 0) DESC, s.sessionId ASC
        """

    static let upsertSessionSQL = """
        INSERT INTO sessions (
            sessionId, hostId, title, cwd, agent, model, closed, busy,
            assignedUser, lastActivityAt, lastMessageId, lastMessagePreview, lastMessageRole
        )
        VALUES (
            :sessionId, :hostId, :title, :cwd, :agent, :model, :closed, :busy,
            :assignedUser, :lastActivityAt, :lastMessageId, :lastMessagePreview, :lastMessageRole
        )
        ON CONFLICT(sessionId) DO UPDATE SET
            hostId = excluded.hostId,
            title = COALESCE(excluded.title, sessions.title),
            cwd = COALESCE(excluded.cwd, sessions.cwd),
            agent = COALESCE(excluded.agent, sessions.agent),
            model = COALESCE(excluded.model, sessions.model),
            closed = COALESCE(excluded.closed, sessions.closed),
            busy = COALESCE(excluded.busy, sessions.busy),
            assignedUser = COALESCE(excluded.assignedUser, sessions.assignedUser),
            lastActivityAt = COALESCE(excluded.lastActivityAt, sessions.lastActivityAt),
            lastMessageId = COALESCE(excluded.lastMessageId, sessions.lastMessageId),
            lastMessagePreview = COALESCE(excluded.lastMessagePreview, sessions.lastMessagePreview),
            lastMessageRole = COALESCE(excluded.lastMessageRole, sessions.lastMessageRole)
        """

    static let upsertMessageSQL = """
        INSERT INTO messages (id, sessionId, role, kind, text, ts, json)
        VALUES (:id, :sessionId, :role, :kind, :text, :ts, :json)
        ON CONFLICT(sessionId, id) DO UPDATE SET
            role = excluded.role,
            kind = excluded.kind,
            text = excluded.text,
            ts = excluded.ts,
            json = excluded.json
        """

    static func fetchSessions(_ db: Database) throws -> [LFGStoredSession] {
        try SessionListRow.fetchAll(db, sql: sessionListSQL).map(\.stored)
    }

    static func fetchMessages(_ db: Database, sessionId: String) throws -> [LFGStoredMessage] {
        try MessageRecord
            .fetchAll(
                db,
                sql: """
                SELECT id, sessionId, role, kind, text, ts, json
                FROM messages
                WHERE sessionId = ?
                ORDER BY COALESCE(ts, 0) ASC, id ASC
                """,
                arguments: [sessionId]
            )
            .map(\.stored)
    }

    static func sessionArguments(_ record: SessionUpsertRecord) -> StatementArguments {
        [
            "sessionId": record.sessionId,
            "hostId": record.hostId,
            "title": record.title,
            "cwd": record.cwd,
            "agent": record.agent,
            "model": record.model,
            "closed": record.closed,
            "busy": record.busy,
            "assignedUser": record.assignedUser,
            "lastActivityAt": record.lastActivityAt,
            "lastMessageId": record.lastMessageId,
            "lastMessagePreview": record.lastMessagePreview,
            "lastMessageRole": record.lastMessageRole,
        ]
    }

    static func messageArguments(_ record: MessageRecord) -> StatementArguments {
        [
            "id": record.id,
            "sessionId": record.sessionId,
            "role": record.role,
            "kind": record.kind,
            "text": record.text,
            "ts": record.ts,
            "json": record.json,
        ]
    }
}

private final class LFGObservationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellable: DatabaseCancellable?

    func set(_ cancellable: DatabaseCancellable) {
        lock.lock()
        self.cancellable = cancellable
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let cancellable = self.cancellable
        self.cancellable = nil
        lock.unlock()
        cancellable?.cancel()
    }
}
