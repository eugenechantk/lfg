import XCTest
@testable import LFGCore

/// Phase-2 background-continuity plumbing: the push sync hint and the events
/// page decode. See `.claude/feature/phase2-background-continuity.md` (SC-B1).
final class BackgroundSyncTests: XCTestCase {

    // MARK: PushSyncHint

    func testHintParsesNumberSeq() {
        let h = PushSyncHint(userInfo: ["hostId": "abc123", "seq": NSNumber(value: 4821)])
        XCTAssertEqual(h, PushSyncHint(hostId: "abc123", seq: 4821))
    }

    func testHintParsesStringSeq() {
        let h = PushSyncHint(userInfo: ["hostId": "abc123", "seq": "77"])
        XCTAssertEqual(h?.seq, 77)
    }

    func testHintRejectsMissingOrEmptyFields() {
        XCTAssertNil(PushSyncHint(userInfo: ["seq": 5]))                    // no hostId
        XCTAssertNil(PushSyncHint(userInfo: ["hostId": "", "seq": 5]))      // empty hostId
        XCTAssertNil(PushSyncHint(userInfo: ["hostId": "abc"]))             // no seq
        XCTAssertNil(PushSyncHint(userInfo: ["hostId": "abc", "seq": "x"])) // junk seq
    }

    func testHintCoexistsWithNavigationPayload() {
        // One push carries alert + content-available: both parsers read the
        // same userInfo independently.
        let userInfo: [AnyHashable: Any] = [
            "sid": "s-1", "kind": "finished",
            "hostId": "h-9", "seq": NSNumber(value: 12),
        ]
        XCTAssertNotNil(PushNotification(userInfo: userInfo))
        XCTAssertEqual(PushSyncHint(userInfo: userInfo)?.hostId, "h-9")
    }

    // MARK: EventsPage decode

    private func page(_ json: String) throws -> EventsPage {
        try EventsPage.decode(Data(json.utf8))
    }

    func testPageDecodesRowsThroughTheStreamPath() throws {
        // payload is the raw journaled JSON STRING — exactly what the SSE data:
        // line would carry — so it must round-trip through LiveEventDecoder.
        let json = """
        {"events":[
          {"seq":10,"ts":1,"sessionId":"s","type":"busy","payload":"{\\"sid\\":\\"s\\",\\"busy\\":true}"},
          {"seq":11,"ts":2,"sessionId":"s","type":"msg","payload":"{\\"sid\\":\\"s\\",\\"m\\":{\\"id\\":\\"m1\\",\\"role\\":\\"assistant\\",\\"kind\\":\\"text\\",\\"text\\":\\"hi\\"}}"}
        ],"head":11,"canServe":true}
        """
        let p = try page(json)
        XCTAssertEqual(p.head, 11)
        XCTAssertTrue(p.canServe)
        XCTAssertEqual(p.events.count, 2)
        XCTAssertEqual(p.events[0].seq, 10)
        guard case .busy(let sid, let busy) = p.events[0].event else { return XCTFail("expected busy") }
        XCTAssertEqual(sid, "s"); XCTAssertTrue(busy)
        guard case .message(_, let m) = p.events[1].event else { return XCTFail("expected message") }
        XCTAssertEqual(m.text, "hi")
    }

    func testPageSkipsUnknownEventTypes() throws {
        let json = """
        {"events":[
          {"seq":5,"ts":1,"sessionId":"s","type":"somethingnew","payload":"{}"},
          {"seq":6,"ts":2,"sessionId":"s","type":"busy","payload":"{\\"sid\\":\\"s\\",\\"busy\\":false}"}
        ],"head":6,"canServe":true}
        """
        let p = try page(json)
        XCTAssertEqual(p.events.map(\.seq), [6])
    }

    func testPageCanServeFalse() throws {
        let p = try page(#"{"events":[],"head":69,"canServe":false}"#)
        XCTAssertFalse(p.canServe)
        XCTAssertEqual(p.head, 69)
        XCTAssertTrue(p.events.isEmpty)
    }

    // MARK: shared cursor key

    func testCursorKeyShape() {
        XCTAssertEqual(HostLinkPolicy.cursorKey(forHostURL: "http://x:8766"),
                       "lfg.cursor.http://x:8766")
    }
}
