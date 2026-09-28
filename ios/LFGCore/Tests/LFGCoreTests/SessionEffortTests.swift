import Foundation
import Testing
@testable import LFGCore

@Suite("Session effort") struct SessionEffortTests {
    // Shape served by GET /api/models on codex-cli 0.156 / Claude Code 2.1.280.
    private let catalog: ModelCatalogResponse = {
        let json = #"""
        {"agents":{
          "claude":{"version":"2.1.280","defaultModel":"claude-opus-5-5",
            "models":["claude-opus-5-5","claude-fable-5-1","claude-sonnet-5","claude-haiku-4-5-20251001"],
            "efforts":{"claude-opus-5-5":["low","medium","high","xhigh","max"],
                       "claude-sonnet-5":["low","medium","high","xhigh","max"],
                       "claude-haiku-4-5-20251001":[]}},
          "codex":{"version":"0.156.0","defaultModel":"gpt-6-astra",
            "models":["gpt-6-astra","gpt-6-sol","gpt-6-luna"],
            "efforts":{"gpt-6-sol":["low","medium","high","xhigh","max","ultra"],
                       "gpt-6-luna":["low","medium","high","xhigh","max","bogus; rm"]}}
        }}
        """#
        return try! JSONDecoder().decode(ModelCatalogResponse.self, from: Data(json.utf8))
    }()

    @Test func codexModelsOfferTheirOwnLevels() {
        #expect(catalog.efforts(for: .codex, model: "gpt-6-sol") == ["low", "medium", "high", "xhigh", "max", "ultra"])
        // Unknown values from a host are never offered.
        #expect(catalog.efforts(for: .codex, model: "gpt-6-luna") == ["low", "medium", "high", "xhigh", "max"])
    }

    @Test func claudeAliasesResolveToTheirCatalogFamily() {
        // Session rows say "opus"; the catalog is keyed "claude-opus-5-5".
        #expect(catalog.efforts(for: .claude, model: "opus") == ["low", "medium", "high", "xhigh", "max"])
        #expect(catalog.efforts(for: .claude, model: "claude-sonnet-5") == ["low", "medium", "high", "xhigh", "max"])
    }

    @Test func modelsWithoutEffortControlOfferNothing() {
        #expect(catalog.efforts(for: .claude, model: "haiku").isEmpty)
    }

    @Test func unknownModelsAndOldHostsFallBackToTheCLIsUsualLevels() {
        // Fable has no entry (unknown), unlike Haiku's explicit [].
        #expect(catalog.efforts(for: .claude, model: "fable") == SessionEffort.usualLevels(for: .claude))
        #expect(catalog.efforts(for: .codex, model: "gpt-9") == SessionEffort.usualLevels(for: .codex))
        #expect(catalog.efforts(for: .codex, model: nil) == SessionEffort.usualLevels(for: .codex))
        #expect(ModelCatalogResponse.fallback.efforts(for: .claude, model: "opus") == ["low", "medium", "high", "xhigh", "max"])
        let old = #"{"agents":{"codex":{"defaultModel":"gpt-5.6-sol","models":["gpt-5.6-sol"]}}}"#
        let decoded = try? JSONDecoder().decode(ModelCatalogResponse.self, from: Data(old.utf8))
        #expect(decoded?.agents["codex"]?.efforts == [:])
    }

    @Test func labelsMatchTheCLIPickers() {
        #expect(SessionEffort.displayName("xhigh") == "Extra high")
        #expect(SessionEffort.displayName("max") == "Max")
        #expect(SessionEffort.displayName("ultra") == "Ultra")
        #expect(SessionEffort.displayName("low") == "Low")
    }

    @Test func sessionRowsCarryEffortAndOlderHostsDecode() throws {
        let json = #"{"sessions":[{"sessionId":"a","agent":"codex","model":"gpt-6-sol","effort":"max"},{"sessionId":"b","agent":"claude"}]}"#
        let sessions = try JSONDecoder().decode(SessionsResponse.self, from: Data(json.utf8)).sessions
        #expect(sessions[0].effort == "max")
        #expect(sessions[1].effort == nil)
    }
}
