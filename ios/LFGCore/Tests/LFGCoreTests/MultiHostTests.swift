import XCTest
@testable import LFGCore

final class MultiHostTests: XCTestCase {

    // MARK: HostStore — migration (SC2)

    func testMigrateLegacyBaseURLBecomesOneDefaultHost() {
        let hosts = HostStore.migrate(hostsData: nil, legacyBaseURL: "mac-studio:8766")
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].url, "mac-studio:8766")
        XCTAssertTrue(hosts[0].isDefault)
    }

    func testMigrateEmptyLegacyYieldsNoHosts() {
        XCTAssertTrue(HostStore.migrate(hostsData: nil, legacyBaseURL: "").isEmpty)
        XCTAssertTrue(HostStore.migrate(hostsData: nil, legacyBaseURL: "   ").isEmpty)
        XCTAssertTrue(HostStore.migrate(hostsData: nil, legacyBaseURL: nil).isEmpty)
    }

    func testExistingHostListWinsOverLegacy() {
        let existing = HostStore.encode([Host(url: "a:1", isDefault: true), Host(url: "b:2")])
        let hosts = HostStore.migrate(hostsData: existing, legacyBaseURL: "legacy:9")
        XCTAssertEqual(hosts.map(\.url), ["a:1", "b:2"])
    }

    func testEncodeDecodeRoundTrip() {
        let input = [Host(url: "a:1", hostId: "id-a", name: "Studio.local", isDefault: true),
                     Host(url: "b:2", hostId: "id-b", name: "Laptop.local")]
        let decoded = HostStore.decode(HostStore.encode(input))
        XCTAssertEqual(decoded, input)
    }

    // MARK: HostStore — default enforcement + selection (SC6)

    func testNormalizedPicksFirstWhenNoDefault() {
        let out = HostStore.normalized([Host(url: "a:1"), Host(url: "b:2")])
        XCTAssertTrue(out[0].isDefault)
        XCTAssertFalse(out[1].isDefault)
    }

    func testNormalizedCollapsesMultipleDefaults() {
        let out = HostStore.normalized([Host(url: "a:1", isDefault: true), Host(url: "b:2", isDefault: true)])
        XCTAssertEqual(out.filter(\.isDefault).map(\.url), ["a:1"])
    }

    func testDefaultHostPrefersMarkedDefaultWhenReachable() {
        let hosts = [Host(url: "a:1"), Host(url: "b:2", isDefault: true)]
        let pick = HostStore.defaultHost(hosts) { _ in true }
        XCTAssertEqual(pick?.url, "b:2")
    }

    func testDefaultHostFallsBackWhenDefaultOffline() {
        let hosts = [Host(url: "a:1"), Host(url: "b:2", isDefault: true)]
        // default (b:2) offline → first reachable (a:1)
        let pick = HostStore.defaultHost(hosts) { $0.url == "a:1" }
        XCTAssertEqual(pick?.url, "a:1")
    }

    func testDefaultHostNilWhenNoneReachable() {
        let hosts = [Host(url: "a:1", isDefault: true), Host(url: "b:2")]
        XCTAssertNil(HostStore.defaultHost(hosts) { _ in false })
    }

    func testHostLabelUsesFriendlyNameFirstComponentElseURL() {
        XCTAssertEqual(Host(url: "http://x:8766", name: "Mac-Studio.local").label, "Mac-Studio")
        XCTAssertEqual(Host(url: "http://mac-studio:8766").label, "mac-studio:8766")
    }

    // MARK: MultiHost.mergeSessions (SC3, SC5 routing table)

    func testMergeTagsSessionsByHostAndDedupesFirstWins() {
        let hostA = Host(url: "a:1")
        let hostB = Host(url: "b:2")
        let s1 = Session(sessionId: "s1", title: "one", agent: "claude")
        let s2 = Session(sessionId: "s2", title: "two", agent: "claude")
        let s1dup = Session(sessionId: "s1", title: "one-b", agent: "claude")
        let merged = MultiHost.mergeSessions([(hostA, [s1, s2]), (hostB, [s1dup])])
        XCTAssertEqual(merged.sessions.map(\.id), ["s1", "s2"])       // dup dropped
        XCTAssertEqual(merged.hostBySession["s1"], "a:1")            // first host wins
        XCTAssertEqual(merged.hostBySession["s2"], "a:1")
    }

    // MARK: MultiHost.reconcileResumable (SC4)

    func testReconcileDedupesSyncedTranscriptsAcrossHosts() {
        let r = ResumableSession(sessionId: "r1", title: "t")
        // Same synced transcript listed by BOTH hosts → one entry.
        let out = MultiHost.reconcileResumable(perHost: [[r], [r]], liveIds: [])
        XCTAssertEqual(out.map(\.sessionId), ["r1"])
    }

    func testReconcileDropsSessionsLiveOnAnyHost() {
        let live = ResumableSession(sessionId: "live", title: "running")
        let closed = ResumableSession(sessionId: "closed", title: "done")
        // host B lists host A's LIVE session as resumable (phantom) → must drop.
        let out = MultiHost.reconcileResumable(perHost: [[live, closed]], liveIds: ["live"])
        XCTAssertEqual(out.map(\.sessionId), ["closed"])
    }

    func testReconcilePreservesFirstAppearanceOrder() {
        let a = ResumableSession(sessionId: "a")
        let b = ResumableSession(sessionId: "b")
        let out = MultiHost.reconcileResumable(perHost: [[a], [b, a]], liveIds: [])
        XCTAssertEqual(out.map(\.sessionId), ["a", "b"])
    }

    // MARK: HostInfo decode (SC1 client side)

    func testHostInfoDecodesAndIsLenient() throws {
        let full = #"{"hostId":"uuid-1","hostName":"Studio.local"}"#.data(using: .utf8)!
        let hi = try JSONDecoder().decode(HostInfo.self, from: full)
        XCTAssertEqual(hi.hostId, "uuid-1")
        XCTAssertEqual(hi.hostName, "Studio.local")
        // Missing fields must not hard-fail (lenient decoding convention).
        let empty = "{}".data(using: .utf8)!
        let hi2 = try JSONDecoder().decode(HostInfo.self, from: empty)
        XCTAssertEqual(hi2.hostId, "")
        XCTAssertEqual(hi2.hostName, "")
    }
}
