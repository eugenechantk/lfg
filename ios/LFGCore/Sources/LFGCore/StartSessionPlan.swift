import Foundation

/// How the "Start Session" Shortcuts action turns its loose inputs into a concrete session: which
/// host, which directory, which agent/model — the same resolution an `lfg://new` link gets in New
/// Session, minus the screen. Pure, so it is tested without a host.
public struct StartSessionPlan: Equatable, Sendable {
    public var host: Host
    public var directory: NewSessionDirectoryHint.Candidate
    public var selection: AgentModelSelection

    public init(host: Host, directory: NewSessionDirectoryHint.Candidate, selection: AgentModelSelection) {
        self.host = host
        self.directory = directory
        self.selection = selection
    }
}

public enum StartSessionPlanner {
    /// The hinted host if one matches, else the default (live default → marked default → first).
    public static func host(hint: String?, hosts: [Host], fallback: Host?) -> Host? {
        NewSessionLinkHints.host(for: hint, in: hosts) ?? fallback
    }

    /// Candidates New Session would offer from the host's directory listing.
    public static func candidates(_ dirs: DirsResponse) -> [NewSessionDirectoryHint.Candidate] {
        var out: [NewSessionDirectoryHint.Candidate] = []
        if !dirs.root.isEmpty { out.append(.init(name: "Root", path: dirs.root)) }
        if !dirs.inbox.isEmpty { out.append(.init(name: "Inbox", path: dirs.inbox)) }
        out.append(contentsOf: dirs.repos.map { .init(name: $0.name, path: $0.cwd) })
        return out
    }

    /// The hinted project, else Inbox.
    public static func directory(hint: String?, dirs: DirsResponse) -> NewSessionDirectoryHint.Candidate {
        NewSessionDirectoryHint.directory(for: hint, in: candidates(dirs), inbox: dirs.inbox)
    }

    /// The hinted agent/model, else the last selection used in New Session, checked against what
    /// this host offers.
    public static func selection(agent: String?, model: String?, catalog: ModelCatalogResponse,
                                 remembered: AgentModelSelection) -> AgentModelSelection {
        NewSessionLinkHints.modelSelection(agent: agent, model: model, catalog: catalog)
            ?? remembered.reconciled(with: catalog)
    }

    /// "Action completed" banner text: what started, where.
    public static func notification(prompt: String, plan: StartSessionPlan) -> (title: String, body: String) {
        let firstLine = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let short = firstLine.count > 80 ? String(firstLine.prefix(79)) + "…" : firstLine
        let agent = plan.selection.agent.displayName
        return ("Action completed",
                "Started \(agent) (\(plan.selection.model)) in \(plan.directory.name) on \(plan.host.label): “\(short)”")
    }
}
