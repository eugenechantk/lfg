import XCTest
@testable import LFGCore

final class FleetCountTrustTests: XCTestCase {
    private func host(_ id: String, down: Bool = false) -> FleetCountTrust.HostStatus {
        .init(id: id, knownDown: down)
    }

    func testNoHostsIsNotTrustworthy() {
        XCTAssertFalse(FleetCountTrust.isTrustworthy(hosts: [], liveFetchedHostIds: []))
    }

    func testNothingFetchedYetIsNotTrustworthy() {
        // Background launch from a push-to-start: empty store, no live answer.
        XCTAssertFalse(FleetCountTrust.isTrustworthy(
            hosts: [host("pro"), host("air")], liveFetchedHostIds: []))
    }

    func testEveryUpHostFetchedIsTrustworthy() {
        XCTAssertTrue(FleetCountTrust.isTrustworthy(
            hosts: [host("pro"), host("air")], liveFetchedHostIds: ["pro", "air"]))
    }

    func testAnUpHostThatHasNotAnsweredVetoes() {
        // The old rule trusted the count after ANY host's first answer.
        XCTAssertFalse(FleetCountTrust.isTrustworthy(
            hosts: [host("pro"), host("air")], liveFetchedHostIds: ["air"]))
    }

    func testASleepingHostDoesNotFreezeTheCard() {
        // 2026-09-21: the Pro slept for two hours; the Air had answered.
        XCTAssertTrue(FleetCountTrust.isTrustworthy(
            hosts: [host("pro", down: true), host("air")], liveFetchedHostIds: ["air"]))
    }

    func testADownHostThatAnsweredEarlierThisLaunchIsStillExcluded() {
        XCTAssertTrue(FleetCountTrust.isTrustworthy(
            hosts: [host("pro", down: true), host("air")], liveFetchedHostIds: ["pro", "air"]))
    }

    func testADownHostDoesNotExcuseAnUnansweredUpHost() {
        XCTAssertFalse(FleetCountTrust.isTrustworthy(
            hosts: [host("pro", down: true), host("air")], liveFetchedHostIds: ["pro"]))
    }

    func testEveryHostKnownDownIsNotTrustworthy() {
        XCTAssertFalse(FleetCountTrust.isTrustworthy(
            hosts: [host("pro", down: true), host("air", down: true)],
            liveFetchedHostIds: ["pro", "air"]))
    }

    func testFetchedIdsForRemovedHostsAreIgnored() {
        XCTAssertTrue(FleetCountTrust.isTrustworthy(
            hosts: [host("air")], liveFetchedHostIds: ["air", "removed-host"]))
        XCTAssertFalse(FleetCountTrust.isTrustworthy(
            hosts: [host("air")], liveFetchedHostIds: ["removed-host"]))
    }
}
