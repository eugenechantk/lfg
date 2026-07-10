// LFG Sessions — a minimal macOS desktop app that lists every Claude Code /
// Codex session across all configured lfg hosts and reopens any of them in
// iTerm2 with one click.
//
//   - Session on THIS machine with a tmux pane  -> iTerm2 window attached to
//     that same tmux session (`tmux attach -t <name>`).
//   - Session on ANOTHER machine (or a local one with no tmux pane) -> iTerm2
//     window with a fresh local tmux session running `claude --resume <id>`
//     in the session's cwd. Works because ~/.claude/projects syncs between
//     hosts, so the transcript is present locally.
//
// Opened iTerm2 windows are resized to span the full height of the desktop
// (screen) they appear on.
//
// Like the iOS client, the list has a search field and a segmented control to
// group by Status (Working / Paused / Idle) or by Directory (collapsible
// sections with running/idle tallies).
//
// Hosts are read from ~/.config/lfg-desktop/hosts.json:
//   { "hosts": ["http://localhost:8766", "http://100.75.162.40:8766"] }
//
// Built by build.sh (swiftc, no Xcode project).

import SwiftUI
import AppKit

// MARK: - API models (subset of lfg's Session type)

struct APISession: Decodable, Identifiable, Hashable {
    let agent: String
    let pid: Int
    let cwd: String?
    let project: String
    let title: String
    let sessionId: String?
    let busy: Bool
    let lastActivityAt: Double?
    let tmuxName: String?
    let model: String?
    let status: String?
    let parentSessionId: String?
    let lastUserText: String?
    let closed: Bool

    var id: String { sessionId ?? "pid-\(pid)" }

    init(agent: String, pid: Int, cwd: String?, project: String, title: String,
         sessionId: String?, busy: Bool, lastActivityAt: Double?, tmuxName: String?,
         model: String?, status: String?, parentSessionId: String? = nil,
         lastUserText: String?, closed: Bool = false) {
        self.agent = agent
        self.pid = pid
        self.cwd = cwd
        self.project = project
        self.title = title
        self.sessionId = sessionId
        self.busy = busy
        self.lastActivityAt = lastActivityAt
        self.tmuxName = tmuxName
        self.model = model
        self.status = status
        self.parentSessionId = parentSessionId
        self.lastUserText = lastUserText
        self.closed = closed
    }

    enum CodingKeys: String, CodingKey {
        case agent, pid, cwd, project, title, sessionId, busy, lastActivityAt, tmuxName, model, status, parentSessionId, lastUserText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decode(String.self, forKey: .agent)
        pid = try c.decode(Int.self, forKey: .pid)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        project = try c.decode(String.self, forKey: .project)
        title = try c.decode(String.self, forKey: .title)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        busy = try c.decode(Bool.self, forKey: .busy)
        lastActivityAt = try c.decodeIfPresent(Double.self, forKey: .lastActivityAt)
        tmuxName = try c.decodeIfPresent(String.self, forKey: .tmuxName)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        parentSessionId = try c.decodeIfPresent(String.self, forKey: .parentSessionId)
        lastUserText = try c.decodeIfPresent(String.self, forKey: .lastUserText)
        closed = false
    }
}

struct SessionsResponse: Decodable { let sessions: [APISession] }
struct ResumableAPISession: Decodable {
    let sessionId: String
    let cwd: String?
    let project: String?
    let title: String
    let lastActivityAt: Double?
    let lastUserText: String?
}
struct ResumableResponse: Decodable { let sessions: [ResumableAPISession] }
struct HostInfoResponse: Decodable { let hostId: String; let hostName: String }

// MARK: - Host state

struct HostState: Identifiable {
    let url: String
    var info: HostInfoResponse?
    var sessions: [APISession] = []
    var closedSessions: [APISession] = []
    var error: String?
    var isLocal: Bool = false

    var id: String { url }

    var label: String {
        if let name = info?.hostName {
            return String(name.split(separator: ".").first ?? Substring(name))
        }
        return url.replacingOccurrences(of: "http://", with: "")
    }
}

/// One session joined with the host it lives on — the unit the list renders.
struct SessionItem: Identifiable {
    let session: APISession
    let hostLabel: String
    let hostIsLocal: Bool

    var id: String { "\(hostLabel)-\(session.id)" }

    enum Status: Int, CaseIterable {
        case paused, working, idle, closed
        var title: String {
            switch self {
            case .paused: return "Paused"
            case .working: return "Working"
            case .idle: return "Idle"
            case .closed: return "Closed"
            }
        }
    }

    var status: Status {
        if session.closed { return .closed }
        if session.status == "blocked" { return .paused }
        if session.busy { return .working }
        return .idle
    }
}

// MARK: - Config

enum Config {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lfg-desktop", isDirectory: true)
    }
    static var hostsFile: URL { dir.appendingPathComponent("hosts.json") }

    struct HostsFile: Codable { var hosts: [String] }

    static func loadHosts() -> [String] {
        if let data = try? Data(contentsOf: hostsFile),
           let parsed = try? JSONDecoder().decode(HostsFile.self, from: data),
           !parsed.hosts.isEmpty {
            return parsed.hosts
        }
        // Seed a default config so the file is discoverable/editable.
        let seed = HostsFile(hosts: ["http://localhost:8766"])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(seed) {
            try? data.write(to: hostsFile)
        }
        return seed.hosts
    }
}

// MARK: - Store

@MainActor
final class SessionStore: ObservableObject {
    @Published var hosts: [HostState] = []
    @Published var refreshing = false
    @Published var lastRefreshed: Date?

    var items: [SessionItem] {
        hosts.flatMap { host in
            host.sessions.map {
                SessionItem(session: $0, hostLabel: host.label, hostIsLocal: host.isLocal)
            }
        }
    }

    var unreachableHosts: [String] {
        hosts.filter { $0.error != nil }.map(\.label)
    }

    var multipleHosts: Bool { hosts.filter { $0.error == nil }.count > 1 }

    private var localHostname: String = {
        var name = ProcessInfo.processInfo.hostName.lowercased()
        for suffix in [".local", ".lan", ".home"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name
    }()

    func refresh() async {
        refreshing = true
        defer { refreshing = false; lastRefreshed = Date() }
        let urls = Config.loadHosts()
        var results: [HostState] = []
        await withTaskGroup(of: HostState.self) { group in
            for url in urls {
                group.addTask { await Self.fetchHost(url: url) }
            }
            for await state in group { results.append(state) }
        }
        // Preserve config order; mark local hosts.
        var ordered: [HostState] = []
        for url in urls {
            guard var state = results.first(where: { $0.url == url }) else { continue }
            state.isLocal = isLocalURL(url) || matchesLocalHostname(state.info?.hostName)
            ordered.append(state)
        }
        // Dedupe two URLs that reached the same machine (Tailscale IP + localhost).
        var seenHostIds = Set<String>()
        var uniqueHosts = ordered.filter { state in
            guard let id = state.info?.hostId else { return true }
            return seenHostIds.insert(id).inserted
        }
        let liveIds = Set(uniqueHosts.flatMap { $0.sessions.compactMap(\.sessionId) })
        var seenClosedIds = Set<String>()
        for i in uniqueHosts.indices {
            let closed = uniqueHosts[i].closedSessions.filter { session in
                guard let id = session.sessionId else { return false }
                if liveIds.contains(id) { return false }
                return seenClosedIds.insert(id).inserted
            }
            uniqueHosts[i].sessions = (uniqueHosts[i].sessions + closed).sorted {
                ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0)
            }
        }
        hosts = uniqueHosts
    }

    private func isLocalURL(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func matchesLocalHostname(_ reported: String?) -> Bool {
        guard let reported else { return false }
        var name = reported.lowercased()
        for suffix in [".local", ".lan", ".home"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name == localHostname
    }

    private static func fetchHost(url: String) async -> HostState {
        var state = HostState(url: url)
        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 4
            return c
        }())
        do {
            guard let infoURL = URL(string: url + "/api/info"),
                  let sessURL = URL(string: url + "/api/sessions"),
                  let resumableURL = URL(string: url + "/api/sessions/resumable?limit=100") else {
                state.error = "bad URL"
                return state
            }
            let (infoData, _) = try await session.data(from: infoURL)
            state.info = try JSONDecoder().decode(HostInfoResponse.self, from: infoData)
            let (sessData, _) = try await session.data(from: sessURL)
            let parsed = try JSONDecoder().decode(SessionsResponse.self, from: sessData)
            state.sessions = parsed.sessions.sorted {
                ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0)
            }
            if let (resumableData, _) = try? await session.data(from: resumableURL),
               let resumable = try? JSONDecoder().decode(ResumableResponse.self, from: resumableData) {
                state.closedSessions = resumable.sessions.map { r in
                    APISession(
                        agent: "claude",
                        pid: -1,
                        cwd: r.cwd,
                        project: r.project ?? Self.projectName(for: r.cwd),
                        title: r.title,
                        sessionId: r.sessionId,
                        busy: false,
                        lastActivityAt: r.lastActivityAt,
                        tmuxName: nil,
                        model: nil,
                        status: nil,
                        lastUserText: r.lastUserText,
                        closed: true
                    )
                }
            }
        } catch {
            state.error = "unreachable"
        }
        return state
    }

    private static func projectName(for cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Session" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

// MARK: - Opening sessions in iTerm2

enum Opener {
    // Absolute paths so the command survives tmux's non-login `sh -c` env.
    static let tmux = resolve("tmux", fallback: "/opt/homebrew/bin/tmux")
    static let claude = resolve("claude", fallback: "/opt/homebrew/bin/claude")

    private static func resolve(_ tool: String, fallback: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(tool)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return fallback }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? fallback : out
    }

    /// Open the session: attach when it's a local tmux session, otherwise
    /// resume the Claude Code session in a fresh local tmux session.
    /// Returns an error message, or nil on success.
    static func open(_ item: SessionItem) -> String? {
        let s = item.session
        if item.hostIsLocal, let name = s.tmuxName {
            return runInNewITermWindow("\(shq(tmux)) attach-session -t \(shq(name))")
        }
        guard s.agent == "claude" || s.agent == "aisdk" else {
            return "Only Claude sessions can be resumed across machines (this is \(s.agent))."
        }
        guard let id = s.sessionId else {
            return "This session has no session id yet — nothing to resume."
        }
        var cwd = s.cwd ?? NSHomeDirectory()
        if !FileManager.default.fileExists(atPath: cwd) {
            return "The session's directory doesn't exist on this machine:\n\(cwd)"
        }
        cwd = (cwd as NSString).standardizingPath
        let tmuxName = "lfgd-\(id.prefix(8))"
        // -A: if we already opened this one, attach instead of erroring.
        let inner = "\(shq(claude)) --resume \(shq(id))"
        let cmd = "\(shq(tmux)) new-session -A -s \(shq(tmuxName)) -c \(shq(cwd)) \(shq(inner))"
        return runInNewITermWindow(cmd)
    }

    /// Single-quote a string for zsh.
    private static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape for embedding inside an AppleScript double-quoted string.
    private static func asq(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Run an AppleScript via `osascript` (thread-safe, unlike NSAppleScript).
    /// Returns (stdout, errorMessage).
    private static func runAppleScript(_ script: String) -> (out: String, err: String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch {
            return ("", "couldn't launch osascript: \(error.localizedDescription)")
        }
        p.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (out, p.terminationStatus == 0 ? nil : (err.isEmpty ? "osascript failed" : err))
    }

    private static func runInNewITermWindow(_ shellCommand: String) -> String? {
        // Launch via the profile `command` parameter, NOT create-then-`write text`:
        // written text races the shell's startup and zsh's line-editor init can
        // swallow it (the window opens to a bare prompt and nothing runs). The
        // command param has no shell in the loop — iTerm tokenizes it itself
        // (single-quoted args OK, but no shell builtins like `exec`).
        let script = """
        tell application "iTerm"
            activate
            set w to (create window with default profile command "\(asq(shellCommand))")
            set b to bounds of w
            return (id of w as string) & "," & (item 1 of b) & "," & (item 2 of b) & "," & (item 3 of b) & "," & (item 4 of b)
        end tell
        """
        let (out, err) = runAppleScript(script)
        if let err { return "iTerm2 scripting failed: \(err)" }
        stretchToFullDesktopHeight(out)
        return nil
    }

    /// Resize the just-created iTerm2 window so it spans the full visible
    /// height of the desktop (screen) it opened on. `result` is
    /// "windowId,x1,y1,x2,y2" (top-left-origin coords).
    private static func stretchToFullDesktopHeight(_ result: String) {
        let parts = result.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 5 else { return }
        let windowId = parts[0]
        let x1 = CGFloat(parts[1])
        let y1 = CGFloat(parts[2])
        let x2 = CGFloat(parts[3])
        let y2 = CGFloat(parts[4])

        // AppleScript bounds use a top-left origin on the main screen with y
        // increasing downward; NSScreen frames use a bottom-left origin with y
        // increasing upward. Convert via the main screen's height.
        guard let mainScreen = NSScreen.screens.first else { return }
        let mainH = mainScreen.frame.height
        let midX = (x1 + x2) / 2
        let midY = (y1 + y2) / 2

        let screen = NSScreen.screens.first { s in
            let f = s.frame
            let top = mainH - (f.origin.y + f.height)
            let bottom = mainH - f.origin.y
            return midX >= f.origin.x && midX < f.origin.x + f.width
                && midY >= top && midY < bottom
        } ?? mainScreen

        // Full visible height (menu bar / Dock excluded) of that screen.
        let vf = screen.visibleFrame
        let top = Int(mainH - (vf.origin.y + vf.height))
        let bottom = Int(mainH - vf.origin.y)
        let script = """
        tell application "iTerm"
            set bounds of window id \(windowId) to {\(Int(x1)), \(top), \(Int(x2)), \(bottom)}
        end tell
        """
        _ = runAppleScript(script)
    }
}

// MARK: - UI

enum GroupMode: String, CaseIterable, Identifiable {
    case status, directory
    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: return "Status"
        case .directory: return "Directory"
        }
    }
}

struct SessionRow: View {
    let item: SessionItem
    let showHost: Bool

    private var session: APISession { item.session }

    private var openable: Bool {
        (item.hostIsLocal && session.tmuxName != nil) || session.sessionId != nil
    }

    private var dotColor: Color {
        switch item.status {
        case .working: return .green
        case .paused: return .orange
        case .idle, .closed: return Color.secondary.opacity(0.35)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.project)
                    if let model = session.model { Text("· \(model)") }
                    Text("· \(session.agent)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if showHost || !item.hostIsLocal {
                badge(item.hostLabel, color: item.hostIsLocal ? .secondary : .purple)
            }
            if item.hostIsLocal, session.tmuxName != nil {
                badge("tmux", color: .blue)
            } else if session.sessionId != nil {
                badge("resume", color: .orange)
            }
            Image(systemName: "arrow.up.forward.square")
                .foregroundStyle(openable ? Color.accentColor : Color.secondary.opacity(0.3))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .opacity(openable ? 1 : 0.5)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct ContentView: View {
    @StateObject private var store = SessionStore()
    @State private var alertMessage: String?
    @State private var searchText = ""
    @State private var groupMode: GroupMode = .status
    /// Collapsible UI state is in-memory per the current run.
    @State private var expandedDirs: Set<String> = []
    @State private var expandedAgentSections: Set<String> = []
    @State private var expandedAgentParents: Set<String> = []
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private struct ListSection: Identifiable {
        let id: String
        let title: String
        let items: [SessionItem]
        var isAgents = false
        var childrenByParentId: [String: [SessionItem]] = [:]
        var running = 0
        var idle = 0
    }

    private struct RenderedSessionRow: Identifiable {
        let id: String
        let item: SessionItem
        let children: [SessionItem]
        let indent: CGFloat
    }

    /// Sessions passing the search query.
    private var matchingItems: [SessionItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.items }
        return store.items.filter { item in
            let s = item.session
            return ([s.title, s.project, s.lastUserText, s.model, s.agent, item.hostLabel]
                .compactMap { $0?.lowercased() } + [item.hostLabel.lowercased()])
                .contains { $0.contains(q) }
        }
    }

    private var sections: [ListSection] {
        let base = matchingItems
        switch groupMode {
        case .status:
            let grouped = statusAgentGrouping(for: base)
            var sections = statusSections(for: grouped.regular, childrenByParentId: grouped.childrenByParentId)
            if !grouped.orphanAgents.isEmpty {
                sections.append(ListSection(
                    id: "status-agents",
                    title: "Agents",
                    items: grouped.orphanAgents,
                    isAgents: true
                ))
            }
            return sections
        case .directory:
            let byDir = Dictionary(grouping: base) { $0.session.cwd ?? $0.session.project }
            // When two different cwds share a leaf name (e.g. dev/…/lfg and an
            // iCloud copy of lfg), label them parent/leaf to tell them apart.
            let leafFor: (String) -> String = { key in
                key.split(separator: "/").last.map(String.init) ?? (key.isEmpty ? "No directory" : key)
            }
            var leafCounts: [String: Int] = [:]
            for key in byDir.keys { leafCounts[leafFor(key), default: 0] += 1 }
            return byDir.map { key, items in
                let sorted = items.sorted { ($0.session.lastActivityAt ?? 0) > ($1.session.lastActivityAt ?? 0) }
                let leaf = leafFor(key)
                let comps = key.split(separator: "/").map(String.init)
                let title = (leafCounts[leaf] ?? 0) > 1 && comps.count >= 2
                    ? comps.suffix(2).joined(separator: "/") : leaf
                return ListSection(
                    id: "dir-\(key)",
                    title: title,
                    items: sorted,
                    running: sorted.filter { $0.status == .working }.count,
                    idle: sorted.filter { $0.status == .idle || $0.status == .closed }.count
                )
            }
            // Most-recently-active directory first, like the iOS client.
            .sorted { ($0.items.first?.session.lastActivityAt ?? 0) > ($1.items.first?.session.lastActivityAt ?? 0) }
        }
    }

    private func statusSections(
        for items: [SessionItem],
        childrenByParentId: [String: [SessionItem]] = [:]
    ) -> [ListSection] {
        SessionItem.Status.allCases.compactMap { g in
            let groupItems = items.filter { $0.status == g }
                .sorted { ($0.session.lastActivityAt ?? 0) > ($1.session.lastActivityAt ?? 0) }
            return groupItems.isEmpty ? nil
                : ListSection(
                    id: "status-\(g.rawValue)",
                    title: g.title,
                    items: groupItems,
                    childrenByParentId: childrenByParentId
                )
        }
    }

    private func statusAgentGrouping(
        for items: [SessionItem]
    ) -> (regular: [SessionItem], childrenByParentId: [String: [SessionItem]], orphanAgents: [SessionItem]) {
        let visibleParentIds = Set(items
            .filter { $0.status != .closed }
            .compactMap { normalizedId($0.session.sessionId) })
        let agentCandidates = items.filter { statusAgentParentId(for: $0) != nil }
        let candidateIds = Set(agentCandidates.map(\.id))
        let childAgents = agentCandidates.filter { item in
            guard let parentId = statusAgentParentId(for: item) else { return false }
            return visibleParentIds.contains(parentId)
        }
        let orphanAgents = agentCandidates.filter { item in
            guard let parentId = statusAgentParentId(for: item) else { return false }
            return !visibleParentIds.contains(parentId)
        }
        let childrenByParentId = Dictionary(grouping: childAgents) { item in
            statusAgentParentId(for: item) ?? ""
        }
        .mapValues { childItems in
            childItems.sorted { ($0.session.lastActivityAt ?? 0) > ($1.session.lastActivityAt ?? 0) }
        }
        let regular = items.filter { !candidateIds.contains($0.id) }
        return (
            regular,
            childrenByParentId,
            orphanAgents.sorted { ($0.session.lastActivityAt ?? 0) > ($1.session.lastActivityAt ?? 0) }
        )
    }

    private func statusAgentParentId(for item: SessionItem) -> String? {
        guard item.status != .paused, item.status != .closed else { return nil }
        return normalizedId(item.session.parentSessionId)
    }

    private func normalizedId(_ value: String?) -> String? {
        guard let id = value?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        return id
    }

    private func isCollapsed(_ section: ListSection) -> Bool {
        if groupMode == .status, section.isAgents {
            return !expandedAgentSections.contains(section.id)
        }
        return groupMode == .directory && !expandedDirs.contains(section.id) && searchText.isEmpty
    }

    private func renderedRows(for section: ListSection) -> [RenderedSessionRow] {
        guard groupMode == .status,
              !section.isAgents,
              !section.childrenByParentId.isEmpty else {
            return section.items.map {
                RenderedSessionRow(id: $0.id, item: $0, children: [], indent: 0)
            }
        }

        var rows: [RenderedSessionRow] = []
        var path: Set<String> = []
        for item in section.items {
            appendRenderedRows(for: item, depth: 0, section: section, path: &path, rows: &rows)
        }
        return rows
    }

    private func appendRenderedRows(
        for item: SessionItem,
        depth: Int,
        section: ListSection,
        path: inout Set<String>,
        rows: inout [RenderedSessionRow]
    ) {
        let parentId = normalizedId(item.session.sessionId)
        let children: [SessionItem]
        if let parentId, !path.contains(parentId) {
            children = section.childrenByParentId[parentId] ?? []
        } else {
            children = []
        }

        rows.append(RenderedSessionRow(
            id: "\(depth)-\(item.id)",
            item: item,
            children: children,
            indent: CGFloat(depth) * 24
        ))

        guard let parentId,
              expandedAgentParents.contains(parentId),
              !children.isEmpty,
              !path.contains(parentId) else { return }
        path.insert(parentId)
        for child in children {
            appendRenderedRows(for: child, depth: depth + 1, section: section, path: &path, rows: &rows)
        }
        path.remove(parentId)
    }

    @ViewBuilder
    private func sessionRow(_ row: RenderedSessionRow) -> some View {
        indented(row.indent) {
            if row.children.isEmpty {
                openButton(for: row.item)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    openButton(for: row.item)
                    if let parentId = normalizedId(row.item.session.sessionId) {
                        agentDisclosure(parentId: parentId, children: row.children)
                    }
                }
            }
        }
    }

    private func openButton(for item: SessionItem) -> some View {
        Button {
            // Off the main thread: the AppleScript round-trip can
            // block for a minute on the first-run automation
            // consent prompt, and must not freeze the UI.
            Task.detached {
                let err = Opener.open(item)
                if let err {
                    await MainActor.run { alertMessage = err }
                }
            }
        } label: {
            SessionRow(item: item, showHost: store.multipleHosts)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func indented<Content: View>(
        _ indent: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if indent > 0 {
            content().padding(.leading, indent)
        } else {
            content()
        }
    }

    private func agentDisclosure(parentId: String, children: [SessionItem]) -> some View {
        let isExpanded = expandedAgentParents.contains(parentId)
        let running = children.filter { $0.status == .working }.count
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expandedAgentParents.contains(parentId) { expandedAgentParents.remove(parentId) }
                else { expandedAgentParents.insert(parentId) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text(agentCountText(children.count))
                if running > 0 {
                    Text("· \(running) running")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func agentCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "agent" : "agents")"
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    if !isCollapsed(section) {
                        ForEach(renderedRows(for: section)) { row in
                            sessionRow(row)
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
            if sections.isEmpty {
                Text(searchText.isEmpty ? "No sessions." : "No sessions match “\(searchText)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if !store.unreachableHosts.isEmpty {
                Text("Unreachable: \(store.unreachableHosts.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        // 660, not 640: in the last ~20pt above the toolbar's fit width the
        // system squeezes the principal item ~14pt off the window centerline.
        .frame(minWidth: 660, minHeight: 420)
        .navigationTitle("lfg")
        // HIG "Toolbars" item groupings: common view controls in the center
        // area, search + actions on the trailing edge.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Group by", selection: $groupMode) {
                    ForEach(GroupMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.refreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.refreshing)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Refresh (auto-refreshes every 10s)")
            }
            // Adjacent items in one placement share a glass capsule by
            // default; hide it so refresh is its own circle beside search.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search sessions", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                // 150pt (not wider): at the 640pt minWidth the centered
                // pill + this cluster must fit without collapsing into ».
                // No custom glass here — the system toolbar item background
                // is the only container around the field.
                .frame(width: 150, height: 30)
            }
        }
        .task { await store.refresh() }
        .onReceive(timer) { _ in
            Task { await store.refresh() }
        }
        .alert("Can't open session", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: ListSection) -> some View {
        if groupMode == .directory || section.isAgents {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if section.isAgents {
                        if expandedAgentSections.contains(section.id) { expandedAgentSections.remove(section.id) }
                        else { expandedAgentSections.insert(section.id) }
                    } else if expandedDirs.contains(section.id) {
                        expandedDirs.remove(section.id)
                    } else {
                        expandedDirs.insert(section.id)
                    }
                }
            } label: {
                let isExpanded = section.isAgents
                    ? expandedAgentSections.contains(section.id)
                    : !isCollapsed(section)
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(section.title)
                    Spacer()
                    if section.isAgents {
                        Text("\(section.items.count)")
                            .foregroundStyle(.secondary)
                    } else {
                        if section.running > 0 { tally(section.running, color: .green) }
                        if section.idle > 0 { tally(section.idle, color: .secondary) }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text(section.title)
                Spacer()
                Text("\(section.items.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tally(_ count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color == .secondary ? Color.secondary.opacity(0.4) : color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

@main
struct LFGSessionsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
