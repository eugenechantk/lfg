import XCTest
@testable import LFGCore

/// `lfg://` links: the existing session deep link (notification taps) and the
/// new-session link a Shortcut uses to hand over a dictated prompt.
final class LFGDeepLinkTests: XCTestCase {
    private func parse(_ raw: String, file: StaticString = #filePath, line: UInt = #line) -> LFGDeepLink? {
        guard let url = URL(string: raw) else {
            XCTFail("not a URL: \(raw)", file: file, line: line)
            return nil
        }
        return LFGDeepLink.parse(url)
    }

    // MARK: lfg://session/<id> — unchanged behavior

    func testSessionLinkParsesTheID() {
        XCTAssertEqual(parse("lfg://session/abc-123"), .session(id: "abc-123"))
        XCTAssertEqual(parse("LFG://Session/abc-123"), .session(id: "abc-123"))
        XCTAssertEqual(parse("lfg://session/a%20b"), .session(id: "a b"))
        // Query items never mattered to the session link.
        XCTAssertEqual(parse("lfg://session/abc?x=1"), .session(id: "abc"))
    }

    func testMalformedSessionLinksAreRejected() {
        XCTAssertNil(parse("lfg://session"))
        XCTAssertNil(parse("lfg://session/"))
        XCTAssertNil(parse("lfg://session/a/b"))
        XCTAssertNil(parse("https://session/abc"))
        XCTAssertNil(parse("lfg://sessions/abc"))
        XCTAssertNil(parse("lfg://other"))
    }

    // MARK: lfg://new

    func testBareNewLinkOpensABlankComposer() {
        XCTAssertEqual(parse("lfg://new"), .newSession(NewSessionLink(prompt: nil, directory: nil)))
        XCTAssertEqual(parse("LFG://NEW"), .newSession(NewSessionLink(prompt: nil, directory: nil)))
        XCTAssertEqual(parse("lfg://new/"), .newSession(NewSessionLink(prompt: nil, directory: nil)))
    }

    func testNewLinkCarriesPromptAndDirectory() {
        XCTAssertEqual(
            parse("lfg://new?prompt=Fix%20the%20login%20bug%0Aon%20iPad&dir=noto"),
            .newSession(NewSessionLink(prompt: "Fix the login bug\non iPad", directory: "noto")))
        XCTAssertEqual(
            parse("lfg://new?dir=%2FUsers%2Fme%2Fdev%2Flfg&prompt=hi"),
            .newSession(NewSessionLink(prompt: "hi", directory: "/Users/me/dev/lfg")))
        // `+` is a literal plus, not a space.
        XCTAssertEqual(parse("lfg://new?prompt=1+1"), .newSession(NewSessionLink(prompt: "1+1", directory: nil)))
    }

    func testBuiltURLRoundTripsReservedCharacters() throws {
        let prompts = [
            "Plan: a=b & c=d, 1+1=2, #hash? /path",
            "Café — 日本語 🎙️\n\nsecond paragraph",
        ]
        for prompt in prompts {
            let link = NewSessionLink(prompt: prompt, directory: "dictate keyboard",
                                      host: "Mac Studio", agent: "codex", model: "gpt-5.5")
            let url = try XCTUnwrap(link.url)
            XCTAssertEqual(LFGDeepLink.parse(url), .newSession(link), url.absoluteString)
        }
        XCTAssertEqual(NewSessionLink(prompt: "Buy milk", directory: nil).url?.absoluteString,
                       "lfg://new?prompt=Buy%20milk")
        XCTAssertEqual(NewSessionLink(prompt: nil, directory: nil).url?.absoluteString, "lfg://new")
        XCTAssertEqual(
            NewSessionLink(prompt: "x", directory: "lfg", host: "Pro", agent: "claude", model: "opus").url?.absoluteString,
            "lfg://new?prompt=x&dir=lfg&host=Pro&agent=claude&model=opus")
    }

    func testNewLinkCarriesHostAgentAndModel() {
        XCTAssertEqual(
            parse("lfg://new?prompt=hi&host=Mac%20Studio&agent=codex&model=gpt-5.5"),
            .newSession(NewSessionLink(prompt: "hi", directory: nil, host: "Mac Studio", agent: "codex", model: "gpt-5.5")))
        XCTAssertEqual(
            parse("lfg://new?host=&agent=%20&model="),
            .newSession(NewSessionLink(prompt: nil, directory: nil)))
    }

    func testProviderIsAnAliasForAgent() {
        XCTAssertEqual(parse("lfg://new?provider=openai"),
                       .newSession(NewSessionLink(prompt: nil, directory: nil, agent: "openai")))
        // `agent` wins when both are present.
        XCTAssertEqual(parse("lfg://new?provider=openai&agent=claude"),
                       .newSession(NewSessionLink(prompt: nil, directory: nil, agent: "claude")))
    }

    func testBlankValuesAreTreatedAsAbsent() {
        XCTAssertEqual(parse("lfg://new?prompt=&dir="), .newSession(NewSessionLink(prompt: nil, directory: nil)))
        XCTAssertEqual(parse("lfg://new?prompt=%20%0A&dir=%20"), .newSession(NewSessionLink(prompt: nil, directory: nil)))
        XCTAssertEqual(parse("lfg://new?prompt"), .newSession(NewSessionLink(prompt: nil, directory: nil)))
    }

    func testUnknownItemsAreIgnoredAndTheFirstValueWins() {
        XCTAssertEqual(parse("lfg://new?source=shortcut&prompt=a&prompt=b&dir=x&dir=y"),
                       .newSession(NewSessionLink(prompt: "a", directory: "x")))
    }

    func testMalformedNewLinksAreRejected() {
        XCTAssertNil(parse("lfg://new/extra?prompt=a"))
        XCTAssertNil(parse("https://new?prompt=a"))
        XCTAssertNil(parse("lfg://newsession?prompt=a"))
    }
}

final class NewSessionDirectoryHintTests: XCTestCase {
    private let candidates: [NewSessionDirectoryHint.Candidate] = [
        .init(name: "Root", path: "/Users/me/dev"),
        .init(name: "Inbox", path: "/Users/me/dev/inbox"),
        .init(name: "Noto", path: "/Users/me/dev/personal/Noto"),
        .init(name: "dictate-keyboard", path: "/Users/me/dev/personal/dictate-keyboard"),
        .init(name: "lfg", path: "/Users/me/dev/personal/lfg"),
        .init(name: "lfg", path: "/Users/me/dev/work/lfg"),
    ]

    private func resolve(_ hint: String) -> NewSessionDirectoryHint.Candidate? {
        NewSessionDirectoryHint.resolve(hint, in: candidates)
    }

    func testPathsPassThroughLabelledByTheirLastComponent() {
        XCTAssertEqual(resolve("/tmp/scratch"), .init(name: "scratch", path: "/tmp/scratch"))
        XCTAssertEqual(resolve("~/dev/x"), .init(name: "x", path: "~/dev/x"))
        // A path that is also in the list keeps the list's display name.
        XCTAssertEqual(resolve("/Users/me/dev/inbox"), .init(name: "Inbox", path: "/Users/me/dev/inbox"))
    }

    func testNamesMatchIgnoringCaseSpacesAndPunctuation() {
        XCTAssertEqual(resolve("noto")?.path, "/Users/me/dev/personal/Noto")
        XCTAssertEqual(resolve("  NOTO ")?.path, "/Users/me/dev/personal/Noto")
        XCTAssertEqual(resolve("dictate keyboard")?.path, "/Users/me/dev/personal/dictate-keyboard")
        XCTAssertEqual(resolve("Dictate-Keyboard.")?.path, "/Users/me/dev/personal/dictate-keyboard")
        XCTAssertEqual(resolve("inbox")?.path, "/Users/me/dev/inbox")
        XCTAssertEqual(resolve("root")?.path, "/Users/me/dev")
    }

    func testFirstListedEntryWinsATie() {
        XCTAssertEqual(resolve("lfg")?.path, "/Users/me/dev/personal/lfg")
    }

    func testLinkedDirectoryFallsBackToInbox() {
        let inbox = "/Users/me/dev/inbox"
        XCTAssertEqual(NewSessionDirectoryHint.directory(for: "noto", in: candidates, inbox: inbox),
                       .init(name: "Noto", path: "/Users/me/dev/personal/Noto"))
        XCTAssertEqual(NewSessionDirectoryHint.directory(for: "does not exist", in: candidates, inbox: inbox),
                       .init(name: "Inbox", path: inbox))
        XCTAssertEqual(NewSessionDirectoryHint.directory(for: nil, in: candidates, inbox: inbox),
                       .init(name: "Inbox", path: inbox))
        XCTAssertEqual(NewSessionDirectoryHint.directory(for: nil, in: [], inbox: ""),
                       .init(name: "Directory", path: ""))
    }

    func testUnknownOrBlankHintsResolveToNothing() {
        XCTAssertNil(resolve("does not exist"))
        XCTAssertNil(resolve(""))
        XCTAssertNil(resolve("   "))
        XCTAssertNil(resolve("!!!"))
    }
}

final class NewSessionLinkHintsTests: XCTestCase {
    private let pro = LFGCore.Host(url: "http://127.0.0.1:8766", name: "Eugenes-MacBook-Pro.local", isDefault: true)
    private let studio = LFGCore.Host(url: "https://studio.tail1234.ts.net", displayName: "Mac Studio")
    private let air = LFGCore.Host(url: "http://100.64.0.9:8766", name: "Eugenes-MacBook-Air")
    private var hosts: [LFGCore.Host] { [pro, studio, air] }

    /// The shape a current host's `GET /api/models` returns.
    private let live = ModelCatalogResponse(agents: [
        "claude": AgentModelCatalog(defaultModel: "claude-opus-5-5",
                                    models: ["claude-opus-5-5", "claude-fable-5-1", "claude-sonnet-5-5", "claude-haiku-4-5-20251001"]),
        "codex": AgentModelCatalog(defaultModel: "gpt-6-astra",
                                   models: ["gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.5"]),
    ])

    // MARK: Hosts

    func testHostHintsMatchNamesLoosely() {
        XCTAssertEqual(NewSessionLinkHints.host(for: "mac studio", in: hosts), studio)
        XCTAssertEqual(NewSessionLinkHints.host(for: "Eugenes MacBook Pro", in: hosts), pro)
        XCTAssertEqual(NewSessionLinkHints.host(for: "macbook air", in: hosts), air)
        XCTAssertEqual(NewSessionLinkHints.host(for: "Studio", in: hosts), studio)
    }

    func testHostHintsMatchAuthorityAndURL() {
        XCTAssertEqual(NewSessionLinkHints.host(for: "100.64.0.9:8766", in: hosts), air)
        XCTAssertEqual(NewSessionLinkHints.host(for: "https://studio.tail1234.ts.net", in: hosts), studio)
    }

    func testUnknownOrBlankHostHintsMatchNothing() {
        XCTAssertNil(NewSessionLinkHints.host(for: "windows box", in: hosts))
        XCTAssertNil(NewSessionLinkHints.host(for: "  ", in: hosts))
        XCTAssertNil(NewSessionLinkHints.host(for: nil, in: hosts))
        XCTAssertNil(NewSessionLinkHints.host(for: "pro", in: []))
    }

    // MARK: Agents

    func testAgentHintsAcceptAgentAndProviderNames() {
        XCTAssertEqual(NewSessionLinkHints.agent(for: "claude"), .claude)
        XCTAssertEqual(NewSessionLinkHints.agent(for: " Claude "), .claude)
        XCTAssertEqual(NewSessionLinkHints.agent(for: "Anthropic"), .claude)
        XCTAssertEqual(NewSessionLinkHints.agent(for: "codex"), .codex)
        XCTAssertEqual(NewSessionLinkHints.agent(for: "OpenAI"), .codex)
        XCTAssertNil(NewSessionLinkHints.agent(for: "gemini"))
        XCTAssertNil(NewSessionLinkHints.agent(for: nil))
    }

    // MARK: Models

    private func selection(_ agent: String?, _ model: String?,
                           catalog: ModelCatalogResponse? = nil) -> AgentModelSelection? {
        NewSessionLinkHints.modelSelection(agent: agent, model: model, catalog: catalog ?? live)
    }

    func testModelHintsResolveExactThenNormalizedThenContains() {
        XCTAssertEqual(selection(nil, "gpt-6-sol"), .init(agent: .codex, model: "gpt-6-sol"))
        XCTAssertEqual(selection(nil, "GPT 5.5"), .init(agent: .codex, model: "gpt-5.5"))
        XCTAssertEqual(selection(nil, "opus"), .init(agent: .claude, model: "claude-opus-5-5"))
        XCTAssertEqual(selection(nil, "Haiku"), .init(agent: .claude, model: "claude-haiku-4-5-20251001"))
        XCTAssertEqual(selection(nil, "astra"), .init(agent: .codex, model: "gpt-6-astra"))
        // Exact beats contains: the bundled catalog has the bare alias.
        XCTAssertEqual(selection(nil, "opus", catalog: .fallback), .init(agent: .claude, model: "opus"))
    }

    func testAModelImpliesItsProviderAndAnAgentNarrowsTheSearch() {
        XCTAssertEqual(selection("claude", "sonnet"), .init(agent: .claude, model: "claude-sonnet-5-5"))
        XCTAssertEqual(selection("openai", "sol"), .init(agent: .codex, model: "gpt-6-sol"))
        // An unknown agent hint doesn't block a model that names its provider.
        XCTAssertEqual(selection("gemini", "opus"), .init(agent: .claude, model: "claude-opus-5-5"))
    }

    func testAnAgentWithoutAUsableModelGetsThatAgentsDefault() {
        XCTAssertEqual(selection("codex", nil), .init(agent: .codex, model: "gpt-6-astra"))
        XCTAssertEqual(selection("codex", "opus"), .init(agent: .codex, model: "gpt-6-astra"))
        XCTAssertEqual(selection("claude", "nonexistent"), .init(agent: .claude, model: "claude-opus-5-5"))
    }

    func testNothingUsableMeansNoExplicitSelection() {
        XCTAssertNil(selection(nil, nil))
        XCTAssertNil(selection(nil, "nonexistent-model"))
        XCTAssertNil(selection("gemini", nil))
        XCTAssertNil(selection(nil, " - "))
    }
}
