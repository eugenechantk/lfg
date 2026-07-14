import XCTest
@testable import LFGCore

final class FleetActivitySnapshotTests: XCTestCase {
    func testContentStateMapsSessionStoreInputsToFleetSnapshot() {
        let hosts = [
            Host(url: "http://studio:8766", name: "studio.local", displayName: "Studio Display", isDefault: true),
            Host(url: "http://air:8766", name: "Air.local"),
            Host(url: "http://mini:8766", displayName: "Mini"),
        ]
        let sessions = [
            Session(sessionId: "s1", title: "Approve deploy"),
            Session(sessionId: "s2", title: "Fix stale activity"),
            Session(sessionId: "s3", title: "Background worker"),
            Session(sessionId: "s4", title: "Pick model"),
            Session(sessionId: "s5", title: "Idle session"),
        ]
        let priorRows = [
            LFGFleetAttributes.Row(sid: "s1", title: "Old", host: "Studio Display", state: "working", since: 10),
            LFGFleetAttributes.Row(sid: "s2", title: "Old", host: "Air", state: "working", since: 20),
            LFGFleetAttributes.Row(sid: "s4", title: "Old", host: "Studio Display", state: "blocked", since: 40),
        ]

        let state = FleetActivitySnapshot.contentState(
            sessions: sessions,
            busy: ["s1": true, "s2": true, "s3": true],
            prompts: ["s1": AgentPrompt(question: "Deploy?", options: []), "s4": AgentPrompt(question: "Model?", options: [])],
            hosts: hosts,
            hostBySession: ["s1": hosts[0].id, "s2": hosts[1].id, "s3": hosts[2].id, "s4": hosts[0].id],
            reachabilityByHost: [hosts[0].id: .ok, hosts[1].id: .hostUnreachable("timeout")],
            priorRows: priorRows,
            now: 200
        )

        XCTAssertEqual(state.working, 2)
        XCTAssertEqual(state.needsInput, 2)
        XCTAssertEqual(state.rows, [
            LFGFleetAttributes.Row(sid: "s4", title: "Pick model", host: "Studio Display", state: "blocked", since: 40),
            LFGFleetAttributes.Row(sid: "s1", title: "Approve deploy", host: "Studio Display", state: "blocked", since: 200),
            LFGFleetAttributes.Row(sid: "s2", title: "Fix stale activity", host: "Air", state: "working", since: 20),
        ])
        XCTAssertEqual(state.hosts, [
            LFGFleetAttributes.ContentState.HostStatus(name: "Studio Display", online: true),
            LFGFleetAttributes.ContentState.HostStatus(name: "Air", online: false),
            LFGFleetAttributes.ContentState.HostStatus(name: "Mini", online: false),
        ])
        XCTAssertEqual(state.updatedAt, 200)
    }
}
