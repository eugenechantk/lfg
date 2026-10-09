import Foundation

/// The model catalog each host last served, kept on the device.
///
/// `GET /api/models` is the authority on which models a host's CLIs offer, but
/// the app used to hold the answer in memory only, so every cold launch fell
/// back to the catalog compiled into the build — which stops at whatever was
/// current when it shipped (gpt-5.6 while hosts ran gpt-6.1). Keeping the
/// host's own answer makes the compiled catalog a first-launch-only floor.
public struct ModelCatalogCache: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var catalog: ModelCatalogResponse
        /// When the host served it. Diagnostic only: a stale entry still beats
        /// the compiled catalog, so nothing expires on age.
        public var fetchedAt: Date

        public init(catalog: ModelCatalogResponse, fetchedAt: Date) {
            self.catalog = catalog
            self.fetchedAt = fetchedAt
        }
    }

    /// Where the app keeps it in `UserDefaults.standard`. Shared with the
    /// Start Session intent, which runs in the app process.
    public static let defaultsKey = "lfg.modelCatalogCache.v1"

    /// Keyed by `Host.id`.
    public private(set) var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public var catalogs: [String: ModelCatalogResponse] {
        entries.mapValues(\.catalog)
    }

    public mutating func record(_ catalog: ModelCatalogResponse, for hostID: String, at date: Date) {
        entries[hostID] = Entry(catalog: catalog, fetchedAt: date)
    }

    public func pruned(keeping hostIDs: Set<String>) -> ModelCatalogCache {
        ModelCatalogCache(entries: entries.filter { hostIDs.contains($0.key) })
    }

    /// Missing or unreadable data is an empty cache, never an error.
    public static func decode(_ data: Data?) -> ModelCatalogCache {
        guard let data, let cache = try? JSONDecoder().decode(ModelCatalogCache.self, from: data) else {
            return ModelCatalogCache()
        }
        return cache
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
