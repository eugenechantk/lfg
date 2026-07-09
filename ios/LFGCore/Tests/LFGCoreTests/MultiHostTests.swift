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

    // MARK: Partial-outage routing (one host down, another up)

    // `Host` must be qualified in *type* position: Foundation exports `NSHost` as
    // `Host` on macOS, so a bare `Host` parameter is ambiguous (initializer
    // position resolves fine, which is why the older tests above don't need this).
    private static let hostA = LFGCore.Host(url: "a:1")                    // reachable
    private static let hostB = LFGCore.Host(url: "b:2", isDefault: true)   // down, marked default
    private static func upExceptB(_ h: LFGCore.Host) -> Bool { h.url != "b:2" }

    func testRouteLiveSessionGoesToItsOwnerWhenReachable() {
        let pick = MultiHost.routeHost(owner: Self.hostA, isClosed: false,
                                       reachable: Self.upExceptB, agnostic: Self.hostA)
        XCTAssertEqual(pick?.url, "a:1")
    }

    /// A live session's pane exists only on its own machine — never reroute it to a
    /// healthy host, or the message lands on a different agent.
    func testRouteLiveSessionStaysOnDownOwnerRatherThanRerouting() {
        let pick = MultiHost.routeHost(owner: Self.hostB, isClosed: false,
                                       reachable: Self.upExceptB, agnostic: Self.hostA)
        XCTAssertEqual(pick?.url, "b:2", "live session must fail honestly, not reroute")
    }

    /// The reported bug: a closed session must restart on a reachable host even when
    /// its owner (or the marked default) is down — transcripts are synced.
    func testRouteClosedSessionRerouteToReachableHostWhenOwnerDown() {
        let pick = MultiHost.routeHost(owner: Self.hostB, isClosed: true,
                                       reachable: Self.upExceptB, agnostic: Self.hostA)
        XCTAssertEqual(pick?.url, "a:1")
    }

    /// Closed sessions carry no owner (`reconcileResumable` drops host identity).
    func testRouteUnknownOwnerUsesAgnosticHost() {
        let pick = MultiHost.routeHost(owner: nil, isClosed: true,
                                       reachable: Self.upExceptB, agnostic: Self.hostA)
        XCTAssertEqual(pick?.url, "a:1")
    }

    func testRouteReturnsNilWhenNoOwnerAndNoReachableHost() {
        XCTAssertNil(MultiHost.routeHost(owner: nil, isClosed: true,
                                         reachable: { _ in false }, agnostic: nil))
    }

    func testIsOfflineOnlyForLiveSessionOnDownHost() {
        // live on a down host → offline
        XCTAssertTrue(MultiHost.isOffline(owner: Self.hostB, isClosed: false, reachable: Self.upExceptB))
        // live on a healthy host → not offline
        XCTAssertFalse(MultiHost.isOffline(owner: Self.hostA, isClosed: false, reachable: Self.upExceptB))
        // closed on a down host → revivable elsewhere, so NOT offline
        XCTAssertFalse(MultiHost.isOffline(owner: Self.hostB, isClosed: true, reachable: Self.upExceptB))
        // no owner → not offline
        XCTAssertFalse(MultiHost.isOffline(owner: nil, isClosed: false, reachable: Self.upExceptB))
    }

    /// End-to-end of the reported scenario: default host down, other host up.
    /// Everything host-agnostic must resolve to the reachable host.
    func testPartialOutageAgnosticWorkLandsOnReachableHost() {
        let hosts = [Self.hostA, Self.hostB]
        let agnostic = HostStore.defaultHost(hosts, reachable: Self.upExceptB)
        XCTAssertEqual(agnostic?.url, "a:1", "create/metadata/resume must skip the down default")
        // and a closed session routes there too
        XCTAssertEqual(MultiHost.routeHost(owner: nil, isClosed: true,
                                           reachable: Self.upExceptB, agnostic: agnostic)?.url, "a:1")
    }

    // MARK: Host recovery (resend what failed while a host was down)

    func testRecoveredHostsDetectsDownToUpTransition() {
        let before: [String: Reachability] = ["a:1": .hostUnreachable("timeout"), "b:2": .ok]
        let after: [String: Reachability] = ["a:1": .ok, "b:2": .ok]
        XCTAssertEqual(MultiHost.recoveredHosts(before: before, after: after), ["a:1"])
    }

    func testRecoveredHostsIgnoresStillUpAndStillDown() {
        let before: [String: Reachability] = ["a:1": .ok, "b:2": .hostUnreachable("x")]
        let after: [String: Reachability] = ["a:1": .ok, "b:2": .hostUnreachable("x")]
        XCTAssertTrue(MultiHost.recoveredHosts(before: before, after: after).isEmpty)
    }

    /// Cold start: `reachabilityByHost` is empty, so every host first appears as
    /// `.ok`. That must NOT count as a recovery or the resend sweep fires on launch.
    func testRecoveredHostsTreatsFirstSightingAsNotARecovery() {
        let after: [String: Reachability] = ["a:1": .ok, "b:2": .ok]
        XCTAssertTrue(MultiHost.recoveredHosts(before: [:], after: after).isEmpty)
    }

    func testRecoveredHostsHandlesBothHostsComingBack() {
        let before: [String: Reachability] = ["a:1": .hostUnreachable("x"), "b:2": .badResponse("HTTP 500")]
        let after: [String: Reachability] = ["a:1": .ok, "b:2": .ok]
        XCTAssertEqual(MultiHost.recoveredHosts(before: before, after: after), ["a:1", "b:2"])
    }

    /// A host that goes down does not count as recovered.
    func testRecoveredHostsIgnoresUpToDownTransition() {
        let before: [String: Reachability] = ["a:1": .ok]
        let after: [String: Reachability] = ["a:1": .hostUnreachable("gone")]
        XCTAssertTrue(MultiHost.recoveredHosts(before: before, after: after).isEmpty)
    }

    func testHostLabelUsesFriendlyNameFirstComponentElseURL() {
        XCTAssertEqual(Host(url: "http://x:8766", name: "Mac-Studio.local").label, "Mac-Studio")
        XCTAssertEqual(Host(url: "http://mac-studio:8766").label, "mac-studio:8766")
    }

    func testHostLabelPrefersUserDisplayNameShownInFull() {
        // User-set displayName wins over the resolved machine hostname and is
        // shown in full (no dot-truncation).
        let h = Host(url: "http://x:8766", name: "Mac-Studio.local", displayName: "Home Server v2.local")
        XCTAssertEqual(h.label, "Home Server v2.local")
        // Blank displayName falls back to the truncated machine hostname.
        XCTAssertEqual(Host(url: "http://x:8766", name: "Mac-Studio.local", displayName: "").label, "Mac-Studio")
    }

    func testHostDisplayNameRoundTripsThroughCoding() {
        let h = Host(url: "http://x:8766", name: "Mac.local", displayName: "My Box", isDefault: true)
        let decoded = HostStore.decode(HostStore.encode([h]))
        XCTAssertEqual(decoded.first?.displayName, "My Box")
        XCTAssertEqual(decoded.first?.name, "Mac.local")
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
