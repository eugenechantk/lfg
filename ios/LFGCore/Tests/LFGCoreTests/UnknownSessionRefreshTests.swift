import Foundation
import Testing

@testable import LFGCore

@Suite("UnknownSessionRefresh")
struct UnknownSessionRefreshTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let sid = "7138081e-42ea-4598-a9bd-63750e5171e8"

    @Test("busy, prompt, queue and message events can all reveal a session")
    func eventsThatCount() {
        #expect(UnknownSessionRefresh.sessionId(of: .busy(sid: sid, busy: true)) == sid)
        #expect(UnknownSessionRefresh.sessionId(of: .prompt(sid: sid, prompt: nil)) == sid)
        #expect(UnknownSessionRefresh.sessionId(of: .queue(sid: sid, queue: [])) == sid)
        #expect(UnknownSessionRefresh.sessionId(of: .message(sid: sid, message: SessionMessage(role: "user"))) == sid)
        #expect(UnknownSessionRefresh.sessionId(of: .heartbeat) == nil)
        #expect(UnknownSessionRefresh.sessionId(of: .reset(sid: sid)) == nil)
    }

    @Test("an unknown session's first event refreshes at once")
    func firstEventRefreshes() {
        var p = UnknownSessionRefresh()
        let r1 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0); #expect(r1)
    }

    @Test("a known session, a refresh in flight, or a local placeholder never refreshes")
    func neverRefreshes() {
        var p = UnknownSessionRefresh()
        let r2 = p.shouldRefresh(for: sid, known: true, inFlight: false, now: t0); #expect(!r2)
        let r3 = p.shouldRefresh(for: sid, known: false, inFlight: true, now: t0); #expect(!r3)
        let r4 = p.shouldRefresh(for: "local-abc", known: false, inFlight: false, now: t0); #expect(!r4)
    }

    @Test("tries are at least 5 s apart and stop after 3 per session")
    func spacingAndCap() {
        var p = UnknownSessionRefresh()
        let r5 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0); #expect(r5)
        let r6 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(1)); #expect(!r6)
        let r7 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(4.9)); #expect(!r7)
        let r8 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(5)); #expect(r8)
        let r9 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(10)); #expect(r9)
        // Fourth try for the same id: never, however long we wait.
        let r10 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(1000)); #expect(!r10)
    }

    @Test("the spacing is shared across sessions; the cap is per session")
    func spacingSharedCapPerSession() {
        var p = UnknownSessionRefresh()
        let other = "9d896817-91ab-42f5-b025-572e40b853bb"
        let r11 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0); #expect(r11)
        let r12 = p.shouldRefresh(for: other, known: false, inFlight: false, now: t0.addingTimeInterval(1)); #expect(!r12)
        let r13 = p.shouldRefresh(for: other, known: false, inFlight: false, now: t0.addingTimeInterval(5)); #expect(r13)
    }

    @Test("forgetting a session that became known resets its tries")
    func forgetResets() {
        var p = UnknownSessionRefresh()
        for i in 0..<3 {
            let r14 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(Double(i) * 5))
            #expect(r14)
        }
        let r15 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(100)); #expect(!r15)
        p.forget(sid)
        let r16 = p.shouldRefresh(for: sid, known: false, inFlight: false, now: t0.addingTimeInterval(200)); #expect(r16)
    }
}
