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
}
