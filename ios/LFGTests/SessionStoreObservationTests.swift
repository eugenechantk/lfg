import Observation
import Testing
import LFGCore
@testable import LFG

/// A live update must wake only the views it changes. Before 2026-10-28 both
/// cases below redrew far more than that once per event: every list row, the
/// headers, RootView and the open session on each stream element, and the open
/// session on every other session's message. With many sessions running that
/// held the main thread near 100%. `.claude/feature/live-session-scroll-perf.md`.
@MainActor
struct SessionStoreObservationTests {
    private final class Flag: @unchecked Sendable {
        var fired = 0
    }

    private func observe(_ read: () -> Void) -> Flag {
        let flag = Flag()
        withObservationTracking(read) { flag.fired += 1 }
        return flag
    }

    private func message(_ id: String) -> SessionMessage {
        SessionMessage(id: id, role: "assistant", kind: "text", text: "progress", ts: 1)
    }

    @Test func repeatedReceivingDoesNotWakeHostHealthReaders() {
        let store = SessionStore(settings: AppSettings())
        store.signal("host-a", .receiving)   // first evidence: a real change
        let flag = observe {
            _ = store.hostStateByHost
            _ = store.fleetState
        }
        store.signal("host-a", .receiving)   // every later event or heartbeat
        store.signal("host-a", .receiving)
        #expect(flag.fired == 0)
    }

    @Test func hostHealthChangeStillWakesReaders() {
        let store = SessionStore(settings: AppSettings())
        store.signal("host-a", .receiving)
        let flag = observe { _ = store.hostStateByHost }
        store.signal("host-a", .failed(reason: "test"))
        #expect(flag.fired == 1)
    }

    @Test func messageForAnotherSessionDoesNotWakeThisOne() {
        let store = SessionStore(settings: AppSettings())
        let flag = observe {
            _ = store.transcript(for: "session-b")
            _ = store.transcriptRevision(for: "session-b")
        }
        store.apply(.message(sid: "session-a", message: message("a-1")))
        #expect(flag.fired == 0)
        #expect(store.transcript(for: "session-a").map(\.id) == ["a-1"])
    }

    @Test func messageWakesItsOwnSession() {
        let store = SessionStore(settings: AppSettings())
        let flag = observe { _ = store.transcript(for: "session-a") }
        store.apply(.message(sid: "session-a", message: message("a-1")))
        #expect(flag.fired == 1)
        #expect(store.transcriptRevision(for: "session-a") == 1)
    }

    @Test func workingClockReadsOnlyItsOwnSession() {
        let store = SessionStore(settings: AppSettings())
        let session = Session(sessionId: "session-b", title: "B", agent: "claude")
        let flag = observe { _ = store.turnStartedAt(session) }
        store.apply(.message(sid: "session-a", message: message("a-1")))
        #expect(flag.fired == 0)
    }
}
