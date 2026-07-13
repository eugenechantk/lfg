import XCTest
@testable import LFGCore

final class SSEParserTests: XCTestCase {

    func testParsesSingleEventAcrossChunks() {
        var p = SSEParser()
        var frames = p.feed("event: busy\n")
        XCTAssertTrue(frames.isEmpty)               // not dispatched until blank line
        frames += p.feed("data: {\"sid\":\"a\",\"busy\":true}\n\n")
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].event, "busy")
        XCTAssertEqual(frames[0].data, "{\"sid\":\"a\",\"busy\":true}")
    }

    func testPartialLineBuffering() {
        var p = SSEParser()
        XCTAssertTrue(p.feed("eve").isEmpty)
        XCTAssertTrue(p.feed("nt: msg\nda").isEmpty)
        let frames = p.feed("ta: {\"sid\":\"x\",\"m\":{\"role\":\"user\",\"kind\":\"text\",\"text\":\"hi\"}}\n\n")
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].event, "msg")
    }

    func testCommentIsHeartbeat() {
        var p = SSEParser()
        let frames = p.feed(": hb\n\n")
        // The comment frame dispatches immediately on its own line.
        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(frames[0].isComment)
        XCTAssertEqual(LiveEventDecoder.decode(frames[0]), .heartbeat)
    }

    func testCRLFStripped() {
        var p = SSEParser()
        let frames = p.feed("event: busy\r\ndata: {\"sid\":\"a\",\"busy\":false}\r\n\r\n")
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data, "{\"sid\":\"a\",\"busy\":false}")
    }

    func testDecodeMessageEvent() {
        let frame = SSEFrame(event: "msg", data: """
        {"sid":"s1","m":{"id":"u1","role":"assistant","kind":"text","text":"hello","html":"<p>hello</p>"}}
        """)
        guard case let .message(sid, message)? = LiveEventDecoder.decode(frame) else {
            return XCTFail("expected message event")
        }
        XCTAssertEqual(sid, "s1")
        XCTAssertEqual(message.id, "u1")
        XCTAssertEqual(message.text, "hello")
        XCTAssertEqual(message.html, "<p>hello</p>")
    }

    func testDecodeResetEvent() {
        let frame = SSEFrame(event: "reset", data: "{\"sid\":\"s1\"}")
        XCTAssertEqual(LiveEventDecoder.decode(frame), .reset(sid: "s1"))
    }

    func testDecodePromptEvent() {
        let frame = SSEFrame(event: "prompt", data: """
        {"sid":"s1","prompt":{"question":"Which DB?","options":[{"index":0,"label":"Postgres","selected":false,"description":"robust"},{"index":1,"label":"SQLite"}]}}
        """)
        guard case let .prompt(sid, prompt)? = LiveEventDecoder.decode(frame) else {
            return XCTFail("expected prompt event")
        }
        XCTAssertEqual(sid, "s1")
        XCTAssertEqual(prompt?.question, "Which DB?")
        XCTAssertEqual(prompt?.options.count, 2)
        XCTAssertEqual(prompt?.options[0].label, "Postgres")
        XCTAssertEqual(prompt?.options[0].description, "robust")
    }

    func testDecodePromptClearedEvent() {
        let frame = SSEFrame(event: "prompt", data: "{\"sid\":\"s1\",\"prompt\":null}")
        guard case let .prompt(sid, prompt)? = LiveEventDecoder.decode(frame) else {
            return XCTFail("expected prompt event")
        }
        XCTAssertEqual(sid, "s1")
        XCTAssertNil(prompt)
    }

    func testDecodeQueueEvent() {
        let frame = SSEFrame(event: "queue", data: """
        {"sid":"s1","queue":[{"id":"m1","text":"hi","status":"failed","attempts":2,"error":"boom"}]}
        """)
        guard case let .queue(sid, items)? = LiveEventDecoder.decode(frame) else {
            return XCTFail("expected queue event")
        }
        XCTAssertEqual(sid, "s1")
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isFailed)
        XCTAssertEqual(items[0].attempts, 2)
    }

    func testDecodeQueueDeliveredAckEvent() {
        let frame = SSEFrame(event: "queue", data: """
        {"kind":"delivered","clientId":"c1","msgId":"m1","userTurnId":"u1"}
        """)
        guard case let .queueAck(sid, ack)? = LiveEventDecoder.decode(frame, sessionIdHint: "s1") else {
            return XCTFail("expected queue ack event")
        }
        XCTAssertEqual(sid, "s1")
        XCTAssertEqual(ack.kind, "delivered")
        XCTAssertEqual(ack.clientId, "c1")
        XCTAssertEqual(ack.msgId, "m1")
        XCTAssertEqual(ack.userTurnId, "u1")
    }

    func testDecodeQueueFailedAckEventWithoutUserTurnId() {
        let frame = SSEFrame(event: "queue", data: #"{"kind":"failed","clientId":"c2","msgId":"m2"}"#)
        guard case let .queueAck(sid, ack)? = LiveEventDecoder.decode(frame) else {
            return XCTFail("expected queue ack event")
        }
        XCTAssertNil(sid)
        XCTAssertEqual(ack.kind, "failed")
        XCTAssertEqual(ack.clientId, "c2")
        XCTAssertEqual(ack.msgId, "m2")
        XCTAssertNil(ack.userTurnId)
    }

    func testMultipleFramesInOneChunk() {
        var p = SSEParser()
        // Explicit trailing "\n\n" so the second frame's terminating blank line
        // is present (a Swift multiline literal would drop the final newline).
        let chunk = "event: busy\ndata: {\"sid\":\"a\",\"busy\":true}\n\n"
                  + "event: busy\ndata: {\"sid\":\"a\",\"busy\":false}\n\n"
        let frames = p.feed(chunk)
        XCTAssertEqual(frames.count, 2)
    }

    func testFeedLineMatchesProductionPath() {
        // The client drives the parser via URLSession.bytes.lines → feedLine.
        var p = SSEParser()
        var events: [LiveEvent] = []
        for line in ["event: busy", "data: {\"sid\":\"a\",\"busy\":true}", "",
                     ": hb",
                     "event: prompt", "data: {\"sid\":\"a\",\"prompt\":null}", ""] {
            if let frame = p.feedLine(line), let ev = LiveEventDecoder.decode(frame) {
                events.append(ev)
            }
        }
        XCTAssertEqual(events, [
            .busy(sid: "a", busy: true),
            .heartbeat,
            .prompt(sid: "a", prompt: nil),
        ])
    }
}
