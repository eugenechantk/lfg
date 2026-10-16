import Foundation

/// The needs-input panel docked at the bottom of a session (S2, boards
/// `s2-question` with kind question / permission / plan, and `s2-signin-prompt`):
/// its header, title, and the layout for the kind of prompt the agent is on.
public struct NeedsInputPanelModel: Equatable, Sendable {
    public struct Choice: Equatable, Sendable {
        public let index: Int
        public let label: String
        public init(index: Int, label: String) { self.index = index; self.label = label }
    }

    public enum Layout: Equatable, Sendable {
        /// Numbered options; a typed answer when the question offers one.
        case question(choices: [Choice], allowsTypedAnswer: Bool)
        /// The command (or file) card, where it runs, and the option each
        /// button sends.
        case permission(command: String, place: String?, allow: Int?, deny: Int?, always: Choice?)
        /// The plan's first steps, the whole plan, and the option each button sends.
        case plan(summary: [String], fullText: String, approve: Int?, keepPlanning: Int?)
        case signIn(website: String, target: String?, initial: String)
    }

    /// The small amber caps line: "Claude is asking · Upload".
    public let label: String
    public let title: String
    public let body: String?
    /// Sign-in prompts have no Dismiss: Escape would interrupt the agent.
    public let canDismiss: Bool
    public let layout: Layout

    public init(prompt: AgentPrompt, agent: String, cwd: String?, host: String?) {
        let agentName = agent == "codex" ? "Codex" : "Claude"
        if let signIn = prompt.signIn {
            label = "Sign-in needed"
            title = "Sign in to \(signIn.website)"
            body = "You log in on this iPhone. The sign-in then goes to Chrome on \(host ?? "your Mac"), where the agent is waiting."
            canDismiss = false
            layout = .signIn(website: signIn.website,
                             target: signIn.targetName.flatMap { $0.isEmpty ? nil : "To \($0)" },
                             initial: Self.initial(of: signIn.website))
            return
        }
        canDismiss = true
        switch prompt.kind {
        case "permission":
            let tool = prompt.permission?.tool ?? ""
            label = "\(agentName) needs permission"
            title = Self.permissionTitle(tool)
            body = nil
            let command = prompt.permission?.command ?? ""
            let card = command.isEmpty ? (prompt.permission?.detail ?? prompt.question) : command
            let place: String?
            switch (cwd.map(Self.homeRelative), host) {
            case let (dir?, host?): place = "In \(dir) on \(host)"
            case let (dir?, nil): place = "In \(dir)"
            case let (nil, host?): place = "On \(host)"
            default: place = nil
            }
            let plainYes: PromptOption? = prompt.options.first { $0.label == "Yes" }
            let anyYes: PromptOption? = prompt.options.first { $0.label.hasPrefix("Yes") && !Self.isAlways($0.label) }
            let allow: Int? = (plainYes ?? anyYes)?.index
            let deny: Int? = prompt.options.last { $0.label.hasPrefix("No") }?.index
            let always = prompt.options.first { Self.isAlways($0.label) }
                .map { Choice(index: $0.index,
                              label: Self.alwaysLabel(Self.rejoined($0.label, wrappedTail: $0.description, cwd: cwd), cwd: cwd)) }
            layout = .permission(command: card, place: place, allow: allow, deny: deny, always: always)
        case "plan":
            label = "Plan ready for review"
            title = "Approve this plan?"
            body = nil
            let text = prompt.plan?.text ?? ""
            let approve = prompt.options.first { $0.label.hasPrefix("Yes") }?.index ?? prompt.options.first?.index
            let keep = prompt.options.last {
                $0.label.hasPrefix("No") || $0.label.localizedCaseInsensitiveContains("keep planning")
                    || $0.label.localizedCaseInsensitiveContains("what to change")
            }?.index
            layout = .plan(summary: Self.planSummary(text), fullText: text, approve: approve, keepPlanning: keep)
        default:
            let header = prompt.header.flatMap { $0.isEmpty ? nil : $0 }
            label = header.map { "\(agentName) is asking · \($0)" } ?? "\(agentName) is asking"
            title = prompt.question
            body = prompt.detail.flatMap { $0.isEmpty ? nil : $0 }
            // Claude's question TUI always adds "Type something." (the host types
            // into it from the pane), even when the transcript's options omit it.
            let typed = prompt.options.contains { Self.isTypedAnswer($0.label) } || agent == "claude"
            let choices = prompt.options
                .filter { !Self.isTypedAnswer($0.label) && !$0.label.hasPrefix("Chat about this") }
                .map { Choice(index: $0.index, label: $0.label) }
            layout = .question(choices: choices, allowsTypedAnswer: typed)
        }
    }

    static func isTypedAnswer(_ label: String) -> Bool {
        label.range(of: "^Type something", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isAlways(_ label: String) -> Bool {
        label.hasPrefix("Yes, and ") || label.hasPrefix("Yes, allow ")
    }

    /// "Yes, and don't ask again for X" → "Don't ask again for X", with home
    /// paths shortened and the TUI's key hint dropped.
    /// A permission option that wrapped in the pane reaches us as a head (the
    /// label) and a tail (parsed as its description; permission options have
    /// none of their own). Claude breaks a long path mid-token with no space,
    /// and prose at a space; prefer the join that contains the session folder.
    static func rejoined(_ label: String, wrappedTail: String?, cwd: String?) -> String {
        guard let tail = wrappedTail?.trimmingCharacters(in: .whitespaces), !tail.isEmpty else { return label }
        let tight = label + tail
        if let cwd, !cwd.isEmpty, tight.contains(cwd) { return tight }
        return label + " " + tail
    }

    static func alwaysLabel(_ label: String, cwd: String? = nil) -> String {
        var rest = label
        for prefix in ["Yes, and ", "Yes, "] where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count)); break
        }
        rest = rest.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        // The session's own folder reads as "this folder" (board: "Always allow
        // fastlane in this folder").
        if let cwd, !cwd.isEmpty {
            rest = rest.replacingOccurrences(of: cwd, with: "this folder")
        }
        rest = homeRelative(rest)
        rest = rest.replacingOccurrences(of: #"^[Dd]on't ask again for (.+?) commands? in "#,
                                         with: "Always allow $1 in ", options: .regularExpression)
        // "always allow access to <folder> from this project": the rule is
        // saved per project anyway; the folder is what the reader needs.
        rest = rest.replacingOccurrences(of: #" from this project$"#, with: "", options: .regularExpression)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    static func permissionTitle(_ tool: String) -> String {
        switch tool {
        case "Bash": return "Run this command?"
        case "Edit", "MultiEdit", "NotebookEdit": return "Allow this edit?"
        case "Write": return "Allow writing this file?"
        case "WebFetch": return "Fetch this page?"
        case "WebSearch": return "Search the web?"
        case "": return "Allow this?"
        default: return "Allow \(tool)?"
        }
    }

    /// "/Users/eugene/dev/x" → "~/dev/x", anywhere in the string.
    static func homeRelative(_ s: String) -> String {
        s.replacingOccurrences(of: #"/Users/[^/\s]+"#, with: "~", options: .regularExpression)
    }

    /// The first three numbered steps, markdown stripped; else the first three
    /// lines that are not headings.
    static func planSummary(_ text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        let numbered = lines.compactMap { line -> String? in
            guard let m = line.range(of: #"^\s{0,3}(#{1,4}\s*)?\d+[.)]\s+\S"#, options: .regularExpression) else { return nil }
            let stripped = line[m.lowerBound...].replacingOccurrences(of: #"^\s*#{1,4}\s*"#, with: "", options: .regularExpression)
            return clean(stripped)
        }
        if !numbered.isEmpty { return Array(numbered.prefix(3)) }
        return Array(lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.map(clean).prefix(3))
    }

    /// "search.google.com" → "G": the first letter of the name before the TLD.
    static func initial(of website: String) -> String {
        let parts = website.split(separator: ".")
        let name = parts.count >= 2 ? parts[parts.count - 2] : parts.first ?? ""
        return name.first.map { String($0).uppercased() } ?? "?"
    }
}
