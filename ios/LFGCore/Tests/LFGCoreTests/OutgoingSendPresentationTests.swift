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

/// Cover for "banners are for terminal outcomes only".
///
/// The bug this pins: every failed outbox attempt raised a banner, but the
/// common cold-tailnet first-drain failure re-queues the row and sends fine on
/// the next pass — so the user got a banner for a message that was never in
/// trouble.
final class SendFailurePolicyTests: XCTestCase {

    /// The exact shape of the spurious banner: host down, so the row is
    /// re-queued and the queued bubble already says "will send when reachable".
    func testUnreachableHostRequeuesSilently() {
        let d = SendFailurePolicy.disposition(hostStillDown: true, hasAttachments: false)
        XCTAssertEqual(d, .requeued)
        XCTAssertFalse(d.announcesToUser)
    }

    /// Attachment sidecars are still on disk, so the send is replayable however
    /// it threw — and burning the row would strand them.
    func testAttachmentsAlwaysRequeueSilently() {
        for hostDown in [true, false] {
            let d = SendFailurePolicy.disposition(hostStillDown: hostDown, hasAttachments: true)
            XCTAssertEqual(d, .requeued, "hostDown=\(hostDown)")
            XCTAssertFalse(d.announcesToUser)
        }
    }

    /// The host answered and the message is what went wrong: nothing else will
    /// happen without the user, so say so.
    func testHostAnsweredAndRejectedIsTerminalAndAnnounced() {
        let d = SendFailurePolicy.disposition(hostStillDown: false, hasAttachments: false)
        XCTAssertEqual(d, .failed)
        XCTAssertTrue(d.announcesToUser)
    }

    func testBannerPrefersTheHostsOwnWords() {
        XCTAssertEqual(
            SendFailurePolicy.bannerMessage(reason: "directory not found: /Uzers/x"),
            "Message not sent — directory not found: /Uzers/x")
    }

    func testBannerFallsBackWhenThereIsNoReason() {
        let fallback = "Message not sent. Tap Retry on the message to try again."
        XCTAssertEqual(SendFailurePolicy.bannerMessage(reason: nil), fallback)
        XCTAssertEqual(SendFailurePolicy.bannerMessage(reason: "   "), fallback)
    }
}
