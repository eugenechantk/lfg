import XCTest
@testable import LFGCore

final class SessionListReconciliationTests: XCTestCase {
    func testSessionListReconcileUsesCurrentLiveIdsForClosedFallback() {
        let host = Host(url: "air:8766")
        let sid = "e03fc30f-cb26-490d-b29d-3b29b8a77ae5"
        let closed = ResumableSession(sessionId: sid, title: "Recovered")

        // B1 mechanism: a previous rebuild may have considered `sid` live, but the
        // current visible live merge is empty. The synced closed fallback must be
        // allowed back into the same rebuilt list instead of being suppressed by
        // stale live ownership from an earlier pass.
        let out = MultiHost.reconcileSessionList(
            perHostLive: [(host, [])],
            closedPerHost: [[closed]])

        XCTAssertTrue(out.liveIds.isEmpty)
        XCTAssertEqual(out.visibleClosed.map(\.sessionId), [sid])
    }

    func testSessionListReconcileDropsClosedOnlyWhenCurrentlyLive() {
        let host = Host(url: "air:8766")
        let live = Session(sessionId: "live", title: "Live", agent: "aisdk")
        let closedLive = ResumableSession(sessionId: "live", title: "Live")
        let closedOther = ResumableSession(sessionId: "closed", title: "Closed")

        let out = MultiHost.reconcileSessionList(
            perHostLive: [(host, [live])],
            closedPerHost: [[closedLive, closedOther]])

        XCTAssertEqual(out.liveIds, ["live"])
        XCTAssertEqual(out.visibleClosed.map(\.sessionId), ["closed"])
    }

    func testSessionListReconcileSuppressesOptimisticAndResumedClosedRows() {
        let host = Host(url: "air:8766")
        let optimistic = Session(sessionId: "optimistic", title: "Pending", agent: "aisdk")
        let closedOptimistic = ResumableSession(sessionId: "optimistic", title: "Pending")
        let closedResumed = ResumableSession(sessionId: "resumed", title: "Resumed")
        let closedVisible = ResumableSession(sessionId: "visible", title: "Visible")

        let out = MultiHost.reconcileSessionList(
            perHostLive: [(host, [])],
            closedPerHost: [[closedOptimistic, closedResumed, closedVisible]],
            optimisticSessions: [optimistic],
            resumedIds: ["resumed"])

        XCTAssertEqual(out.optimistic.map(\.sessionId), ["optimistic"])
        XCTAssertEqual(out.visibleClosed.map(\.sessionId), ["visible"])
    }
}
