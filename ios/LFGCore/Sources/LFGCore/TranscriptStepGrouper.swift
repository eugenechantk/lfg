import Foundation

// S2 session view (canvas boards `s2-view`, `s2-tools-group`, `s2-tools-single`):
// consecutive tool rows fold into ONE step — "Read 6 files, ran 3 commands" —
// that expands to each call, and each call expands to its input and result.
// A step ends after edits.
// Pure, so the folding and pairing rules are tested here, not eyeballed.

/// What a tool call does, for its verb, its icon and the step summary.
public enum ToolKind: String, Sendable, Equatable, CaseIterable {
    case read, explore, search, edit, command, web, agent, ask, other

    /// The verb on a single call's row ("Ran", "Read", …).
    public var verb: String {
        switch self {
        case .read: return "Read"
        case .explore: return "Explored"
        case .search: return "Searched"
        case .edit: return "Edited"
        case .command: return "Ran"
        case .web: return "Fetched"
        case .agent: return "Started agent ·"
        case .ask: return "Asked ·"
        case .other: return "Used"
        }
    }

    /// The summary phrase for `count` calls of this kind ("read 3 files").
    func phrase(_ count: Int) -> String {
        func plural(_ word: String) -> String { count == 1 ? word : word + "s" }
        switch self {
        case .read: return "read \(count) \(plural("file"))"
        case .explore: return "explored \(count) \(plural("time"))"
        case .search: return "searched \(count) \(plural("pattern"))"
        case .edit: return "edited \(count) \(plural("file"))"
        case .command: return "ran \(count) \(plural("command"))"
        case .web: return "fetched \(count) \(plural("page"))"
        case .agent: return "started \(count) \(plural("agent"))"
        case .ask: return "asked \(count) \(plural("question"))"
        case .other: return "used \(count) \(plural("tool"))"
        }
    }
}

/// One tool call: the call row, its paired result (when there is one), and what
/// the expanded card shows.
public struct ToolCall: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ToolKind
    /// Short, single-line: the command, file, pattern or URL.
    public let target: String
    /// The full call text the host sent, for the card's input section.
    public let input: String
    public let result: String?
    public let isError: Bool
    /// Result time minus call time, when both are known.
    public let durationMs: Double?

    public var verb: String { kind.verb }

    /// "lines 1600–1660" for a Read that asked for part of a file (board
    /// `s2-tools-group`). Parsed from the call text, "Read: {json}".
    public var inputDetail: String? {
        guard kind == .read, let colon = input.firstIndex(of: ":"),
              let data = input[input.index(after: colon)...].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let offset = (json["offset"] as? NSNumber)?.intValue
        let limit = (json["limit"] as? NSNumber)?.intValue
        switch (offset, limit) {
        case let (o?, l?) where l > 0: return "lines \(o)–\(o + l - 1)"
        case let (o?, nil): return "from line \(o)"
        case let (nil, l?) where l > 0: return "lines 1–\(l)"
        default: return nil
        }
    }
    /// "Ran bun test …" — a single call's row label.
    public var label: String { target.isEmpty ? verb.replacingOccurrences(of: " ·", with: "") : "\(verb) \(target)" }
}

/// A run of consecutive tool rows, folded into one step.
public struct ToolStepGroup: Sendable, Equatable, Identifiable {
    /// The first row's id: stable while the run grows at its end.
    public let id: String
    /// Indices into the message array this group covers.
    public let indices: ClosedRange<Int>
    /// Results that arrived after the step closed (see `items(for:)`).
    public let lateResults: [Int]
    public let calls: [ToolCall]

    public var isSingleCall: Bool { calls.count == 1 }
    /// The most common kind, for the step's icon.
    public var dominantKind: ToolKind {
        let counts = Dictionary(grouping: calls, by: \.kind).mapValues(\.count)
        return calls.map(\.kind).max { counts[$0, default: 0] < counts[$1, default: 0] } ?? .other
    }
    public var hasError: Bool { calls.contains(where: \.isError) }
    public var durationMs: Double? {
        let parts = calls.compactMap(\.durationMs)
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    /// "Ran bun test …" for one call; "Read 6 files, ran 3 commands" for many.
    public var summary: String {
        if isSingleCall { return calls[0].label }
        var order: [ToolKind] = []
        var counts: [ToolKind: Int] = [:]
        for call in calls {
            if counts[call.kind] == nil { order.append(call.kind) }
            counts[call.kind, default: 0] += 1
        }
        // Most calls first; ties keep the order they first appeared (boards:
        // "Read 4 files, ran 2 commands" though the run starts with a command).
        let ranked = order.enumerated()
            .sorted { (counts[$0.element] ?? 0, -$0.offset) > (counts[$1.element] ?? 0, -$1.offset) }
            .map(\.element)
        let text = ranked.map { $0.phrase(counts[$0] ?? 0) }.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

public enum TranscriptItem: Sendable, Equatable {
    /// A non-tool message, by index.
    case message(Int)
    case steps(ToolStepGroup)
}

public enum TranscriptStepGrouper {
    public static func items(for messages: [SessionMessage]) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var runStart: Int?
        // A step ends after edits: the commands that follow (a test run) start
        // the next one. Boards: `s2-queued` "Edited 2 files" then "Ran bun
        // test…"; `s2-question` "Ran 7 commands, edited 1 file" stays one step.
        // The split waits until every earlier call has its result, so parallel
        // calls never lose their results to the next step.
        var lastWasEdit: Bool?
        var openIds = Set<String>()
        var openAnonymous = 0
        // A message sent mid-tool is absorbed at the tool boundary, so its user
        // turn lands between a call and that call's result. The result then
        // joins the step that holds its call instead of starting a stray one.
        var closedOpenIds: [String: Int] = [:]   // unanswered call id → item index
        var lateResults: [Int: [Int]] = [:]      // item index → result indices
        func closeRun(at end: Int) {
            guard let start = runStart else { return }
            for uid in openIds { closedOpenIds[uid] = items.count }
            items.append(.steps(group(messages, start...end)))
            runStart = nil; lastWasEdit = nil; openIds = []; openAnonymous = 0
        }
        for (i, m) in messages.enumerated() {
            if m.kind == "tool_use" {
                let isEdit = classify(m).0 == .edit
                if runStart != nil, lastWasEdit == true, !isEdit,
                   openIds.isEmpty, openAnonymous == 0 {
                    closeRun(at: i - 1)
                }
                if runStart == nil { runStart = i }
                lastWasEdit = isEdit
                if let uid = m.toolUseId { openIds.insert(uid) } else { openAnonymous += 1 }
            } else if m.kind == "tool_result" {
                if let uid = m.toolUseId, !openIds.contains(uid), let owner = closedOpenIds.removeValue(forKey: uid),
                   case .steps(let earlier) = items[owner] {
                    lateResults[owner, default: []].append(i)
                    items[owner] = .steps(group(messages, earlier.indices, lateResults: lateResults[owner] ?? []))
                    continue
                }
                if runStart == nil { runStart = i }
                if let uid = m.toolUseId, openIds.remove(uid) != nil {
                } else if openAnonymous > 0 {
                    openAnonymous -= 1
                }
            } else {
                closeRun(at: i - 1)
                items.append(.message(i))
            }
        }
        closeRun(at: messages.count - 1)
        return items
    }

    public static func isToolRow(_ m: SessionMessage) -> Bool {
        m.kind == "tool_use" || m.kind == "tool_result"
    }

    static func group(_ messages: [SessionMessage], _ range: ClosedRange<Int>,
                      lateResults: [Int] = []) -> ToolStepGroup {
        struct Draft { var useIndex: Int?; var resultIndex: Int? }
        var drafts: [Draft] = []
        var draftByUseId: [String: Int] = [:]
        for i in Array(range) + lateResults {
            let m = messages[i]
            if m.kind == "tool_use" {
                if let uid = m.toolUseId { draftByUseId[uid] = drafts.count }
                drafts.append(Draft(useIndex: i))
            } else {
                // Pair by id, else with the nearest unanswered call before it.
                if let uid = m.toolUseId, let d = draftByUseId[uid], drafts[d].resultIndex == nil {
                    drafts[d].resultIndex = i
                } else if let d = drafts.lastIndex(where: { $0.useIndex != nil && $0.resultIndex == nil
                                                            && (m.toolUseId == nil || messages[$0.useIndex!].toolUseId == nil) }) {
                    drafts[d].resultIndex = i
                } else {
                    drafts.append(Draft(useIndex: nil, resultIndex: i))
                }
            }
        }
        let calls = drafts.map { d -> ToolCall in
            let use = d.useIndex.map { messages[$0] }
            let res = d.resultIndex.map { messages[$0] }
            let (kind, target) = use.map(classify) ?? (.other, "")
            var duration: Double?
            if let a = use?.ts, let b = res?.ts, b >= a { duration = b - a }
            return ToolCall(
                id: (use ?? res)?.stableID ?? UUID().uuidString,
                kind: kind,
                target: target,
                input: use?.text ?? "",
                result: res?.text,
                isError: res?.isError == true,
                durationMs: duration)
        }
        let firstID = messages[range.lowerBound].stableID
        return ToolStepGroup(id: firstID, indices: range, lateResults: lateResults, calls: calls)
    }

    /// Kind + one-line target from a call row: the structured `tool` field when
    /// the host sends it, else the display text ("Bash: {json}" from older
    /// Claude hosts, "Ran\n…" / "Explored\n…" / "Edited …" from Codex).
    static func classify(_ m: SessionMessage) -> (ToolKind, String) {
        let text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tool = m.tool {
            if let target = tool.target, !target.isEmpty { return (kind(forToolName: tool.name), target) }
            // No structured target (AskUserQuestion today): read it from the
            // call's own "Name: {json}" text.
            let json = text.hasPrefix(tool.name + ":") ? String(text.dropFirst(tool.name.count + 1)) : ""
            return (kind(forToolName: tool.name), legacyTarget(name: tool.name, json: json))
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let first = lines.first ?? ""
        let rest = lines.dropFirst().first ?? ""
        switch true {
        case first == "Ran": return (.command, rest)
        case first == "Explored": return (.explore, rest)
        case first.hasPrefix("Edited "): return (.edit, String(first.dropFirst("Edited ".count)))
        case first.hasPrefix("Searching the web"): return (.web, "")
        case first.hasPrefix("Waiting for agents"): return (.agent, "")
        case first.hasPrefix("Started agent · "): return (.agent, String(first.dropFirst("Started agent · ".count)))
        case first == "Started child agent": return (.agent, "")
        default: break
        }
        // "Name: {json}" — the legacy Claude shape.
        if let colon = first.firstIndex(of: ":") {
            let name = String(first[..<colon])
            if !name.contains(" ") {
                let json = String(text[text.index(after: text.firstIndex(of: ":")!)...])
                return (kind(forToolName: name), legacyTarget(name: name, json: json))
            }
        }
        return (.other, first)
    }

    static func kind(forToolName name: String) -> ToolKind {
        switch name {
        case "Read", "NotebookRead": return .read
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .edit
        case "Bash", "BashOutput", "KillShell": return .command
        case "Grep", "Glob": return .search
        case "WebFetch", "WebSearch": return .web
        case "Agent", "Task": return .agent
        case "AskUserQuestion": return .ask
        default: return .other
        }
    }

    private static func legacyTarget(name: String, json: String) -> String {
        guard let data = json.trimmingCharacters(in: .whitespaces).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        let keys: [String]
        switch kind(forToolName: name) {
        case .command: keys = ["command"]
        case .read, .edit: keys = ["file_path", "notebook_path"]
        case .search: keys = ["pattern"]
        case .web: keys = ["url", "query"]
        case .agent: keys = ["description"]
        case .ask:
            let first = (obj["questions"] as? [[String: Any]])?.first?["question"] as? String
            return first?.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        default: keys = []
        }
        for k in keys {
            if let v = obj[k] as? String,
               let line = v.split(separator: "\n").first.map({ $0.trimmingCharacters(in: .whitespaces) }),
               !line.isEmpty { return line }
        }
        return ""
    }
}

/// How much of a result the expanded card shows: commands show their tail
/// (where the outcome is), everything else its head.
public enum ToolCallPreview {
    public struct Lines: Equatable, Sendable {
        public let lines: [String]
        public let total: Int
        public let fromEnd: Bool
    }

    public static func lines(of text: String, kind: ToolKind, limit: Int) -> Lines {
        var all = text.components(separatedBy: "\n")
        while all.last?.isEmpty == true { all.removeLast() }
        let fromEnd = kind == .command
        let shown = fromEnd ? Array(all.suffix(limit)) : Array(all.prefix(limit))
        return Lines(lines: shown, total: all.count, fromEnd: fromEnd)
    }
}
