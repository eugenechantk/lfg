import XCTest
@testable import LFGCore

final class ChildAgentSessionTests: XCTestCase {
    func testDecodesChildAgentResponseLeniently() throws {
        let data = #"""
        {
          "id": "parent-id",
          "agents": [
            {
              "id": "agent-one",
              "description": "Map studio app",
              "agentType": "Explore",
              "spawnDepth": 1,
              "status": "running",
              "startedAt": 1000,
              "lastActivityAt": 2000,
              "finishedAt": null
            },
            {
              "id": "agent-two",
              "status": "future-status"
            }
          ]
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(ChildAgentSessionsResponse.self, from: data)

        XCTAssertEqual(response.id, "parent-id")
        XCTAssertEqual(response.agents.count, 2)
        XCTAssertEqual(response.agents[0].description, "Map studio app")
        XCTAssertEqual(response.agents[0].agentType, "Explore")
        XCTAssertEqual(response.agents[0].spawnDepth, 1)
        XCTAssertEqual(response.agents[0].status, .running)
        XCTAssertEqual(response.agents[0].lastActivityAt, 2000)
        XCTAssertNil(response.agents[0].finishedAt)
        XCTAssertEqual(response.agents[1].description, "Child agent")
        XCTAssertEqual(response.agents[1].agentType, "Agent")
        XCTAssertEqual(response.agents[1].spawnDepth, 1)
        XCTAssertEqual(response.agents[1].status, .unknown)
    }

    func testCollectionPresentationPrioritizesActiveAndProblemStates() {
        let agents = [
            ChildAgentSession(id: "a", description: "A", status: .running),
            ChildAgentSession(id: "b", description: "B", status: .failed),
            ChildAgentSession(id: "c", description: "C", status: .completed),
            ChildAgentSession(id: "d", description: "D", status: .stopped),
        ]

        let presentation = ChildAgentCollectionPresentation(agents: agents)

        XCTAssertEqual(presentation.title, "4 child sessions")
        XCTAssertEqual(presentation.compactStatus, "1 running · 1 failed")
        XCTAssertEqual(presentation.runningCount, 1)
    }

    func testCollectionPresentationHandlesSingularAndTerminalStates() {
        let completed = ChildAgentCollectionPresentation(agents: [
            ChildAgentSession(id: "a", description: "A", status: .completed),
        ])
        XCTAssertEqual(completed.title, "1 child session")
        XCTAssertEqual(completed.compactStatus, "Completed")

        let mixed = ChildAgentCollectionPresentation(agents: [
            ChildAgentSession(id: "a", description: "A", status: .completed),
            ChildAgentSession(id: "b", description: "B", status: .stopped),
        ])
        XCTAssertEqual(mixed.compactStatus, "1 completed · 1 stopped")
    }

    func testStatusPresentationIsStableForEveryServerValue() {
        XCTAssertEqual(ChildAgentStatus.running.label, "Running")
        XCTAssertEqual(ChildAgentStatus.completed.label, "Completed")
        XCTAssertEqual(ChildAgentStatus.failed.label, "Failed")
        XCTAssertEqual(ChildAgentStatus.stopped.label, "Stopped")
        XCTAssertEqual(ChildAgentStatus.unknown.label, "Unknown")
        XCTAssertTrue(ChildAgentStatus.running.isActive)
        XCTAssertFalse(ChildAgentStatus.completed.isActive)
    }

    func testSessionWorkCountersHaveAccessibleZeroSingularAndPluralCopy() {
        XCTAssertNil(SessionWorkListPresentation.childAgentLabel(count: 0))
        XCTAssertEqual(
            SessionWorkListPresentation.childAgentLabel(count: 1),
            "1 child agent running"
        )
        XCTAssertEqual(
            SessionWorkListPresentation.childAgentLabel(count: 3),
            "3 child agents running"
        )
        XCTAssertNil(SessionWorkListPresentation.backgroundProcessLabel(count: 0))
        XCTAssertEqual(
            SessionWorkListPresentation.backgroundProcessLabel(count: 1),
            "1 background process running"
        )
        XCTAssertEqual(
            SessionWorkListPresentation.backgroundProcessLabel(count: 2),
            "2 background processes running"
        )
    }
}

/// Cover for the child-sessions bar dismissing once its work is stale.
///
/// Timestamps are epoch **milliseconds** throughout, matching the server and
/// `SessionStore.PendingSend.ts`.
final class ChildSessionsBarVisibilityTests: XCTestCase {

    private let t0 = 1_787_369_000_000.0

    private func agent(
        _ id: String,
        _ status: ChildAgentStatus,
        started: Double? = nil,
        activity: Double? = nil,
        finished: Double? = nil
    ) -> ChildAgentSession {
        ChildAgentSession(
            id: id, status: status,
            startedAt: started, lastActivityAt: activity, finishedAt: finished)
    }

    func testNoAgentsMeansNoBar() {
        XCTAssertFalse(ChildSessionsBarVisibility.shouldShow(agents: [], lastUserSendAt: nil))
        XCTAssertFalse(ChildSessionsBarVisibility.shouldShow(agents: [], lastUserSendAt: t0))
    }

    /// The old behaviour, still correct until the user moves on.
    func testFinishedAgentsShowUntilTheUserSendsAgain() {
        let agents = [agent("a", .completed, started: t0, finished: t0 + 1_000)]
        XCTAssertTrue(ChildSessionsBarVisibility.shouldShow(agents: agents, lastUserSendAt: nil))
    }

    /// The bug: a follow-up makes the previous turn's finished work stale.
    func testFinishedAgentsHideAfterAFollowUp() {
        let agents = [
            agent("a", .completed, started: t0, finished: t0 + 1_000),
            agent("b", .failed, started: t0, finished: t0 + 2_000),
        ]
        XCTAssertFalse(
            ChildSessionsBarVisibility.shouldShow(agents: agents, lastUserSendAt: t0 + 5_000))
    }

    /// Running work outranks everything — this is what re-shows the bar for
    /// agents the new turn spawns.
    func testRunningAgentKeepsTheBarEvenRightAfterASend() {
        let agents = [
            agent("a", .completed, finished: t0 + 1_000),
            agent("b", .running, started: t0 + 6_000),
        ]
        XCTAssertTrue(
            ChildSessionsBarVisibility.shouldShow(agents: agents, lastUserSendAt: t0 + 5_000))
    }

    /// Agents spawned by the new turn that have since finished are NOT stale.
    func testAgentsThatFinishedAfterTheSendStillShow() {
        let agents = [agent("a", .completed, started: t0 + 6_000, finished: t0 + 7_000)]
        XCTAssertTrue(
            ChildSessionsBarVisibility.shouldShow(agents: agents, lastUserSendAt: t0 + 5_000))
    }

    /// A send at exactly the newest activity counts as superseding it, so a
    /// same-millisecond tie cannot leave the bar stuck on screen.
    func testSendAtTheSameInstantSupersedes() {
        let agents = [agent("a", .completed, finished: t0 + 5_000)]
        XCTAssertFalse(
            ChildSessionsBarVisibility.shouldShow(agents: agents, lastUserSendAt: t0 + 5_000))
    }

    /// Rows can arrive with no timestamps at all (lenient decoding).
    func testUntimedAgentsHideOnceSomethingHasBeenSent() {
        let agents = [agent("a", .completed)]
        XCTAssertTrue(ChildSessionsBarVisibility.shouldShow(agents: agents, lastUserSendAt: nil))
        XCTAssertFalse(ChildSessionsBarVisibility.shouldShow(agents: agents, lastUserSendAt: t0))
    }

    /// `lastActivityAt` and `startedAt` stand in when `finishedAt` is absent.
    func testLatestActivityFallsBackThroughTheAvailableTimestamps() {
        XCTAssertEqual(
            ChildSessionsBarVisibility.latestActivity(
                of: agent("a", .completed, started: t0, activity: t0 + 500)),
            t0 + 500)
        XCTAssertEqual(
            ChildSessionsBarVisibility.latestActivity(of: agent("a", .completed, started: t0)),
            t0)
        XCTAssertNil(ChildSessionsBarVisibility.latestActivity(of: agent("a", .completed)))
    }
}
