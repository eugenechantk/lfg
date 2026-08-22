import XCTest
@testable import LFGCore

final class SessionFocusTests: XCTestCase {
    func testDisappearingFocusedSessionClearsReadFocus() {
        let focused = SessionFocus.afterDisappearing("s1", focusedID: "s1")

        XCTAssertNil(focused)
        XCTAssertFalse(SessionFocus.isFocused("s1", focusedID: focused))
    }

    func testDisappearingOldDetailDoesNotClearNewFocus() {
        let focused = SessionFocus.afterDisappearing("old", focusedID: "new")

        XCTAssertEqual(focused, "new")
        XCTAssertTrue(SessionFocus.isFocused("new", focusedID: focused))
    }

    func testClearedFocusLeavesLaterMessageUnread() {
        let focused = SessionFocus.afterDisappearing("s1", focusedID: "s1")

        XCTAssertFalse(SessionFocus.isFocused("s1", focusedID: focused))
        XCTAssertTrue(ReadState.isUnread(lastMessageID: "unread-c-1",
                                         lastSeenMessageID: "blip-b-1"))
    }

    func testStillFocusedSessionSuppressesUnreadGrouping() {
        let focused = "s1"

        XCTAssertTrue(SessionFocus.isFocused("s1", focusedID: focused))
        XCTAssertFalse(SessionFocus.isFocused("s2", focusedID: focused))
    }

    func testFocusSnapshotCapturesTheExactCurrentListRow() {
        let rows = [(id: "s0", title: "Other"), (id: "s1", title: "Open")]

        let snapshot = SessionFocus.snapshotCandidate(
            "s1",
            candidates: rows,
            id: { $0.id }
        )

        XCTAssertEqual(snapshot?.title, "Open")
    }

    func testFocusSnapshotDoesNotGuessAnotherSession() {
        let snapshot = SessionFocus.snapshotCandidate(
            "missing",
            candidates: [(id: "s0", title: "Other")],
            id: { $0.id }
        )

        XCTAssertNil(snapshot)
    }
}
