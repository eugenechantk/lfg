import Foundation

/// One changed field on the "Saved · N changes" card: the field, its old value, its new value.
public struct TaskChange: Sendable, Equatable, Identifiable {
    public var field: String
    public var from: String
    public var to: String
    public var id: String { field }
    public init(field: String, from: String, to: String) { self.field = field; self.from = from; self.to = to }
}

/// The chat agent saves a task directly, so the app shows what changed by diffing the task
/// before and after (no proposal step on the server).
public enum TaskChangeDiff {
    public static func changes(before a: ScheduledTaskRecord, after b: ScheduledTaskRecord,
                               timeZone: TimeZone = .current, locale: Locale = .current) -> [TaskChange] {
        var out: [TaskChange] = []
        func add(_ field: String, _ from: String, _ to: String) { if from != to { out.append(.init(field: field, from: from, to: to)) } }
        add("Name", a.name, b.name)
        if a.schedule != b.schedule {
            let now = Date()
            let from = TaskScheduleSummary.changeLine(a.schedule, now: now, timeZone: timeZone, locale: locale)
            let to = TaskScheduleSummary.changeLine(b.schedule, now: now, timeZone: timeZone, locale: locale)
            out.append(.init(field: "Schedule", from: from, to: from == to ? "\(to) (adjusted)" : to))
        }
        add("Agent", agentName(a.agent), agentName(b.agent))
        add("Model", ModelName.display(a.modelLabel), ModelName.display(b.modelLabel))
        add("Folder", a.cwd, b.cwd)
        if a.prompt != b.prompt { out.append(.init(field: "Instructions", from: excerpt(a.prompt), to: excerpt(b.prompt))) }
        add("Status", a.enabled ? "On" : "Paused", b.enabled ? "On" : "Paused")
        return out
    }

    static func agentName(_ agent: String) -> String { agent == "codex" ? "Codex" : "Claude Code" }

    static func excerpt(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }
}

/// A model id as people write it: "gpt-6-astra" → "GPT-6 Astra", "claude-opus-5-5" → "Claude Opus 5.5".
/// Labels that are already words ("Claude default") pass through.
public enum ModelName {
    public static func display(_ id: String) -> String {
        guard !id.contains(" "), !id.isEmpty else { return id }
        var parts = id.split(separator: "-").map(String.init)
        var out: [String] = []
        if parts.first?.lowercased() == "gpt", parts.count > 1 {
            out.append("GPT-\(parts[1])"); parts.removeFirst(2)
        }
        for part in parts {
            if let last = out.last, part.allSatisfy(\.isNumber), last.last?.isNumber == true, !last.hasPrefix("GPT-") {
                out[out.count - 1] = "\(last).\(part)"
            } else {
                out.append(part.prefix(1).uppercased() + part.dropFirst())
            }
        }
        return out.joined(separator: " ")
    }
}
