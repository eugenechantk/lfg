import Testing
@testable import LFGCore

struct CLIModelDefaultTests {
    @Test func defaultSurvivesRestoreAndChangingCatalogs() {
        for agent in AgentKind.allCases {
            let selection = AgentModelSelection(agent: agent, model: "")
            #expect(AgentModelSelection.restoringPersisted(agentRawValue: agent.rawValue, model: "") == selection)
            #expect(AgentModelSelection.restoring(agentRawValue: agent.rawValue, model: "") == selection)
            for model in ["first-model", "next-model"] {
                let catalog = ModelCatalogResponse(agents: [agent.rawValue: AgentModelCatalog(defaultModel: model, models: [model])])
                #expect(selection.reconciled(with: catalog) == selection)
            }
        }
        #expect(AgentModelSelection.default.model.isEmpty)
        #expect(ModelChipLabel.model("") == "Default")
    }

    @Test func directoryHistoryOverridesAGlobalRememberedDefault() {
        let previous = Session(sessionId: "old", title: "Old", agent: "codex", model: "old-model", cwd: "/repo", lastActivityAt: 1)
        let selection = AgentModelSelection.inferred(forCwd: "/repo", in: [previous], fallback: .init(agent: .codex, model: ""))
        #expect(selection.model == "old-model")
        #expect(selection.agent == .codex)
    }

    @Test func freshDirectoryIgnoresEveryGlobalRememberedChoice() {
        for agent in AgentKind.allCases {
            for model in ["", "previous-model"] {
                for cwd in ["/fresh", "", "   "] {
                    let selection = AgentModelSelection.inferred(forCwd: cwd, in: [], fallback: .init(agent: agent, model: model))
                    #expect(selection == .init(agent: .claude, model: ""))
                }
            }
        }
    }

    @Test func eachSessionToolOffersDefaultFirst() {
        let sections = SessionHandoff.modelSections(current: .codex)
        #expect(sections.count == 2)
        for section in sections {
            #expect(section.models.first == "")
            #expect(section.models.filter(\.isEmpty).count == 1)
        }
    }

    @Test func configuredDefaultDoesNotBecomeAnAdvertisedRecommendation() {
        let catalog = ModelCatalogResponse(agents: ["codex": AgentModelCatalog(defaultModel: "configured-model", models: ["recommended-model"])])
        #expect(catalog.defaultModel(for: .codex) == "configured-model")
    }
}
