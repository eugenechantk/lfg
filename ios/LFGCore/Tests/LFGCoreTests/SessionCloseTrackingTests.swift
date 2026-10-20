import Testing
@testable import LFGCore

@Suite("Session close lifecycle")
struct SessionCloseTrackingTests {
    private func session(_ id: String = "session-a") -> Session {
        Session(sessionId: id, title: "Close me", cwd: "/tmp/lfg")
    }

    @Test("one close stays pending through live removal and archive snapshots")
    func pendingSnapshots() {
        let original = session()
        var tracking = SessionCloseTracking()
        let began1 = tracking.begin(original)
        #expect(began1)
        #expect(tracking.isEnding(original.id))
        let began2 = tracking.begin(original)
        #expect(!began2)
        #expect(tracking.preservingPending(in: []) == [original])
        var archived = original
        archived.closed = true
        #expect(tracking.preservingPending(in: [archived]) == [original])
        #expect(tracking.preservingPending(in: [archived, session("other")]).count == 2)
    }

    @Test("success removes the current row even if a stale live or history snapshot returns")
    func successfulClose() {
        let original = session()
        var tracking = SessionCloseTracking()
        let began3 = tracking.begin(original)
        #expect(began3)
        tracking.finish(original.id, succeeded: true)
        #expect(!tracking.isEnding(original.id))
        #expect(tracking.isEnded(original.id))
        #expect(tracking.preservingPending(in: []).isEmpty)
        let began4 = tracking.begin(original)
        #expect(!began4)
        tracking.clearEnded(original.id)
        #expect(!tracking.isEnded(original.id))
        let began5 = tracking.begin(original)
        #expect(began5)
    }

    @Test("failure clears the pending state and permits retry")
    func failureAndRetry() {
        let original = session()
        var tracking = SessionCloseTracking()
        let began6 = tracking.begin(original)
        #expect(began6)
        tracking.finish(original.id, succeeded: false)
        #expect(!tracking.isEnding(original.id))
        #expect(!tracking.isEnded(original.id))
        let began7 = tracking.begin(original)
        #expect(began7)
        tracking.finish(original.id, succeeded: true)
        #expect(tracking.isEnded(original.id))
    }

    @Test("independent sessions can close at once without clearing each other's state")
    func simultaneousCloses() {
        var tracking = SessionCloseTracking()
        let began8 = tracking.begin(session("a"))
        #expect(began8)
        let began9 = tracking.begin(session("b"))
        #expect(began9)
        tracking.finish("a", succeeded: false)
        #expect(tracking.isEnding("b"))
        tracking.finish("b", succeeded: true)
        #expect(!tracking.isEnded("a"))
        #expect(tracking.isEnded("b"))
    }

    @Test("unknown completions never hide an unrelated session")
    func unknownCompletion() {
        var tracking = SessionCloseTracking()
        tracking.finish("unknown", succeeded: true)
        #expect(!tracking.isEnded("unknown"))
    }

    @Test("only created, live, managed sessions can end")
    func eligibility() {
        #expect(SessionCloseTracking.canEnd(session()))
        #expect(!SessionCloseTracking.canEnd(session("local-pending")))
        #expect(!SessionCloseTracking.canEnd(session("")))
        var closed = session()
        closed.closed = true
        #expect(!SessionCloseTracking.canEnd(closed))
        var external = session()
        external.control = "external"
        #expect(!SessionCloseTracking.canEnd(external))
    }
}
