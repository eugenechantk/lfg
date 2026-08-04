import XCTest
@testable import LFGCore

/// `closed` moved from a client-side constant to a server-computed field. These
/// pin both halves of the contract: the client honours what the server says, and
/// the cross-host phantom filter — the one part a single server cannot do — stays.
final class ResumableClosedTests: XCTestCase {
    private func decode(_ json: String) throws -> ResumableSession {
        try JSONDecoder().decode(ResumableSession.self, from: Data(json.utf8))
    }

    func testDecodesServerComputedClosedFlag() throws {
        let r = try decode(#"{"sessionId":"s1","closed":true}"#)
        XCTAssertTrue(r.closed)
    }

    /// An older server omits the field. Appearing in `/api/sessions/resumable`
    /// has always meant "closed", so the default must preserve that.
    func testDefaultsToClosedWhenAnOlderServerOmitsTheField() throws {
        let r = try decode(#"{"sessionId":"s1"}"#)
        XCTAssertTrue(r.closed)
    }

    /// The server may legitimately say "not closed here" one day (e.g. once it
    /// gains peer awareness); the client must not override that with a constant.
    func testHonoursAnExplicitFalseRatherThanAssumingClosed() throws {
        let r = try decode(#"{"sessionId":"s1","closed":false}"#)
        XCTAssertFalse(r.closed)
    }

    /// The reason `closed` cannot be fully server-side: `~/.claude/projects` is
    /// synced and a server has no peer awareness, so host B reports host A's
    /// *running* session as closed-here. Only the client sees every host.
    func testCrossHostFilterDropsASessionLiveOnAnotherHost() {
        let hostBSaysClosed = [ResumableSession(sessionId: "live-on-A", closed: true)]

        let out = MultiHost.reconcileResumable(
            perHost: [hostBSaysClosed],
            liveIds: ["live-on-A"]      // host A is running it
        )

        XCTAssertTrue(out.isEmpty, "a session live on any host must not show as closed")
    }

    func testCrossHostFilterKeepsAGenuinelyClosedSessionAndDedupes() {
        let hostA = [ResumableSession(sessionId: "ended", closed: true)]
        let hostB = [ResumableSession(sessionId: "ended", closed: true)]   // same synced transcript

        let out = MultiHost.reconcileResumable(perHost: [hostA, hostB], liveIds: [])

        XCTAssertEqual(out.map(\.sessionId), ["ended"])
    }
}
