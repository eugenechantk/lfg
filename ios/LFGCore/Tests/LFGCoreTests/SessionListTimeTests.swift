import Testing
@testable import LFGCore

@Suite("Session list time")
struct SessionListTimeTests {
    @Test("working duration starts at the session start, across later messages")
    func workingUsesStart() {
        let session = Session(startedAt: 1_000, lastActivityAt: 9_000)
        #expect(SessionListTime.resolve(session: session, isWorking: true) == .runningSince(1_000))
    }

    @Test("nonworking rows use the last activity")
    func nonworkingUsesActivity() {
        let session = Session(startedAt: 1_000, lastActivityAt: 9_000)
        #expect(SessionListTime.resolve(session: session, isWorking: false) == .lastActivity(9_000))

        let closed = Session(lastActivityAt: 7_000, closed: true)
        #expect(SessionListTime.resolve(session: closed, isWorking: false) == .lastActivity(7_000))
    }

    @Test("missing start cannot turn message age into running duration")
    func missingStart() {
        let session = Session(lastActivityAt: 9_000)
        #expect(SessionListTime.resolve(session: session, isWorking: true) == nil)
        #expect(SessionListTime.resolve(session: session, isWorking: false) == .lastActivity(9_000))
    }
}
