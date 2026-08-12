import XCTest
@testable import LFGCore

final class DirectoryFilterIndicatorTests: XCTestCase {
    func testNoFilterIsOff() {
        let i = DirectoryFilterIndicator.resolve(hasHiddenDirectories: false, hiddenLiveSessionCount: 0)
        XCTAssertEqual(i, .off)
        XCTAssertFalse(i.isActive)
        XCTAssertNil(i.badge)
    }

    /// The bug this type exists for: a configured filter that happens to be
    /// hiding nothing live must still read as active, or the list is silently
    /// filtered with no trace in the chrome.
    func testConfiguredFilterHidingNothingLiveIsStillActive() {
        let i = DirectoryFilterIndicator.resolve(hasHiddenDirectories: true, hiddenLiveSessionCount: 0)
        XCTAssertEqual(i, .active)
        XCTAssertTrue(i.isActive)
        XCTAssertNil(i.badge, "nothing live to count, so no number — but still active")
    }

    func testConfiguredFilterHidingLiveSessionsBadgesTheCount() {
        let i = DirectoryFilterIndicator.resolve(hasHiddenDirectories: true, hiddenLiveSessionCount: 3)
        XCTAssertEqual(i, .activeWithCount(3))
        XCTAssertTrue(i.isActive)
        XCTAssertEqual(i.badge, 3)
    }

    /// A count with no configured filter is incoherent; the mute list is the
    /// authority, so it wins.
    func testCountWithoutAFilterIsStillOff() {
        XCTAssertEqual(
            DirectoryFilterIndicator.resolve(hasHiddenDirectories: false, hiddenLiveSessionCount: 5),
            .off)
    }
}
