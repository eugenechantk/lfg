import XCTest
@testable import LFGCore

final class NewSessionModelDefaultsTests: XCTestCase {

    private let fallback = AgentModelSelection(agent: .claude, model: "claude-opus-5")

    private func session(
        _ id: String, cwd: String?, agent: String, model: String?, at: Double
    ) -> Session {
        Session(sessionId: id, title: id, agent: agent, model: model, cwd: cwd, lastActivityAt: at)
    }

    // SC1: the directory decides, not the last thing the user happened to start.
    func testPicksTheNewestSessionInThatDirectory() {
        let sessions = [
            session("a1", cwd: "/a", agent: "codex", model: "gpt-5.6-terra", at: 10),
            session("a2", cwd: "/a", agent: "codex", model: "gpt-5.6-sol", at: 30),
            session("b1", cwd: "/b", agent: "claude", model: "opus", at: 40),
        ]
        let a = AgentModelSelection.inferred(forCwd: "/a", in: sessions, fallback: fallback)
        XCTAssertEqual(a.agent, .codex)
        XCTAssertEqual(a.model, "gpt-5.6-sol")

        let b = AgentModelSelection.inferred(forCwd: "/b", in: sessions, fallback: fallback)
        XCTAssertEqual(b.agent, .claude)
        XCTAssertEqual(b.model, "opus")
    }

    // The list arrives grouped for display, so recency must be re-derived here.
    func testIgnoresTheIncomingListOrder() {
        let sessions = [
            session("new", cwd: "/a", agent: "claude", model: "haiku", at: 99),
            session("old", cwd: "/a", agent: "codex", model: "gpt-5.6-sol", at: 1),
        ].reversed().map { $0 }
        let s = AgentModelSelection.inferred(forCwd: "/a", in: sessions, fallback: fallback)
        XCTAssertEqual(s.agent, .claude)
        XCTAssertEqual(s.model, "haiku")
    }

    // SC3: nothing to learn from → the remembered pair stands.
    func testFallsBackWhenTheDirectoryHasNoSessions() {
        let sessions = [session("b1", cwd: "/b", agent: "codex", model: "gpt-5.6-sol", at: 5)]
        let s = AgentModelSelection.inferred(forCwd: "/untouched", in: sessions, fallback: fallback)
        XCTAssertEqual(s, fallback)
    }

    func testFallsBackOnAnEmptyDirectoryString() {
        let sessions = [session("a1", cwd: "/a", agent: "codex", model: "gpt-5.6-sol", at: 5)]
        XCTAssertEqual(
            AgentModelSelection.inferred(forCwd: "", in: sessions, fallback: fallback), fallback)
        XCTAssertEqual(
            AgentModelSelection.inferred(forCwd: "   ", in: sessions, fallback: fallback), fallback)
    }

    // A closed row from an older server carries no model, but its agent is still
    // real information — a codex directory should not propose claude.
    func testUsesTheAgentAloneWhenNoSessionCarriesAModel() {
        let sessions = [
            session("a1", cwd: "/a", agent: "codex", model: nil, at: 10),
            session("a2", cwd: "/a", agent: "codex", model: "", at: 20),
        ]
        let s = AgentModelSelection.inferred(forCwd: "/a", in: sessions, fallback: fallback)
        XCTAssertEqual(s.agent, .codex)
        XCTAssertEqual(s.model, AgentKind.codex.defaultModel)
    }

    // A newer session with no model must not shadow the model we can actually read.
    func testPrefersTheNewestSessionThatHasAModel() {
        let sessions = [
            session("a1", cwd: "/a", agent: "claude", model: "sonnet", at: 10),
            session("a2", cwd: "/a", agent: "claude", model: nil, at: 20),
        ]
        let s = AgentModelSelection.inferred(forCwd: "/a", in: sessions, fallback: fallback)
        XCTAssertEqual(s.model, "sonnet")
    }

    // SC6: catalogs evolve; a retired model must never reach a create request.
    func testUnknownModelDegradesToTheAgentDefaultNotTheRawValue() {
        let sessions = [session("a1", cwd: "/a", agent: "codex", model: "gpt-4o-ancient", at: 10)]
        let s = AgentModelSelection.inferred(forCwd: "/a", in: sessions, fallback: fallback)
        XCTAssertEqual(s.agent, .codex)
        XCTAssertEqual(s.model, AgentKind.codex.defaultModel)
    }

    // An agent this build doesn't know is not a runtime we can propose.
    func testUnknownAgentIsSkippedInFavourOfAKnownOne() {
        let sessions = [
            session("a1", cwd: "/a", agent: "some-future-runtime", model: "x", at: 30),
            session("a2", cwd: "/a", agent: "claude", model: "sonnet", at: 20),
        ]
        let s = AgentModelSelection.inferred(forCwd: "/a", in: sessions, fallback: fallback)
        XCTAssertEqual(s.agent, .claude)
        XCTAssertEqual(s.model, "sonnet")
    }

    func testTrailingSlashesAndWhitespaceMatchTheSameDirectory() {
        let sessions = [session("a1", cwd: "/a/b/", agent: "claude", model: "haiku", at: 10)]
        let s = AgentModelSelection.inferred(forCwd: " /a/b ", in: sessions, fallback: fallback)
        XCTAssertEqual(s.model, "haiku")
    }

    func testDoesNotWalkUpToAParentDirectory() {
        let sessions = [session("a1", cwd: "/a/b/sub", agent: "codex", model: "gpt-5.6-sol", at: 10)]
        let s = AgentModelSelection.inferred(forCwd: "/a/b", in: sessions, fallback: fallback)
        XCTAssertEqual(s, fallback)
    }

    // SC2 (client half): the closed rows this inference reads from must decode
    // the server's new `model` field.
    func testResumableSessionDecodesModel() throws {
        let json = """
        {"sessions":[
          {"sessionId":"r1","title":"t","project":"p","cwd":"/a",
           "lastActivityAt":5.0,"agent":"codex","lastUserText":"hi",
           "model":"gpt-5.6-sol","closed":true},
          {"sessionId":"r2","title":"t2","cwd":"/b","agent":"claude","closed":true}
        ]}
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(ResumableResponse.self, from: json)
        XCTAssertEqual(page.sessions[0].model, "gpt-5.6-sol")
        // Absent on an older server — must decode, not throw.
        XCTAssertNil(page.sessions[1].model)
    }
}
