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

    // MARK: Keepalive cadence + gating
    //
    // The 2026-08-16 cellular log showed the phone dropping every ~20s. Root
    // cause was the NAT-warming keepalive: it only fired while the stream was
    // already healthy, so a drop silenced it, the carrier binding idled out at
    // ~30s, Tailscale re-punched, traffic black-holed, and the stream could not
    // get back to healthy to re-enable it.

    func testKeepaliveFiresInEveryStartedStateNotJustHealthyOnes() {
        // The whole point: connecting and backing-off links still warm the NAT
        // binding. Only a stopped link goes quiet.
        for tick in 1...12 {
            XCTAssertTrue(HostLinkPolicy.keepaliveShouldPing(
                linkStarted: true, isCold: false, tick: tick))
            XCTAssertFalse(HostLinkPolicy.keepaliveShouldPing(
                linkStarted: false, isCold: false, tick: tick))
        }
    }

    // MARK: Stream idle timeout vs the stale watchdog
    //
    // `URLRequest.timeoutInterval` was hardcoded to 18 to bound the connect phase,
    // but it is an idle timeout over the WHOLE request — so it silently capped the
    // byte-stall watchdog. Dials logged `stale=40s` and URLSession killed them at
    // ~18s of quiet. Zero "STALL — no bytes" lines exist in any captured log.

    func testStreamTimeoutIsNeverTighterThanTheStaleWatchdog() {
        // The regression in one assertion: whatever the path grade, the timeout
        // handed to URLSession must not pre-empt the watchdog.
        for rtt in [0.005, 0.1, 0.3, 1.0, 2.0, 5.0] {
            var q = PathQuality()
            q.record(rtt: rtt)
            XCTAssertGreaterThanOrEqual(
                HostLinkPolicy.streamRequestTimeout(for: q),
                HostLinkPolicy.staleTimeout(for: q),
                "URLSession would kill the stream before the watchdog at rtt=\(rtt)")
        }
    }

    func testARelayedPathActuallyGetsItsWidenedBudget() {
        var relayed = PathQuality()
        relayed.record(rtt: 2.0)
        let stale = HostLinkPolicy.staleTimeout(for: relayed)
        XCTAssertGreaterThan(stale, HostLinkPolicy.headersTimeout,
                             "a slow path must widen past the connect bound")
        XCTAssertEqual(HostLinkPolicy.streamRequestTimeout(for: relayed), stale, accuracy: 0.001)
    }

    func testTheConnectPhaseKeepsItsOwnBound() {
        // A fresh link has no samples, so its watchdog is the 20s floor; the
        // connect bound must stay below that or a black-holed dial hangs longer
        // than it used to.
        XCTAssertEqual(HostLinkPolicy.headersTimeout, 18, accuracy: 0.001)
        XCTAssertLessThan(HostLinkPolicy.headersTimeout,
                          HostLinkPolicy.staleTimeout(for: PathQuality()))
    }

    func testAFastPathIsUnchangedByTheFix() {
        // LAN-grade paths already had staleTimeout == 20 > 18, so the effective
        // budget moves 18 → 20 and nothing else about them changes.
        var lan = PathQuality()
        lan.record(rtt: 0.005)
        XCTAssertEqual(HostLinkPolicy.streamRequestTimeout(for: lan),
                       HostLinkPolicy.staleTimeout(for: lan), accuracy: 0.001)
    }

    // MARK: Cold hosts
    //
    // The Air was unreachable for the whole 2026-08-16 log — six hours, never one
    // set of response headers — while burning an 18s stream timeout per attempt
    // and a keepalive every 10s on the same cellular link the reachable host was
    // struggling over. Every `APP foreground` reset its backoff ladder to 1s.

    func testAFreshLinkIsNeverCold() {
        XCTAssertFalse(HostLinkPolicy.isCold(lastContactAt: nil))
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(HostLinkPolicy.isCold(lastContactAt: now, now: now))
    }

    func testAHostStrugglingButStillAnsweringIsNotCold() {
        // The threshold must sit clear of every transient this client rides out:
        // the widest stale watchdog (40s) and the top of the reconnect ladder (30s).
        let widestWatchdog = HostLinkPolicy.staleTimeout(for: {
            var q = PathQuality(); q.record(rtt: 2.0); return q
        }())
        XCTAssertGreaterThan(HostLinkPolicy.coldAfter, widestWatchdog)
        XCTAssertGreaterThan(HostLinkPolicy.coldAfter, HostLinkPolicy.reconnectDelay(attempt: 99))

        let start = Date(timeIntervalSince1970: 10_000)
        let justUnder = start.addingTimeInterval(HostLinkPolicy.coldAfter - 1)
        XCTAssertFalse(HostLinkPolicy.isCold(lastContactAt: start, now: justUnder))
    }

    func testAHostUnreachedPastTheThresholdIsCold() {
        let start = Date(timeIntervalSince1970: 10_000)
        let past = start.addingTimeInterval(HostLinkPolicy.coldAfter)
        XCTAssertTrue(HostLinkPolicy.isCold(lastContactAt: start, now: past))
        XCTAssertTrue(HostLinkPolicy.isCold(
            lastContactAt: start, now: start.addingTimeInterval(6 * 3600)))
    }

    func testColdHostKeepsPingingButOnceAMinute() {
        var fired = 0
        for tick in 1...60 {
            if HostLinkPolicy.keepaliveShouldPing(linkStarted: true, isCold: true, tick: tick) {
                fired += 1
            }
        }
        // 60 ticks × 10s = 10 minutes. One per minute, and never zero — going
        // silent would mean never noticing the host come back.
        XCTAssertEqual(fired, 10)
        XCTAssertGreaterThan(fired, 0)
    }

    func testForegroundSkipsBackoffForAReachableHostOnly() {
        XCTAssertTrue(HostLinkPolicy.foregroundMaySkipBackoff(isCold: false))
        XCTAssertFalse(HostLinkPolicy.foregroundMaySkipBackoff(isCold: true))
    }

    func testAColdHostStillClimbsToTheBackoffCapRatherThanStalling() {
        // Denying the foreground skip must not strand the host: its own ladder
        // still runs, and still tops out at a bounded retry interval.
        let cap = HostLinkPolicy.reconnectDelay(attempt: 99)
        XCTAssertEqual(cap, 30, accuracy: 0.001)
        XCTAssertGreaterThan(cap, 0, "a cold host must keep retrying, just slower")
    }

    func testKeepaliveCadenceIsFixedAndDoesNotStretchWithPingDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        // A ping that took 9s (a slow path widening its own timeout) must not
        // push the next tick to 19s — that was the measured regression.
        let next = HostLinkPolicy.keepaliveNextDeadline(
            after: start, now: start.addingTimeInterval(9))
        XCTAssertEqual(next.timeIntervalSince(start),
                       HostLinkPolicy.keepaliveInterval, accuracy: 0.001)
    }

    func testKeepaliveRebasesRatherThanBurstingAfterAnOverrun() {
        let start = Date(timeIntervalSince1970: 1_000)
        // Tick overran its own deadline by 5s (ping took 15s > 10s interval).
        // Next tick is one full interval from NOW, not a backlog of catch-ups.
        let now = start.addingTimeInterval(15)
        let next = HostLinkPolicy.keepaliveNextDeadline(after: start, now: now)
        XCTAssertEqual(next.timeIntervalSince(now),
                       HostLinkPolicy.keepaliveInterval, accuracy: 0.001)
    }

    func testKeepaliveStaysWellInsideTheCarrierNatBindingExpiry() {
        // What protects the NAT binding is the QUIET GAP — the time from one
        // ping finishing to the next starting. A slow ping is itself traffic on
        // the binding (it is retrying the whole time), so its duration is not
        // part of the gap. The invariant is therefore: gap <= keepaliveInterval,
        // always, however long the pings run.
        let worstPing = HostLinkPolicy.keepaliveTimeout(for: {
            var q = PathQuality(); q.record(rtt: 2.0); return q
        }())
        XCTAssertLessThanOrEqual(worstPing, HostLinkPolicy.keepaliveInterval,
                                 "a ping may never overlap the next tick")

        let bindingExpiry: TimeInterval = 30
        var due = Date(timeIntervalSince1970: 1_000)
        for _ in 0..<5 {
            let finished = due.addingTimeInterval(worstPing)
            let next = HostLinkPolicy.keepaliveNextDeadline(after: due, now: finished)
            let quietGap = next.timeIntervalSince(finished)
            XCTAssertLessThanOrEqual(quietGap, HostLinkPolicy.keepaliveInterval + 0.001,
                                     "binding left unwarmed for \(quietGap)s")
            // And even measured pessimistically start-to-start, a tick can never
            // drift out to the ~30s expiry.
            XCTAssertLessThan(next.timeIntervalSince(due), bindingExpiry,
                              "tick-to-tick reached the binding expiry")
            due = next
        }
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

    /// The foreground kick must fire before the stale watchdog would, and only
    /// after a heartbeat has actually been missed — otherwise it either never
    /// helps (too late) or churns healthy streams (too eager).
    func testQuietRedialSitsBetweenOneHeartbeatAndTheStaleWatchdog() {
        XCTAssertGreaterThan(HostLinkPolicy.quietRedialAfter, HostLinkPolicy.keepaliveInterval)
        XCTAssertLessThan(HostLinkPolicy.quietRedialAfter, HostLinkPolicy.staleTimeout)
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
