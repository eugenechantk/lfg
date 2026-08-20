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
