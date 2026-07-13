import XCTest
@testable import LFGCore

final class OptimisticSendReconciliationTests: XCTestCase {
    func testMatchingUserTurnRequiresLocalUserTranscriptEntry() {
        let messages = [
            SessionMessage(role: "assistant", kind: "text", text: "Ship it now"),
            SessionMessage(role: "user", kind: "thinking", text: "Ship it now")
        ]

        XCTAssertFalse(OptimisticSendReconciliation.containsMatchingUserTurn(
            matchText: "Ship it now",
            in: messages))
    }

    func testMatchingUserTurnNormalizesWhitespaceAndCase() {
        let messages = [
            SessionMessage(role: "user", kind: "text", text: "Please   Ship\nIt NOW")
        ]

        XCTAssertTrue(OptimisticSendReconciliation.containsMatchingUserTurn(
            matchText: "please ship it now",
            in: messages))
    }

    func testShortPendingTextDoesNotMatchAmbiguously() {
        let messages = [
            SessionMessage(role: "user", kind: "text", text: "ok")
        ]

        XCTAssertFalse(OptimisticSendReconciliation.containsMatchingUserTurn(
            matchText: "ok",
            in: messages))
    }

    func testQueueItemMatchingUsesNormalizedPendingPrefix() {
        let queue = [
            QueueItem(id: "q1", text: "Please   Ship\nIt Now With Extra Context", status: "delivered")
        ]

        XCTAssertEqual(
            OptimisticSendReconciliation.matchingQueueItem(
                matchText: "please ship it now",
                in: queue)?.id,
            "q1")
    }
}
