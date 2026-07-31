import XCTest
@testable import LFGCore

final class RecentDirsTests: XCTestCase {
    func testPushOntoEmpty() {
        XCTAssertEqual(RecentDirs.pushing("/a/b", onto: []), ["/a/b"])
    }

    func testMostRecentGoesFirst() {
        let out = RecentDirs.pushing("/second", onto: ["/first"])
        XCTAssertEqual(out, ["/second", "/first"])
    }

    /// Re-selecting an existing entry must MOVE it, not duplicate it — otherwise
    /// the list degenerates into a history log and the cap evicts real entries.
    func testReselectPromotesWithoutDuplicating() {
        let out = RecentDirs.pushing("/c", onto: ["/a", "/b", "/c", "/d"])
        XCTAssertEqual(out, ["/c", "/a", "/b", "/d"])
        XCTAssertEqual(out.filter { $0 == "/c" }.count, 1)
    }

    func testCapEvictsOldest() {
        let out = RecentDirs.pushing("/new", onto: ["/1", "/2", "/3", "/4", "/5"], cap: 5)
        XCTAssertEqual(out, ["/new", "/1", "/2", "/3", "/4"])
        XCTAssertEqual(out.count, 5)
    }

    func testCapOfOneKeepsOnlyNewest() {
        XCTAssertEqual(RecentDirs.pushing("/new", onto: ["/old"], cap: 1), ["/new"])
    }

    /// A failed create must not push an empty row into the picker.
    func testBlankPathIsIgnored() {
        XCTAssertEqual(RecentDirs.pushing("", onto: ["/a"]), ["/a"])
        XCTAssertEqual(RecentDirs.pushing("   ", onto: ["/a"]), ["/a"])
        XCTAssertEqual(RecentDirs.pushing("\n", onto: []), [])
    }

    func testTrailingSlashIsNormalised() {
        let out = RecentDirs.pushing("/a/b/", onto: ["/a/b"])
        XCTAssertEqual(out, ["/a/b"], "trailing slash must not create a second entry")
    }

    func testRootIsPreserved() {
        XCTAssertEqual(RecentDirs.pushing("/", onto: []), ["/"])
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(RecentDirs.pushing("  /a/b  ", onto: []), ["/a/b"])
    }

    func testExistingBlanksAreDropped() {
        XCTAssertEqual(RecentDirs.pushing("/a", onto: ["", "  ", "/b"]), ["/a", "/b"])
    }

    func testNonPositiveCapReturnsExistingUnchanged() {
        XCTAssertEqual(RecentDirs.pushing("/a", onto: ["/b"], cap: 0), ["/b"])
    }

    func testRemoving() {
        XCTAssertEqual(RecentDirs.removing("/b", from: ["/a", "/b", "/c"]), ["/a", "/c"])
        XCTAssertEqual(RecentDirs.removing("/b/", from: ["/a", "/b"]), ["/a"])
        XCTAssertEqual(RecentDirs.removing("/zz", from: ["/a"]), ["/a"])
    }
}
