import Foundation
import Testing
@testable import LFGCore

@Suite("S2 composer pills: Subagents")
struct SubagentPillTests {
    private func agent(_ id: String, _ status: ChildAgentStatus) -> ChildAgentSession {
        ChildAgentSession(id: id, description: id, status: status)
    }

    @Test("running work leads in green, then how many have finished")
    func running() {
        let pill = SubagentPill(agents: [agent("a", .running), agent("b", .completed),
                                         agent("c", .completed), agent("d", .failed)])
        #expect(pill.running == "1 running")
        #expect(pill.progress == "· 3/4 done")
        #expect(pill.accessibilityLabel == "Subagents: 1 running, 2 done, 1 failed")
    }

    @Test("the ring splits into done (green) and failed (red); running is the empty track")
    func ring() {
        let pill = SubagentPill(agents: [agent("a", .running), agent("b", .completed),
                                         agent("c", .completed), agent("d", .failed)])
        #expect(pill.doneFraction == 0.5)
        #expect(pill.failedFraction == 0.25)
    }

    @Test("with nothing running there is no green label, only the tally")
    func finished() {
        let pill = SubagentPill(agents: [agent("a", .completed), agent("b", .stopped)])
        #expect(pill.running == nil)
        #expect(pill.progress == "2/2 done")
        #expect(pill.doneFraction == 1)
        #expect(pill.accessibilityLabel == "Subagents: 2 done")
    }

    @Test("stopped and unknown agents count as finished but not as failed")
    func stoppedCountsDone() {
        let pill = SubagentPill(agents: [agent("a", .stopped), agent("b", .unknown), agent("c", .running)])
        #expect(pill.progress == "· 2/3 done")
        #expect(pill.failedFraction == 0)
    }

    @Test("no agents means no pill")
    func empty() {
        #expect(SubagentPill(agents: []).isEmpty)
        #expect(SubagentPill(agents: []).doneFraction == 0)
    }

    @Test("only running subagents make the composer pill visible",
          arguments: [ChildAgentStatus.running, .completed, .failed, .stopped, .unknown])
    func visibility(status: ChildAgentStatus) {
        let pill = SubagentPill(agents: [agent("a", status), agent("b", .completed)])
        #expect(pill.isVisible == (status == .running))
    }

    @Test("the pill disappears when the last running subagent finishes")
    func lastAgentFinishes() {
        #expect(SubagentPill(agents: [agent("a", .running), agent("b", .failed)]).isVisible)
        #expect(!SubagentPill(agents: [agent("a", .completed), agent("b", .failed)]).isVisible)
        #expect(!SubagentPill(agents: []).isVisible)
    }
}
