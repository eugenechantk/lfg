import XCTest
@testable import LFGCore

final class FleetActivitySnapshotTests: XCTestCase {
    private func prompt(_ q: String) -> AgentPrompt { AgentPrompt(question: q, options: []) }

    func testCountsAndOrdersNeedsInputFirstAndCarriesElapsedTime() {
        let sessions = [
            Session(sessionId: "s1", title: "Approve deploy"),
            Session(sessionId: "s2", title: "Fix stale activity"),
            Session(sessionId: "s3", title: "Background worker"),
            Session(sessionId: "s4", title: "Pick model"),
            Session(sessionId: "s5", title: "Idle session"),
        ]
        // s2 keeps its start time; s1 flipped working -> needsInput so its timer
        // restarts at `now` rather than inheriting the working row's.
        let priorRows = [
            LFGFleetAttributes.Row(sid: "s1", title: "Old", state: "working", since: 10),
            LFGFleetAttributes.Row(sid: "s2", title: "Old", state: "working", since: 20),
            LFGFleetAttributes.Row(sid: "s4", title: "Old", state: "needsInput", since: 40),
        ]

        let state = FleetActivitySnapshot.contentState(
            sessions: sessions,
            busy: ["s1": true, "s2": true, "s3": true],
            prompts: ["s1": prompt("Deploy?"), "s4": prompt("Model?")],
            priorRows: priorRows,
            now: 200
        )

        XCTAssertEqual(state.working, 2)      // s2, s3
        XCTAssertEqual(state.needsInput, 2)   // s1, s4 — a prompt outranks busy
        XCTAssertEqual(state.rows, [
            LFGFleetAttributes.Row(sid: "s4", title: "Pick model", state: "needsInput", since: 40),
            LFGFleetAttributes.Row(sid: "s1", title: "Approve deploy", state: "needsInput", since: 200),
            LFGFleetAttributes.Row(sid: "s2", title: "Fix stale activity", state: "working", since: 20),
        ])
        XCTAssertEqual(state.more, 1)         // s3 folded into "1 More"
        XCTAssertEqual(state.updatedAt, 200)
    }

    /// Regression: a session closed in the client kept rendering as "working"
    /// forever. `closed` is client-synthesized and `busy` is only ever seeded for
    /// live sessions — nothing clears it on close — so the stale `true` survived.
    func testClosedSessionIsExcludedEvenWithAStaleBusyFlag() {
        let state = FleetActivitySnapshot.contentState(
            sessions: [
                Session(sessionId: "e64271a9", title: "Ended but still busy", closed: true),
                Session(sessionId: "live", title: "Actually working"),
            ],
            busy: ["e64271a9": true, "live": true],
            prompts: [:],
            now: 100
        )

        XCTAssertEqual(state.working, 1)
        XCTAssertEqual(state.rows.map(\.sid), ["live"])
    }

    /// A closed session outranks even a pending prompt, matching `group(for:)`,
    /// whose `.closed` branch comes before `.needsInput`.
    func testClosedSessionIsExcludedEvenWithAPendingPrompt() {
        let state = FleetActivitySnapshot.contentState(
            sessions: [Session(sessionId: "c1", title: "Ended", closed: true)],
            busy: [:],
            prompts: ["c1": prompt("Still waiting?")],
            now: 100
        )

        XCTAssertEqual(state.needsInput, 0)
        XCTAssertTrue(state.rows.isEmpty)
    }

    /// "Paused" is neither working nor needs-input, and it outranks busy.
    func testBlockedSessionIsExcluded() {
        let state = FleetActivitySnapshot.contentState(
            sessions: [Session(sessionId: "b1", title: "Paused", status: "blocked")],
            busy: ["b1": true],
            prompts: [:],
            now: 100
        )

        XCTAssertEqual(state.working, 0)
        XCTAssertTrue(state.rows.isEmpty)
    }

    /// ...but a paused session that is *asking* something is still actionable.
    func testBlockedSessionWithAPromptStillCountsAsNeedsInput() {
        let state = FleetActivitySnapshot.contentState(
            sessions: [Session(sessionId: "b1", title: "Paused, asking", status: "blocked")],
            busy: [:],
            prompts: ["b1": prompt("Approve?")],
            now: 100
        )

        XCTAssertEqual(state.needsInput, 1)
        XCTAssertEqual(state.rows.map(\.sid), ["b1"])
    }

    func testIdleSessionsAreExcludedEntirely() {
        let state = FleetActivitySnapshot.contentState(
            sessions: [Session(sessionId: "a", title: "Done"), Session(sessionId: "b", title: "Also done")],
            busy: ["a": false],
            prompts: [:],
            now: 5
        )

        XCTAssertEqual(state.working, 0)
        XCTAssertEqual(state.needsInput, 0)
        XCTAssertTrue(state.rows.isEmpty)
        XCTAssertEqual(state.more, 0)
    }

    func testMoreCountsOnlyTheOverflowBeyondRenderedRows() {
        let sessions = (1...7).map { Session(sessionId: "s\($0)", title: "Session \($0)") }
        let busy = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId!, true) })

        let state = FleetActivitySnapshot.contentState(
            sessions: sessions, busy: busy, prompts: [:], now: 1
        )

        XCTAssertEqual(state.working, 7)
        XCTAssertEqual(state.rows.count, FleetActivitySnapshot.maxRows)
        XCTAssertEqual(state.more, 7 - FleetActivitySnapshot.maxRows)
    }

    func testFallsBackToTruncatedSessionIdWhenTitleIsEmpty() {
        let state = FleetActivitySnapshot.contentState(
            sessions: [Session(sessionId: "abcdefghijkl", title: "")],
            busy: ["abcdefghijkl": true],
            prompts: [:],
            now: 1
        )

        XCTAssertEqual(state.rows.first?.title, "abcdefgh")
    }

    func testDuplicatePriorRowsDoNotTrap() {
        let dupes = [
            LFGFleetAttributes.Row(sid: "s1", title: "A", state: "working", since: 10),
            LFGFleetAttributes.Row(sid: "s1", title: "B", state: "working", since: 99),
        ]

        let state = FleetActivitySnapshot.contentState(
            sessions: [Session(sessionId: "s1", title: "One")],
            busy: ["s1": true],
            prompts: [:],
            priorRows: dupes,
            now: 300
        )

        XCTAssertEqual(state.rows.first?.since, 10)
    }
}
