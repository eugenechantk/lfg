import Foundation

/// A link into the app via the `lfg://` scheme.
///
/// - `lfg://session/<id>` opens a session (notification taps, Live Activities).
/// - `lfg://new?prompt=<text>&dir=<hint>&host=<hint>&agent=<hint>&model=<hint>`
///   opens New Session with the composer, directory, host and model prefilled —
///   what an Action-button Shortcut uses to hand over a dictated task. It never
///   starts a session by itself: any app can open a URL, so the send stays a
///   deliberate tap in the app.
public enum LFGDeepLink: Equatable, Sendable {
    case session(id: String)
    case newSession(NewSessionLink)

    public static func parse(_ url: URL) -> LFGDeepLink? {
        guard url.scheme?.lowercased() == "lfg" else { return nil }
        let path = url.path.split(separator: "/", omittingEmptySubsequences: true)
        switch url.host?.lowercased() {
        case "session":
            guard path.count == 1,
                  let sid = String(path[0]).removingPercentEncoding,
                  !sid.isEmpty else { return nil }
            return .session(id: sid)
        case "new":
            guard path.isEmpty else { return nil }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            // First value wins; unknown items are ignored so a newer Shortcut
            // never breaks an older build.
            func value(_ name: String) -> String? {
                guard let raw = items.first(where: { $0.name == name })?.value,
                      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return raw
            }
            return .newSession(NewSessionLink(
                prompt: value("prompt"),
                directory: value("dir"),
                host: value("host"),
                // `provider` reads more naturally in a Shortcut; `agent` is lfg's own word.
                agent: value("agent") ?? value("provider"),
                model: value("model")))
        default:
            return nil
        }
    }
}

/// What an `lfg://new` link asks New Session to show. Every field is optional
/// and blank values arrive as nil. They are hints, resolved on the device by
/// `NewSessionDirectoryHint` and `NewSessionLinkHints`.
public struct NewSessionLink: Equatable, Sendable {
    public var prompt: String?
    /// An absolute or `~` path, or a directory name.
    public var directory: String?
    /// A host's display name, machine name, URL authority or URL.
    public var host: String?
    /// `claude` / `codex`, or a provider name (`anthropic` / `openai`).
    public var agent: String?
    /// A model id or a loose name for one (`opus`, `GPT 5.5`).
    public var model: String?

    public init(prompt: String?, directory: String?, host: String? = nil,
                agent: String? = nil, model: String? = nil) {
        self.prompt = prompt
        self.directory = directory
        self.host = host
        self.agent = agent
        self.model = model
    }

    /// `lfg://new[?prompt=…][&dir=…][&host=…][&agent=…][&model=…]`, encoding
    /// everything outside RFC 3986's unreserved set so `&`, `=`, `+` and `#`
    /// survive inside values.
    public var url: URL? {
        let fields = [("prompt", prompt), ("dir", directory), ("host", host), ("agent", agent), ("model", model)]
        let pairs = fields.compactMap { name, value -> String? in
            guard let value, !value.isEmpty,
                  let encoded = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { return nil }
            return "\(name)=\(encoded)"
        }
        return URL(string: pairs.isEmpty ? "lfg://new" : "lfg://new?" + pairs.joined(separator: "&"))
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

/// Resolves a link's `dir` hint against the directories New Session offers.
/// Names are what a person says out loud ("dictate keyboard"), so matching
/// ignores case, spaces and punctuation.
public enum NewSessionDirectoryHint {
    public struct Candidate: Equatable, Sendable {
        public var name: String
        public var path: String

        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    /// The candidate a hint names, or nil when it names none. Paths (`/…`, `~…`)
    /// are taken as given, keeping a listed entry's display name when there is
    /// one. Among names, the first listed match wins.
    public static func resolve(_ hint: String, in candidates: [Candidate]) -> Candidate? {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            if let listed = candidates.first(where: { $0.path == trimmed }) { return listed }
            let last = (trimmed as NSString).lastPathComponent
            return Candidate(name: last.isEmpty ? trimmed : last, path: trimmed)
        }
        let key = looseKey(trimmed)
        guard !key.isEmpty else { return nil }
        return candidates.first { looseKey($0.name) == key }
            ?? candidates.first { looseKey(($0.path as NSString).lastPathComponent) == key }
    }

    /// The directory a linked New Session shows: the hint's match, else Inbox.
    /// A link describes the whole draft, so a missing or unknown hint must not
    /// leave a previous link's project selected. With no Inbox known yet the
    /// path is empty, which New Session already shows as "Directory".
    public static func directory(for hint: String?, in candidates: [Candidate], inbox: String) -> Candidate {
        if let hint, let match = resolve(hint, in: candidates) { return match }
        return Candidate(name: inbox.isEmpty ? "Directory" : "Inbox", path: inbox)
    }
}

/// Resolves a link's `host`, `agent` and `model` hints. Like directory names,
/// these are often spoken ("mac studio", "GPT five point five" → "GPT 5.5"), so
/// each resolves exact first, then ignoring case/spaces/punctuation, then by
/// containment — and anything unresolved leaves New Session on its defaults.
public enum NewSessionLinkHints {
    /// The configured host a hint names, or nil.
    public static func host(for hint: String?, in hosts: [Host]) -> Host? {
        guard let hint = trimmed(hint) else { return nil }
        func names(_ h: Host) -> [String] {
            [h.displayName, h.name, h.name?.split(separator: ".").first.map(String.init), h.label]
                .compactMap { $0 }.filter { !$0.isEmpty }
        }
        let lower = hint.lowercased()
        if let exact = hosts.first(where: { h in
            (names(h) + [h.logLabel, h.url]).contains { $0.lowercased() == lower }
        }) { return exact }
        let key = looseKey(hint)
        guard !key.isEmpty else { return nil }
        return hosts.first { names($0).contains { looseKey($0) == key } }
            ?? hosts.first { names($0).contains { looseKey($0).contains(key) } }
    }

    /// The agent an `agent`/`provider` hint names, or nil.
    public static func agent(for hint: String?) -> AgentKind? {
        guard let hint = trimmed(hint) else { return nil }
        switch looseKey(hint) {
        case "claude", "anthropic": return .claude
        case "codex", "openai": return .codex
        default: return nil
        }
    }

    /// The agent/model pair a link asks for, resolved against `catalog`, or nil
    /// when the link names nothing usable (New Session keeps its defaults).
    ///
    /// A model found in the catalog brings its own agent. An agent whose model
    /// is missing or unknown gets that agent's catalog default.
    public static func modelSelection(agent agentHint: String?, model modelHint: String?,
                                      catalog: ModelCatalogResponse) -> AgentModelSelection? {
        let kind = agent(for: agentHint)
        let pool = kind.map { [$0] } ?? AgentKind.allCases
        if let modelHint, let found = model(modelHint, in: pool, catalog: catalog) {
            return found
        }
        return kind.map { AgentModelSelection(agent: $0, model: catalog.defaultModel(for: $0)) }
    }

    private static func model(_ hint: String, in pool: [AgentKind],
                               catalog: ModelCatalogResponse) -> AgentModelSelection? {
        guard let hint = trimmed(hint) else { return nil }
        let entries = pool.flatMap { agent in
            catalog.models(for: agent).map { AgentModelSelection(agent: agent, model: $0) }
        }
        let lower = hint.lowercased()
        if let exact = entries.first(where: { $0.model.lowercased() == lower }) { return exact }
        let key = looseKey(hint)
        guard !key.isEmpty else { return nil }
        return entries.first { looseKey($0.model) == key }
            ?? entries.first { looseKey($0.model).contains(key) }
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

/// Lowercased letters and digits only: how two spoken or typed names compare.
private func looseKey(_ s: String) -> String {
    String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}
