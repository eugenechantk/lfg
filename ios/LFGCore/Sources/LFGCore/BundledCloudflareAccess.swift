import Foundation

/// A private-build bootstrap payload. The app target may package this as an
/// ignored resource, then immediately copy the credential into device-only
/// Keychain storage on launch.
public struct BundledCloudflareAccessConfiguration: Sendable, Equatable {
    public let hostURL: String
    public let credential: CloudflareAccessCredential

    private struct Payload: Decodable {
        let hostURL: String
        let clientID: String
        let clientSecret: String
    }

    public init?(data: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }

        let hostURL = payload.hostURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = payload.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = payload.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty,
              !clientSecret.isEmpty,
              let canonicalURL = Self.canonicalHTTPSOrigin(for: hostURL) else { return nil }

        self.hostURL = canonicalURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.credential = CloudflareAccessCredential(clientID: clientID, clientSecret: clientSecret)
    }

    /// A bundled private host is additive: it makes a fresh install usable but
    /// never replaces the user's existing default or duplicates the same URL.
    public func addingHostIfNeeded(to hosts: [Host]) -> [Host] {
        guard !hosts.contains(where: { Self.canonicalHTTPSOrigin(for: $0.url) == hostURL }) else {
            return hosts
        }
        return HostStore.normalized(
            hosts + [Host(url: hostURL, isDefault: hosts.isEmpty)]
        )
    }

    private static func canonicalHTTPSOrigin(for value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }

        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = components.host?.lowercased()
        origin.port = components.port
        return origin.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
