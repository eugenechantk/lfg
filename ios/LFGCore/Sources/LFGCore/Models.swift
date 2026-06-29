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
    public var lastUserText: String?
    public var startedAt: Double?
    public var lastActivityAt: Double?
    public var tmuxTarget: String?
    public var tmuxName: String?
    public var managed: Bool?

    public var id: String { sessionId ?? tmuxName ?? title }

    public var isBlocked: Bool { status == "blocked" }
    public var isClaude: Bool { agent == "claude" || agent == "aisdk" }
    /// Only pane-backed (CLI/tmux) sessions can be answered/steered via send-keys.
    public var hasPane: Bool { tmuxTarget != nil }

    public init(
        sessionId: String? = nil, title: String = "", agent: String = "aisdk",
        model: String? = nil, project: String? = nil, cwd: String? = nil,
        status: String? = nil, statusReason: String? = nil, statusDetail: String? = nil,
        assignedUser: String? = nil, lastUserText: String? = nil,
        startedAt: Double? = nil, lastActivityAt: Double? = nil,
        tmuxTarget: String? = nil, tmuxName: String? = nil, managed: Bool? = nil
    ) {
        self.sessionId = sessionId; self.title = title; self.agent = agent
        self.model = model; self.project = project; self.cwd = cwd
        self.status = status; self.statusReason = statusReason; self.statusDetail = statusDetail
        self.assignedUser = assignedUser; self.lastUserText = lastUserText
        self.startedAt = startedAt; self.lastActivityAt = lastActivityAt
        self.tmuxTarget = tmuxTarget; self.tmuxName = tmuxName; self.managed = managed
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
        lastUserText = try c.decodeIfPresent(String.self, forKey: .lastUserText)
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
        lastActivityAt = try c.decodeIfPresent(Double.self, forKey: .lastActivityAt)
        tmuxTarget = try c.decodeIfPresent(String.self, forKey: .tmuxTarget)
        tmuxName = try c.decodeIfPresent(String.self, forKey: .tmuxName)
        managed = try c.decodeIfPresent(Bool.self, forKey: .managed)
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

    public init(question: String, options: [PromptOption], detail: String? = nil) {
        self.question = question; self.options = options; self.detail = detail
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
    public var mtime: Double?
    public var agent: String?
    public var id: String { sessionId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = (try c.decodeIfPresent(String.self, forKey: .sessionId)) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        mtime = try c.decodeIfPresent(Double.self, forKey: .mtime)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
    }
}

public struct ResumableResponse: Codable, Sendable { public var sessions: [ResumableSession] }

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
