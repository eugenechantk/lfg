import Foundation
import Testing
@testable import LFGCore

@Suite("S2 Subagents sheet rows")
struct SubagentRowTests {
    private let now = 1_800_000_000_000.0

    @Test("the board's four rows: running, two done with results, one failed")
    func boardRows() {
        let running = ChildAgentSession(id: "a", description: "Check the desktop fork menu", agentType: "general-purpose",
                                        status: .running, startedAt: now - 72_000)
        let done = ChildAgentSession(id: "b", description: "Find every fork caller", agentType: "Explore",
                                     status: .completed, startedAt: now - 300_000, finishedAt: now - 252_000,
                                     result: "Found 6 callers in 4 files")
        let failed = ChildAgentSession(id: "c", description: "Measure fork latency on Air", agentType: "general-purpose",
                                       status: .failed, startedAt: now - 100_000, finishedAt: now - 70_000,
                                       result: "Host Air was unreachable")
        let r = SubagentRow(running, nowMs: now)
        #expect(r.mark == .running && r.line == "Running" && r.tone == .live)
        #expect(r.meta == "general-purpose · 1m 12s")
        let d = SubagentRow(done, nowMs: now)
        #expect(d.mark == .done && d.line == "Found 6 callers in 4 files" && d.tone == .result)
        #expect(d.meta == "Explore · 48s")
        let f = SubagentRow(failed, nowMs: now)
        #expect(f.mark == .failed && f.line == "Host Air was unreachable" && f.tone == .failed)
        #expect(f.meta == "general-purpose · 30s")
    }

    @Test("without a result a finished row says Done or Failed")
    func noResult() {
        let done = ChildAgentSession(id: "b", description: "x", status: .completed)
        #expect(SubagentRow(done, nowMs: now).line == "Done")
        #expect(SubagentRow(done, nowMs: now).meta == "Agent")
        let failed = ChildAgentSession(id: "c", description: "y", status: .failed)
        #expect(SubagentRow(failed, nowMs: now).line == "Failed")
    }

    @Test("durations: seconds, then minutes with two-digit seconds")
    func durations() {
        #expect(SubagentRow.duration(ms: 48_000) == "48s")
        #expect(SubagentRow.duration(ms: 125_000) == "2m 05s")
        #expect(SubagentRow.duration(ms: 3_725_000) == "1h 02m")
    }

    @Test("the sheet's summary counts running, done and failed, skipping zeros")
    func summary() {
        let agents = [
            ChildAgentSession(id: "a", status: .running),
            ChildAgentSession(id: "b", status: .completed),
            ChildAgentSession(id: "c", status: .completed),
            ChildAgentSession(id: "d", status: .failed),
        ]
        #expect(SubagentPill(agents: agents).sheetSummary == "1 running · 2 done · 1 failed")
        #expect(SubagentPill(agents: [ChildAgentSession(id: "b", status: .completed)]).sheetSummary == "1 done")
    }
}
