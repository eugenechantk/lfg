// An offline host's sessions kept showing as "Working".
//
// Both of a client's sources for `busy`/`prompt` go silent together when a host
// drops — the journal because nothing can be delivered, and the REST snapshot
// because the merged list deliberately keeps serving that host's LAST GOOD
// sessions so a blip doesn't empty the list. The frozen snapshot still says
// `busy: true`, and once the journal's last word ages past
// `JournalFreshness.defaultTTL` it is re-asserted on every rebuild — so the
// handful of the Air's sessions that happened to be mid-turn when it went down
// read "Working" until it came back, surviving even a cold launch.
import Testing
import Foundation
@testable import LFGCore

@Suite("Offline host live claims")
struct OfflineHostLiveClaimsTests {
    // `Host.id` is its url. Fully qualified because Foundation exports NSHost as
    // `Host` on macOS, which makes a bare `Host` annotation ambiguous here.
    private let air = LFGCore.Host(url: "air:8766", name: "Air")
    private let pro = LFGCore.Host(url: "pro:8766", name: "Pro")

    private func session(_ id: String) -> Session {
        Session(sessionId: id, title: id)
    }

    /// Air owns a1/a2, Pro owns p1.
    private func owner(_ sid: String) -> LFGCore.Host? {
        sid.hasPrefix("a") ? air : pro
    }

    private func unreachable(down: Set<String>) -> Set<String> {
        MultiHost.unreachableLiveSessionIds(
            live: [session("a1"), session("a2"), session("p1")],
            owner: owner,
            reachable: { !down.contains($0.id) })
    }

    @Test("a down host's sessions are all retractable, the healthy host's are not")
    func retractsOnlyTheDownHost() {
        #expect(unreachable(down: [air.id]) == ["a1", "a2"])
    }

    @Test("everything reachable retracts nothing")
    func healthyFleetRetractsNothing() {
        #expect(unreachable(down: []).isEmpty)
    }

    @Test("a whole fleet down retracts everything — no session can still be Working")
    func wholeFleetDown() {
        #expect(unreachable(down: [air.id, pro.id]) == ["a1", "a2", "p1"])
    }

    @Test("a session with no known owner is left alone rather than guessed at")
    func unroutedSessionIsUntouched() {
        // Routing hasn't landed yet (a just-created session, say). Retracting on a
        // missing owner would blank live state for sessions on a healthy host.
        let out = MultiHost.unreachableLiveSessionIds(
            live: [session("a1")], owner: { _ in nil }, reachable: { _ in false })
        #expect(out.isEmpty)
    }

    // The grace window is the whole reason `reachable` must be the known-down
    // predicate and not `isLive`: a degraded host is blipping, and retracting
    // there would flicker every session in the list on a transient stall.
    @Test("a blipping host inside its grace window retracts nothing")
    func degradedHostIsNotRetracted() {
        let state = HostStateMachine.reduce(.live, .probeFailed(reason: "timeout"), now: Date())
        #expect(state.showsOfflineBanner == false)
        let out = MultiHost.unreachableLiveSessionIds(
            live: [session("a1")], owner: owner,
            reachable: { _ in !state.showsOfflineBanner })
        #expect(out.isEmpty)
    }
}
