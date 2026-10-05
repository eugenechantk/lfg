import XCTest
@testable import LFGCore

final class StartSessionPlanTests: XCTestCase {
    private let pro = LFGCore.Host(url: "http://127.0.0.1:8766", name: "Eugenes-MacBook-Pro.local", isDefault: true)
    private let air = LFGCore.Host(url: "http://100.64.0.9:8766", name: "Eugenes-MacBook-Air")
    private let dirs = DirsResponse(root: "/Users/me/dev", inbox: "/Users/me/dev/inbox",
                                    repos: [Repo(name: "Noto", cwd: "/Users/me/dev/personal/Noto"),
                                            Repo(name: "lfg", cwd: "/Users/me/dev/personal/lfg")])
    private let live = ModelCatalogResponse(agents: [
        "claude": AgentModelCatalog(defaultModel: "claude-opus-5-5", models: ["claude-opus-5-5", "claude-sonnet-5-5"]),
        "codex": AgentModelCatalog(defaultModel: "gpt-6-astra", models: ["gpt-6-astra", "gpt-5.5"]),
    ])

    func testHostHintOrFallback() {
        XCTAssertEqual(StartSessionPlanner.host(hint: "macbook air", hosts: [pro, air], fallback: pro), air)
        XCTAssertEqual(StartSessionPlanner.host(hint: nil, hosts: [pro, air], fallback: pro), pro)
        XCTAssertEqual(StartSessionPlanner.host(hint: "nope", hosts: [pro, air], fallback: pro), pro)
        XCTAssertNil(StartSessionPlanner.host(hint: nil, hosts: [], fallback: nil))
    }

    func testDirectoryHintOrInbox() {
        XCTAssertEqual(StartSessionPlanner.directory(hint: "noto", dirs: dirs), .init(name: "Noto", path: "/Users/me/dev/personal/Noto"))
        XCTAssertEqual(StartSessionPlanner.directory(hint: nil, dirs: dirs), .init(name: "Inbox", path: "/Users/me/dev/inbox"))
        XCTAssertEqual(StartSessionPlanner.directory(hint: "unknown", dirs: dirs), .init(name: "Inbox", path: "/Users/me/dev/inbox"))
        XCTAssertEqual(StartSessionPlanner.directory(hint: "root", dirs: dirs).path, "/Users/me/dev")
    }

    func testSelectionHintElseRememberedReconciled() {
        let remembered = AgentModelSelection(agent: .claude, model: "opus")          // not in the live catalog
        XCTAssertEqual(StartSessionPlanner.selection(agent: "codex", model: nil, catalog: live, remembered: remembered),
                       .init(agent: .codex, model: "gpt-6-astra"))
        XCTAssertEqual(StartSessionPlanner.selection(agent: nil, model: "GPT 5.5", catalog: live, remembered: remembered),
                       .init(agent: .codex, model: "gpt-5.5"))
        XCTAssertEqual(StartSessionPlanner.selection(agent: nil, model: nil, catalog: live, remembered: remembered),
                       .init(agent: .claude, model: "claude-opus-5-5"))                   // remembered, reconciled
        XCTAssertEqual(StartSessionPlanner.selection(agent: nil, model: nil, catalog: live,
                                                     remembered: .init(agent: .claude, model: "claude-sonnet-5-5")),
                       .init(agent: .claude, model: "claude-sonnet-5-5"))
    }

    func testNotificationSaysWhatStartedWhere() {
        let plan = StartSessionPlan(host: pro, directory: .init(name: "Noto", path: "/x"),
                                    selection: .init(agent: .codex, model: "gpt-6-astra"))
        let n = StartSessionPlanner.notification(prompt: "Fix the toolbar\nsecond line", plan: plan)
        XCTAssertEqual(n.title, "Action completed")
        XCTAssertEqual(n.body, "Started Codex (gpt-6-astra) in Noto on Eugenes-MacBook-Pro: “Fix the toolbar”")
        let long = StartSessionPlanner.notification(prompt: String(repeating: "x", count: 200), plan: plan).body
        XCTAssertTrue(long.hasSuffix("…”"))
    }
}
