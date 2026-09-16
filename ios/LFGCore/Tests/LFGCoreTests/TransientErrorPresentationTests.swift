import XCTest
@testable import LFGCore

final class TransientErrorPresentationTests: XCTestCase {
    private let lifetimeMs: Double = 6_000

    func testSessionErrorDoesNotAppearInAnotherSession() {
        XCTAssertFalse(
            TransientErrorPresentation.shouldPresent(
                audience: .session("session-a"),
                viewingSessionID: "session-b",
                failedPendingClientIDs: [],
                ageMs: 0,
                lifetimeMs: lifetimeMs
            )
        )
    }

    func testPendingSendErrorDisappearsWhenItsFailedRowIsGone() {
        XCTAssertFalse(
            TransientErrorPresentation.shouldPresent(
                audience: .pendingSend(sessionID: "session-a", clientID: "send-1"),
                viewingSessionID: "session-a",
                failedPendingClientIDs: [],
                ageMs: 1_000,
                lifetimeMs: lifetimeMs
            )
        )
    }

    func testPendingSendErrorAppearsOnlyForItsMatchingFailedRow() {
        XCTAssertTrue(
            TransientErrorPresentation.shouldPresent(
                audience: .pendingSend(sessionID: "session-a", clientID: "send-1"),
                viewingSessionID: "session-a",
                failedPendingClientIDs: ["send-1"],
                ageMs: 1_000,
                lifetimeMs: lifetimeMs
            )
        )
        XCTAssertFalse(
            TransientErrorPresentation.shouldPresent(
                audience: .pendingSend(sessionID: "session-a", clientID: "send-1"),
                viewingSessionID: "session-a",
                failedPendingClientIDs: ["send-2"],
                ageMs: 1_000,
                lifetimeMs: lifetimeMs
            )
        )
    }

    func testExpiredEventDoesNotRestartItsLifetimeWhenDetailAppears() {
        XCTAssertTrue(
            TransientErrorPresentation.shouldPresent(
                audience: .global,
                viewingSessionID: "session-a",
                failedPendingClientIDs: [],
                ageMs: lifetimeMs - 1,
                lifetimeMs: lifetimeMs
            )
        )
        XCTAssertFalse(
            TransientErrorPresentation.shouldPresent(
                audience: .global,
                viewingSessionID: "session-a",
                failedPendingClientIDs: [],
                ageMs: lifetimeMs,
                lifetimeMs: lifetimeMs
            )
        )
        XCTAssertFalse(
            TransientErrorPresentation.shouldPresent(
                audience: .global,
                viewingSessionID: "session-a",
                failedPendingClientIDs: [],
                ageMs: lifetimeMs + 1,
                lifetimeMs: lifetimeMs
            )
        )
    }

    func testFreshGlobalAndMatchingSessionEventsStillAppear() {
        for audience: TransientErrorAudience in [.global, .session("session-a")] {
            XCTAssertTrue(
                TransientErrorPresentation.shouldPresent(
                    audience: audience,
                    viewingSessionID: "session-a",
                    failedPendingClientIDs: [],
                    ageMs: 0,
                    lifetimeMs: lifetimeMs
                ),
                "audience=\(audience)"
            )
        }
    }
}
