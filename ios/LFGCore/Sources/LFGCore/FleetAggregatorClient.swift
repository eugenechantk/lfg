import Foundation

/// Where the fleet Live Activity is published from (`workers/fleet-aggregator`).
///
/// A Live Activity push replaces the card's whole content and iOS never merges two
/// senders, so with sessions on more than one host exactly one party may publish:
/// a Cloudflare Worker that merges every host's slice. The phone talks to that
/// Worker directly — for its push-to-start token, the broadcast channel, and card
/// start/end reports — so keeping the card alive needs NO lfg host to be awake.
///
/// The address and key are handed out once by any reachable host (the app is
/// already authenticated there) and cached, rather than baked into the binary.
public struct FleetAggregatorConfig: Codable, Equatable, Sendable {
    public var url: URL
    public var secret: String

    public init(url: URL, secret: String) {
        self.url = url
        self.secret = secret
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> FleetAggregatorConfig? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FleetAggregatorConfig.self, from: data)
    }

    /// A host's answer to `GET api/push/live-activity/aggregator`. `url: null`
    /// (or a server that predates the route) means "no aggregator; talk to hosts".
    public static func fromHostResponse(_ data: Data) -> FleetAggregatorConfig? {
        struct Response: Decodable { let url: String?; let secret: String? }
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let raw = r.url, let url = URL(string: raw), url.scheme == "https",
              let secret = r.secret, !secret.isEmpty else { return nil }
        return FleetAggregatorConfig(url: url, secret: secret)
    }
}

public struct FleetAggregatorClient: Sendable {
    public let config: FleetAggregatorConfig
    private let session: URLSession

    public init(config: FleetAggregatorConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Requests (pure — tested without a network)

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], json: [String: Any]? = nil) -> URLRequest {
        var comps = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return req
    }

    /// `deviceId` lets the Worker keep ONE current token per device: a rotation
    /// replaces the old token instead of adding a second, so one start is one card.
    public func startTokenRequest(_ hex: String, env: String, deviceId: String?) -> URLRequest {
        var body: [String: Any] = ["token": hex, "env": env]
        if let deviceId, !deviceId.isEmpty { body["deviceId"] = deviceId }
        return request("POST", "v1/start-token", json: body)
    }

    public func channelRequest(env: String) -> URLRequest {
        request("GET", "v1/channel", query: [URLQueryItem(name: "env", value: env)])
    }

    public func startedRequest() -> URLRequest { request("POST", "v1/started", json: [:]) }
    public func endedRequest() -> URLRequest { request("POST", "v1/ended", json: [:]) }

    // MARK: Calls

    @discardableResult
    private func perform(_ req: URLRequest) async throws -> Data {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw LFGError.decoding("non-HTTP response") }
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

    public func registerStartToken(_ hex: String, env: String, deviceId: String?) async throws {
        try await perform(startTokenRequest(hex, env: env, deviceId: deviceId))
    }

    /// `nil` is a normal answer: no channel configured for this APNs environment.
    public func channel(env: String) async throws -> String? {
        struct Response: Decodable { let channelId: String? }
        let data = try await perform(channelRequest(env: env))
        return try? JSONDecoder().decode(Response.self, from: data).channelId
    }

    public func reportStarted() async throws { try await perform(startedRequest()) }
    public func reportEnded() async throws { try await perform(endedRequest()) }
}
