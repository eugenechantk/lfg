import Foundation
import Security
import LFGCore

enum HostCredentialStoreError: LocalizedError {
    case invalidHostURL
    case invalidCredential
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidHostURL:
            return "Enter a valid HTTP or HTTPS host address."
        case .invalidCredential:
            return "Cloudflare Access requires both a Client ID and Client Secret."
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "The credential could not be saved in Keychain (\(detail))."
        }
    }
}

/// Device-local Cloudflare Access credentials, keyed by the configured host's
/// canonical origin. Nothing secret is stored in UserDefaults or Host Codable
/// state, and `ThisDeviceOnly` prevents the machine credential from silently
/// migrating to another phone through an encrypted backup.
final class HostCredentialStore: @unchecked Sendable {
    static let shared = HostCredentialStore()

    private let service = "dev.omg.lfg.cloudflare-access"

    private struct Record: Codable {
        let clientID: String
        let clientSecret: String
    }

    func credential(forHostURL hostURL: String) -> CloudflareAccessCredential? {
        guard let account = Self.accountKey(for: hostURL) else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        return CloudflareAccessCredential(
            clientID: record.clientID,
            clientSecret: record.clientSecret
        )
    }

    func save(_ credential: CloudflareAccessCredential, forHostURL hostURL: String) throws {
        guard let account = Self.accountKey(for: hostURL) else {
            throw HostCredentialStoreError.invalidHostURL
        }
        let clientID = credential.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = credential.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw HostCredentialStoreError.invalidCredential
        }
        let data = try JSONEncoder().encode(Record(clientID: clientID, clientSecret: clientSecret))
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = identity
            for (key, value) in update { add[key] = value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw HostCredentialStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw HostCredentialStoreError.keychain(status)
        }
    }

    func remove(forHostURL hostURL: String) throws {
        guard let account = Self.accountKey(for: hostURL) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HostCredentialStoreError.keychain(status)
        }
    }

    func move(from oldURL: String, to newURL: String) throws {
        guard let oldAccount = Self.accountKey(for: oldURL),
              let newAccount = Self.accountKey(for: newURL),
              oldAccount != newAccount,
              let credential = credential(forHostURL: oldURL) else { return }
        try save(credential, forHostURL: newURL)
        try remove(forHostURL: oldURL)
    }

    func client(forHostURL hostURL: String) -> LFGClient? {
        LFGClient(string: hostURL, accessCredential: credential(forHostURL: hostURL))
    }

    func client(forResourceURL resourceURL: URL) -> LFGClient? {
        guard let origin = Self.originString(for: resourceURL) else { return nil }
        return client(forHostURL: origin)
    }

    static func accountKey(for hostURL: String) -> String? {
        var value = hostURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if !value.contains("://") { value = "http://" + value }
        guard let url = URL(string: value) else { return nil }
        return originString(for: url)
    }

    private static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
