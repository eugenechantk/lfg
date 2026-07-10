import Foundation
@preconcurrency import GRDB

/// API shorthand for transcript messages stored by `LFGStore`.
public typealias Message = SessionMessage

/// A host row persisted by `LFGStore`.
public struct LFGStoredHost: Sendable, Hashable, Identifiable {
    /// The configured host URL, used as the stable row identity.
    public var id: String { url }
    /// The configured host URL.
    public var url: String
    /// The resolved machine identity, when known.
    public var hostId: String?
    /// The resolved machine hostname, when known.
    public var name: String?
    /// A user-supplied display name, when configured.
    public var displayName: String?
    /// Whether this host is the default target for new sessions.
    public var isDefault: Bool

    /// Creates a stored-host snapshot.
    public init(url: String, hostId: String?, name: String?, displayName: String?, isDefault: Bool) {
        self.url = url
        self.hostId = hostId
        self.name = name
        self.displayName = displayName
        self.isDefault = isDefault
    }
}

/// A session-list row joined with local read-state.
public struct LFGStoredSession: Sendable, Hashable, Identifiable {
    /// The stable session identity.
    public var id: String { sessionId }
    /// The stable session identity.
    public var sessionId: String
    /// The configured host URL currently associated with this session.
    public var hostId: String
    /// The display title.
    public var title: String?
    /// The working directory path.
    public var cwd: String?
    /// The agent kind string.
    public var agent: String?
    /// The model alias.
    public var model: String?
    /// Whether this is a closed/resumable session.
    public var closed: Bool
    /// Whether the executing pane is currently busy, when known.
    public var busy: Bool?
    /// The assigned user email, when known.
    public var assignedUser: String?
    /// Last activity as epoch milliseconds.
    public var lastActivityAt: Double?
    /// The newest transcript message id, when known.
    public var lastMessageId: String?
    /// The newest transcript message preview text, when known.
    public var lastMessagePreview: String?
    /// The newest transcript message role, when known.
    public var lastMessageRole: String?
    /// The newest message id this viewer has seen, when known.
    public var lastSeenMessageId: String?
    /// The last time this session was opened, as epoch milliseconds.
    public var openedAt: Double?
    /// Whether the latest stored message is unread for this viewer.
    public var isUnread: Bool { ReadState.isUnread(lastMessageID: lastMessageId, lastSeenMessageID: lastSeenMessageId) }

    /// Creates a stored-session snapshot.
    public init(
        sessionId: String,
        hostId: String,
        title: String?,
        cwd: String?,
        agent: String?,
        model: String?,
        closed: Bool,
        busy: Bool?,
        assignedUser: String?,
        lastActivityAt: Double?,
        lastMessageId: String?,
        lastMessagePreview: String?,
        lastMessageRole: String?,
        lastSeenMessageId: String?,
        openedAt: Double?
    ) {
        self.sessionId = sessionId
        self.hostId = hostId
        self.title = title
        self.cwd = cwd
        self.agent = agent
        self.model = model
        self.closed = closed
        self.busy = busy
        self.assignedUser = assignedUser
        self.lastActivityAt = lastActivityAt
        self.lastMessageId = lastMessageId
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageRole = lastMessageRole
        self.lastSeenMessageId = lastSeenMessageId
        self.openedAt = openedAt
    }
}

/// A transcript message row persisted by `LFGStore`.
public struct LFGStoredMessage: Sendable, Hashable, Identifiable {
    /// The transcript message identity.
    public var id: String
    /// The owning session identity.
    public var sessionId: String
    /// The speaker role.
    public var role: String
    /// The transcript entry kind.
    public var kind: String
    /// The plain text body.
    public var text: String
    /// The message timestamp as epoch milliseconds.
    public var ts: Double?
    /// The encoded lenient API payload retained for richer rendering.
    public var json: String
    /// The decoded API payload, when the stored JSON is still understood.
    public var message: SessionMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionMessage.self, from: data)
    }

    /// Creates a stored-message snapshot.
    public init(id: String, sessionId: String, role: String, kind: String, text: String, ts: Double?, json: String) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.kind = kind
        self.text = text
        self.ts = ts
        self.json = json
    }
}

/// Local read-state for one session.
public struct LFGReadStateSnapshot: Sendable, Hashable {
    /// The owning session identity.
    public var sessionId: String
    /// The newest message id this viewer has seen, when known.
    public var lastSeenMessageId: String?
    /// The last time this session was opened, as epoch milliseconds.
    public var openedAt: Double?

    /// Creates a read-state snapshot.
    public init(sessionId: String, lastSeenMessageId: String?, openedAt: Double?) {
        self.sessionId = sessionId
        self.lastSeenMessageId = lastSeenMessageId
        self.openedAt = openedAt
    }
}

struct HostRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hosts"

    var id: String
    var hostId: String?
    var name: String?
    var displayName: String?
    var isDefault: Bool

    init(_ host: Host) {
        id = host.url
        hostId = host.hostId
        name = host.name
        displayName = host.displayName
        isDefault = host.isDefault
    }

    var stored: LFGStoredHost {
        LFGStoredHost(url: id, hostId: hostId, name: name, displayName: displayName, isDefault: isDefault)
    }
}

struct SessionListRow: Decodable, FetchableRecord {
    var sessionId: String
    var hostId: String
    var title: String?
    var cwd: String?
    var agent: String?
    var model: String?
    var closed: Bool
    var busy: Bool?
    var assignedUser: String?
    var lastActivityAt: Double?
    var lastMessageId: String?
    var lastMessagePreview: String?
    var lastMessageRole: String?
    var lastSeenMessageId: String?
    var openedAt: Double?

    var stored: LFGStoredSession {
        LFGStoredSession(
            sessionId: sessionId,
            hostId: hostId,
            title: title,
            cwd: cwd,
            agent: agent,
            model: model,
            closed: closed,
            busy: busy,
            assignedUser: assignedUser,
            lastActivityAt: lastActivityAt,
            lastMessageId: lastMessageId,
            lastMessagePreview: lastMessagePreview,
            lastMessageRole: lastMessageRole,
            lastSeenMessageId: lastSeenMessageId,
            openedAt: openedAt
        )
    }
}

struct SessionUpsertRecord {
    var sessionId: String
    var hostId: String
    var title: String?
    var cwd: String?
    var agent: String?
    var model: String?
    var closed: Bool?
    var busy: Bool?
    var assignedUser: String?
    var lastActivityAt: Double?
    var lastMessageId: String?
    var lastMessagePreview: String?
    var lastMessageRole: String?

    init?(_ session: Session, hostId: String) {
        guard let sessionId = LFGStoreRecordHelpers.sessionID(for: session) else { return nil }
        let sparse = LFGStoreRecordHelpers.isSparseSessionUpdate(session)

        self.sessionId = sessionId
        self.hostId = hostId
        title = LFGStoreRecordHelpers.nonEmpty(session.title)
        cwd = session.cwd
        agent = sparse && session.agent == "aisdk" ? nil : LFGStoreRecordHelpers.nonEmpty(session.agent)
        model = session.model
        closed = sparse && !session.closed ? nil : session.closed
        busy = session.busy
        assignedUser = session.assignedUser
        lastActivityAt = session.lastActivityAt ?? session.last?.ts
        lastMessageId = LFGStoreRecordHelpers.nonEmpty(session.last?.id)
        lastMessagePreview = LFGStoreRecordHelpers.nonEmpty(session.last?.text)
        lastMessageRole = LFGStoreRecordHelpers.nonEmpty(session.last?.role)
    }
}

struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    var id: String
    var sessionId: String
    var role: String
    var kind: String
    var text: String
    var ts: Double?
    var json: String

    init(sessionId: String, message: SessionMessage) {
        id = LFGStoreRecordHelpers.messageID(for: message)
        self.sessionId = sessionId
        role = message.role
        kind = message.kind
        text = message.text
        ts = message.ts
        json = LFGStoreRecordHelpers.jsonString(for: message)
    }

    var stored: LFGStoredMessage {
        LFGStoredMessage(id: id, sessionId: sessionId, role: role, kind: kind, text: text, ts: ts, json: json)
    }
}

struct ReadStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "readState"

    var sessionId: String
    var lastSeenMessageId: String?
    var openedAt: Double?

    var stored: LFGReadStateSnapshot {
        LFGReadStateSnapshot(sessionId: sessionId, lastSeenMessageId: lastSeenMessageId, openedAt: openedAt)
    }
}

enum LFGStoreRecordHelpers {
    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    static func sessionID(for session: Session) -> String? {
        if let sessionId = nonEmpty(session.sessionId) { return sessionId }
        if let tmuxName = nonEmpty(session.tmuxName) { return tmuxName }
        return nonEmpty(session.title)
    }

    static func isSparseSessionUpdate(_ session: Session) -> Bool {
        session.title.isEmpty &&
        session.model == nil &&
        session.project == nil &&
        session.cwd == nil &&
        session.status == nil &&
        session.statusReason == nil &&
        session.statusDetail == nil &&
        session.assignedUser == nil &&
        session.lastUserText == nil &&
        session.startedAt == nil &&
        session.lastActivityAt == nil &&
        session.tmuxTarget == nil &&
        session.tmuxName == nil &&
        session.managed == nil &&
        session.last == nil
    }

    static func messageID(for message: SessionMessage) -> String {
        if let id = nonEmpty(message.id) { return id }
        return "synthetic-\(fnv1a64([message.role, message.kind, String(message.ts ?? 0), message.text]))"
    }

    static func jsonString(for message: SessionMessage) -> String {
        // sortedKeys: byte-identical re-encoding is what makes re-ingestion a
        // true no-op (upsert idempotency is asserted down to this column).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(message)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func fnv1a64(_ parts: [String]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for part in parts {
            for byte in part.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x00000100000001B3
            }
            hash ^= UInt64(0xff)
            hash = hash &* 0x00000100000001B3
        }
        return String(hash, radix: 16)
    }
}
