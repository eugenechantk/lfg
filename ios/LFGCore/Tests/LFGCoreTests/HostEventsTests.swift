import XCTest
@testable import LFGCore

/// Verifies the Phase-1 event-stream plumbing: SSE `id:` capture, frame →
/// `HostStreamElement` decoding, and the pure `HostLinkPolicy` numbers.
/// See `.claude/feature/phase1-connectivity-core.md` (SC3, SC4, SC5).
final class HostEventsTests: XCTestCase {

    // MARK: SSE id: capture

    func testParserCapturesIdFieldOnFrames() {
        var p = SSEParser()
        let frames = p.feed("id: 42\nevent: busy\ndata: {\"sid\":\"s\",\"busy\":true}\n\n")
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].id, "42")
        XCTAssertEqual(frames[0].event, "busy")
    }

    func testLastEventIdPersistsAcrossFramesPerSpec() {
        var p = SSEParser()
        var frames = p.feed("id: 7\nevent: busy\ndata: {}\n\n")
        XCTAssertEqual(frames[0].id, "7")
        // Next frame has no id: line — the last one remains in effect.
        frames = p.feed("event: queue\ndata: {}\n\n")
        XCTAssertEqual(frames[0].id, "7")
        // A new id replaces it.
        frames = p.feed("id: 9\nevent: busy\ndata: {}\n\n")
        XCTAssertEqual(frames[0].id, "9")
    }

    // MARK: HostStreamDecoder

    func testDecodesJournaledEventWithSeq() {
        var p = SSEParser()
        let frames = p.feed("id: 101\nevent: msg\ndata: {\"sid\":\"abc\",\"m\":{\"id\":\"m1\",\"role\":\"assistant\",\"kind\":\"text\",\"text\":\"hi\"}}\n\n")
        guard case .event(let seq, let ev)? = HostStreamDecoder.decode(frames[0]) else {
            return XCTFail("expected .event")
        }
        XCTAssertEqual(seq, 101)
        guard case .message(let sid, let m) = ev else { return XCTFail("expected .message") }
        XCTAssertEqual(sid, "abc")
        XCTAssertEqual(m.text, "hi")
    }

    func testDecodesHeartbeatWithHead() {
        var p = SSEParser()
        let frames = p.feed(": hb 4821\n\n")
        // Comment lines dispatch immediately as comment frames in our parser.
        let comment = frames.first ?? SSEFrame(event: "", data: "", isComment: true)
        guard case .heartbeat(let head)? = HostStreamDecoder.decode(comment) else {
            return XCTFail("expected .heartbeat, got \(String(describing: HostStreamDecoder.decode(comment)))")
        }
        XCTAssertEqual(head, 4821)
    }

    func testDecodesBareHeartbeatWithoutHead() {
        var p = SSEParser()
        let frames = p.feed(": hb\n\n")
        guard case .heartbeat(let head)? = HostStreamDecoder.decode(frames[0]) else {
            return XCTFail("expected .heartbeat")
        }
        XCTAssertNil(head)
    }

    func testDecodesResyncWithHead() {
        var p = SSEParser()
        let frames = p.feed("event: resync\ndata: {\"head\":69}\n\n")
        guard case .resync(let head)? = HostStreamDecoder.decode(frames[0]) else {
            return XCTFail("expected .resync")
        }
        XCTAssertEqual(head, 69)
    }

    func testUnknownEventTypeDecodesToNilNotCrash() {
        var p = SSEParser()
        let frames = p.feed("id: 5\nevent: somethingnew\ndata: {\"x\":1}\n\n")
        XCTAssertNil(HostStreamDecoder.decode(frames[0]))
    }

    func testEventWithoutIdIsSkipped() {
        // A journaled event must carry a seq — without one the cursor can't
        // advance safely, so the element is dropped (REST reconcile covers it).
        var p = SSEParser()
        let frames = p.feed("event: busy\ndata: {\"sid\":\"s\",\"busy\":false}\n\n")
        XCTAssertNil(HostStreamDecoder.decode(frames[0]))
    }

    // MARK: HostLinkPolicy

    func testReconnectScheduleStartsImmediateAndCapsAt30() {
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: 0), 0)
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: 1), 1)
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: 2), 2)
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: 3), 5)
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: 4), 10)
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: 5), 30)
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: 99), 30)
        XCTAssertEqual(HostLinkPolicy.reconnectDelay(attempt: -1), 0)
    }

    func testStaleTimeoutMeetsDetectionTarget() {
        // SC3: detection ≤ 20s; two missed 10s heartbeats.
        XCTAssertLessThanOrEqual(HostLinkPolicy.staleTimeout, 20)
        XCTAssertGreaterThan(HostLinkPolicy.staleTimeout, 2 * HostLinkPolicy.keepaliveInterval - 5)
    }

    func testUnreachableBannerOnlyAfterSustainedFailure() {
        let now = Date()
        XCTAssertFalse(HostLinkPolicy.showUnreachable(unhealthySince: nil, now: now))
        XCTAssertFalse(HostLinkPolicy.showUnreachable(unhealthySince: now.addingTimeInterval(-10), now: now))
        XCTAssertFalse(HostLinkPolicy.showUnreachable(unhealthySince: now.addingTimeInterval(-29.9), now: now))
        XCTAssertTrue(HostLinkPolicy.showUnreachable(unhealthySince: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(HostLinkPolicy.showUnreachable(unhealthySince: now.addingTimeInterval(-300), now: now))
    }
}
