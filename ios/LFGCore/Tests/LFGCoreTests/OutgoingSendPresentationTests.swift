import XCTest
@testable import LFGCore

final class OutgoingSendPresentationTests: XCTestCase {
    func testIdleLiveSessionSendsAsAFinishedBubble() {
        let p = OutgoingSendPresentation.classify(
            hostUnreachable: false, sessionNeedsResume: false,
            agentBusy: false, awaitingPrompt: false)

        XCTAssertEqual(p, .sentBubble)
        XCTAssertTrue(p.showsAsBubble)
        XCTAssertTrue(p.isConfirmed)
    }

    func testBusySessionWaitsInTheStrip() {
        let p = OutgoingSendPresentation.classify(
            hostUnreachable: false, sessionNeedsResume: false,
            agentBusy: true, awaitingPrompt: false)

        XCTAssertEqual(p, .queuedBehindTurn)
        XCTAssertFalse(p.showsAsBubble)
    }

    func testSessionSittingOnAPromptWaitsInTheStrip() {
        XCTAssertEqual(
            OutgoingSendPresentation.classify(
                hostUnreachable: false, sessionNeedsResume: false,
                agentBusy: false, awaitingPrompt: true),
            .queuedBehindTurn)
    }

    /// The feature: a closed session is a queued message, not a bubble, and not
    /// confirmed — the host has to revive a pane before anything can run.
    func testClosedSessionQueuesForResumeRatherThanRenderingABubble() {
        let p = OutgoingSendPresentation.classify(
            hostUnreachable: false, sessionNeedsResume: true,
            agentBusy: false, awaitingPrompt: false)

        XCTAssertEqual(p, .queuedForResume)
        XCTAssertFalse(p.showsAsBubble)
        XCTAssertFalse(p.isConfirmed)
    }

    /// A `busy` flag latched before the pane was reaped says nothing about the
    /// session the resume is about to create, so it must not win here.
    func testResumeBeatsAStaleBusyFlag() {
        XCTAssertEqual(
            OutgoingSendPresentation.classify(
                hostUnreachable: false, sessionNeedsResume: true,
                agentBusy: true, awaitingPrompt: true),
            .queuedForResume)
    }

    func testUnreachableHostBeatsEverything() {
        for needsResume in [false, true] {
            for busy in [false, true] {
                XCTAssertEqual(
                    OutgoingSendPresentation.classify(
                        hostUnreachable: true, sessionNeedsResume: needsResume,
                        agentBusy: busy, awaitingPrompt: busy),
                    .offlineQueued,
                    "needsResume=\(needsResume) busy=\(busy)")
            }
        }
    }

    /// Only the immediate path may claim the backend has the message. Every
    /// waiting state has to earn its accent colour from the transcript.
    func testNoWaitingStateIsEverConfirmedOrABubble() {
        for p: OutgoingSendPresentation in [.queuedBehindTurn, .queuedForResume, .offlineQueued] {
            XCTAssertFalse(p.isConfirmed, "\(p)")
            XCTAssertFalse(p.showsAsBubble, "\(p)")
        }
    }
}
