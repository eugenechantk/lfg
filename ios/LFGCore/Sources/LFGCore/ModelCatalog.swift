import Foundation

// MARK: - Agent / model catalogs (mirrors server allowlists)

public enum AgentKind: String, CaseIterable, Sendable, Identifiable {
    case claude           // claude CLI (tmux)
    case codex            // codex CLI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Bundled picker catalog. Current hosts override this at runtime via
    /// `GET /api/models`; these values keep old/offline hosts usable.
    public var pickerModels: [String] {
        switch self {
        case .claude:
            // Claude Code resolves these aliases against its installed catalog,
            // so they remain valid when the host predates GET /api/models.
            return ["opus", "fable", "sonnet", "haiku"]
        case .codex:
            // Compatibility IDs accepted by the previous host generation. A
            // current host replaces these with its live CLI-discovered catalog.
            return ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        }
    }

    /// Accepted persisted/transcript-derived values. Older exact Claude IDs
    /// remain readable even though aliases are the compatibility picker choices.
    public var models: [String] {
        self == .claude
            ? pickerModels + ["claude-opus-5", "claude-fable-5", "claude-sonnet-5", "claude-haiku-4-5"]
            : pickerModels
    }

    public var defaultModel: String { pickerModels.first ?? "sonnet" }
}

/// One installed CLI's account-scoped model catalog. Every field is lenient so
/// an older/newer host cannot make the whole create flow undecodable.
public struct AgentModelCatalog: Codable, Sendable, Equatable {
    public var version: String?
    public var defaultModel: String
    public var models: [String]
    /// Reasoning levels per model id. `[]` = the model has no effort control
    /// (Claude Haiku); a model missing here is unknown. Older hosts omit it.
    public var efforts: [String: [String]]

    public init(version: String? = nil, defaultModel: String, models: [String], efforts: [String: [String]] = [:]) {
        self.version = version
        self.defaultModel = defaultModel
        self.models = models
        self.efforts = efforts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        defaultModel = (try c.decodeIfPresent(String.self, forKey: .defaultModel)) ?? ""
        models = (try? c.decode([String].self, forKey: .models)) ?? []
        efforts = (try? c.decode([String: [String]].self, forKey: .efforts)) ?? [:]
    }
}

public struct ModelCatalogResponse: Codable, Sendable, Equatable {
    public var agents: [String: AgentModelCatalog]

    public init(agents: [String: AgentModelCatalog] = [:]) {
        self.agents = agents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = (try? c.decode([String: AgentModelCatalog].self, forKey: .agents)) ?? [:]
    }

    public static let fallback = ModelCatalogResponse(agents: Dictionary(
        uniqueKeysWithValues: AgentKind.allCases.map { kind in
            (kind.rawValue, AgentModelCatalog(defaultModel: kind.defaultModel, models: kind.pickerModels))
        }
    ))

    public func models(for agent: AgentKind) -> [String] {
        guard let discovered = agents[agent.rawValue]?.models.filter(AgentModelSelection.isSafeModelName),
              !discovered.isEmpty else { return agent.pickerModels }
        var seen = Set<String>()
        return discovered.filter { seen.insert($0).inserted }
    }

    public func defaultModel(for agent: AgentKind) -> String {
        let available = models(for: agent)
        guard let preferred = agents[agent.rawValue]?.defaultModel,
              available.contains(preferred) else { return available.first ?? agent.defaultModel }
        return preferred
    }

    public func version(for agent: AgentKind) -> String? {
        agents[agent.rawValue]?.version
    }

    /// Effort levels a session on `model` can switch between, in the CLI's own
    /// order. Claude rows carry aliases (`opus`) while the catalog is keyed by
    /// full ids (`claude-opus-5-5`), so an alias resolves to the first catalog
    /// model of its family — the one the alias launches. Unknown models, and
    /// hosts that predate the field, get the CLI's usual levels.
    public func efforts(for agent: AgentKind, model: String?) -> [String] {
        let byModel = agents[agent.rawValue]?.efforts ?? [:]
        var levels: [String]?
        if let model {
            levels = byModel[model]
            if levels == nil, agent == .claude, let family = SessionEffort.claudeFamily(of: model) {
                let candidates = models(for: agent) + byModel.keys.sorted()
                levels = candidates.first { $0.lowercased().contains(family) && byModel[$0] != nil }
                    .flatMap { byModel[$0] }
            }
        }
        return (levels ?? SessionEffort.usualLevels(for: agent)).filter(SessionEffort.isKnown)
    }
}

/// A validated agent/model pair for starting a new session.
///
/// Model catalogs evolve, so persisted values must be resolved through the
/// current catalog before a create request uses them. A still-valid agent keeps
/// its identity when its old model disappears and falls back to that agent's
/// current default; an unknown agent falls back to the global default pair.
public struct AgentModelSelection: Equatable, Sendable {
    public var agent: AgentKind
    public var model: String

    public init(agent: AgentKind, model: String) {
        self.agent = agent
        self.model = model
    }

    public static let `default` = AgentModelSelection(
        agent: .claude,
        model: AgentKind.claude.defaultModel
    )

    public static func restoring(agentRawValue: String?, model: String?) -> AgentModelSelection {
        guard let agentRawValue, let agent = AgentKind(rawValue: agentRawValue) else {
            return .default
        }
        guard let model, agent.models.contains(model) else {
            return AgentModelSelection(agent: agent, model: agent.defaultModel)
        }
        return AgentModelSelection(agent: agent, model: model)
    }

    /// Persisted selections may come from a newer host catalog than the app's
    /// bundled fallback. Preserve a syntactically safe future id until the host
    /// catalog can reconcile it instead of erasing it during app initialization.
    public static func restoringPersisted(agentRawValue: String?, model: String?) -> AgentModelSelection {
        guard let agentRawValue, let agent = AgentKind(rawValue: agentRawValue) else {
            return .default
        }
        guard let model, isSafeModelName(model) else {
            return AgentModelSelection(agent: agent, model: agent.defaultModel)
        }
        return AgentModelSelection(agent: agent, model: model)
    }

    public func reconciled(with catalog: ModelCatalogResponse) -> AgentModelSelection {
        let available = catalog.models(for: agent)
        guard available.contains(model) else {
            return AgentModelSelection(agent: agent, model: catalog.defaultModel(for: agent))
        }
        return self
    }

    public static func isSafeModelName(_ model: String) -> Bool {
        guard !model.isEmpty, model.utf8.count <= 80 else { return false }
        return model.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 46, 58, 95: return true
            default: return false
            }
        }
    }
}
