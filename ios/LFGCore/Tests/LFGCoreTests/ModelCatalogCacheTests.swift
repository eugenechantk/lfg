import XCTest
@testable import LFGCore

final class ModelCatalogCacheTests: XCTestCase {

    private let pro = ModelCatalogResponse(agents: [
        "codex": AgentModelCatalog(version: "0.160.0", defaultModel: "gpt-6.1-sol",
                                   models: ["gpt-6.1-sol", "gpt-6-astra", "gpt-5.6-sol"],
                                   efforts: ["gpt-6.1-sol": ["low", "high"]]),
        "claude": AgentModelCatalog(defaultModel: "claude-opus-5-5",
                                    models: ["claude-opus-5-5", "claude-fable-5-1"]),
    ])
    private let air = ModelCatalogResponse(agents: [
        "codex": AgentModelCatalog(defaultModel: "gpt-6-astra", models: ["gpt-6-astra"]),
    ])

    // SC1: what the host said survives a relaunch, per host.
    func testRoundTripsEachHostsCatalog() {
        var cache = ModelCatalogCache()
        cache.record(pro, for: "pro", at: Date(timeIntervalSince1970: 100))
        cache.record(air, for: "air", at: Date(timeIntervalSince1970: 200))

        let restored = ModelCatalogCache.decode(cache.encoded())
        XCTAssertEqual(restored, cache)
        XCTAssertEqual(restored.catalogs["pro"]?.models(for: .codex), ["gpt-6.1-sol", "gpt-6-astra", "gpt-5.6-sol"])
        XCTAssertEqual(restored.catalogs["pro"]?.defaultModel(for: .codex), "gpt-6.1-sol")
        XCTAssertEqual(restored.catalogs["pro"]?.efforts(for: .codex, model: "gpt-6.1-sol"), ["low", "high"])
        XCTAssertEqual(restored.catalogs["air"]?.models(for: .codex), ["gpt-6-astra"])
        XCTAssertEqual(restored.entries["air"]?.fetchedAt, Date(timeIntervalSince1970: 200))
    }

    // A newer answer replaces the older one, and its time is what is kept.
    func testRecordingAgainReplacesTheEntry() {
        var cache = ModelCatalogCache()
        cache.record(air, for: "pro", at: Date(timeIntervalSince1970: 1))
        cache.record(pro, for: "pro", at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(cache.catalogs["pro"], pro)
        XCTAssertEqual(cache.entries["pro"]?.fetchedAt, Date(timeIntervalSince1970: 2))
    }

    // A first launch, a wiped default or a shape from a future build must
    // decode to "nothing saved" — never crash, never a half-read catalog.
    func testMissingOrCorruptDataIsAnEmptyCache() {
        XCTAssertEqual(ModelCatalogCache.decode(nil), ModelCatalogCache())
        XCTAssertEqual(ModelCatalogCache.decode(Data("{ truncated".utf8)), ModelCatalogCache())
        XCTAssertEqual(ModelCatalogCache.decode(Data("[1,2,3]".utf8)), ModelCatalogCache())
    }

    // A host removed in Settings must not leave its list behind forever.
    func testPruningKeepsOnlyConfiguredHosts() {
        var cache = ModelCatalogCache()
        cache.record(pro, for: "pro", at: Date())
        cache.record(air, for: "air", at: Date())
        let pruned = cache.pruned(keeping: ["pro"])
        XCTAssertEqual(Set(pruned.catalogs.keys), ["pro"])
    }
}
