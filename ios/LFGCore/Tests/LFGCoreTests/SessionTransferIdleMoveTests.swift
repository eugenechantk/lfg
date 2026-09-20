import XCTest
@testable import LFGCore

final class SessionTransferIdleMoveTests: XCTestCase {
    private let cloudflare530 = "<!doctype html>\n<!--[if lt IE 7]> <html class=\"no-js ie6 oldie\" lang=\"en-US\"> <![endif]-->"

    // MARK: movesWithoutSource

    func testIdleSessionMovesWithoutTheSourceEvenWhenItLooksUp() {
        XCTAssertTrue(SessionTransfer.movesWithoutSource(sourceKnownDown: false, busy: false, promptPending: false))
    }

    func testBusySessionOnAReachableSourceStillClosesFirst() {
        XCTAssertFalse(SessionTransfer.movesWithoutSource(sourceKnownDown: false, busy: true, promptPending: false))
    }

    func testAPendingPromptIsNotIdle() {
        XCTAssertFalse(SessionTransfer.movesWithoutSource(sourceKnownDown: false, busy: false, promptPending: true))
    }

    func testAKnownDownSourceAlwaysMovesWithoutIt() {
        XCTAssertTrue(SessionTransfer.movesWithoutSource(sourceKnownDown: true, busy: true, promptPending: true))
    }

    func testTheResultingPlanSkipsTheCloseForcesTheResumeAndDefersCleanup() {
        let plan = SessionTransfer.plan(
            sourceKnownDown: SessionTransfer.movesWithoutSource(sourceKnownDown: false, busy: false, promptPending: false))
        XCTAssertFalse(plan.closeSource)
        XCTAssertTrue(plan.force)
        XCTAssertTrue(plan.deferSourceClose)
    }

    // MARK: isEdgeOriginDown

    func testCloudflare530HtmlIsTheEdgeNotTheHost() {
        XCTAssertTrue(SessionTransfer.isEdgeOriginDown(status: 530, body: cloudflare530))
    }

    func testGateway502And504HtmlAreTheEdge() {
        XCTAssertTrue(SessionTransfer.isEdgeOriginDown(status: 502, body: "<html><head><title>502 Bad Gateway</title>"))
        XCTAssertTrue(SessionTransfer.isEdgeOriginDown(status: 504, body: "  \n<!DOCTYPE html><title>cloudflare</title>"))
        XCTAssertTrue(SessionTransfer.isEdgeOriginDown(status: 530, body: "error code: 1033"))
    }

    func testLfgsOwnJson502IsNotTheEdge() {
        // The codex resume path answers 502 with JSON on purpose.
        XCTAssertFalse(SessionTransfer.isEdgeOriginDown(status: 502, body: "{\"error\":\"codex exited: unknown variant\"}"))
    }

    func testOrdinaryStatusesAreNeverTheEdge() {
        XCTAssertFalse(SessionTransfer.isEdgeOriginDown(status: 500, body: cloudflare530))
        XCTAssertFalse(SessionTransfer.isEdgeOriginDown(status: 404, body: "no such session"))
        XCTAssertFalse(SessionTransfer.isEdgeOriginDown(status: 409, body: "{}"))
    }

    // MARK: the close-failure escalation (busy sessions)

    func testAnEdge530OnCloseMeansTheHostWentAway() {
        XCTAssertTrue(SessionTransfer.closeFailureIsUnreachable(LFGError.http(status: 530, body: cloudflare530)))
    }

    func testARealRefusalOnCloseStillAborts() {
        XCTAssertFalse(SessionTransfer.closeFailureIsUnreachable(LFGError.http(status: 500, body: "boom")))
        XCTAssertFalse(SessionTransfer.closeFailureIsUnreachable(LFGError.http(status: 502, body: "{\"error\":\"x\"}")))
    }
}
