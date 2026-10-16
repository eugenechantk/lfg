import Foundation
import Testing
@testable import LFGCore

@Suite("S2 session top bar: status line")
struct SessionStatusLineTests {
    private let now: Double = 1_760_500_000_000

    @Test("working shows minutes and seconds since the turn started, then host and project")
    func working() {
        let line = SessionStatusLine.resolve(.working(sinceMs: now - (3 * 60 + 12) * 1000),
                                             queued: 0, host: "Pro", project: "lfg", nowMs: now)
        #expect(line == SessionStatusLine(tone: .live, label: "Working · 3m 12s", detail: "· Pro · lfg"))
        #expect(SessionStatusLine.resolve(.working(sinceMs: nil), queued: 0, host: "Pro", project: "lfg", nowMs: now).label == "Working")
        #expect(SessionStatusLine.resolve(.working(sinceMs: now - 40_000), queued: 0, host: nil, project: nil, nowMs: now).label == "Working · 40s")
    }

    @Test("queued messages show their count; the project then drops for room")
    func queued() {
        let line = SessionStatusLine.resolve(.working(sinceMs: now - 220_000), queued: 1, host: "Pro", project: "lfg", nowMs: now)
        #expect(line.label == "Working · 3m 40s")
        #expect(line.detail == "· 1 queued · Pro")
    }

    @Test("needs input and sign-in say how long the agent has waited")
    func waiting() {
        #expect(SessionStatusLine.resolve(.needsInput(sinceMs: now - 120_000), queued: 0, host: "Pro", project: "lfg", nowMs: now)
                == SessionStatusLine(tone: .attention, label: "Needs input · 2m", detail: "· Pro · lfg"))
        #expect(SessionStatusLine.resolve(.needsSignIn(sinceMs: now - 300_000), queued: 0, host: "Air", project: "inbox", nowMs: now)
                == SessionStatusLine(tone: .attention, label: "Needs sign-in · 5m", detail: "· Air · inbox"))
        #expect(SessionStatusLine.resolve(.needsInput(sinceMs: nil), queued: 0, host: nil, project: "lfg", nowMs: now).label == "Needs input")
    }

    @Test("an offline host names itself in the label, not again in the detail")
    func offline() {
        let line = SessionStatusLine.resolve(.hostOffline(sinceMs: now - 120_000), queued: 0, host: "Air", project: "inbox", nowMs: now)
        #expect(line == SessionStatusLine(tone: .attention, label: "Air offline · 2m", detail: "· inbox"))
        #expect(SessionStatusLine.resolve(.hostOffline(sinceMs: nil), queued: 0, host: nil, project: nil, nowMs: now).label == "Host offline")
    }

    @Test("paused names the reason")
    func paused() {
        #expect(SessionStatusLine.resolve(.paused(reason: "out_of_credits"), queued: 0, host: "Pro", project: "lfg", nowMs: now).label
                == "Paused · out of credits")
    }

    @Test("a transient activity (forking, moving) replaces the state label")
    func activity() {
        #expect(SessionStatusLine.resolve(.activity("Forking…"), queued: 0, host: "Pro", project: "lfg", nowMs: now)
                == SessionStatusLine(tone: .live, label: "Forking…", detail: "· Pro · lfg"))
    }

    @Test("idle has no dot or label, just where it is")
    func idle() {
        #expect(SessionStatusLine.resolve(.idle, queued: 0, host: "Pro", project: "lfg", nowMs: now)
                == SessionStatusLine(tone: .none, label: nil, detail: "Pro · lfg"))
        #expect(SessionStatusLine.resolve(.idle, queued: 2, host: nil, project: nil, nowMs: now).detail == "2 queued")
    }
}
