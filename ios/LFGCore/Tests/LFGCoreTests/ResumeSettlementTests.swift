import XCTest
@testable import LFGCore

/// `MultiHost.settledResumes` — when an id-stable (codex) resume stops
/// suppressing its own closed row. Regression for 2026-09-06: a resume whose
/// pane died during codex bootstrap left the session neither live nor closed
/// until app relaunch.
final class ResumeSettlementTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_788_688_573)

    func testStaysSuppressedWhileWaitingWithinTTL() {
        let settled = MultiHost.settledResumes(
            pending: ["codex-1": t0], liveIds: [], now: t0.addingTimeInterval(5))
        XCTAssertTrue(settled.isEmpty)
    }

    func testSettlesOnceSeenLive() {
        let settled = MultiHost.settledResumes(
            pending: ["codex-1": t0], liveIds: ["codex-1"], now: t0.addingTimeInterval(2))
        XCTAssertEqual(settled, ["codex-1"])
    }

    func testSettlesAfterTTLWhenTheReviveNeverLanded() {
        let settled = MultiHost.settledResumes(
            pending: ["codex-1": t0], liveIds: [], now: t0.addingTimeInterval(61))
        XCTAssertEqual(settled, ["codex-1"])
        XCTAssertTrue(MultiHost.settledResumes(
            pending: ["codex-1": t0], liveIds: [], now: t0.addingTimeInterval(59)).isEmpty)
    }

    func testOnlyTheSettledIdsAreReturned() {
        let settled = MultiHost.settledResumes(
            pending: ["live": t0, "fresh": t0.addingTimeInterval(50), "stale": t0],
            liveIds: ["live"], now: t0.addingTimeInterval(61))
        XCTAssertEqual(settled, ["live", "stale"])
    }

    func testASettledResumeReturnsToTheClosedList() {
        // Once lifted from `resumedIds`, reconcileSessionList shows the closed row again.
        let host = Host(url: "http://127.0.0.1:8766", hostId: "pro", name: "Pro")
        let closed = ResumableSession(sessionId: "codex-1", cwd: "/x", mtime: 1, closed: true)
        let hidden = MultiHost.reconcileSessionList(
            perHostLive: [(host: host, sessions: [])], closedPerHost: [[closed]], resumedIds: ["codex-1"])
        XCTAssertTrue(hidden.visibleClosed.isEmpty)
        let shown = MultiHost.reconcileSessionList(
            perHostLive: [(host: host, sessions: [])], closedPerHost: [[closed]], resumedIds: [])
        XCTAssertEqual(shown.visibleClosed.map(\.sessionId), ["codex-1"])
    }
}
