import Foundation
import os

public enum LFGError: Error, LocalizedError, Sendable {
    case badURL
    case notReachable(underlying: String)
    case http(status: Int, body: String)
    case decoding(String)
    /// The live stream went silent — no bytes (not even heartbeats) for longer
    /// than the stale timeout, so the connection is treated as dead and dropped
    /// to force a reconnect.
    case streamStalled

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL."
        case .notReachable(let u): return "Can't reach the host: \(u)"
        case .http(let s, let b): return "Server error \(s): \(b)"
        case .decoding(let m): return "Unexpected response: \(m)"
        case .streamStalled: return "Live stream stalled — reconnecting."
        }
    }
}

public enum Reachability: Sendable, Equatable {
    case ok
    case hostUnreachable(String)   // no route / connection refused (tailnet or host down)
    case badResponse(String)       // reached something, but not a healthy lfg
}

/// Stateless async client for the lfg HTTP/SSE API. `Sendable` so it can be
/// shared across the actor boundary. Construct with the base URL the user sets
/// (loopback, LAN, or a Tailscale MagicDNS https URL).
public struct LFGClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public init?(string: String, session: URLSession = .shared) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s) else { return nil }
        self.init(baseURL: url, session: session)
    }

    // MARK: URL building

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { comps?.queryItems = query }
        return comps?.url ?? baseURL.appendingPathComponent(path)
    }

    // MARK: Core request helpers

    /// Default timeout for a user-initiated read. The poll loop overrides this with a
    /// much shorter budget (`HostProbePolicy.pollTimeout`): an offline Tailscale peer
    /// black-holes packets rather than refusing the connection, so a request to a dead
    /// host hangs for the entire timeout instead of failing fast.
    public static let readTimeout: TimeInterval = 15

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [],
                                   timeout: TimeInterval = LFGClient.readTimeout,
                                   as type: T.Type) async throws -> T {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        return try await perform(req, as: T.self)
    }

    @discardableResult
    private func send(_ method: String, _ path: String, json body: [String: Any?]? = nil) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        if let body {
            var clean: [String: Any] = [:]
            for (k, v) in body { clean[k] = (v ?? NSNull()) }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: clean)
        }
        return try await performRaw(req)
    }

    private func perform<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let data = try await performRaw(req)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw LFGError.decoding(String(describing: error)) }
    }

    private func performRaw(_ req: URLRequest) async throws -> Data {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw LFGError.decoding("non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LFGError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let e as LFGError {
            throw e
        } catch {
            throw LFGError.notReachable(underlying: error.localizedDescription)
        }
    }

    // MARK: Reachability

    public func ping() async -> Reachability {
        do {
            _ = try await get("api/sessions", as: SessionsResponse.self)
            return .ok
        } catch let LFGError.http(status, _) {
            return .badResponse("HTTP \(status)")
        } catch let LFGError.notReachable(u) {
            return .hostUnreachable(u)
        } catch {
            return .badResponse(error.localizedDescription)
        }
    }

    // MARK: Reads

    public func sessions(timeout: TimeInterval = LFGClient.readTimeout) async throws -> [Session] {
        try await get("api/sessions", timeout: timeout, as: SessionsResponse.self).sessions
    }

    public func repos() async throws -> [Repo] {
        try await get("api/repos", as: ReposResponse.self).repos
    }

    public func dirs() async throws -> DirsResponse {
        try await get("api/dirs", as: DirsResponse.self)
    }

    public func createDir(name: String) async throws -> Repo {
        let data = try await send("POST", "api/dirs/new", json: ["name": name])
        struct R: Decodable { let name: String; let cwd: String }
        let r = try JSONDecoder().decode(R.self, from: data)
        return Repo(name: r.name, cwd: r.cwd)
    }

    public func setInbox(path: String) async throws -> String {
        let data = try await send("POST", "api/dirs/inbox", json: ["path": path])
        struct R: Decodable { let inbox: String }
        return try JSONDecoder().decode(R.self, from: data).inbox
    }

    public func users() async throws -> [String] {
        let data = try await performRaw({ var r = URLRequest(url: url("api/users")); r.httpMethod = "GET"; return r }())
        let dec = JSONDecoder()
        // Current shape: { users: [{ email, avatar }] }.
        if let roster = try? dec.decode(RosterResponse.self, from: data) { return roster.users.map(\.email) }
        // Back-compat: { users: ["a","b"] } or a bare array.
        if let wrapped = try? dec.decode(UsersResponse.self, from: data) { return wrapped.users }
        if let arr = try? dec.decode([String].self, from: data) { return arr }
        return []
    }

    public func usage() async throws -> Usage {
        try await get("api/claude/usage", as: Usage.self)
    }

    /// Host identity for the multi-host client — resolves this host's stable id
    /// and friendly name so the session list can label + dedupe by machine.
    public func info() async throws -> HostInfo {
        try await get("api/info", as: HostInfo.self)
    }

    public func resumable(limit: Int = 30,
                          timeout: TimeInterval = LFGClient.readTimeout) async throws -> [ResumableSession] {
        try await get("api/sessions/resumable",
                      query: [URLQueryItem(name: "limit", value: String(limit))],
                      timeout: timeout,
                      as: ResumableResponse.self).sessions
    }

    public func messages(_ id: String, limit: Int = 40, full: Bool = false) async throws -> [SessionMessage] {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if full { q.append(URLQueryItem(name: "full", value: "1")) }
        return try await get("api/sessions/\(id)/messages", query: q, as: MessagesResponse.self).messages
    }

    /// Current outbound message queue for a session — used as a poll-based
    /// fallback to reconcile optimistic sends when a live `queue` event is missed.
    public func queue(_ id: String) async throws -> [QueueItem] {
        try await get("api/sessions/\(id)/queue", as: QueueResponse.self).queue
    }

    public func messagesBackward(_ id: String, before: Int?, limit: Int = 220) async throws -> MessagesResponse {
        var q = [URLQueryItem(name: "page", value: "backward"),
                 URLQueryItem(name: "limit", value: String(limit))]
        if let before { q.append(URLQueryItem(name: "before", value: String(before))) }
        return try await get("api/sessions/\(id)/messages", query: q, as: MessagesResponse.self)
    }

    // MARK: Create / resume

    public func newSession(_ r: NewSessionRequest) async throws -> NewSessionResponse {
        let data = try await send("POST", "api/sessions/new", json: [
            "cwd": r.cwd, "prompt": r.prompt, "agent": r.agent, "model": r.model, "user": r.user,
        ])
        return try JSONDecoder().decode(NewSessionResponse.self, from: data)
    }

    public func resume(_ r: ResumeRequest) async throws -> NewSessionResponse {
        let data = try await send("POST", "api/sessions/resume", json: [
            "sessionId": r.sessionId, "model": r.model, "user": r.user, "prompt": r.prompt,
        ])
        return try JSONDecoder().decode(NewSessionResponse.self, from: data)
    }

    public func fork(_ r: ForkRequest) async throws -> NewSessionResponse {
        let data = try await send("POST", "api/sessions/fork", json: [
            "sessionId": r.sessionId, "model": r.model, "user": r.user,
        ])
        return try JSONDecoder().decode(NewSessionResponse.self, from: data)
    }

    // MARK: Steering

    @discardableResult
    public func sendMessage(_ id: String, text: String) async throws -> SendResponse {
        let data = try await send("POST", "api/sessions/\(id)/send", json: ["text": text])
        // Best-effort decode: a plain `{ ok, msg }` still decodes (resumed stays
        // nil). Tolerate a body that doesn't fit (return an empty response) so a
        // successful send never throws just because the shape drifted.
        return (try? JSONDecoder().decode(SendResponse.self, from: data)) ?? SendResponse()
    }

    public func answer(_ id: String, index: Int) async throws {
        _ = try await send("POST", "api/sessions/\(id)/answer", json: ["index": index])
    }

    public func dismiss(_ id: String) async throws {
        _ = try await send("POST", "api/sessions/\(id)/dismiss")
    }

    public func interrupt(_ id: String) async throws {
        _ = try await send("POST", "api/sessions/\(id)/interrupt")
    }

    /// Remove a not-yet-delivered queued message (held in lfg's queue).
    public func removeQueued(_ id: String, _ msgID: String) async throws {
        _ = try await send("DELETE", "api/sessions/\(id)/queue/\(msgID)")
    }

    /// Interrupt the current turn and deliver this queued message immediately.
    public func sendQueuedNow(_ id: String, _ msgID: String) async throws {
        _ = try await send("POST", "api/sessions/\(id)/queue/\(msgID)/send-now")
    }

    public func setModel(_ id: String, model: String) async throws {
        _ = try await send("POST", "api/sessions/\(id)/model", json: ["model": model])
    }

    public func rename(_ id: String, title: String) async throws {
        _ = try await send("PUT", "api/sessions/\(id)/title", json: ["title": title])
    }

    public func assign(_ id: String, user: String?) async throws {
        _ = try await send("POST", "api/sessions/\(id)/user", json: ["user": user])
    }

    public func close(_ id: String) async throws {
        _ = try await send("POST", "api/sessions/\(id)/close")
    }

    public func retryQueued(_ id: String, messageID: String) async throws {
        _ = try await send("POST", "api/sessions/\(id)/queue/\(messageID)/retry")
    }

    /// Upload image bytes for a session; the server persists them and returns an
    /// absolute path to include in a message (Claude Code reads local image paths
    /// as image input). `contentType` should be image/png|jpeg|gif|webp.
    public func upload(_ sessionID: String, data: Data, contentType: String) async throws -> String {
        var req = URLRequest(url: url("api/sessions/\(sessionID)/upload"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let respData = try await performRaw(req)
        struct UploadResponse: Decodable { let path: String }
        return try JSONDecoder().decode(UploadResponse.self, from: respData).path
    }

    // MARK: Push notifications

    /// Register this device's APNs token so the server can notify it when a
    /// session finishes a turn or needs input. `env` is "sandbox" for a Debug
    /// build run from Xcode, "production" for TestFlight/App Store.
    public func registerPush(token: String, env: String, owner: String?) async throws {
        _ = try await send("POST", "api/push/register", json: [
            "token": token, "env": env, "owner": owner,
        ])
    }

    public func unregisterPush(token: String) async throws {
        _ = try await send("POST", "api/push/unregister", json: ["token": token])
    }

    // MARK: Live stream (SSE)

    /// Subscribe to live transcript/prompt/busy/queue events for up to 24 sessions.
    /// The server backfills ~40 recent messages per session, then streams deltas.
    /// How long the live stream may go completely silent (no data *and* no
    /// heartbeats) before we treat it as a dead connection and drop it to force a
    /// reconnect. The server emits a `: hb` heartbeat every 15s, so this is two
    /// missed heartbeats plus margin — long enough not to trip on a healthy idle
    /// session, short enough to recover promptly from a silent stall (app
    /// backgrounded, radio dropped, NAT/proxy black-holed the socket — cases that
    /// produce neither an error nor a clean EOF, so nothing else would notice).
    public static let streamStaleTimeout: TimeInterval = 35

    public func liveStream(ids: [String]) -> AsyncThrowingStream<LiveEvent, Error> {
        let capped = Array(ids.prefix(24))
        let target = url("api/live/stream", query: [URLQueryItem(name: "ids", value: capped.joined(separator: ","))])
        let session = self.session
        let staleTimeout = Self.streamStaleTimeout
        return AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: target)
                req.httpMethod = "GET"
                req.timeoutInterval = .infinity
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw LFGError.http(status: http.statusCode, body: "")
                    }
                    // Timestamp of the last byte seen on the wire, shared with the
                    // watchdog. Cheap lock (no actor hop in the byte loop); updated
                    // once per line, which is plenty since a healthy connection
                    // delivers at least a heartbeat line every 15s.
                    let lastActivity = OSAllocatedUnfairLock(initialState: Date())

                    // Watchdog: if no byte arrives for staleTimeout, the socket has
                    // silently stalled (no error, no EOF — e.g. the app was
                    // backgrounded, the radio dropped, or a NAT/proxy black-holed
                    // the connection). Finish the stream with an error; that
                    // terminates the AsyncThrowingStream, whose `onTermination`
                    // cancels this task and unblocks the (otherwise indefinitely
                    // parked) byte loop below. The store then reconnects.
                    let watchdog = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(5))
                            if Task.isCancelled { return }
                            let last = lastActivity.withLock { $0 }
                            if Date().timeIntervalSince(last) > staleTimeout {
                                continuation.finish(throwing: LFGError.streamStalled)
                                return
                            }
                        }
                    }
                    defer { watchdog.cancel() }

                    // Split the raw byte stream on \n ourselves. URLSession's
                    // `.lines` helper *swallows blank lines*, but SSE uses the
                    // blank line as the event-dispatch boundary — so we'd never
                    // dispatch a frame. Manual splitting preserves the blanks.
                    var parser = SSEParser()
                    var lineBytes = [UInt8]()
                    lineBytes.reserveCapacity(256)
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            lastActivity.withLock { $0 = Date() }
                            var line = String(decoding: lineBytes, as: UTF8.self)
                            if line.hasSuffix("\r") { line.removeLast() }
                            lineBytes.removeAll(keepingCapacity: true)
                            if let frame = parser.feedLine(line), let event = LiveEventDecoder.decode(frame) {
                                continuation.yield(event)
                            }
                        } else {
                            lineBytes.append(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Journaled event stream (cursor-resumable, Phase 1)

    /// Subscribe to `GET /api/events?since=<seq>` — the whole host's journaled
    /// event stream. Unlike `liveStream(ids:)` there is no id selection and no
    /// cap: nothing about the subscription changes when sessions open/close, so
    /// the connection is never rebuilt for lifecycle reasons. On reconnect,
    /// pass the last applied seq and the server replays exactly what was
    /// missed (or emits `.resync` when the cursor is unserviceable).
    ///
    /// Byte handling mirrors `liveStream`: manual `\n` splitting (`.lines`
    /// swallows SSE's blank dispatch boundaries) and a silent-stall watchdog —
    /// at `HostLinkPolicy.staleTimeout` (20s ≈ two missed 10s heartbeats).
    public func events(since: Int64) -> AsyncThrowingStream<HostStreamElement, Error> {
        let target = url("api/events", query: [URLQueryItem(name: "since", value: String(since))])
        let session = self.session
        let staleTimeout = HostLinkPolicy.staleTimeout
        return AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: target)
                req.httpMethod = "GET"
                req.timeoutInterval = .infinity
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw LFGError.http(status: http.statusCode, body: "")
                    }
                    let lastActivity = OSAllocatedUnfairLock(initialState: Date())
                    let watchdog = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(5))
                            if Task.isCancelled { return }
                            let last = lastActivity.withLock { $0 }
                            if Date().timeIntervalSince(last) > staleTimeout {
                                continuation.finish(throwing: LFGError.streamStalled)
                                return
                            }
                        }
                    }
                    defer { watchdog.cancel() }

                    var parser = SSEParser()
                    var lineBytes = [UInt8]()
                    lineBytes.reserveCapacity(256)
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            lastActivity.withLock { $0 = Date() }
                            var line = String(decoding: lineBytes, as: UTF8.self)
                            if line.hasSuffix("\r") { line.removeLast() }
                            lineBytes.removeAll(keepingCapacity: true)
                            if let frame = parser.feedLine(line),
                               let element = HostStreamDecoder.decode(frame) {
                                continuation.yield(element)
                            }
                        } else {
                            lineBytes.append(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Keepalive: tiny GET whose round-trip keeps the cellular NAT mapping warm
    /// and measures RTT. Returns the host's journal head (a cheap gap check).
    public func ping(timeout: TimeInterval = 5) async throws -> (head: Int64, rtt: TimeInterval) {
        struct P: Decodable { let seq: Int64? }
        let started = Date()
        let p = try await get("api/ping", timeout: timeout, as: P.self)
        return (head: p.seq ?? 0, rtt: Date().timeIntervalSince(started))
    }
}
