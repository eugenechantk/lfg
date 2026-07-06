import XCTest
@testable import LFGCore

final class ReadStateTests: XCTestCase {
    func testNeverOpenedButActiveIsUnread() {
        XCTAssertTrue(ReadState.isUnread(lastActivityAt: 1000, lastOpenedAt: nil))
    }

    func testActivityAfterOpenIsUnread() {
        XCTAssertTrue(ReadState.isUnread(lastActivityAt: 2000, lastOpenedAt: 1000))
    }

    func testOpenedAfterActivityIsRead() {
        XCTAssertFalse(ReadState.isUnread(lastActivityAt: 1000, lastOpenedAt: 2000))
    }

    func testOpenedExactlyAtActivityIsRead() {
        // Opening stamps "now"; equal timestamps mean the viewer is caught up.
        XCTAssertFalse(ReadState.isUnread(lastActivityAt: 1000, lastOpenedAt: 1000))
    }

    func testNoActivityIsNeverUnread() {
        XCTAssertFalse(ReadState.isUnread(lastActivityAt: nil, lastOpenedAt: nil))
        XCTAssertFalse(ReadState.isUnread(lastActivityAt: 0, lastOpenedAt: nil))
    }
}
