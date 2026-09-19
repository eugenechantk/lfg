import XCTest
@testable import LFGCore

final class ManualUnreadTests: XCTestCase {

    func testAfterOpeningClearsOnlyOpenedSession() {
        let flags: Set<String> = ["s1", "s2", "s3"]

        XCTAssertEqual(ManualUnread.afterOpening("s2", flags: flags), ["s1", "s3"])
    }

    func testAfterOpeningLeavesUnrelatedFlagsUntouched() {
        let flags: Set<String> = ["s1", "s3"]

        XCTAssertEqual(ManualUnread.afterOpening("missing", flags: flags), flags)
    }

    func testCanMarkUnreadRejectsPlaceholderAndEmptyIDs() {
        XCTAssertFalse(ManualUnread.canMarkUnread(""))
        XCTAssertFalse(ManualUnread.canMarkUnread("local-123"))
    }

    func testCanMarkUnreadAcceptsServerSessionID() {
        XCTAssertTrue(ManualUnread.canMarkUnread("session-123"))
    }

    func testListActionOffersMarkUnreadForReadRow() {
        XCTAssertEqual(ManualUnread.listAction(sessionID: "s1", isUnread: false, isClosed: false), .markUnread)
    }

    func testListActionOffersMarkReadForUnreadRow() {
        XCTAssertEqual(ManualUnread.listAction(sessionID: "s1", isUnread: true, isClosed: false), .markRead)
    }

    func testListActionIsNilForPlaceholderAndClosed() {
        XCTAssertNil(ManualUnread.listAction(sessionID: "local-1", isUnread: false, isClosed: false))
        XCTAssertNil(ManualUnread.listAction(sessionID: "", isUnread: true, isClosed: false))
        XCTAssertNil(ManualUnread.listAction(sessionID: "s1", isUnread: false, isClosed: true))
        XCTAssertNil(ManualUnread.listAction(sessionID: "s1", isUnread: true, isClosed: true))
    }
}
