import Foundation

/// A private-build bootstrap payload. The app target may package this as an
/// ignored resource, then immediately copy the credential into device-only
/// Keychain storage on launch.
public struct BundledCloudflareAccessConfiguration: Sendable, Equatable {
    public let hostURLs: [String]
    public let credential: CloudflareAccessCredential

    /// The first bundled origin remains the compatibility/default origin.
    public var hostURL: String { hostURLs[0] }

    private struct Payload: Decodable {
        let hostURL: String?
        let hostURLs: [String]?
        let clientID: String
        let clientSecret: String
    }

    public init?(data: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }

        let clientID = payload.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = payload.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty,
              !clientSecret.isEmpty else { return nil }

        let rawHostURLs: [String]
        if let hostURLs = payload.hostURLs {
            rawHostURLs = hostURLs
        } else if let hostURL = payload.hostURL {
            rawHostURLs = [hostURL]
        } else {
            return nil
        }

        var seen = Set<String>()
        var canonicalURLs: [String] = []
        for rawURL in rawHostURLs {
            guard let canonicalURL = Self.canonicalHTTPSOrigin(for: rawURL) else { return nil }
            if seen.insert(canonicalURL).inserted {
                canonicalURLs.append(canonicalURL)
            }
        }
        guard !canonicalURLs.isEmpty else { return nil }

        self.hostURLs = canonicalURLs
        self.credential = CloudflareAccessCredential(clientID: clientID, clientSecret: clientSecret)
    }

    /// Bundled private hosts are additive: they make a fresh install usable but
    /// never replace the user's existing default or duplicate the same origin.
    public func addingHostsIfNeeded(to hosts: [Host]) -> [Host] {
        var result = hosts
        for hostURL in hostURLs where !result.contains(where: {
            Self.canonicalHTTPSOrigin(for: $0.url) == hostURL
        }) {
            result.append(Host(url: hostURL, isDefault: result.isEmpty))
        }
        return result == hosts ? hosts : HostStore.normalized(result)
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
