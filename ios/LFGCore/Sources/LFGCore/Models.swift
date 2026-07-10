import Foundation

// MARK: - Session

/// A live agent session as returned by `GET /api/sessions`.
/// Decoding is lenient: the server may add/omit fields across versions, so every
/// property is optional with a sensible default rather than a hard decode failure.
public struct Session: Codable, Sendable, Identifiable, Hashable {
    public var sessionId: String?
    public var title: String
    public var agent: String          // "aisdk" | "claude" | "codex" | "codex-aisdk" | "opencode"
    public var model: String?         // short alias: opus/sonnet/haiku/fable, gpt-5.5, …
    public var project: String?
    public var cwd: String?
    public var status: String?        // "ok" | "blocked"
    public var statusReason: String?  // "model_unavailable" | "out_of_credits" | null
    public var statusDetail: String?
    public var assignedUser: String?
    public var parentSessionId: String?
    public var lastUserText: String?
    public var startedAt: Double?
    public var lastActivityAt: Double?
    public var tmuxTarget: String?
    public var tmuxName: String?
    public var managed: Bool?
    /// Best-effort "mid-turn" baseline from the REST list. Used to correct a
    /// stale "Working" badge for sessions the live SSE stream doesn't cover (or
    /// whose busy delta was missed across a reconnect). nil on older servers.
    public var busy: Bool?
    /// The session's newest transcript message, as the server's `previewLast` sees
    /// it — metadata lines (`mode`, `permission-mode`, `bridge-session`, `ai-title`)
    /// and `isMeta` turns are already filtered out. Its `id` (the transcript line's
    /// uuid) is what read-state keys off: unlike `lastActivityAt`, which is the
    /// transcript file's mtime and advances whenever anything touches the file,
    /// this only changes when the conversation does. See `ReadState.isUnread`.
    public var last: SessionMessage?
    /// Client-synthesized (never sent by the server): a closed/resumable session
    /// whose live pane is gone but whose transcript survives on disk. Surfaced in
    /// the list from `/api/sessions/resumable` so it stays visible; sending to it
    /// auto-resumes the conversation server-side. See `SessionStore.refresh`.
    public var closed: Bool

    public var id: String { sessionId ?? tmuxName ?? title }

    public var isBlocked: Bool { status == "blocked" }
    public var isClaude: Bool { agent == "claude" || agent == "aisdk" }
    /// Only pane-backed (CLI/tmux) sessions can be answered/steered via send-keys.
    public var hasPane: Bool { tmuxTarget != nil }

    public init(
        sessionId: String? = nil, title: String = "", agent: String = "aisdk",
        model: String? = nil, project: String? = nil, cwd: String? = nil,
        status: String? = nil, statusReason: String? = nil, statusDetail: String? = nil,
        assignedUser: String? = nil, parentSessionId: String? = nil, lastUserText: String? = nil,
        startedAt: Double? = nil, lastActivityAt: Double? = nil,
        tmuxTarget: String? = nil, tmuxName: String? = nil, managed: Bool? = nil,
        busy: Bool? = nil, last: SessionMessage? = nil, closed: Bool = false
    ) {
        self.sessionId = sessionId; self.title = title; self.agent = agent
        self.model = model; self.project = project; self.cwd = cwd
        self.status = status; self.statusReason = statusReason; self.statusDetail = statusDetail
        self.assignedUser = assignedUser; self.parentSessionId = parentSessionId
        self.lastUserText = lastUserText
        self.startedAt = startedAt; self.lastActivityAt = lastActivityAt
        self.tmuxTarget = tmuxTarget; self.tmuxName = tmuxName; self.managed = managed
        self.busy = busy; self.last = last; self.closed = closed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        agent = (try c.decodeIfPresent(String.self, forKey: .agent)) ?? "aisdk"
        model = try c.decodeIfPresent(String.self, forKey: .model)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        statusReason = try c.decodeIfPresent(String.self, forKey: .statusReason)
        statusDetail = try c.decodeIfPresent(String.self, forKey: .statusDetail)
        assignedUser = try c.decodeIfPresent(String.self, forKey: .assignedUser)
        parentSessionId = try c.decodeIfPresent(String.self, forKey: .parentSessionId)
        lastUserText = try c.decodeIfPresent(String.self, forKey: .lastUserText)
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
        lastActivityAt = try c.decodeIfPresent(Double.self, forKey: .lastActivityAt)
        tmuxTarget = try c.decodeIfPresent(String.self, forKey: .tmuxTarget)
        tmuxName = try c.decodeIfPresent(String.self, forKey: .tmuxName)
        managed = try c.decodeIfPresent(Bool.self, forKey: .managed)
        busy = try c.decodeIfPresent(Bool.self, forKey: .busy)
        // Never let a malformed preview line fail the whole session decode.
        last = (try? c.decodeIfPresent(SessionMessage.self, forKey: .last)) ?? nil
        closed = (try c.decodeIfPresent(Bool.self, forKey: .closed)) ?? false
    }
}

public struct SessionsResponse: Codable, Sendable {
    public var sessions: [Session]
}

// MARK: - Transcript message

/// One transcript line. `html` is server-prerendered (marked.parse) for text kinds.
public struct SessionMessage: Codable, Sendable, Identifiable, Hashable {
    public var id: String?            // transcript uuid; may be null
    public var role: String           // user | assistant | tool | system
    public var kind: String           // text | thinking | tool_use | tool_result
    public var text: String
    public var ts: Double?
    public var apiError: Bool?
    public var html: String?

    /// Stable identity for SwiftUI lists even when `id` is null.
    public var stableID: String {
        if let id, !id.isEmpty { return id }
        return "\(role)|\(kind)|\(ts ?? 0)|\(text.hashValue)"
    }

    public init(
        id: String? = nil, role: String = "assistant", kind: String = "text",
        text: String = "", ts: Double? = nil, apiError: Bool? = nil, html: String? = nil
    ) {
        self.id = id; self.role = role; self.kind = kind; self.text = text
        self.ts = ts; self.apiError = apiError; self.html = html
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        role = (try c.decodeIfPresent(String.self, forKey: .role)) ?? "assistant"
        kind = (try c.decodeIfPresent(String.self, forKey: .kind)) ?? "text"
        text = (try c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        ts = try c.decodeIfPresent(Double.self, forKey: .ts)
        apiError = try c.decodeIfPresent(Bool.self, forKey: .apiError)
        html = try c.decodeIfPresent(String.self, forKey: .html)
    }
}

public struct MessagesResponse: Codable, Sendable {
    public var id: String?
    public var messages: [SessionMessage]
    public var total: Int?
    public var nextBefore: Int?
}

// MARK: - Interactive prompt

public struct PromptOption: Codable, Sendable, Hashable, Identifiable {
    public var index: Int
    public var label: String
    public var selected: Bool?
    public var description: String?
    public var id: Int { index }

    public init(index: Int, label: String, selected: Bool? = nil, description: String? = nil) {
        self.index = index; self.label = label; self.selected = selected; self.description = description
    }
}

/// A blocking selector surfaced by a CLI agent (AskUserQuestion / permission /
/// plan-approval / trust). Answered with `POST /api/sessions/:id/answer {index}`.
public struct AgentPrompt: Codable, Sendable, Hashable {
    public var question: String
    public var options: [PromptOption]
    public var detail: String?
    /// Short category chip the agent attaches to each question (AskUserQuestion
    /// `header`, e.g. "Auth method"). Nil for pane-scraped prompts, which carry
    /// no header. Surfaced so the panel can label what the question is about.
    public var header: String?
    /// True when the question accepts multiple answers. Carried so the panel can
    /// signal it; single-tap answering still applies (multi-select toggling is
    /// not yet wired through the answer path).
    public var multiSelect: Bool?
    /// The assistant prose shown directly above the selector — the explanation
    /// the model wrote right before asking. Scraped from the pane because
    /// AskUserQuestion's turn isn't flushed to the transcript until answered, so
    /// this is the only context the user has while the question is live. Nil when
    /// the agent asked with no preamble. Rendered above the question in the panel.
    public var context: String?

    public init(
        question: String,
        options: [PromptOption],
        detail: String? = nil,
        header: String? = nil,
        multiSelect: Bool? = nil,
        context: String? = nil
    ) {
        self.question = question; self.options = options; self.detail = detail
        self.header = header; self.multiSelect = multiSelect; self.context = context
    }
}

// MARK: - Outbound message queue

public struct QueueItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var status: String         // delivered | queued | sending | failed
    public var attempts: Int?
    public var error: String?

    public var isFailed: Bool { status == "failed" }

    public init(id: String, text: String, status: String, attempts: Int? = nil, error: String? = nil) {
        self.id = id; self.text = text; self.status = status; self.attempts = attempts; self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        text = (try c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        status = (try c.decodeIfPresent(String.self, forKey: .status)) ?? "queued"
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

public struct QueueResponse: Codable, Sendable {
    public var id: String?
    public var queue: [QueueItem]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        queue = (try c.decodeIfPresent([QueueItem].self, forKey: .queue)) ?? []
    }
}

// MARK: - Repos / users / usage

public struct Repo: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var cwd: String
    public var id: String { cwd }
    public init(name: String, cwd: String) { self.name = name; self.cwd = cwd }
}

public struct ReposResponse: Codable, Sendable { public var repos: [Repo] }

/// Directories available for new sessions: scanned repos + the root and inbox
/// fallbacks.
public struct DirsResponse: Codable, Sendable {
    public var root: String
    public var inbox: String
    public var repos: [Repo]
}

/// `GET /api/users` returns a roster of `{ email, avatar }` objects (avatar is a
/// Gravatar URL computed server-side). Older/bare-array shapes are handled in
/// `LFGClient.users()`.
public struct RosterUser: Codable, Sendable, Hashable, Identifiable {
    public var email: String
    public var avatar: String?
    public var id: String { email }
}
public struct RosterResponse: Codable, Sendable { public var users: [RosterUser] }
public struct UsersResponse: Codable, Sendable { public var users: [String] }

public struct UsageWindow: Codable, Sendable, Hashable {
    public var pct: Double?
    public var resetsAt: String?
}

public struct Usage: Codable, Sendable, Hashable {
    public var ok: Bool?
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
}

// MARK: - Resumable sessions

public struct ResumableSession: Codable, Sendable, Hashable, Identifiable {
    public var sessionId: String
    public var title: String?
    public var project: String?
    public var cwd: String?
    /// Last-activity epoch millis. The server sends this as `lastActivityAt`
    /// (older builds may send `mtime`); decode either.
    public var mtime: Double?
    public var agent: String?
    public var lastUserText: String?
    public var id: String { sessionId }

    public init(sessionId: String, title: String? = nil, project: String? = nil,
                cwd: String? = nil, mtime: Double? = nil, agent: String? = nil,
                lastUserText: String? = nil) {
        self.sessionId = sessionId; self.title = title; self.project = project
        self.cwd = cwd; self.mtime = mtime; self.agent = agent
        self.lastUserText = lastUserText
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, title, project, cwd, mtime, agent, lastActivityAt, lastUserText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = (try c.decodeIfPresent(String.self, forKey: .sessionId)) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        if let la = try c.decodeIfPresent(Double.self, forKey: .lastActivityAt) {
            mtime = la
        } else {
            mtime = try c.decodeIfPresent(Double.self, forKey: .mtime)
        }
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        lastUserText = try c.decodeIfPresent(String.self, forKey: .lastUserText)
    }

    // Manual encode: an explicit CodingKeys enum with an extra `lastActivityAt`
    // case (no matching stored property) suppresses Encodable synthesis.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        try c.encodeIfPresent(mtime, forKey: .lastActivityAt)
        try c.encodeIfPresent(agent, forKey: .agent)
        try c.encodeIfPresent(lastUserText, forKey: .lastUserText)
    }
}

public struct ResumableResponse: Codable, Sendable {
    public var sessions: [ResumableSession]
    public var nextBefore: Double?
}

// MARK: - Create / resume request + response

public struct NewSessionRequest: Codable, Sendable {
    public var cwd: String
    public var prompt: String
    public var agent: String?     // claude | codex | aisdk | codex-aisdk | opencode
    public var model: String?
    public var user: String?

    public init(cwd: String, prompt: String, agent: String? = nil, model: String? = nil, user: String? = nil) {
        self.cwd = cwd; self.prompt = prompt; self.agent = agent; self.model = model; self.user = user
    }
}

public struct ResumeRequest: Codable, Sendable {
    public var sessionId: String
    public var model: String?
    public var user: String?
    public var prompt: String?
    public init(sessionId: String, model: String? = nil, user: String? = nil, prompt: String? = nil) {
        self.sessionId = sessionId; self.model = model; self.user = user; self.prompt = prompt
    }
}

/// Fork a session into a new branch (`claude --resume <id> --fork-session`). The
/// source transcript is left untouched; the server mints a new sessionId for the
/// branch and returns it in a `NewSessionResponse`. Unlike resume, no prompt —
/// a fork lands at the composer carrying the copied history, ready to diverge.
public struct ForkRequest: Codable, Sendable {
    public var sessionId: String
    public var model: String?
    public var user: String?
    public init(sessionId: String, model: String? = nil, user: String? = nil) {
        self.sessionId = sessionId; self.model = model; self.user = user
    }
}

/// Response of `GET /api/info` — a host's identity for the multi-host client.
/// `hostId` is the machine's stable uuid (dedupe key for the same machine
/// reached via two URLs); `hostName` is its friendly hostname for display.
public struct HostInfo: Codable, Sendable, Hashable {
    public var hostId: String
    public var hostName: String
    public init(hostId: String, hostName: String) {
        self.hostId = hostId; self.hostName = hostName
    }

    enum CodingKeys: String, CodingKey { case hostId, hostName }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hostId = (try c.decodeIfPresent(String.self, forKey: .hostId)) ?? ""
        hostName = (try c.decodeIfPresent(String.self, forKey: .hostName)) ?? ""
    }
}

public struct NewSessionResponse: Codable, Sendable {
    public var ok: Bool?
    public var sessionId: String?
    public var tmuxName: String?
    public var cwd: String?
    public var agent: String?
    public var alreadyLive: Bool?
}

/// Response to POST /api/sessions/{id}/send. Normally just `{ ok, msg }`, but if
/// the target session's pane had been reaped while idle the server resumes the
/// conversation and returns `resumed: true` plus the (possibly new) `sessionId`
/// the revived session now lives under — so the client can re-point at it.
public struct SendResponse: Codable, Sendable {
    public var ok: Bool?
    public var resumed: Bool?
    public var sessionId: String?
    public var resumedFrom: String?
    /// The server's queue entry for this send (id/text/status), so the client can
    /// correlate the optimistic bubble to a server queue id immediately — used to
    /// drive remove / edit / send-now actions on the still-pending message.
    public var msg: QueueItem?
}

// MARK: - Live SSE event

public enum LiveEvent: Sendable, Equatable {
    case message(sid: String, message: SessionMessage)
    case prompt(sid: String, prompt: AgentPrompt?)
    case busy(sid: String, busy: Bool)
    case queue(sid: String, queue: [QueueItem])
    case heartbeat
}

// MARK: - Agent / model catalogs (mirrors server allowlists)

public enum AgentKind: String, CaseIterable, Sendable, Identifiable {
    case aisdk            // claude via AI SDK (server default)
    case claude           // claude CLI (tmux) — needed for the interactive prompt panel
    case codex            // codex CLI
    case codexAisdk = "codex-aisdk"
    case opencode

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aisdk: return "Claude (ai-sdk)"
        case .claude: return "Claude (CLI)"
        case .codex: return "Codex (CLI)"
        case .codexAisdk: return "Codex (ai-sdk)"
        case .opencode: return "opencode"
        }
    }

    /// Models offered for this agent. Claude paths use the server allowlists;
    /// codex/opencode are catalog-driven so we provide common defaults.
    public var models: [String] {
        switch self {
        // First entry is the default. Claude → opus, Codex → gpt-5.5.
        case .aisdk: return ["opus", "sonnet", "haiku"]
        case .claude: return ["opus", "sonnet", "haiku", "fable"]
        case .codex, .codexAisdk: return ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"]
        case .opencode: return ["anthropic/claude-sonnet-4-6", "anthropic/claude-opus-4-8"]
        }
    }

    public var defaultModel: String { models.first ?? "sonnet" }
}
