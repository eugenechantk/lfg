import Foundation

/// A configured backend host. The multi-host client fans out to every host in
/// the list; each entry is one `lfg serve` machine on the Tailscale network.
///
/// Identity is the entered `url` (unique within the list). `hostId`/`name` are
/// resolved lazily from `GET /api/info`: `hostId` is the machine's stable uuid
/// (used to detect the SAME machine reached via two URLs — Tailscale IP vs
/// MagicDNS), and `name` is its friendly hostname for display.
public struct Host: Codable, Sendable, Hashable, Identifiable {
    public var url: String
    public var hostId: String?
    public var name: String?
    /// The default host for *creating* new sessions (there is exactly one).
    public var isDefault: Bool

    public var id: String { url }

    public init(url: String, hostId: String? = nil, name: String? = nil, isDefault: Bool = false) {
        self.url = url
        self.hostId = hostId
        self.name = name
        self.isDefault = isDefault
    }

    enum CodingKeys: String, CodingKey { case url, hostId, name, isDefault }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = (try c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        hostId = try c.decodeIfPresent(String.self, forKey: .hostId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        isDefault = (try c.decodeIfPresent(Bool.self, forKey: .isDefault)) ?? false
    }

    /// Short label for chips/pickers: the friendly hostname (first dotted
    /// component, so `Mac-Studio.local` → `Mac-Studio`), else a compact URL.
    public var label: String {
        if let name, !name.isEmpty {
            return String(name.split(separator: ".").first ?? Substring(name))
        }
        // Strip scheme + trailing port for a compact fallback.
        var s = url
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        return s
    }
}

/// Pure helpers for persisting + reconciling the host list. Kept free of
/// UserDefaults / UIKit so `swift test` can verify migration and default-host
/// selection deterministically; `AppSettings` is the thin persistence shell.
public enum HostStore {
    public static func decode(_ data: Data?) -> [Host] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([Host].self, from: data)) ?? []
    }

    public static func encode(_ hosts: [Host]) -> Data {
        (try? JSONEncoder().encode(hosts)) ?? Data()
    }

    /// Migrate persisted config into a host list. If a host list already exists,
    /// it wins. Otherwise a non-empty legacy single `baseURL` becomes a
    /// one-element list marked default. Empty/absent both → [].
    public static func migrate(hostsData: Data?, legacyBaseURL: String?) -> [Host] {
        let existing = decode(hostsData)
        if !existing.isEmpty { return normalized(existing) }
        let legacy = (legacyBaseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if legacy.isEmpty { return [] }
        return [Host(url: legacy, isDefault: true)]
    }

    /// Guarantee exactly one default: if none is marked (or several are), the
    /// first host becomes the sole default. Empty list stays empty.
    public static func normalized(_ hosts: [Host]) -> [Host] {
        guard !hosts.isEmpty else { return [] }
        if hosts.filter(\.isDefault).count == 1 { return hosts }
        return hosts.enumerated().map { i, h in
            var h = h; h.isDefault = (i == 0); return h
        }
    }

    /// Which host a NEW session should be created on: the marked default when
    /// it's reachable, otherwise the first reachable host, otherwise nil.
    /// "Reachable" is supplied by the caller (the store's per-host health).
    public static func defaultHost(_ hosts: [Host], reachable: (Host) -> Bool) -> Host? {
        if let def = hosts.first(where: { $0.isDefault }), reachable(def) { return def }
        return hosts.first(where: reachable)
    }
}
