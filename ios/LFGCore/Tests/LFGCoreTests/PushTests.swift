import XCTest
@testable import LFGCore

final class PushTests: XCTestCase {

    // MARK: SC5 — notification → session routing

    func testParseNotificationExtractsSidAndKind() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Needs you", "body": "?"]],
            "sid": "abc-123",
            "kind": "needs-input",
        ]
        let note = PushNotification(userInfo: userInfo)
        XCTAssertEqual(note?.sid, "abc-123")
        XCTAssertEqual(note?.kind, .needsInput)
    }

    func testParseNotificationToleratesUnknownKind() {
        let note = PushNotification(userInfo: ["sid": "s1", "kind": "weird"])
        XCTAssertEqual(note?.sid, "s1")
        XCTAssertNil(note?.kind)
    }

    func testParseNotificationRejectsMissingSid() {
        XCTAssertNil(PushNotification(userInfo: ["kind": "finished"]))
        XCTAssertNil(PushNotification(userInfo: ["sid": ""]))
    }

    func testParseNotificationExtractsEmbeddedSessionSnapshot() {
        let userInfo: [AnyHashable: Any] = [
            "sid": "abc-123",
            "kind": "finished",
            "session": [
                "id": "abc-123",
                "title": "Fix the bug",
                "project": "lfg",
                "cwd": "/Users/x/dev/lfg",
                "agent": "claude",
                "model": "sonnet",
                "status": "ok",
                "lastActivityAt": 1782700000000,
            ],
        ]
        let note = PushNotification(userInfo: userInfo)
        XCTAssertEqual(note?.session?.sessionId, "abc-123")
        XCTAssertEqual(note?.session?.title, "Fix the bug")
        XCTAssertEqual(note?.session?.cwd, "/Users/x/dev/lfg")
        XCTAssertEqual(note?.session?.model, "sonnet")
        XCTAssertEqual(note?.session?.lastActivityAt, 1782700000000)
    }

    func testParseNotificationWithoutSessionLeavesSnapshotNil() {
        let note = PushNotification(userInfo: ["sid": "s1", "kind": "finished"])
        XCTAssertNil(note?.session)
    }

    func testParseNotificationIgnoresMismatchedSessionId() {
        let note = PushNotification(userInfo: [
            "sid": "abc-123",
            "session": ["id": "different", "title": "X"],
        ])
        XCTAssertNil(note?.session)
    }

    // MARK: token formatting

    func testTokenHexEncoding() {
        let data = Data([0x00, 0x0f, 0xa1, 0xff])
        XCTAssertEqual(apnsTokenHex(data), "000fa1ff")
    }

    // MARK: SC6 — registration state machine

    func testRegistrationHappyPath() {
        var s: PushRegistrationState = .notDetermined
        s = reducePushRegistration(s, .permissionGranted)
        XCTAssertEqual(s, .authorizing)
        s = reducePushRegistration(s, .gotToken("tok"))
        XCTAssertEqual(s, .authorizing)
        s = reducePushRegistration(s, .serverAccepted(token: "tok"))
        XCTAssertEqual(s, .registered(token: "tok"))
        XCTAssertTrue(s.isActive)
    }

    func testRegistrationDenied() {
        let s = reducePushRegistration(.notDetermined, .permissionDenied)
        XCTAssertEqual(s, .denied)
        XCTAssertFalse(s.isActive)
    }

    func testServerFailureSurfacesReason() {
        var s: PushRegistrationState = .authorizing
        s = reducePushRegistration(s, .serverFailed(reason: "HTTP 500"))
        XCTAssertEqual(s, .failed(reason: "HTTP 500"))
        XCTAssertFalse(s.isActive)
    }

    func testDenialAfterRegistrationDeactivates() {
        var s: PushRegistrationState = .registered(token: "t")
        XCTAssertTrue(s.isActive)
        s = reducePushRegistration(s, .permissionDenied)
        XCTAssertEqual(s, .denied)
    }
}
