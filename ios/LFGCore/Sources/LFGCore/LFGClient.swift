import Foundation
import os

public enum LFGError: Error, LocalizedError, Sendable {
    case badURL
    case notReachable(underlying: String)
    /// A URLSession-level failure that kept its `URLError` code.
    ///
    /// Distinct from `notReachable` only because the **code** is load-bearing:
    /// `SendTerminalityPolicy` needs to tell "the request never went out" from
    /// "the request went out and we stopped listening", and the two are the
    /// same string. Reads identically to the user.
    case transport(code: Int?, underlying: String)
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
        case .transport(_, let u): return "Can't reach the host: \(u)"
        case .http(let s, let b): return "Server error \(s): \(b)"
        case .decoding(let m): return "Unexpected response: \(m)"
        case .streamStalled: return "Live stream stalled — reconnecting."
        }
    }

    /// A short line fit to show the user inline, next to a failed message.
    ///
    /// `errorDescription` is diagnostic — it pastes the raw response body, so a
    /// rejected create reads `Server error 400: {"error":"directory not found:
    /// ~/dev/inbox"}`. The server sends `{"error": "..."}` on every failure, so
    /// unwrap that one field and show the sentence by itself.
    public var userMessage: String {
        guard case .http(_, let body) = self else {
            return errorDescription ?? "Something went wrong."
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = obj["error"] as? String,
           !message.isEmpty {
            return message
        }
        return trimmed.isEmpty ? (errorDescription ?? "Something went wrong.") : trimmed
    }
}

public enum Reachability: Sendable, Equatable {
    case ok
    case hostUnreachable(String)   // no route / connection refused (tailnet or host down)
    case badResponse(String)       // reached something, but not a healthy lfg
}

/// Cloudflare Access machine credential for one configured host.
///
/// Deliberately not `Codable`: the app stores this value in Keychain and passes
/// it into `LFGClient`; it must never hitch a ride in the persisted Host JSON.
public struct CloudflareAccessCredential: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    fileprivate func apply(to request: inout URLRequest) {
        request.setValue(clientID, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
    }
}

/// Stateless async client for the lfg HTTP/SSE API. `Sendable` so it can be
/// shared across the actor boundary. Construct with the base URL the user sets
/// (loopback, LAN, or a Tailscale MagicDNS https URL).
public struct LFGClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let accessCredential: CloudflareAccessCredential?

    public init(baseURL: URL,
                session: URLSession = .shared,
                accessCredential: CloudflareAccessCredential? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.accessCredential = accessCredential
    }

    public init?(string: String,
                 session: URLSession = .shared,
                 accessCredential: CloudflareAccessCredential? = nil) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s) else { return nil }
        self.init(baseURL: url, session: session, accessCredential: accessCredential)
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

    /// A request for an API or host-owned resource. Access credentials are
    /// scoped to the exact origin (scheme + host + effective port), so a
    /// transcript's arbitrary external image URL can never receive them.
    public func resourceRequest(for resourceURL: URL) -> URLRequest {
        authenticated(URLRequest(url: resourceURL))
    }

    /// True when a request to `resourceURL` would carry this host's Access
    /// credential — i.e. a player that can't send headers (AVPlayer) must go
    /// through the app's own loader instead of fetching the URL directly.
    public func authenticatesRequests(to resourceURL: URL) -> Bool {
        accessCredential != nil && Self.sameOrigin(resourceURL, baseURL)
    }

    /// `GET /api/file?path=…` for a host-side absolute path. `maxWidth` asks the
    /// server for a downscaled JPEG rendition of a raster image (`w=`), which
    /// it buckets to 480/1200/2400 and caches; non-images ignore it.
    ///
    /// The path is escaped with `escapedForQueryValue` rather than handed to
    /// `URLQueryItem`: `+` is legal in a query, so `URLComponents` leaves it
    /// alone, and the server reads the value through `URLSearchParams`, which
    /// applies form decoding and turns it into a space. Screenshot names carry
    /// `+` routinely (`…-t+3.5s.jpg`) and every one of them 404'd.
    public func hostFileURL(forPath path: String, maxWidth: Int? = nil) -> URL? {
        var query = [URLQueryItem(name: "path", value: path)]
        if let maxWidth, maxWidth > 0 { query.append(URLQueryItem(name: "w", value: String(maxWidth))) }
        guard let base = url("api/file", query: query) as URL?,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return url("api/file", query: query) }
        comps.percentEncodedQuery = query
            .map { "\($0.name)=\(Self.escapedForQueryValue($0.value ?? ""))" }
            .joined(separator: "&")
        return comps.url ?? base
    }

    /// Percent-encode a query VALUE so no byte of it can be reinterpreted by the
    /// receiver — including the characters `URLComponents` considers legal in a
    /// query and therefore passes through (`+`, `?`, `;`) but a form decoder or
    /// a naive parser may not.
    static func escapedForQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+?;&=#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Load a host-owned image, document, or browser frame through the same
    /// authenticated transport as the API. External URLs remain credential-free.
    public func resourceData(from resourceURL: URL) async throws -> Data {
        try await performRaw(resourceRequest(for: resourceURL))
    }

    /// Download a potentially large protected resource to URLSession's
    /// temporary file rather than materializing it in memory. The caller must
    /// move/copy the returned file before the temporary location is reclaimed.
    public func downloadResource(from resourceURL: URL) async throws -> URL {
        let request = resourceRequest(for: resourceURL)
        do {
            let (file, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LFGError.decoding("non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LFGError.http(status: http.statusCode, body: "")
            }
            return file
        } catch let error as LFGError {
            throw error
        } catch {
            throw LFGError.notReachable(underlying: error.localizedDescription)
        }
    }

    /// Attach this host's Access credential unconditionally. For requests whose
    /// URL is derived from `baseURL` but can't pass the origin check, such as the
    /// ws/wss terminal socket.
    func applyAccessCredential(to request: inout URLRequest) {
        accessCredential?.apply(to: &request)
    }

    private func authenticated(_ request: URLRequest) -> URLRequest {
        guard let accessCredential,
              Self.sameOrigin(request.url, baseURL) else { return request }
        var request = request
        accessCredential.apply(to: &request)
        return request
    }

    private static func sameOrigin(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs,
              let lhsScheme = lhs.scheme?.lowercased(),
              let rhsScheme = rhs.scheme?.lowercased(),
              let lhsHost = lhs.host?.lowercased(),
              let rhsHost = rhs.host?.lowercased(),
              lhsScheme == rhsScheme,
              lhsHost == rhsHost else { return false }

        func effectivePort(_ url: URL, scheme: String) -> Int? {
            if let port = url.port { return port }
            switch scheme {
            case "https": return 443
            case "http": return 80
            default: return nil
            }
        }
        return effectivePort(lhs, scheme: lhsScheme) == effectivePort(rhs, scheme: rhsScheme)
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
    private func send(_ method: String, _ path: String, json body: [String: Any?]? = nil, timeout: TimeInterval = 20) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.timeoutInterval = timeout
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
            let (data, resp) = try await session.data(for: authenticated(req))
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

    // Phone sign-in deliberately bypasses transcript/attachment paths.
    public func phoneSignInTargets() async throws -> [PhoneSignInTarget] {
        try await get("api/browser-sign-in/targets", as: PhoneSignInTargets.self).targets
    }

    public func phoneSignInRequest(_ transfer: PhoneSignInTransfer) throws -> URLRequest {
        _ = try PhoneSignInPolicy.loginURL(baseURL.absoluteString)
        var request = URLRequest(url: url("api/browser-sign-in/transfer"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(transfer)
        return authenticated(request)
    }

    public func phoneSignInRequests(sessionID: String) async throws -> [PhoneSignInAgentRequest] {
        try await get("api/browser-sign-in/requests", query: [.init(name: "sessionId", value: sessionID)], as: PhoneSignInAgentRequests.self).requests
    }
    public func phoneSignInRequestStatus(_ id: String) async throws -> PhoneSignInAgentRequest {
        try await get("api/browser-sign-in/requests/\(id)", as: PhoneSignInAgentRequest.self)
    }
    public func cancelPhoneSignInRequest(_ id: String) async throws {
        _ = try await send("POST", "api/browser-sign-in/requests/\(id)/cancel", json: [:])
    }
    public func agentPhoneSignInRequest(_ id: String, cookies: [PhoneSignInCookie]) throws -> URLRequest {
        _ = try PhoneSignInPolicy.loginURL(baseURL.absoluteString)
        var request = URLRequest(url: url("api/browser-sign-in/requests/\(id)/complete"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Payload: Encodable { let cookies: [PhoneSignInCookie] }
        request.httpBody = try JSONEncoder().encode(Payload(cookies: cookies))
        return authenticated(request)
    }
    public func completePhoneSignInRequest(_ id: String, cookies: [PhoneSignInCookie]) async throws -> PhoneSignInAgentRequest {
        try await deliverPhoneSignIn(agentPhoneSignInRequest(id, cookies: cookies), as: PhoneSignInAgentRequest.self)
    }
    public func sendPhoneSignIn(_ transfer: PhoneSignInTransfer) async throws -> PhoneSignInResult {
        try await deliverPhoneSignIn(phoneSignInRequest(transfer), as: PhoneSignInResult.self)
    }
    private func deliverPhoneSignIn<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        // An ephemeral session prevents cookie bundles from entering a shared URL cache.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let transport = URLSession(configuration: configuration, delegate: PhoneSignInRedirectGuard(), delegateQueue: nil)
        defer { transport.invalidateAndCancel() }
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw LFGError.notReachable(underlying: "Sign-in could not be delivered. Check the destination before retrying.")
        }
        return try JSONDecoder().decode(T.self, from: data)
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

    public func models(refresh: Bool = false) async throws -> ModelCatalogResponse {
        try await get("api/models", query: refresh ? [URLQueryItem(name: "refresh", value: "1")] : [],
                      as: ModelCatalogResponse.self)
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

    /// One page of closed/resumable sessions, newest first.
    ///
    /// `q` widens the CORPUS, not the response: with a query the host searches
    /// every transcript it has rather than only the newest page, and returns the
    /// same page shape with the same `before`/`nextBefore` cursor. That is what
    /// lets search have its own pagination instead of being limited to whatever
    /// the list had already loaded. A host that predates the parameter simply
    /// ignores it and returns its normal page.
    public func resumable(limit: Int = 30,
                          before: Double? = nil,
                          q: String? = nil,
                          exclude: [String] = [],
                          timeout: TimeInterval = LFGClient.readTimeout) async throws -> ResumableResponse {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        if let q, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query.append(URLQueryItem(name: "q", value: q))
        }
        // Hidden-dir globs, filtered by the host BEFORE pagination. Filtering
        // only client-side starves the page: a churny population can own the
        // entire newest-mtime window, so a page of 60 yields a handful of
        // visible rows. Old hosts ignore the param; the client-side filter
        // stays as the backstop either way.
        for e in exclude { query.append(URLQueryItem(name: "exclude", value: e)) }
        return try await get("api/sessions/resumable",
                             query: query,
                             timeout: timeout,
                             as: ResumableResponse.self)
    }

    public func searchSessions(_ q: String, limit: Int = 60,
                               cursor: String? = nil, exclude: [String] = [],
                               timeout: TimeInterval = 45) async throws -> RankedSearchResponse {
        if cursor?.hasPrefix("legacy:") == true {
            let before = Double(String(cursor!.dropFirst("legacy:".count)))
            let page = try await resumable(limit: limit, before: before, q: q,
                                           exclude: exclude, timeout: timeout)
            return RankedSearchResponse(sessions: page.sessions,
                                        nextCursor: page.nextBefore.map { "legacy:\($0)" })
        }
        var query = [URLQueryItem(name: "q", value: q),
                     URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        for path in exclude { query.append(URLQueryItem(name: "exclude", value: path)) }
        for attempt in 0..<40 {
            do {
                return try await get("api/sessions/search", query: query, timeout: timeout,
                                     as: RankedSearchResponse.self)
            } catch LFGError.http(let status, _) where status == 503 && attempt < 39 {
                try await Task.sleep(for: .seconds(3))
            } catch LFGError.http(let status, _) where status == 409 && cursor != nil {
                var restarted = try await searchSessions(q, limit: limit, cursor: nil,
                                                         exclude: exclude, timeout: timeout)
                restarted.reset = true
                return restarted
            } catch LFGError.http(let status, _) where status == 404 {
                let page = try await resumable(limit: limit, q: q, exclude: exclude,
                                               timeout: timeout)
                return RankedSearchResponse(sessions: page.sessions,
                                            nextCursor: page.nextBefore.map { "legacy:\($0)" })
            }
        }
        throw LFGError.http(status: 503, body: "session search index is still warming")
    }

    public func messages(_ id: String, limit: Int = 40, full: Bool = false) async throws -> [SessionMessage] {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if full { q.append(URLQueryItem(name: "full", value: "1")) }
        return try await get("api/sessions/\(id)/messages", query: q, as: MessagesResponse.self).messages
    }

    public func childAgents(_ id: String) async throws -> [ChildAgentSession] {
        try await get(
            "api/sessions/\(id)/subagents",
            as: ChildAgentSessionsResponse.self
        ).agents
    }

    public func childAgentMessages(
        parentID: String,
        childID: String,
        limit: Int = 0,
        full: Bool = true
    ) async throws -> [SessionMessage] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if full { query.append(URLQueryItem(name: "full", value: "1")) }
        return try await get(
            "api/sessions/\(parentID)/subagents/\(childID)/messages",
            query: query,
            as: MessagesResponse.self
        ).messages
    }

    /// Current outbound message queue for a session — used as a poll-based
    /// fallback to reconcile optimistic sends when a live `queue` event is missed.
    public func queue(_ id: String) async throws -> [QueueItem] {
        try await get("api/sessions/\(id)/queue", as: QueueResponse.self).queue
    }

    public func messagesBackward(
        _ id: String,
        before: Int?,
        limit: Int = 220,
        maxBytes: Int? = nil
    ) async throws -> MessagesResponse {
        var q = [URLQueryItem(name: "page", value: "backward"),
                 URLQueryItem(name: "limit", value: String(limit))]
        if let before { q.append(URLQueryItem(name: "before", value: String(before))) }
        if let maxBytes { q.append(URLQueryItem(name: "maxBytes", value: String(maxBytes))) }
        return try await get("api/sessions/\(id)/messages", query: q, as: MessagesResponse.self)
    }

    /// Lazily walk a transcript from newest to oldest in bounded responses.
    ///
    /// The old history path requested as many as 5,000 messages as one JSON
    /// response. That is effectively free over loopback but can be ~10 MB and
    /// take minutes to finish beside a long-lived event stream through a
    /// Cloudflare Tunnel. Pull-based iteration is deliberate: the caller gets
    /// the newest page before the next network request starts, so it can render
    /// useful content immediately while older history continues loading.
    /// - Parameter firstPageByteLimit: byte budget for the FIRST (newest) page
    ///   only. First paint is the only page the user is waiting on — every later
    ///   one lands above content they are already reading — so it is requested
    ///   much smaller and the walk then returns to `pageByteLimit` through the
    ///   same cursor. At 48 KiB versus 256 KiB that is ~5x fewer bytes before
    ///   anything is on screen, which is the whole delay on a relayed path.
    ///   Pass `nil` to use `pageByteLimit` for every page.
    public func messageHistoryPages(
        _ id: String,
        limit: Int = 5_000,
        pageSize: Int = 500,
        pageByteLimit: Int? = 256 * 1024,
        firstPageByteLimit: Int? = 48 * 1024,
        pageRetryDelay: Duration = .seconds(2)
    ) -> MessageHistoryPages {
        let clamp: (Int) -> Int = { min(1024 * 1024, max(16 * 1024, $0)) }
        return MessageHistoryPages(
            client: self,
            sessionID: id,
            maxMessages: min(5_000, max(0, limit)),
            pageSize: min(500, max(1, pageSize)),
            pageByteLimit: pageByteLimit.map(clamp),
            firstPageByteLimit: firstPageByteLimit.map(clamp) ?? pageByteLimit.map(clamp),
            pageRetryDelay: pageRetryDelay
        )
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
            "force": r.force == true ? true : nil,
        ])
        return try JSONDecoder().decode(NewSessionResponse.self, from: data)
    }

    /// Transfer pre-flight: does this host hold the synced transcript for `id`,
    /// and how fresh is its copy? Throws `.http(404)` on a server that predates
    /// the route — callers treat that as "unknown", not "missing".
    public func transcriptStatus(_ id: String) async throws -> TranscriptStatus {
        try await get("api/sessions/\(id)/transcript-status", timeout: 12, as: TranscriptStatus.self)
    }

    public func fork(_ r: ForkRequest) async throws -> NewSessionResponse {
        let data = try await send("POST", "api/sessions/fork", json: [
            "sessionId": r.sessionId, "model": r.model, "user": r.user,
        ])
        return try JSONDecoder().decode(NewSessionResponse.self, from: data)
    }

    /// Switch tools using an immutable snapshot and the explicitly selected model.
    public func handoff(sessionId: String, to selection: AgentModelSelection, user: String? = nil) async throws -> NewSessionResponse {
        let data = try await send("POST", "api/sessions/handoff", json: [
            "sessionId": sessionId, "agent": selection.agent.rawValue, "model": selection.model, "user": user,
        ], timeout: 90)
        let response = try JSONDecoder().decode(NewSessionResponse.self, from: data)
        guard response.ok != false, response.agent == selection.agent.rawValue,
              let id = response.sessionId, !id.isEmpty, id != sessionId else {
            throw LFGError.decoding("Host did not return a new \(selection.agent.displayName) session")
        }
        return response
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
        return authenticated(req)
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

    /// Remove a message only if LFG has not committed it to the agent yet.
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

    /// Upload attachment bytes for a session; the server persists them and returns
    /// an absolute path to include in a message (the agent reads local file paths
    /// — images, PDFs, text — as input).
    ///
    /// `filename` is what the file is called on the host, and therefore what the
    /// transcript card is labelled: pass the real name whenever one exists. It
    /// travels percent-encoded because HTTP headers are latin-1 and real
    /// filenames are not; the server re-sanitizes it regardless.
    public func upload(
        _ sessionID: String,
        data: Data,
        contentType: String,
        filename: String? = nil
    ) async throws -> String {
        var req = URLRequest(url: url("api/sessions/\(sessionID)/upload"))
        req.httpMethod = "POST"
        // Videos and large documents are far heavier than the photos this
        // endpoint used to carry; 30s was a timeout on a slow relayed path.
        req.timeoutInterval = 120
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let filename, !filename.isEmpty {
            let encoded = filename.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "._-"))
            ) ?? filename
            req.setValue(encoded, forHTTPHeaderField: "X-LFG-Filename")
        }
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

    /// The broadcast channel this device's fleet card must subscribe to.
    ///
    /// Replaces update-token registration entirely. A card started with this
    /// channel id is addressable by the server forever after — no background wake,
    /// nothing to hand back. `nil` is a normal answer, not an error: broadcast
    /// capability is a toggle in Apple's developer portal, so a server that has no
    /// channel yet says so and the app simply lets the server start the card.
    public func liveActivityChannel(env: String) async throws -> String? {
        struct Response: Decodable { let channelId: String? }
        // POST with the env in the body, not GET with a query string: `send`
        // builds its URL by appending a PATH component, so a "?" would be
        // percent-escaped into the path and the server would never see the query.
        let data = try await send("POST", "api/push/live-activity/channel", json: ["env": env])
        return try JSONDecoder().decode(Response.self, from: data).channelId
    }

    /// Where the fleet Live Activity is published from, if this deployment has an
    /// aggregator (`workers/fleet-aggregator`). `nil` means "talk to hosts as
    /// before"; a server that predates the route throws (404) and callers treat
    /// that the same way.
    public func liveActivityAggregator() async throws -> FleetAggregatorConfig? {
        FleetAggregatorConfig.fromHostResponse(try await send("GET", "api/push/live-activity/aggregator"))
    }

    /// Tell the server this app just created a fleet card.
    ///
    /// Carries no payload: with the channel there is no longer any per-card secret
    /// to hand over, and the server needs only the FACT so it adopts the card
    /// rather than push-to-starting a second one beside it.
    public func reportLiveActivityStarted() async throws {
        _ = try await send("POST", "api/push/live-activity/started", json: [:])
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
    /// at `HostLinkPolicy.staleTimeout` (20s ≈ two missed 10s heartbeats), widened
    /// up to 2× on a slow path — see `PathQuality`. `quality` defaults to "nothing
    /// measured", which reproduces the fixed 20s exactly.
    public func events(since: Int64,
                       quality: PathQuality = PathQuality()) -> AsyncThrowingStream<HostStreamElement, Error> {
        let target = url("api/events", query: [URLQueryItem(name: "since", value: String(since))])
        let baseRequest = resourceRequest(for: target)
        let session = self.session
        let staleTimeout = HostLinkPolicy.staleTimeout(for: quality)
        let label = logLabel
        let log = ConnectionLog.shared
        return AsyncThrowingStream { continuation in
            let task = Task {
                let dialedAt = Date()
                // The quality and the watchdog it bought are logged on every dial
                // so a stall in the timeline can be read against the timeout that
                // was actually in force, not the one in the source.
                log.log(.stream,
                        String(format: "dial since=%lld %@ stale=%.0fs",
                               since, quality.summary, staleTimeout),
                        host: label)
                var req = baseRequest
                req.httpMethod = "GET"
                // NOT .infinity: URLSession's timeoutInterval is an IDLE timeout
                // (resets on every received byte), so a black-holed connect (TCP
                // accepted by the kernel, headers never arriving — SIGSTOPed or
                // vanished server) has to be bounded or it hangs forever.
                //
                // But it spans the WHOLE request, not just the connect. Hardcoding
                // it to 18 therefore capped the byte-stall watchdog below at 18s no
                // matter what `staleTimeout` said: on a relayed path this dial logs
                // `stale=40s` and URLSession still killed the stream at ~18s of
                // quiet. Across every 2026-08-16 connection log the watchdog's
                // "STALL — no bytes" line appears ZERO times and `-1001 timedOut`
                // at 18–21s idle appears constantly — it had never once fired.
                // Heartbeats are 10s apart and this path routinely jitters them to
                // 10–11s, so two delayed in a row killed a stream the policy was
                // willing to keep.
                req.timeoutInterval = HostLinkPolicy.streamRequestTimeout(for: quality)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                // The connect phase keeps its own bound, since the byte watchdog
                // below can only start once headers are in hand. Same mechanism as
                // that watchdog: finishing the continuation runs `onTermination`,
                // which cancels this task and with it the URLSession request.
                // `AsyncBytes` is not Sendable, so it cannot be raced across a task
                // group — the flag is what crosses, not the stream.
                let gotHeaders = OSAllocatedUnfairLock(initialState: false)
                let headerWatchdog = Task {
                    try? await Task.sleep(for: .seconds(HostLinkPolicy.headersTimeout))
                    if Task.isCancelled { return }
                    guard !gotHeaders.withLock({ $0 }) else { return }
                    log.log(.stream,
                            String(format: "no response headers in %.0fs, giving up",
                                   HostLinkPolicy.headersTimeout),
                            host: label)
                    continuation.finish(throwing: LFGError.streamStalled)
                }
                defer { headerWatchdog.cancel() }
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    gotHeaders.withLock { $0 = true }
                    headerWatchdog.cancel()
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

/// Pull-based transcript history sequence returned by
/// `LFGClient.messageHistoryPages`. Each `next()` advances one cursor and may
/// retry that same cursor once, which makes page delivery—not merely request
/// size—progressive without restarting already-delivered history.
public struct MessageHistoryPages: AsyncSequence, Sendable {
    public typealias Element = [SessionMessage]

    private let client: LFGClient
    private let sessionID: String
    private let maxMessages: Int
    private let pageSize: Int
    private let pageByteLimit: Int?
    private let firstPageByteLimit: Int?
    private let pageRetryDelay: Duration

    fileprivate init(client: LFGClient, sessionID: String,
                     maxMessages: Int, pageSize: Int,
                     pageByteLimit: Int?, firstPageByteLimit: Int?,
                     pageRetryDelay: Duration) {
        self.client = client
        self.sessionID = sessionID
        self.maxMessages = maxMessages
        self.pageSize = pageSize
        self.pageByteLimit = pageByteLimit
        self.firstPageByteLimit = firstPageByteLimit
        self.pageRetryDelay = pageRetryDelay
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            client: client,
            sessionID: sessionID,
            maxMessages: maxMessages,
            pageSize: pageSize,
            pageByteLimit: pageByteLimit,
            firstPageByteLimit: firstPageByteLimit,
            pageRetryDelay: pageRetryDelay
        )
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let client: LFGClient
        private let sessionID: String
        private let maxMessages: Int
        private let pageSize: Int
        private let pageByteLimit: Int?
        private let firstPageByteLimit: Int?
        private let pageRetryDelay: Duration
        private var before: Int?
        private var delivered = 0
        private var seenCursors: Set<Int> = []
        private var finished = false

        fileprivate init(client: LFGClient, sessionID: String,
                         maxMessages: Int, pageSize: Int,
                         pageByteLimit: Int?, firstPageByteLimit: Int?,
                         pageRetryDelay: Duration) {
            self.client = client
            self.sessionID = sessionID
            self.maxMessages = maxMessages
            self.pageSize = pageSize
            self.pageByteLimit = pageByteLimit
            self.firstPageByteLimit = firstPageByteLimit
            self.pageRetryDelay = pageRetryDelay
        }

        public mutating func next() async throws -> [SessionMessage]? {
            try Task.checkCancellation()
            guard !finished, delivered < maxMessages else { return nil }

            let requestLimit = Swift.min(pageSize, maxMessages - delivered)
            let page: MessagesResponse
            do {
                page = try await requestPage(limit: requestLimit)
            } catch {
                try Task.checkCancellation()
                try await Task.sleep(for: pageRetryDelay)
                page = try await requestPage(limit: requestLimit)
            }
            guard !page.messages.isEmpty else {
                finished = true
                return nil
            }

            // A compatible server respects the requested limit. Keep the client
            // cap authoritative even if an older or drifting host returns more.
            let messages = page.messages.count <= requestLimit
                ? page.messages
                : Array(page.messages.suffix(requestLimit))
            delivered += messages.count

            if delivered >= maxMessages {
                finished = true
            } else if let next = page.nextBefore,
                      seenCursors.insert(next).inserted {
                before = next
            } else {
                // nil means the beginning; a repeat is malformed server state.
                // Both terminate rather than spinning on the same page forever.
                finished = true
            }
            return messages
        }

        /// Byte budget for the request about to go out. `delivered == 0` is the
        /// first (newest) page — the only one the user is actually waiting on,
        /// and the one a retry must also keep small.
        private var currentByteLimit: Int? {
            delivered == 0 ? firstPageByteLimit : pageByteLimit
        }

        private func requestPage(limit: Int) async throws -> MessagesResponse {
            try await client.messagesBackward(
                sessionID,
                before: before,
                limit: limit,
                maxBytes: currentByteLimit
            )
        }
    }
}

/// Never replay a credential-bearing POST or host access headers to a redirect destination.
private final class PhoneSignInRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
