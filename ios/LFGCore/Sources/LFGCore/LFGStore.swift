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
}

private extension LFGStore {
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
