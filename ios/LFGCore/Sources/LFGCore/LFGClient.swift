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

    /// Short name for this host in the connection log — the timeline is read on
    /// a phone, so the full URL would push every message off the screen.
    /// Must match `Host.logLabel` exactly (port included) or the same machine
    /// shows up under two names in one timeline.
    public var logLabel: String {
        guard let h = baseURL.host else { return baseURL.absoluteString }
        return baseURL.port.map { "\(h):\($0)" } ?? h
    }

    /// A network error rendered for a human reading a timeline at 11pm.
    ///
    /// `localizedDescription` alone loses the one field that actually
    /// discriminates cellular failure modes: a `URLError.Code` of
    /// `.networkConnectionLost` (path yanked mid-request), `.notConnectedToInternet`
    /// (no path at dial time), `.timedOut` (black hole) and `.cannotConnectToHost`
    /// (refused) all read as vague prose but mean completely different things
    /// about whose fault the drop was.
    public static func describe(_ error: Error) -> String {
        if let u = error as? URLError {
            return "URLError.\(u.code.rawValue) \(urlErrorName(u.code)) — \(u.localizedDescription)"
        }
        if case LFGError.http(let status, _) = error { return "HTTP \(status)" }
        let ns = error as NSError
        return "\(ns.domain).\(ns.code) — \(ns.localizedDescription)"
    }

    private static func urlErrorName(_ code: URLError.Code) -> String {
        switch code {
        case .networkConnectionLost: return "networkConnectionLost"
        case .notConnectedToInternet: return "notConnectedToInternet"
        case .timedOut: return "timedOut"
        case .cannotConnectToHost: return "cannotConnectToHost"
        case .cannotFindHost: return "cannotFindHost"
        case .dnsLookupFailed: return "dnsLookupFailed"
        case .internationalRoamingOff: return "internationalRoamingOff"
        case .dataNotAllowed: return "dataNotAllowed"
        case .callIsActive: return "callIsActive"
        case .secureConnectionFailed: return "secureConnectionFailed"
        case .cancelled: return "cancelled"
        default: return "other"
        }
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
        let started = Date()
        do {
            _ = try await get("api/sessions", as: SessionsResponse.self)
            ConnectionLog.shared.log(.probe,
                String(format: "ok in %.2fs", Date().timeIntervalSince(started)), host: logLabel)
            return .ok
        } catch let LFGError.http(status, _) {
            ConnectionLog.shared.log(.probe,
                String(format: "HTTP %d after %.2fs", status, Date().timeIntervalSince(started)),
                host: logLabel)
            return .badResponse("HTTP \(status)")
        } catch let LFGError.notReachable(u) {
            ConnectionLog.shared.log(.probe,
                String(format: "unreachable after %.2fs — %@", Date().timeIntervalSince(started), u),
                host: logLabel)
            return .hostUnreachable(u)
        } catch {
            ConnectionLog.shared.log(.probe,
                String(format: "failed after %.2fs — %@",
                       Date().timeIntervalSince(started), LFGClient.describe(error)),
                host: logLabel)
            return .badResponse(error.localizedDescription)
        }
    }

    // MARK: Reads

    public func sessions(timeout: TimeInterval = LFGClient.readTimeout) async throws -> [Session] {
        try await get("api/sessions", timeout: timeout, as: SessionsResponse.self).sessions
    }

    /// Versioned latest-frame URL. The frame id prevents URLCache/AsyncImage
    /// from presenting an older browser action after new metadata arrives.
    public func browserFrameURL(sessionId: String, frameId: String) -> URL {
        url("api/browser/frame", query: [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "frameId", value: frameId),
        ])
    }

    public func browserFrameMetadata(sessionId: String) async throws -> BrowserFrame {
        try await get("api/browser/frame/meta", query: [
            URLQueryItem(name: "sessionId", value: sessionId),
        ], as: BrowserFrame.self)
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
                          before: Double? = nil,
                          timeout: TimeInterval = LFGClient.readTimeout) async throws -> ResumableResponse {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try await get("api/sessions/resumable",
                             query: query,
                             timeout: timeout,
                             as: ResumableResponse.self)
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
    public func sendMessage(_ id: String, text: String, clientId: String? = nil) async throws -> SendResponse {
        let data = try await send("POST", "api/sessions/\(id)/send", json: sendMessageBody(text: text, clientId: clientId))
        // Best-effort decode: a plain `{ ok, msg }` still decodes (resumed stays
        // nil). Tolerate a body that doesn't fit (return an empty response) so a
        // successful send never throws just because the shape drifted.
        return (try? JSONDecoder().decode(SendResponse.self, from: data)) ?? SendResponse()
    }

    /// The message-send as a plain URLRequest, for transports this client
    /// doesn't own — the app routes it through a background URLSession so the
    /// system finishes the POST even if the app is suspended or killed
    /// mid-transfer (Phase 2 Task C). Body construction must stay identical to
    /// `sendMessage`.
    public func sendMessageRequest(_ id: String, text: String, clientId: String? = nil) throws -> URLRequest {
        var req = URLRequest(url: url("api/sessions/\(id)/send"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: sendMessageBody(text: text, clientId: clientId).compactMapValues { $0 })
        return req
    }

    private func sendMessageBody(text: String, clientId: String?) -> [String: Any?] {
        var body: [String: Any?] = ["text": text]
        if let clientId { body["clientId"] = clientId }
        return body
    }

    /// Decode a send response body (the background-transport counterpart of
    /// `sendMessage`'s lenient decode).
    public static func decodeSendResponse(_ data: Data) -> SendResponse {
        (try? JSONDecoder().decode(SendResponse.self, from: data)) ?? SendResponse()
    }

    public func answer(_ id: String, index: Int) async throws {
        _ = try await send("POST", "api/sessions/\(id)/answer", json: ["index": index])
    }

    public func dismiss(_ id: String) async throws {
        _ = try await send("POST", "api/sessions/\(id)/dismiss")
    }

    /// Interrupt the current turn.
    ///
    /// Returns whether the turn actually STOPPED — the server confirms against
    /// the pane rather than reporting the exit code of `tmux send-keys`, which
    /// only ever proved the pane existed. `nil` means the server could not tell
    /// (pane unscrapeable, or an older server that doesn't send the field), which
    /// callers must treat as "unknown", never as success.
    @discardableResult
    public func interrupt(_ id: String) async throws -> Bool? {
        let data = try await send("POST", "api/sessions/\(id)/interrupt")
        struct InterruptResponse: Decodable { let stopped: Bool? }
        return (try? JSONDecoder().decode(InterruptResponse.self, from: data))?.stopped
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

    /// Register the ActivityKit push-to-start token. `env` uses the same
    /// "sandbox"/"production" strings as ordinary alert-push registration —
    /// the server treats anything else as sandbox.
    public func registerLiveActivityStartToken(_ hex: String, env: String) async throws {
        _ = try await send("POST", "api/push/live-activity/start-token", json: [
            "token": hex, "env": env,
        ])
    }

    /// There is exactly one (fleet) Live Activity per device, so the update token
    /// needs no session targeting. `sessionId` remains accepted so an older
    /// server that still keys tokens per session does not reject the call.
    public func registerLiveActivityUpdateToken(
        _ hex: String,
        env: String,
        sessionId: String? = nil
    ) async throws {
        var body = ["token": hex, "env": env]
        if let sessionId { body["sessionId"] = sessionId }
        _ = try await send("POST", "api/push/live-activity/update-token", json: body)
    }

    /// Tell the server the fleet Live Activity is gone.
    ///
    /// The app ends the card when ITS active count reaches zero; the server's
    /// count is derived separately and need not reach zero at the same moment, so
    /// without this it keeps pushing updates into a dismissed activity — and a
    /// dead Live Activity token still answers 200, so nothing else corrects it.
    /// On receipt the server forgets the card and push-to-starts a new one, which
    /// is the only way a card can reappear while the app is suspended.
    public func reportLiveActivityEnded() async throws {
        _ = try await send("POST", "api/push/live-activity/ended", json: [:])
    }

    public func unregisterPush(token: String) async throws {
        _ = try await send("POST", "api/push/unregister", json: ["token": token])
    }


    // MARK: Journaled event stream (cursor-resumable, Phase 1)

    /// Subscribe to `GET /api/events?since=<seq>` — the whole host's journaled
    /// event stream. There is no id selection and no cap: nothing about the
    /// subscription changes when sessions open/close, so the connection is
    /// never rebuilt for lifecycle reasons. On reconnect,
    /// pass the last applied seq and the server replays exactly what was
    /// missed (or emits `.resync` when the cursor is unserviceable).
    ///
    /// Byte handling: manual `\n` splitting (`.lines` swallows SSE's blank
    /// dispatch boundaries) and a silent-stall watchdog —
    /// at `HostLinkPolicy.staleTimeout` (20s ≈ two missed 10s heartbeats).
    public func events(since: Int64) -> AsyncThrowingStream<HostStreamElement, Error> {
        let target = url("api/events", query: [URLQueryItem(name: "since", value: String(since))])
        let session = self.session
        let staleTimeout = HostLinkPolicy.staleTimeout
        let label = logLabel
        let log = ConnectionLog.shared
        return AsyncThrowingStream { continuation in
            let task = Task {
                let dialedAt = Date()
                log.log(.stream, "dial since=\(since)", host: label)
                var req = URLRequest(url: target)
                req.httpMethod = "GET"
                // NOT .infinity: URLSession's timeoutInterval is an IDLE timeout
                // (resets on every received byte), so with 10s server heartbeats
                // a healthy stream never trips it — while a black-holed connect
                // (TCP accepted by the kernel, headers never arriving — SIGSTOPed
                // or vanished server) fails within 18s instead of hanging
                // forever. The custom watchdog below can only start AFTER headers
                // arrive; this covers the phase it can't. Caught live in the
                // Phase-1 gate test.
                req.timeoutInterval = 18
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    // Time-to-headers is the number that separates "the host is
                    // gone" from "the Tailscale path is cold": a re-punch or DERP
                    // failover shows up here as seconds, not milliseconds.
                    log.log(.stream,
                            String(format: "headers status=%d in %.2fs", status,
                                   Date().timeIntervalSince(dialedAt)),
                            host: label)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw LFGError.http(status: http.statusCode, body: "")
                    }
                    let lastActivity = OSAllocatedUnfairLock(initialState: Date())
                    let watchdog = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(5))
                            if Task.isCancelled { return }
                            let last = lastActivity.withLock { $0 }
                            let quiet = Date().timeIntervalSince(last)
                            if quiet > staleTimeout {
                                log.log(.stream,
                                        String(format: "STALL — no bytes for %.1fs, giving up", quiet),
                                        host: label)
                                continuation.finish(throwing: LFGError.streamStalled)
                                return
                            }
                        }
                    }
                    defer { watchdog.cancel() }

                    var parser = SSEParser()
                    var lineBytes = [UInt8]()
                    lineBytes.reserveCapacity(256)
                    var events = 0
                    var heartbeats = 0
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            let previous = lastActivity.withLock { was -> Date in
                                let prior = was; was = Date(); return prior
                            }
                            var line = String(decoding: lineBytes, as: UTF8.self)
                            if line.hasSuffix("\r") { line.removeLast() }
                            lineBytes.removeAll(keepingCapacity: true)
                            if let frame = parser.feedLine(line),
                               let element = HostStreamDecoder.decode(frame) {
                                switch element {
                                case .heartbeat(let head):
                                    heartbeats += 1
                                    // The single most useful line in the whole
                                    // log: `gap` is the observable that turns
                                    // "it felt like it dropped" into a number.
                                    log.log(.stream,
                                            String(format: "hb head=%@ gap=%.1fs",
                                                   head.map(String.init) ?? "?",
                                                   Date().timeIntervalSince(previous)),
                                            host: label)
                                case .event(let seq, _):
                                    events += 1
                                    if events == 1 {
                                        log.log(.stream, "first event seq=\(seq)", host: label)
                                    }
                                case .resync(let head):
                                    log.log(.stream, "RESYNC head=\(head) (cursor unserviceable)", host: label)
                                }
                                continuation.yield(element)
                            }
                        } else {
                            lineBytes.append(byte)
                        }
                    }
                    log.log(.stream,
                            String(format: "closed cleanly after %.0fs — %d events, %d heartbeats",
                                   Date().timeIntervalSince(dialedAt), events, heartbeats),
                            host: label)
                    continuation.finish()
                } catch {
                    if !(error is CancellationError) {
                        log.log(.stream,
                                String(format: "ERROR after %.1fs — %@",
                                       Date().timeIntervalSince(dialedAt), LFGClient.describe(error)),
                                host: label)
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Keepalive: tiny GET whose round-trip keeps the cellular NAT mapping warm
    /// and measures RTT. Returns the host's journal head (a cheap gap check).
    public func keepalivePing(timeout: TimeInterval = 5) async throws -> (head: Int64, rtt: TimeInterval) {
        struct P: Decodable { let seq: Int64? }
        let started = Date()
        do {
            let p = try await get("api/ping", timeout: timeout, as: P.self)
            let rtt = Date().timeIntervalSince(started)
            // RTT is how a DERP relay outs itself: a direct Tailscale path is
            // single-digit ms on LAN and tens of ms on a punched cellular path,
            // while a relayed one lands in the hundreds.
            ConnectionLog.shared.log(.keepalive,
                String(format: "rtt=%.0fms head=%lld", rtt * 1000, p.seq ?? 0), host: logLabel)
            return (head: p.seq ?? 0, rtt: rtt)
        } catch {
            ConnectionLog.shared.log(.keepalive,
                String(format: "FAILED after %.2fs — %@",
                       Date().timeIntervalSince(started), LFGClient.describe(error)),
                host: logLabel)
            throw error
        }
    }

    /// One bounded page of journaled events — the background-wake fetch shape
    /// (push wake / BGAppRefresh can't hold an SSE stream). Short timeout: a
    /// background execution window is ~30s total for everything.
    public func eventsPage(since: Int64, limit: Int = 500,
                           timeout: TimeInterval = 10) async throws -> EventsPage {
        var req = URLRequest(url: url("api/events/page", query: [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]))
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        let data = try await performRaw(req)
        return try EventsPage.decode(data)
    }
}
