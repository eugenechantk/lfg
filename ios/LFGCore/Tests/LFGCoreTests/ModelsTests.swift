import XCTest
@testable import LFGCore

final class ModelsTests: XCTestCase {

    func testDecodeSessionsResponseLeniently() throws {
        // Mirrors the real /api/sessions payload (extra fields, some null).
        let json = """
        {"sessions":[
          {"agent":"aisdk","pid":1,"cmd":"x","cwd":"/repo","project":"lfg",
           "title":"Audit the auth flow","lastUserText":"hi","sessionId":"a2e5",
           "startedAt":1.0,"transcriptPath":"/t","lastActivityAt":2.0,"last":null,
           "tmuxTarget":"lfg-x:0.0","tmuxName":"lfg-x","managed":true,
           "assignedUser":"eugene","model":"sonnet","status":"ok",
           "statusReason":null,"statusDetail":null},
          {"agent":"claude","pid":2,"cmd":"y","cwd":null,"project":"p","title":"t2",
           "sessionId":null,"status":"blocked","statusReason":"model_unavailable",
           "statusDetail":"opus gone","tmuxName":"lfg-y","managed":true}
        ]}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(SessionsResponse.self, from: json)
        XCTAssertEqual(resp.sessions.count, 2)
        let s0 = resp.sessions[0]
        XCTAssertEqual(s0.sessionId, "a2e5")
        XCTAssertEqual(s0.model, "sonnet")
        XCTAssertEqual(s0.assignedUser, "eugene")
        XCTAssertTrue(s0.hasPane)
        XCTAssertFalse(s0.isBlocked)
        let s1 = resp.sessions[1]
        XCTAssertTrue(s1.isBlocked)
        XCTAssertEqual(s1.statusReason, "model_unavailable")
        XCTAssertNil(s1.sessionId)
        XCTAssertFalse(s1.hasPane)
    }

    func testDecodeMessagesResponse() throws {
        let json = """
        {"id":"a2e5","messages":[
          {"id":"u1","role":"user","kind":"text","text":"do it","ts":1.0},
          {"id":"a1","role":"assistant","kind":"text","text":"# Report","ts":2.0,"html":"<h1>Report</h1>"},
          {"id":"t1","role":"tool","kind":"tool_result","text":"ok","ts":3.0}
        ]}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(MessagesResponse.self, from: json)
        XCTAssertEqual(resp.messages.count, 3)
        XCTAssertEqual(resp.messages[1].html, "<h1>Report</h1>")
        XCTAssertEqual(resp.messages[2].kind, "tool_result")
        // stableID falls back gracefully and is unique-ish per message.
        XCTAssertNotEqual(resp.messages[0].stableID, resp.messages[1].stableID)
    }

    func testDecodeReposAndUsage() throws {
        let repos = try JSONDecoder().decode(ReposResponse.self, from:
            #"{"repos":[{"name":"lfg","cwd":"/a/lfg"},{"name":"web","cwd":"/a/web"}]}"#.data(using: .utf8)!)
        XCTAssertEqual(repos.repos.map(\.name), ["lfg", "web"])

        let usage = try JSONDecoder().decode(Usage.self, from:
            #"{"ok":true,"fiveHour":{"pct":12.5,"resetsAt":"2026-06-27T00:00:00Z"},"sevenDay":{"pct":40.0,"resetsAt":null}}"#.data(using: .utf8)!)
        XCTAssertEqual(usage.fiveHour?.pct, 12.5)
        XCTAssertEqual(usage.sevenDay?.pct, 40.0)
    }

    func testClientStringInitNormalizesURL() {
        XCTAssertEqual(LFGClient(string: "127.0.0.1:8766")?.baseURL.absoluteString, "http://127.0.0.1:8766")
        XCTAssertEqual(LFGClient(string: "https://host.ts.net/")?.baseURL.absoluteString, "https://host.ts.net")
        XCTAssertNil(LFGClient(string: "   "))
    }

    func testDecodeRoster() throws {
        // Real /api/users shape: objects with email + gravatar avatar.
        let json = #"{"users":[{"email":"eugene@omg.dev","avatar":"https://gravatar/x"},{"email":"benny@omg.dev","avatar":"https://gravatar/y"}]}"#
        let roster = try JSONDecoder().decode(RosterResponse.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(roster.users.map(\.email), ["eugene@omg.dev", "benny@omg.dev"])
        XCTAssertEqual(roster.users[0].avatar, "https://gravatar/x")
    }

    func testAgentKindModels() {
        XCTAssertEqual(AgentKind.aisdk.defaultModel, "opus")
        XCTAssertEqual(AgentKind.claude.defaultModel, "opus")
        XCTAssertEqual(AgentKind.codex.defaultModel, "gpt-5.5")
        XCTAssertTrue(AgentKind.claude.models.contains("fable"))
        XCTAssertEqual(AgentKind.allCases.count, 5)
    }
}
