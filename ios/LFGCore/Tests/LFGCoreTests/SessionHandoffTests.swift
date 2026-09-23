import Testing
@testable import LFGCore

@Suite("Session handoff routing") struct SessionHandoffTests {
    @Test func modelsAreGroupedWithCurrentToolFirst() {
        for current in AgentKind.allCases {
            let sections = SessionHandoff.modelSections(current: current)
            #expect(sections.count == 2)
            #expect(sections[0].agent == current)
            #expect(sections[0].title == "Switch in place")
            #expect(sections[0].models == current.models)
            #expect(sections[1].agent != current)
            #expect(sections[1].title == (current == .claude ? "Switch to Codex" : "Switch to Claude Code"))
            for target in AgentKind.allCases {
                for closed in [false, true] {
                    #expect(SessionHandoff.modelSwitchRoute(from: current, to: target, closed: closed) ==
                        (current != target ? .handoff : closed ? .resume : .inPlace))
                }
            }
        }
    }

    @Test func closedSessionUsesHostWithFreshestKnownCopy() {
        let a = Host(url: "http://a.test")
        let b = Host(url: "http://b.test")
        let copies = [(host: a, sessions: [ResumableSession(sessionId: "source", mtime: 10)]),
                      (host: b, sessions: [ResumableSession(sessionId: "source", mtime: 20)])]
        #expect(SessionHandoff.sourceHost(sessionId: "source", liveOwner: nil, copies: copies, isReachable: { _ in true })?.id == b.id)
        #expect(SessionHandoff.sourceHost(sessionId: "source", liveOwner: nil, copies: copies, isReachable: { $0.id == a.id })?.id == a.id)
        #expect(SessionHandoff.sourceHost(sessionId: "missing", liveOwner: nil, copies: copies, isReachable: { _ in true }) == nil)
    }

    @Test func liveSessionNeverFallsBackToAnotherHostsSnapshot() {
        let owner = Host(url: "http://owner.test")
        let other = Host(url: "http://other.test")
        #expect(SessionHandoff.sourceHost(sessionId: "source", liveOwner: owner,
            copies: [(other, [ResumableSession(sessionId: "source", mtime: 20)])],
            isReachable: { $0.id != owner.id })?.id == owner.id)
    }
}
