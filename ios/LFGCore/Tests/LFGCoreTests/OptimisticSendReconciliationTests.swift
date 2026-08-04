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

    /// The scan is tail-bounded so a queued message doesn't rescan a long
    /// transcript on every render while it waits. A just-sent turn is always at
    /// the tail; anything older than the window is deliberately out of scope.
    func testMatchingUserTurnScansOnlyTheMostRecentUserTurns() {
        let stale = SessionMessage(role: "user", kind: "text", text: "the older message")
        let filler = (0 ..< 40).map {
            SessionMessage(role: "user", kind: "text", text: "filler turn \($0)")
        }

        XCTAssertFalse(OptimisticSendReconciliation.containsMatchingUserTurn(
            matchText: "the older message",
            in: [stale] + filler))

        // …and the same text lands the moment it is inside the window.
        XCTAssertTrue(OptimisticSendReconciliation.containsMatchingUserTurn(
            matchText: "the older message",
            in: filler + [stale]))
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
