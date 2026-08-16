import XCTest
@testable import LFGCore

final class QueueAckResolutionTests: XCTestCase {
    func testDeliveredRemovesTheRowOnceTheTurnIsLocal() {
        XCTAssertEqual(
            QueueAckResolution.resolve(ackKind: "delivered", transcriptHasMatchingUserTurn: true),
            .remove)
    }

    /// The resume path acks `delivered` the instant the host accepts the resume
    /// request — seconds before the revived agent writes anything. Dropping the
    /// row there leaves a hole in the conversation.
    func testDeliveredKeepsTheRowWhileTheTurnIsMissingLocally() {
        XCTAssertEqual(
            QueueAckResolution.resolve(ackKind: "delivered", transcriptHasMatchingUserTurn: false),
            .awaitTranscript)
    }

    func testFailedMarksTheRowRegardlessOfTheTranscript() {
        for present in [false, true] {
            XCTAssertEqual(
                QueueAckResolution.resolve(ackKind: "failed", transcriptHasMatchingUserTurn: present),
                .markFailed)
        }
    }

    func testUnknownAckKindsAreIgnored() {
        XCTAssertEqual(
            QueueAckResolution.resolve(ackKind: "queued", transcriptHasMatchingUserTurn: false),
            .ignore)
        XCTAssertEqual(
            QueueAckResolution.resolve(ackKind: "", transcriptHasMatchingUserTurn: true),
            .ignore)
    }

    func testOfflineMessageWithoutServerQueueCanBeRemovedLocally() {
        XCTAssertEqual(
            QueuedMessageRemovalResolution.resolve(outcome: .noServerRow),
            .removeLocally)
    }

    func testServerHeldMessageIsRemovedLocallyAfterServerAcceptsRemoval() {
        XCTAssertEqual(
            QueuedMessageRemovalResolution.resolve(outcome: .removed),
            .removeLocally)
    }

    /// A queue row the host has pruned (or never had) cannot execute, so the
    /// bubble must not be undeletable just because the id is stale. This is the
    /// case that stranded rows on screen with no way to dismiss them.
    func testMessageUnknownToTheServerIsRemovedLocally() {
        XCTAssertEqual(
            QueuedMessageRemovalResolution.resolve(outcome: .unknownToServer),
            .removeLocally)
    }

    func testAgentCommittedMessageStaysVisibleWhenServerRejectsRemoval() {
        XCTAssertEqual(
            QueuedMessageRemovalResolution.resolve(outcome: .rejected),
            .keepPending)
    }

    /// An offline/timed-out request says nothing about whether the message will
    /// run, so the row stays until the host can answer.
    func testFailedRequestKeepsTheRowVisible() {
        XCTAssertEqual(
            QueuedMessageRemovalResolution.resolve(outcome: .requestFailed),
            .keepPending)
    }
}
