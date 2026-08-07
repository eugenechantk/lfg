// LFG Sessions — a minimal macOS desktop app that lists every Claude Code /
// Codex session across all configured lfg hosts and reopens any of them in
// iTerm2 with one click.
//
//   - Session on THIS machine with a tmux pane  -> iTerm2 window attached to
//     that same tmux session (`tmux attach -t <name>`).
//   - Session on ANOTHER machine with a tmux pane -> iTerm2 window ssh-attached
//     to that same remote tmux session.
//   - Session with no tmux pane -> iTerm2 window with a fresh local tmux
//     session running `claude --resume <id>` in the session's cwd. Works
//     because ~/.claude/projects syncs between hosts, so the transcript is
//     present locally.
//
// Opened iTerm2 windows are resized to span the full height of the desktop
// (screen) they appear on.
//
// Like the iOS client, the list has a search field and a segmented control to
// group by Status (Working / Paused / Idle) or by Directory (collapsible
// sections with running/idle tallies).
//
// Hosts are read from ~/.config/lfg-desktop/hosts.json:
//   { "hosts": ["http://localhost:8766", {"url": "http://100.75.162.40:8766", "ssh": "user@air"}] }
//
// Built by build.sh (swiftc, no Xcode project).

import SwiftUI
import AppKit
import Darwin
import Dispatch

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
struct SessionStatesResponse: Decodable { let needsInputSessionIds: [String] }

// MARK: - Host state

struct HostState: Identifiable {
    let url: String
    let sshTarget: String?
    var displayName: String?
    var info: HostInfoResponse?
    var sessions: [APISession] = []
    var closedSessions: [APISession] = []
    var needsInputSessionIds: Set<String> = []
    var error: String?
    var isLocal: Bool = false

    var id: String { url }

    var label: String {
        Config.HostEntry(url: url, displayName: displayName)
            .displayLabel(reportedHostName: info?.hostName)
    }
}

enum HostConnectionStatus: Equatable {
    case connected, connecting, offline

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .offline: return "Offline"
        }
    }
}

/// Pure connection-presentation rules shared by the title-bar UI and the
/// desktop feature tests. An unresolved host is connecting, never offline.
enum ConnectionPresentation {
    static func status(resolved: Bool, reachable: Bool) -> HostConnectionStatus {
        guard resolved else { return .connecting }
        return reachable ? .connected : .offline
    }

    static func aggregate(configured: Int, resolved: Int, reachable: Int) -> HostConnectionStatus {
        guard configured > 0, resolved >= configured else { return .connecting }
        return reachable > 0 ? .connected : .offline
    }
}

/// One session joined with the host it lives on — the unit the list renders.
struct SessionItem: Identifiable {
    let session: APISession
    let hostURL: String
    let hostId: String
    let hostLabel: String
    let hostIsLocal: Bool
    let hostSSHTarget: String?
    let needsInput: Bool

    init(
        session: APISession,
        hostURL: String,
        hostId: String,
        hostLabel: String,
        hostIsLocal: Bool,
        hostSSHTarget: String?,
        needsInput: Bool = false
    ) {
        self.session = session
        self.hostURL = hostURL
        self.hostId = hostId
        self.hostLabel = hostLabel
        self.hostIsLocal = hostIsLocal
        self.hostSSHTarget = hostSSHTarget
        self.needsInput = needsInput
    }

    var id: String { "\(hostId)-\(session.id)" }

    var canOpen: Bool {
        session.tmuxName != nil || session.sessionId != nil
    }

    var opensByResume: Bool {
        session.tmuxName == nil && session.sessionId != nil
    }

    enum Status: Int, CaseIterable {
        case needsInput, paused, working, idle, closed
        var title: String {
            switch self {
            case .needsInput: return "Needs Input"
            case .paused: return "Paused"
            case .working: return "Working"
            case .idle: return "Idle"
            case .closed: return "Closed"
            }
        }
    }

    var status: Status {
        if session.closed { return .closed }
        if needsInput { return .needsInput }
        if session.status == "blocked" { return .paused }
        if session.busy { return .working }
        return .idle
    }
}

/// Compact, deterministic slices for the menu-bar window. A row appears once:
/// actionable first, then active, then the most recent remainder.
struct MenuBarSessionProjection {
    static let activeLimit = 4
    static let recentLimit = 5

    let needsInput: [SessionItem]
    let running: [SessionItem]
    let recent: [SessionItem]
    let needsInputCount: Int
    let runningCount: Int
    let recentCount: Int

    init(items: [SessionItem]) {
        let actionable = items.filter { $0.status == .needsInput }
            .sorted(by: Self.oldestFirst)
        let active = items.filter { $0.status == .working }
            .sorted(by: Self.newestFirst)
        let remainder = items.filter { $0.status != .needsInput && $0.status != .working }
            .sorted(by: Self.newestFirst)

        needsInputCount = actionable.count
        runningCount = active.count
        recentCount = remainder.count
        needsInput = Array(actionable.prefix(Self.activeLimit))
        running = Array(active.prefix(Self.activeLimit))
        recent = Array(remainder.prefix(Self.recentLimit))
    }

    private static func oldestFirst(_ lhs: SessionItem, _ rhs: SessionItem) -> Bool {
        let left = lhs.session.lastActivityAt ?? 0
        let right = rhs.session.lastActivityAt ?? 0
        return left == right ? lhs.id < rhs.id : left < right
    }

    private static func newestFirst(_ lhs: SessionItem, _ rhs: SessionItem) -> Bool {
        let left = lhs.session.lastActivityAt ?? 0
        let right = rhs.session.lastActivityAt ?? 0
        return left == right ? lhs.id < rhs.id : left > right
    }
}

enum SessionSearch {
    static func matches(_ item: SessionItem, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let session = item.session
        return [session.title, session.project, session.lastUserText, session.model,
                session.agent, item.hostLabel]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(q) }
    }
}

// MARK: - Config

enum Config {
    static var dir: URL {
        directory(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
    static var hostsFile: URL { dir.appendingPathComponent("hosts.json") }

    struct HostEntry: Codable, Equatable, Identifiable {
        var url: String
        var ssh: String?
        var displayName: String?

        var id: String { url }

        enum CodingKeys: String, CodingKey { case url, ssh, displayName }

        init(url: String, ssh: String? = nil, displayName: String? = nil) {
            self.url = url
            self.ssh = ssh
            self.displayName = displayName
        }

        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let url = try? single.decode(String.self) {
                self.url = url
                self.ssh = nil
                self.displayName = nil
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = try c.decode(String.self, forKey: .url)
            ssh = try c.decodeIfPresent(String.self, forKey: .ssh)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        }

        func encode(to encoder: Encoder) throws {
            let name = Config.normalizedDisplayName(displayName)
            if ssh == nil && name == nil {
                var single = encoder.singleValueContainer()
                try single.encode(url)
                return
            }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(url, forKey: .url)
            try c.encodeIfPresent(ssh, forKey: .ssh)
            try c.encodeIfPresent(name, forKey: .displayName)
        }

        func displayLabel(reportedHostName: String?) -> String {
            if let displayName = Config.normalizedDisplayName(displayName) {
                return displayName
            }
            if let reportedHostName, !reportedHostName.isEmpty {
                return String(reportedHostName.split(separator: ".").first ?? Substring(reportedHostName))
            }
            if let components = URLComponents(string: url), let host = components.host {
                return components.port.map { "\(host):\($0)" } ?? host
            }
            if let range = url.range(of: "://") { return String(url[range.upperBound...]) }
            return url
        }
    }

    struct HostsFile: Codable { var hosts: [HostEntry] }

    /// Production uses the standard home-directory location. The explicit
    /// override gives UI automation a disposable config root so it never has
    /// to edit the user's real host list.
    static func directory(environment: [String: String], homeDirectory: URL) -> URL {
        if let override = environment["LFG_DESKTOP_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".config/lfg-desktop", isDirectory: true)
    }

    static func loadHosts() -> [HostEntry] {
        if let hosts = loadHosts(from: dir),
           !hosts.isEmpty {
            return hosts
        }
        // Seed a default config so the file is discoverable/editable.
        let seed = HostsFile(hosts: [HostEntry(url: "http://localhost:8766")])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(seed) {
            try? data.write(to: hostsFile)
        }
        return seed.hosts
    }

    static func sshTarget(for entry: HostEntry) -> String? {
        if let ssh = entry.ssh?.trimmingCharacters(in: .whitespacesAndNewlines), !ssh.isEmpty {
            return ssh
        }
        guard let host = URL(string: entry.url)?.host, !host.isEmpty else { return nil }
        return "\(NSUserName())@\(host)"
    }

    static func saveHosts(_ hosts: [HostEntry]) throws {
        try saveHosts(hosts, to: dir)
    }

    static func loadHosts(from directory: URL) -> [HostEntry]? {
        let file = directory.appendingPathComponent("hosts.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return decodeHosts(data)
    }

    static func saveHosts(_ hosts: [HostEntry], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encodeHosts(hosts)
        try data.write(to: directory.appendingPathComponent("hosts.json"), options: .atomic)
    }

    static func decodeHosts(_ data: Data) -> [HostEntry]? {
        try? JSONDecoder().decode(HostsFile.self, from: data).hosts
    }

    static func encodeHosts(_ hosts: [HostEntry]) throws -> Data {
        let normalized = hosts.map {
            HostEntry(url: $0.url, ssh: $0.ssh, displayName: normalizedDisplayName($0.displayName))
        }
        return try JSONEncoder().encode(HostsFile(hosts: normalized))
    }

    static func normalizedDisplayName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Store

@MainActor
final class SessionStore: ObservableObject {
    @Published var configuredHosts: [Config.HostEntry] = Config.loadHosts()
    @Published var hosts: [HostState] = []
    @Published var duplicateHostsByURL: [String: HostState] = [:]
    @Published var refreshing = false
    @Published var lastRefreshed: Date?
    @Published var movingIds: Set<String> = []
    @Published var closingIds: Set<String> = []

    var items: [SessionItem] {
        let all = hosts.flatMap { host in
            host.sessions.map {
                SessionItem(
                    session: $0,
                    hostURL: host.url,
                    hostId: host.info?.hostId ?? host.url,
                    hostLabel: host.label,
                    hostIsLocal: host.isLocal,
                    hostSSHTarget: host.sshTarget,
                    needsInput: $0.sessionId.map(host.needsInputSessionIds.contains) ?? false
                )
            }
        }
        // A host can list one sessionId twice (e.g. a session resumed into a
        // new tmux pane while the old pane is still tracked). Duplicate row
        // IDs crash the AppKit-backed List on expand — keep the freshest.
        var byId: [String: SessionItem] = [:]
        var order: [String] = []
        for item in all {
            if let existing = byId[item.id] {
                if (item.session.lastActivityAt ?? 0) > (existing.session.lastActivityAt ?? 0) {
                    byId[item.id] = item
                }
            } else {
                byId[item.id] = item
                order.append(item.id)
            }
        }
        return order.compactMap { byId[$0] }
    }

    var unreachableHosts: [String] {
        hosts.filter { $0.error != nil }.map(\.label)
    }

    var multipleHosts: Bool { hosts.filter { $0.error == nil }.count > 1 }

    var runningCount: Int { items.filter { $0.status == .working }.count }

    var connectionStatus: HostConnectionStatus {
        let states = configuredHosts.map(resolvedState(for:))
        return ConnectionPresentation.aggregate(
            configured: configuredHosts.count,
            resolved: states.compactMap { $0 }.count,
            reachable: states.compactMap { $0 }.filter { $0.error == nil }.count
        )
    }

    func connectionStatus(for entry: Config.HostEntry) -> HostConnectionStatus {
        let state = resolvedState(for: entry)
        return ConnectionPresentation.status(resolved: state != nil, reachable: state?.error == nil)
    }

    func displayLabel(for entry: Config.HostEntry) -> String {
        entry.displayLabel(reportedHostName: resolvedState(for: entry)?.info?.hostName)
    }

    func reloadConfiguration() {
        applyConfiguration(Config.loadHosts())
    }

    private var localHostname: String = {
        var name = ProcessInfo.processInfo.hostName.lowercased()
        for suffix in [".local", ".lan", ".home"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name
    }()

    struct MoveTarget: Identifiable, Hashable {
        let hostId: String
        let label: String
        let url: String

        var id: String { hostId }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false; lastRefreshed = Date() }
        let entries = Config.loadHosts()
        applyConfiguration(entries)
        var results: [HostState] = []
        await withTaskGroup(of: HostState.self) { group in
            for entry in entries {
                group.addTask { await Self.fetchHost(entry: entry) }
            }
            for await state in group { results.append(state) }
        }
        // Preserve config order; mark local hosts.
        var ordered: [HostState] = []
        for entry in entries {
            guard var state = results.first(where: { $0.url == entry.url }) else { continue }
            let url = entry.url
            state.isLocal = isLocalURL(url) || matchesLocalHostname(state.info?.hostName)
            ordered.append(state)
        }
        // Dedupe two URLs that reached the same machine (Tailscale IP + localhost).
        var hostsById: [String: HostState] = [:]
        var duplicates: [String: HostState] = [:]
        var uniqueHosts: [HostState] = []
        for state in ordered {
            guard let id = state.info?.hostId else {
                uniqueHosts.append(state)
                continue
            }
            if let existing = hostsById[id] {
                duplicates[state.url] = existing
            } else {
                hostsById[id] = state
                uniqueHosts.append(state)
            }
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
        duplicateHostsByURL = duplicates
        hosts = uniqueHosts
    }

    func moveTargets(for item: SessionItem) -> [MoveTarget] {
        guard let _ = item.session.sessionId,
              item.session.agent == "claude" || item.session.agent == "aisdk" else {
            return []
        }
        return hosts.compactMap { host in
            guard host.error == nil else { return nil }
            let hostId = host.info?.hostId ?? host.url
            guard hostId != item.hostId else { return nil }
            return MoveTarget(hostId: hostId, label: host.label, url: host.url)
        }
    }

    func move(item: SessionItem, to target: MoveTarget) async -> String? {
        guard let sessionId = item.session.sessionId else {
            return "Move failed: this session has no session id."
        }
        movingIds.insert(sessionId)
        defer { movingIds.remove(sessionId) }

        if let err = await MoveCoordinator.move(item: item, to: target) {
            return err
        }
        await refresh()
        return nil
    }

    /// Ends the session's live process on its host. The transcript survives, so a
    /// closed session stays resumable — this is "stop running", not "delete".
    func close(item: SessionItem) async -> String? {
        guard let sessionId = item.session.sessionId else {
            return "Close failed: this session has no session id."
        }
        closingIds.insert(sessionId)
        defer { closingIds.remove(sessionId) }

        if let err = await MoveCoordinator.close(item: item) {
            return err
        }
        await refresh()
        return nil
    }

    /// Sets the user title override on the session's own host. An empty title
    /// clears the override, and the server falls back to the first-prompt title.
    func rename(item: SessionItem, to title: String) async -> String? {
        guard item.session.sessionId != nil else {
            return "Rename failed: this session has no session id."
        }
        if let err = await MoveCoordinator.rename(item: item, to: title) {
            return err
        }
        await refresh()
        return nil
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

    private func resolvedState(for entry: Config.HostEntry) -> HostState? {
        hosts.first { $0.url == entry.url } ?? duplicateHostsByURL[entry.url]
    }

    func applyConfiguration(_ entries: [Config.HostEntry]) {
        configuredHosts = entries
        var namesByURL: [String: String] = [:]
        for entry in entries {
            namesByURL[entry.url] = Config.normalizedDisplayName(entry.displayName)
        }
        for index in hosts.indices {
            hosts[index].displayName = namesByURL[hosts[index].url]
        }
    }

    private static func fetchHost(entry: Config.HostEntry) async -> HostState {
        let url = entry.url
        var state = HostState(
            url: url,
            sshTarget: Config.sshTarget(for: entry),
            displayName: Config.normalizedDisplayName(entry.displayName)
        )
        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 4
            return c
        }())
        do {
            guard let infoURL = URL(string: url + "/api/info"),
                  let sessURL = URL(string: url + "/api/sessions"),
                  let resumableURL = URL(string: url + "/api/sessions/resumable?limit=100"),
                  let statesURL = URL(string: url + "/api/session-states") else {
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
            // Older lfg hosts do not expose this lightweight endpoint yet.
            // Keep the host usable; only its Needs Input section is absent.
            if let (statesData, statesResponse) = try? await session.data(from: statesURL),
               (statesResponse as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
               let states = try? JSONDecoder().decode(SessionStatesResponse.self, from: statesData) {
                state.needsInputSessionIds = Set(states.needsInputSessionIds)
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

// MARK: - Moving sessions between hosts

enum MoveCoordinator {
    private struct ResumeResponse: Decodable {
        let ok: Bool?
        let tmuxName: String?
        let sessionId: String?
        let error: String?
        let message: String?
        let alreadyLive: Bool?
    }

    static func move(item: SessionItem, to target: SessionStore.MoveTarget) async -> String? {
        guard let sessionId = item.session.sessionId else {
            return "Move failed: this session has no session id."
        }

        do {
            try await postClose(sourceURL: item.hostURL, sessionId: sessionId)
        } catch {
            return "Move failed at close: \(detail(for: error))"
        }

        let finalActivity = (try? await fetchResumable(baseURL: item.hostURL)
            .first { $0.sessionId == sessionId }?
            .lastActivityAt) ?? item.session.lastActivityAt

        do {
            let synced = try await waitForSync(
                targetURL: target.url,
                sessionId: sessionId,
                finalActivity: finalActivity
            )
            if !synced {
                return "Closed on \(item.hostLabel), but the transcript hasn't synced to \(target.label) yet. The session is safe — resume it there once sync catches up."
            }
        } catch {
            return "Move failed while waiting for sync: \(detail(for: error))"
        }

        do {
            try await postResume(targetURL: target.url, sessionId: sessionId)
        } catch {
            return "Move failed at resume: \(detail(for: error))"
        }
        return nil
    }

    /// Close without the move dance — no sync wait, no resume on a target host.
    static func close(item: SessionItem) async -> String? {
        guard let sessionId = item.session.sessionId else {
            return "Close failed: this session has no session id."
        }
        do {
            try await postClose(sourceURL: item.hostURL, sessionId: sessionId)
        } catch {
            return "Close failed: \(detail(for: error))"
        }
        return nil
    }

    /// The title override is stored per host (`~/.lfg/session-titles.json`), so it
    /// PUTs to the host the session actually lives on — not whichever host the
    /// list was last refreshed from.
    static func rename(item: SessionItem, to title: String) async -> String? {
        guard let sessionId = item.session.sessionId else {
            return "Rename failed: this session has no session id."
        }
        do {
            var req = try request(
                baseURL: item.hostURL,
                path: "/api/sessions/\(sessionId)/title",
                method: "PUT"
            )
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
            let (data, response) = try await sharedSession.data(for: req)
            try validateHTTP(response, data: data)
        } catch {
            return "Rename failed: \(detail(for: error))"
        }
        return nil
    }

    private static func postClose(sourceURL: String, sessionId: String) async throws {
        let (data, response) = try await sharedSession.data(for: try request(
            baseURL: sourceURL,
            path: "/api/sessions/\(sessionId)/close",
            method: "POST"
        ))
        try validateHTTP(response, data: data)
    }

    private static func waitForSync(
        targetURL: String,
        sessionId: String,
        finalActivity: Double?
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(90)
        while true {
            if let sessions = try? await fetchResumable(baseURL: targetURL),
               let found = sessions.first(where: { $0.sessionId == sessionId }) {
                if let finalActivity {
                    if let targetActivity = found.lastActivityAt,
                       targetActivity >= finalActivity - 1.0 {
                        return true
                    }
                } else {
                    return true
                }
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return false }
            let sleepSeconds = min(3.0, remaining)
            try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
        }
    }

    private static func postResume(targetURL: String, sessionId: String) async throws {
        var req = try request(baseURL: targetURL, path: "/api/sessions/resume", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["sessionId": sessionId])
        let (data, response) = try await sharedSession.data(for: req)
        try validateHTTP(response, data: data)
        let decoded = try? JSONDecoder().decode(ResumeResponse.self, from: data)
        if decoded?.ok == false {
            throw MoveError.server(decoded?.error ?? decoded?.message ?? "resume endpoint returned ok=false")
        }
        if let error = decoded?.error, !error.isEmpty {
            throw MoveError.server(error)
        }
        if decoded == nil,
           let text = try? JSONDecoder().decode(String.self, from: data),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MoveError.server(text)
        }
        _ = decoded?.tmuxName
        _ = decoded?.sessionId
        _ = decoded?.alreadyLive
    }

    private static func fetchResumable(baseURL: String) async throws -> [ResumableAPISession] {
        let (data, response) = try await sharedSession.data(for: try request(
            baseURL: baseURL,
            path: "/api/sessions/resumable?limit=100",
            method: "GET"
        ))
        try validateHTTP(response, data: data)
        return try JSONDecoder().decode(ResumableResponse.self, from: data).sessions
    }

    private static let sharedSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    private static func request(baseURL: String, path: String, method: String) throws -> URLRequest {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + path) else {
            throw MoveError.server("bad URL: \(baseURL)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        return req
    }

    private static func validateHTTP(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MoveError.server(body.isEmpty ? "HTTP \(http.statusCode)" : "HTTP \(http.statusCode): \(body)")
        }
    }

    private static func detail(for error: Error) -> String {
        if let moveError = error as? MoveError {
            return moveError.message
        }
        return error.localizedDescription
    }

    private enum MoveError: Error {
        case server(String)

        var message: String {
            switch self {
            case .server(let message): return message
            }
        }
    }
}

// MARK: - Headless move-flow test hook

enum MoveTestCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.count > 1 else { return }
        if args[1] == "--rename-test" { runRenameTest(args) }
        guard args[1] == "--move-test" else { return }
        guard args.count == 5 else {
            writeResult(ok: false, error: "usage: lfg --move-test <sessionId> <sourceURL> <targetURL>")
            Darwin.exit(1)
        }

        let sessionId = args[2]
        let sourceURL = args[3]
        let targetURL = args[4]

        Task.detached {
            let ok = await run(sessionId: sessionId, sourceURL: sourceURL, targetURL: targetURL)
            Darwin.exit(ok ? 0 : 1)
        }
        dispatchMain()
    }

    /// Exercises the same `MoveCoordinator.rename` the context menu calls, against a
    /// live host — the GUI gesture can't be driven while the login session is locked,
    /// and this keeps the network seam verifiable either way.
    private static func runRenameTest(_ args: [String]) -> Never {
        guard args.count == 5 else {
            writeResult(ok: false, error: "usage: lfg --rename-test <sessionId> <hostURL> <title>")
            Darwin.exit(1)
        }
        let sessionId = args[2]
        let hostURL = args[3]
        let title = args[4]

        Task.detached {
            let session = await fetchSourceSession(sessionId: sessionId, sourceURL: hostURL)
            let item = SessionItem(
                session: session ?? fallbackSession(sessionId: sessionId),
                hostURL: hostURL,
                hostId: "source",
                hostLabel: hostLabel(for: hostURL),
                hostIsLocal: false,
                hostSSHTarget: nil
            )
            if let error = await MoveCoordinator.rename(item: item, to: title) {
                writeResult(ok: false, error: error)
                Darwin.exit(1)
            }
            writeResult(ok: true, error: nil)
            Darwin.exit(0)
        }
        dispatchMain()
    }

    private static func run(sessionId: String, sourceURL: String, targetURL: String) async -> Bool {
        let sourceSession = await fetchSourceSession(sessionId: sessionId, sourceURL: sourceURL)
        let item = SessionItem(
            session: sourceSession ?? fallbackSession(sessionId: sessionId),
            hostURL: sourceURL,
            hostId: "source",
            hostLabel: hostLabel(for: sourceURL),
            hostIsLocal: false,
            hostSSHTarget: nil
        )
        let target = SessionStore.MoveTarget(
            hostId: await fetchHostId(targetURL) ?? "target",
            label: hostLabel(for: targetURL),
            url: targetURL
        )

        if let error = await MoveCoordinator.move(item: item, to: target) {
            writeResult(ok: false, error: error)
            return false
        }
        writeResult(ok: true, error: nil)
        return true
    }

    private static func fetchSourceSession(sessionId: String, sourceURL: String) async -> APISession? {
        guard let url = URL(string: sourceURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/sessions") else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            let parsed = try JSONDecoder().decode(SessionsResponse.self, from: data)
            return parsed.sessions.first { $0.sessionId == sessionId }
        } catch {
            return nil
        }
    }

    private static func fetchHostId(_ baseURL: String) async -> String? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/info"),
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let info = try? JSONDecoder().decode(HostInfoResponse.self, from: data) else {
            return nil
        }
        return info.hostId
    }

    private static func fallbackSession(sessionId: String) -> APISession {
        APISession(
            agent: "claude",
            pid: -1,
            cwd: nil,
            project: "Session",
            title: sessionId,
            sessionId: sessionId,
            busy: false,
            lastActivityAt: nil,
            tmuxName: nil,
            model: nil,
            status: nil,
            lastUserText: nil
        )
    }

    private static func hostLabel(for url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private static func writeResult(ok: Bool, error: String?) {
        if ok {
            print("{\"ok\":true}")
        } else {
            print("{\"ok\":false,\"error\":\"\(jsonEscaped(error ?? ""))\"}")
        }
        fflush(stdout)
    }

    private static func jsonEscaped(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result += String(scalar)
                }
            }
        }
        return result
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()
}

// MARK: - Headless desktop-feature tests

/// Deterministic coverage for host-config compatibility and connection-status
/// presentation. Kept in the production source because this app intentionally
/// has no Xcode project or separate test target.
enum DesktopFeatureTestCLI {
    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.dropFirst().first == "--desktop-feature-test" else { return }
        do {
            try run()
            print("{\"ok\":true,\"tests\":33}")
            fflush(stdout)
            Darwin.exit(0)
        } catch {
            print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
            fflush(stdout)
            Darwin.exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        let legacyData = Data(#"{"hosts":["http://localhost:8766",{"url":"http://studio:8766","ssh":"me@studio"}]}"#.utf8)
        let legacy = try require(Config.decodeHosts(legacyData), "legacy config decodes")
        try expect(legacy.count == 2, "legacy string and object entries load")
        try expect(legacy[0].displayName == nil, "legacy string has no display name")
        try expect(legacy[1].ssh == "me@studio", "legacy object keeps SSH target")
        let isolatedDirectory = Config.directory(
            environment: ["LFG_DESKTOP_CONFIG_DIR": "/tmp/lfg-desktop-ui-audit"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        try expect(isolatedDirectory.path == "/tmp/lfg-desktop-ui-audit",
                   "UI audit can isolate config from the user's home directory")

        let named = Config.HostEntry(
            url: "http://studio:8766",
            ssh: "me@studio",
            displayName: "  Creative Studio  "
        )
        let encoded = try Config.encodeHosts([named])
        let roundTripped = try require(Config.decodeHosts(encoded)?.first, "named config round-trips")
        try expect(roundTripped.displayName == "Creative Studio", "display name is normalized on persistence")
        try expect(roundTripped.ssh == "me@studio", "named config keeps SSH target")
        try expect(roundTripped.displayLabel(reportedHostName: "Mac-Studio.local") == "Creative Studio",
                   "display name wins over reported hostname")

        let blankName = Config.HostEntry(url: "http://studio:8766", displayName: "  ")
        try expect(blankName.displayLabel(reportedHostName: "Mac-Studio.local") == "Mac-Studio",
                   "blank display name falls back to short hostname")
        try expect(blankName.displayLabel(reportedHostName: nil) == "studio:8766",
                   "missing hostname falls back to compact URL")
        let namedState = HostState(
            url: "http://studio:8766",
            sshTarget: nil,
            displayName: "Creative Studio",
            info: HostInfoResponse(hostId: "studio-id", hostName: "Mac-Studio.local")
        )
        try expect(namedState.label == "Creative Studio", "live host state uses configured display name")
        let fallbackState = HostState(
            url: "http://studio:8766",
            sshTarget: nil,
            displayName: nil,
            info: HostInfoResponse(hostId: "studio-id", hostName: "Mac-Studio.local")
        )
        try expect(fallbackState.label == "Mac-Studio", "live host state falls back to reported hostname")

        let persistenceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lfg-desktop-feature-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: persistenceDirectory) }
        try Config.saveHosts([named], to: persistenceDirectory)
        let persistedNamed = try require(
            Config.loadHosts(from: persistenceDirectory)?.first,
            "saved custom display name reloads from disk"
        )
        try expect(persistedNamed.displayName == "Creative Studio",
                   "custom display name persists on disk")
        try expect(persistedNamed.displayLabel(reportedHostName: "Mac-Studio.local") == "Creative Studio",
                   "reloaded custom display name remains authoritative")
        try Config.saveHosts([blankName], to: persistenceDirectory)
        let persistedBlank = try require(
            Config.loadHosts(from: persistenceDirectory)?.first,
            "saved blank display name reloads from disk"
        )
        try expect(persistedBlank.displayName == nil, "blank display name persists as nil/omitted")
        try expect(persistedBlank.displayLabel(reportedHostName: "Mac-Studio.local") == "Mac-Studio",
                   "reloaded blank display name restores hostname fallback")

        let sourceSession = APISession(
            agent: "claude",
            pid: 42,
            cwd: "/tmp/project",
            project: "project",
            title: "Session",
            sessionId: "session-1",
            busy: true,
            lastActivityAt: 1,
            tmuxName: "lfg-session",
            model: "opus",
            status: nil,
            lastUserText: "Ship it"
        )
        let store = SessionStore()
        store.hosts = [
            HostState(
                url: "http://source:8766",
                sshTarget: nil,
                displayName: nil,
                info: HostInfoResponse(hostId: "source-id", hostName: "Alpha.local"),
                sessions: [sourceSession]
            ),
            HostState(
                url: "http://target:8766",
                sshTarget: nil,
                displayName: nil,
                info: HostInfoResponse(hostId: "target-id", hostName: "Beta.local")
            )
        ]
        let renamedConfiguration = [
            Config.HostEntry(url: "http://source:8766", displayName: "Creative Studio"),
            Config.HostEntry(url: "http://target:8766", displayName: "Render Farm")
        ]
        try Config.saveHosts(renamedConfiguration, to: persistenceDirectory)
        let reloadedRenamedConfiguration = try require(
            Config.loadHosts(from: persistenceDirectory),
            "renamed store configuration reloads from disk"
        )
        store.applyConfiguration(reloadedRenamedConfiguration)
        let renamedItem = try require(store.items.first, "renamed session item exists")
        try expect(renamedItem.hostLabel == "Creative Studio",
                   "items immediately use saved display name before refresh")
        try expect(SessionSearch.matches(renamedItem, query: "creative studio"),
                   "session search matches saved display name")
        try expect(store.moveTargets(for: renamedItem).first?.label == "Render Farm",
                   "move target immediately uses saved display name")
        store.hosts[1].error = "unreachable"
        try expect(store.unreachableHosts == ["Render Farm"],
                   "unreachable-host copy uses saved display name")
        let blankStoreConfiguration = [
            Config.HostEntry(url: "http://source:8766", displayName: "  "),
            renamedConfiguration[1]
        ]
        try Config.saveHosts(blankStoreConfiguration, to: persistenceDirectory)
        let reloadedBlankStoreConfiguration = try require(
            Config.loadHosts(from: persistenceDirectory),
            "blank store configuration reloads from disk"
        )
        store.applyConfiguration(reloadedBlankStoreConfiguration)
        try expect(store.hosts[0].label == "Alpha",
                   "blank saved name immediately restores live hostname fallback")

        try expect(ConnectionPresentation.aggregate(configured: 1, resolved: 0, reachable: 0) == .connecting,
                   "unresolved host is connecting")
        try expect(ConnectionPresentation.aggregate(configured: 1, resolved: 1, reachable: 1) == .connected,
                   "reachable host is connected")
        try expect(ConnectionPresentation.aggregate(configured: 1, resolved: 1, reachable: 0) == .offline,
                   "resolved unreachable host is offline")
        try expect(ConnectionPresentation.status(resolved: false, reachable: false) == .connecting,
                   "unresolved per-host chip is connecting")

        _ = NSApplication.shared
        let shortStatusWidth = statusBarWidth(displayNames: ["Studio", "Travel Mac"])
        let longStatusWidth = statusBarWidth(displayNames: [
            "Extremely Long Creative Production Mac Studio Host",
            "Travel Mac"
        ])
        try expect(longStatusWidth - shortStatusWidth > 180,
                   "long status display names retain their intrinsic width")

        let needsInput = menuTestItem(
            id: "needs-input",
            lastActivity: 100,
            busy: true,
            status: "blocked",
            needsInput: true
        )
        try expect(needsInput.status == .needsInput,
                   "needs input outranks paused and working")
        let paused = menuTestItem(
            id: "paused",
            lastActivity: 150,
            busy: true,
            status: "blocked"
        )
        try expect(paused.status == .paused,
                   "upstream failure remains paused when no prompt is present")

        let projected = MenuBarSessionProjection(items: [
            menuTestItem(id: "needs-newer", lastActivity: 200, needsInput: true),
            needsInput,
            menuTestItem(id: "working-old", lastActivity: 250, busy: true),
            menuTestItem(id: "working-new", lastActivity: 300, busy: true),
            menuTestItem(id: "recent-old", lastActivity: 10),
            paused,
            menuTestItem(id: "recent-new", lastActivity: 20),
        ])
        try expect(projected.needsInput.map(\.session.id) == ["needs-input", "needs-newer"],
                   "needs-input rows are oldest-waiting first")
        try expect(projected.running.map(\.session.id) == ["working-new", "working-old"],
                   "running rows are newest-active first")
        try expect(projected.recent.map(\.session.id) == ["paused", "recent-new", "recent-old"],
                   "recent rows exclude actionable/running duplicates and sort by recency")
        try expect(projected.needsInputCount == 2 && projected.runningCount == 2 && projected.recentCount == 3,
                   "section totals describe the uncapped projection")

        let capped = MenuBarSessionProjection(items:
            (0..<7).map {
                menuTestItem(id: "needs-\($0)", lastActivity: Double($0), needsInput: true)
            } +
            (0..<7).map {
                menuTestItem(id: "recent-\($0)", lastActivity: Double($0))
            }
        )
        try expect(capped.needsInput.count == MenuBarSessionProjection.activeLimit && capped.needsInputCount == 7,
                   "needs-input rows are capped while retaining the full count")
        try expect(capped.recent.count == MenuBarSessionProjection.recentLimit && capped.recentCount == 7,
                   "recent rows are capped while retaining the full count")
    }

    @MainActor
    private static func statusBarWidth(displayNames: [String]) -> CGFloat {
        let store = SessionStore()
        store.configuredHosts = displayNames.enumerated().map { index, name in
            Config.HostEntry(url: "http://host-\(index):8766", displayName: name)
        }
        let content = DesktopConnectionStatusBar()
            .environmentObject(store)
            .fixedSize(horizontal: true, vertical: false)
        return ImageRenderer(content: content).nsImage?.size.width ?? 0
    }

    private static func menuTestItem(
        id: String,
        lastActivity: Double,
        busy: Bool = false,
        status: String? = nil,
        needsInput: Bool = false
    ) -> SessionItem {
        SessionItem(
            session: APISession(
                agent: "claude",
                pid: id.hashValue,
                cwd: "/tmp/project",
                project: "project",
                title: id,
                sessionId: id,
                busy: busy,
                lastActivityAt: lastActivity,
                tmuxName: "lfg-\(id)",
                model: "opus",
                status: status,
                lastUserText: nil
            ),
            hostURL: "http://localhost:8766",
            hostId: "host",
            hostLabel: "This Mac",
            hostIsLocal: true,
            hostSSHTarget: nil,
            needsInput: needsInput
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(message) }
        return value
    }

    private struct TestFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

/// Off-screen status-bar fixtures for visual auditing when a macOS login
/// session is locked and ScreenCaptureKit cannot inspect live windows.
enum DesktopStatusSnapshotCLI {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.dropFirst().first == "--status-snapshots" else { return }
        guard args.count == 3 else {
            print("{\"ok\":false,\"error\":\"usage: lfg --status-snapshots <output-directory>\"}")
            Darwin.exit(1)
        }
        do {
            let directory = URL(fileURLWithPath: args[2], isDirectory: true)
            try renderFixtures(to: directory)
            print("{\"ok\":true,\"snapshots\":4,\"directory\":\"\(directory.path)\"}")
            fflush(stdout)
            Darwin.exit(0)
        } catch {
            print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
            fflush(stdout)
            Darwin.exit(1)
        }
    }

    @MainActor
    private static func renderFixtures(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared

        let oneHost = Config.HostEntry(url: "http://studio:8766", displayName: "Creative Studio")
        let working = APISession(
            agent: "claude",
            pid: 1,
            cwd: "/tmp/project",
            project: "project",
            title: "Working",
            sessionId: "working-1",
            busy: true,
            lastActivityAt: 1,
            tmuxName: "lfg-working",
            model: "opus",
            status: nil,
            lastUserText: nil
        )
        try render(
            store: makeStore(
                configured: [oneHost],
                states: [HostState(
                    url: oneHost.url,
                    sshTarget: nil,
                    displayName: oneHost.displayName,
                    info: HostInfoResponse(hostId: "studio-id", hostName: "Studio.local"),
                    sessions: [working]
                )]
            ),
            width: 320,
            to: directory.appendingPathComponent("single-connected-running.png")
        )
        try render(
            store: makeStore(configured: [oneHost], states: []),
            width: 240,
            to: directory.appendingPathComponent("single-connecting.png")
        )
        var offline = HostState(
            url: oneHost.url,
            sshTarget: nil,
            displayName: oneHost.displayName,
            info: HostInfoResponse(hostId: "studio-id", hostName: "Studio.local")
        )
        offline.error = "unreachable"
        try render(
            store: makeStore(configured: [oneHost], states: [offline]),
            width: 240,
            to: directory.appendingPathComponent("single-offline.png")
        )

        let connected = Config.HostEntry(url: "http://connected:8766", displayName: "Studio")
        let unreachable = Config.HostEntry(url: "http://offline:8766", displayName: "Travel Mac")
        let longName = Config.HostEntry(
            url: "http://long:8766",
            displayName: "Extremely Long Creative Production Mac Studio Host"
        )
        var unreachableState = HostState(
            url: unreachable.url,
            sshTarget: nil,
            displayName: unreachable.displayName,
            info: HostInfoResponse(hostId: "offline-id", hostName: "Offline.local")
        )
        unreachableState.error = "unreachable"
        try render(
            store: makeStore(
                configured: [connected, unreachable, longName],
                states: [
                    HostState(
                        url: connected.url,
                        sshTarget: nil,
                        displayName: connected.displayName,
                        info: HostInfoResponse(hostId: "connected-id", hostName: "Connected.local")
                    ),
                    unreachableState,
                    HostState(
                        url: longName.url,
                        sshTarget: nil,
                        displayName: longName.displayName,
                        info: HostInfoResponse(hostId: "long-id", hostName: "Long.local")
                    )
                ]
            ),
            width: 720,
            to: directory.appendingPathComponent("multi-connected-offline-full-name.png")
        )
    }

    @MainActor
    private static func makeStore(
        configured: [Config.HostEntry],
        states: [HostState]
    ) -> SessionStore {
        let store = SessionStore()
        store.configuredHosts = configured
        store.hosts = states
        return store
    }

    @MainActor
    private static func render(store: SessionStore, width: CGFloat, to url: URL) throws {
        let content = DesktopConnectionStatusBar()
            .environmentObject(store)
            .padding(.horizontal, 16)
            .frame(width: width, height: 52, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotFailure("Could not render \(url.lastPathComponent)")
        }
        try png.write(to: url, options: .atomic)
    }

    private struct SnapshotFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
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

    /// Open the session: attach when it's a local tmux session, ssh-attach
    /// when it's a remote tmux session, otherwise resume locally.
    /// Returns an error message, or nil on success.
    static func open(_ item: SessionItem) -> String? {
        let s = item.session
        if item.hostIsLocal, let name = s.tmuxName {
            return runInNewITermWindow("\(shq(tmux)) attach-session -t \(shq(name))")
        }
        if !item.hostIsLocal, let name = s.tmuxName {
            guard let target = item.hostSSHTarget else {
                return "This host has no SSH target configured and no URL host to derive one from."
            }
            return runInNewITermWindow(sshAttachCommand(sshTarget: target, tmuxName: name))
        }
        return resumeLocally(item)
    }

    static func resumeLocally(_ item: SessionItem) -> String? {
        let s = item.session
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

    static func sshAttachCommand(sshTarget: String, tmuxName: String) -> String {
        let remote = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux attach-session -t \(shq(tmuxName))"
        return "ssh -t -o ConnectTimeout=5 \(shq(sshTarget)) \(itermDoubleQuoted(remote))"
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

    private static func itermDoubleQuoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
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
    let isMoving: Bool

    private var session: APISession { item.session }

    private var dotColor: Color {
        switch item.status {
        case .needsInput: return .orange
        case .working: return .green
        case .paused: return .red
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
            } else if !item.hostIsLocal, session.tmuxName != nil {
                badge("ssh", color: .green)
            } else if item.opensByResume {
                badge("resume", color: .orange)
            }
            if isMoving {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("moving…")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.up.forward.square")
                .foregroundStyle(item.canOpen && !isMoving ? Color.accentColor : Color.secondary.opacity(0.3))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .opacity(item.canOpen && !isMoving ? 1 : 0.5)
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

struct MenuBarSessionRow: View {
    let item: SessionItem
    let showHost: Bool
    let action: () -> Void

    private var statusColor: Color {
        switch item.status {
        case .needsInput: return .orange
        case .paused: return .red
        case .working: return .green
        case .idle, .closed: return Color.secondary.opacity(0.35)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.session.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.session.project)
                        if let model = item.session.model {
                            Text("·")
                            Text(model)
                        }
                        if showHost || !item.hostIsLocal {
                            Text("·")
                            Text(item.hostLabel)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.canOpen ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.canOpen)
        .opacity(item.canOpen ? 1 : 0.55)
        .accessibilityIdentifier("menu_bar_session_\(item.id)")
    }
}

struct MenuBarQuickAccessView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.openWindow) private var openWindow
    @State private var alertMessage: String?
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let snapshotMode: Bool

    init(snapshotMode: Bool = false) {
        self.snapshotMode = snapshotMode
    }

    private var projection: MenuBarSessionProjection {
        MenuBarSessionProjection(items: store.items)
    }

    private var connectionColor: Color {
        switch store.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .offline: return .red
        }
    }

    private var connectionSummary: String {
        let status = store.connectionStatus.label
        let actionable = projection.needsInputCount
        if actionable > 0 {
            return "\(status) · \(actionable) need\(actionable == 1 ? "s" : "") input"
        }
        if projection.runningCount > 0 {
            return "\(status) · \(projection.runningCount) running"
        }
        return status
    }

    private var sessionContentHeight: CGFloat {
        guard !store.items.isEmpty else { return 104 }
        let visibleRows = projection.needsInput.count + projection.running.count + projection.recent.count
        let visibleSections = [
            projection.needsInputCount,
            projection.runningCount,
            projection.recentCount,
        ].filter { $0 > 0 }.count
        let overflowLines = [
            projection.needsInputCount > projection.needsInput.count,
            projection.runningCount > projection.running.count,
            projection.recentCount > projection.recent.count,
        ].filter { $0 }.count
        let ideal = CGFloat(visibleRows * 49 + visibleSections * 23 + overflowLines * 18 + 20)
        return min(430, max(104, ideal))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("lfg")
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(connectionColor)
                            .frame(width: 6, height: 6)
                        Text(connectionSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if snapshotMode {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.refreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.refreshing)
                    .help("Refresh sessions")
                    .accessibilityIdentifier("menu_bar_refresh_button")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            Group {
                if snapshotMode {
                    sessionListContent
                } else {
                    ScrollView {
                        sessionListContent
                    }
                }
            }
            .frame(height: sessionContentHeight)

            Divider()

            Button {
                openWindow(id: "sessions")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                    Text("Open All Sessions")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu_bar_open_all_button")
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if store.lastRefreshed == nil {
                await store.refresh()
            }
        }
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

    private var sessionListContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: store.refreshing ? "arrow.clockwise" : "rectangle.stack")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(store.refreshing ? "Loading sessions…" : "No sessions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .accessibilityIdentifier("menu_bar_empty_state")
            } else {
                sessionSection(
                    title: "Needs Input",
                    symbol: "exclamationmark.bubble.fill",
                    color: .orange,
                    items: projection.needsInput,
                    total: projection.needsInputCount
                )
                sessionSection(
                    title: "Running",
                    symbol: "bolt.fill",
                    color: .green,
                    items: projection.running,
                    total: projection.runningCount
                )
                sessionSection(
                    title: "Recent",
                    symbol: "clock",
                    color: .secondary,
                    items: projection.recent,
                    total: projection.recentCount
                )
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func sessionSection(
        title: String,
        symbol: String,
        color: Color,
        items: [SessionItem],
        total: Int
    ) -> some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(total)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)

                ForEach(items) { item in
                    MenuBarSessionRow(item: item, showHost: store.multipleHosts) {
                        open(item)
                    }
                }

                if total > items.count {
                    Text("\(total - items.count) more in All Sessions")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, 1)
                }
            }
        }
    }

    private func open(_ item: SessionItem) {
        Task.detached {
            let error = Opener.open(item)
            if let error {
                await MainActor.run { alertMessage = error }
            }
        }
    }
}

struct HostsSettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var configuredHosts: [Config.HostEntry] = Config.loadHosts()
    @State private var newHost = ""
    @State private var newSSH = ""
    @State private var validationMessage: String?
    @State private var saveError: String?

    private struct HostRow: Identifiable {
        let index: Int
        let entry: Config.HostEntry
        var id: Int { index }
    }

    private var rows: [HostRow] {
        configuredHosts.enumerated().map { HostRow(index: $0.offset, entry: $0.element) }
    }

    private var trimmedNewHost: String {
        newHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewSSH: String {
        newSSH.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var configPath: String {
        Config.hostsFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            List {
                ForEach(rows) { row in
                    settingsRow(for: row)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 220)

            HStack(spacing: 8) {
                TextField("http://host:8766", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("host_url_field")
                    .onSubmit(addHost)
                TextField("user@host (optional)", text: $newSSH)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("host_ssh_field")
                    .onSubmit(addHost)
                Button("Add") { addHost() }
                    .disabled(trimmedNewHost.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("add_host_button")
            }

            if let message = validationMessage ?? saveError {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Text("Backed by \(configPath)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 360)
        .navigationTitle("Hosts")
        .task {
            configuredHosts = Config.loadHosts()
            await store.refresh()
        }
    }

    @ViewBuilder
    private func settingsRow(for row: HostRow) -> some View {
        let state = store.hosts.first { $0.url == row.entry.url }
        let duplicate = store.duplicateHostsByURL[row.entry.url]
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(state: state, duplicate: duplicate))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.entry.url)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if state?.isLocal == true || duplicate?.isLocal == true {
                        badge("this Mac", color: .blue)
                    }
                }
                TextField(
                    displayNamePlaceholder(state: state, duplicate: duplicate),
                    text: displayNameBinding(for: row.index)
                )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Display name for \(row.entry.url)")
                    .accessibilityIdentifier("host_display_name_field_\(row.index)")
                    .onSubmit { persist(configuredHosts) }
                Text(detailText(entry: row.entry, state: state, duplicate: duplicate))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(sshDetailText(for: row.entry))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                persist(configuredHosts)
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Save display name")
            .accessibilityLabel("Save display name for \(row.entry.url)")
            .accessibilityIdentifier("save_host_display_name_button_\(row.index)")
            Button {
                removeHost(at: row.index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove host")
            .accessibilityIdentifier("remove_host_button_\(row.index)")
        }
        .padding(.vertical, 3)
    }

    private func statusColor(state: HostState?, duplicate: HostState?) -> Color {
        if state?.error == nil && (state != nil || duplicate != nil) { return .green }
        return .red
    }

    private func detailText(entry: Config.HostEntry, state: HostState?, duplicate: HostState?) -> String {
        if let state {
            if state.error != nil { return "Unreachable" }
            return "\(entry.displayLabel(reportedHostName: state.info?.hostName)) · \(sessionCountText(state.sessions.count))"
        }
        if let duplicate {
            let label = entry.displayLabel(reportedHostName: duplicate.info?.hostName)
            return "Reachable duplicate of \(label) · \(sessionCountText(duplicate.sessions.count))"
        }
        return "Unreachable"
    }

    private func displayNamePlaceholder(state: HostState?, duplicate: HostState?) -> String {
        let hostName = state?.info?.hostName ?? duplicate?.info?.hostName
        if let hostName, !hostName.isEmpty {
            return String(hostName.split(separator: ".").first ?? Substring(hostName))
        }
        return "Display name (optional)"
    }

    private func displayNameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard configuredHosts.indices.contains(index) else { return "" }
                return configuredHosts[index].displayName ?? ""
            },
            set: { value in
                guard configuredHosts.indices.contains(index) else { return }
                configuredHosts[index].displayName = value
                saveError = nil
            }
        )
    }

    private func sessionCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "session" : "sessions")"
    }

    private func sshDetailText(for entry: Config.HostEntry) -> String {
        if let target = Config.sshTarget(for: entry) {
            return "SSH: \(target)"
        }
        return "SSH: unavailable"
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func addHost() {
        saveError = nil
        let url = trimmedNewHost
        guard validate(url) else { return }
        let ssh = trimmedNewSSH.isEmpty ? nil : trimmedNewSSH
        persist(configuredHosts + [Config.HostEntry(url: url, ssh: ssh)])
        newHost = ""
        newSSH = ""
    }

    private func removeHost(at index: Int) {
        guard configuredHosts.indices.contains(index) else { return }
        saveError = nil
        validationMessage = nil
        var next = configuredHosts
        next.remove(at: index)
        persist(next)
    }

    private func validate(_ url: String) -> Bool {
        if url.isEmpty {
            validationMessage = "Enter a host URL."
            return false
        }
        if configuredHosts.contains(where: { $0.url == url }) {
            validationMessage = "That host is already configured."
            return false
        }
        guard let parsed = URL(string: url),
              parsed.scheme?.isEmpty == false,
              parsed.host?.isEmpty == false else {
            validationMessage = "Enter a URL with a scheme and host."
            return false
        }
        validationMessage = nil
        return true
    }

    private func persist(_ hosts: [Config.HostEntry]) {
        do {
            try Config.saveHosts(hosts)
            configuredHosts = Config.loadHosts()
            store.reloadConfiguration()
            Task { await store.refresh() }
        } catch {
            saveError = "Couldn't save hosts: \(error.localizedDescription)"
        }
    }
}

/// iOS-parity connection status in the leading title-bar slot. One host gets
/// the aggregate Connected/Connecting/Offline label and running count; a fleet
/// gets one compact named chip per configured host.
struct DesktopConnectionStatusBar: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        Group {
            if store.configuredHosts.count > 1 {
                HStack(spacing: 12) {
                    ForEach(Array(store.configuredHosts.enumerated()), id: \.offset) { _, host in
                        hostChip(host)
                    }
                }
            } else {
                let status = store.connectionStatus
                HStack(spacing: 6) {
                    statusDot(status)
                    Text(status.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusTextColor(status))
                    if store.runningCount > 0 {
                        Text("· \(store.runningCount) running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(singleHostAccessibilityLabel(status))
            }
        }
        .lineLimit(1)
        .accessibilityIdentifier("host_connection_status")
    }

    private func hostChip(_ host: Config.HostEntry) -> some View {
        let status = store.connectionStatus(for: host)
        return HStack(spacing: 5) {
            statusDot(status)
            Text(store.displayLabel(for: host))
                .font(.caption.weight(.medium))
                .foregroundStyle(statusTextColor(status))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.displayLabel(for: host)) \(status.label.lowercased())")
    }

    private func statusDot(_ status: HostConnectionStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private func statusColor(_ status: HostConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .secondary
        case .offline: return .orange
        }
    }

    private func statusTextColor(_ status: HostConnectionStatus) -> Color {
        switch status {
        case .connected: return .primary
        case .connecting: return .secondary
        case .offline: return .orange
        }
    }

    private func singleHostAccessibilityLabel(_ status: HostConnectionStatus) -> String {
        guard store.runningCount > 0 else { return status.label }
        return "\(status.label), \(store.runningCount) running"
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var alertMessage: String?
    @State private var searchText = ""
    @State private var groupMode: GroupMode = .status
    /// Collapsible UI state is in-memory per the current run.
    @State private var expandedDirs: Set<String> = []
    @State private var expandedAgentSections: Set<String> = []
    @State private var expandedAgentParents: Set<String> = []
    @State private var pendingMove: PendingMove?
    @State private var pendingClose: SessionItem?
    @State private var pendingRename: SessionItem?
    @State private var renameText = ""
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

    private struct PendingMove: Identifiable {
        let item: SessionItem
        let target: SessionStore.MoveTarget

        var id: String { "\(item.id)-\(target.id)" }
    }

    /// Sessions passing the search query.
    private var matchingItems: [SessionItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.items }
        return store.items.filter { SessionSearch.matches($0, query: q) }
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
        guard item.status != .needsInput, item.status != .paused, item.status != .closed else { return nil }
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
        let isMoving = item.session.sessionId.map {
            store.movingIds.contains($0) || store.closingIds.contains($0)
        } ?? false
        return Button {
            guard !isMoving else { return }
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
            SessionRow(item: item, showHost: store.multipleHosts, isMoving: isMoving)
        }
        .buttonStyle(.plain)
        .disabled(isMoving)
        .contextMenu {
            if !isMoving {
                if item.session.sessionId != nil {
                    Button("Rename…") {
                        renameText = item.session.title
                        pendingRename = item
                    }
                }
                if !item.hostIsLocal, item.session.sessionId != nil {
                    Button("Resume locally") {
                        resumeLocally(item)
                    }
                }
                ForEach(store.moveTargets(for: item)) { target in
                    Button("Move to \(target.label)") {
                        requestMove(item, to: target)
                    }
                }
                if item.session.sessionId != nil {
                    Divider()
                    Button("Close session", role: .destructive) {
                        requestClose(item)
                    }
                }
            }
        }
    }

    private func requestClose(_ item: SessionItem) {
        guard let sessionId = item.session.sessionId,
              !store.closingIds.contains(sessionId) else { return }
        // Closing an idle session is cheap and reversible (resume brings it
        // back), so only interrupt for one that's mid-turn.
        if item.status == .working {
            pendingClose = item
        } else {
            startClose(item)
        }
    }

    private func startClose(_ item: SessionItem) {
        Task {
            let err = await store.close(item: item)
            if let err {
                alertMessage = err
            }
        }
    }

    private func startRename(_ item: SessionItem, to title: String) {
        Task {
            let err = await store.rename(item: item, to: title)
            if let err {
                alertMessage = err
            }
        }
    }

    private func resumeLocally(_ item: SessionItem) {
        Task.detached {
            let err = Opener.resumeLocally(item)
            if let err {
                await MainActor.run { alertMessage = err }
            }
        }
    }

    private func requestMove(_ item: SessionItem, to target: SessionStore.MoveTarget) {
        guard let sessionId = item.session.sessionId, !store.movingIds.contains(sessionId) else { return }
        let pending = PendingMove(item: item, target: target)
        if item.status == .working {
            pendingMove = pending
        } else {
            startMove(pending)
        }
    }

    private func startMove(_ pending: PendingMove) {
        Task {
            let err = await store.move(item: pending.item, to: pending.target)
            if let err {
                alertMessage = err
            }
        }
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
        // The leading host-status cluster is wider than the old static title.
        // 760 keeps common two-host names alongside the centered picker and
        // fixed trailing refresh/search cluster.
        .frame(minWidth: 760, minHeight: 420)
        .navigationTitle("")
        // HIG "Toolbars" item groupings: common view controls in the center
        // area, search + actions on the trailing edge.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                DesktopConnectionStatusBar()
            }
            .sharedBackgroundVisibility(.hidden)
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
        .alert("Session is working — move anyway?", isPresented: .init(
            get: { pendingMove != nil },
            set: { if !$0 { pendingMove = nil } }
        )) {
            Button("Move", role: .destructive) {
                if let pendingMove {
                    startMove(pendingMove)
                }
                pendingMove = nil
            }
            Button("Cancel", role: .cancel) {
                pendingMove = nil
            }
        } message: {
            Text("The source session will be closed before lfg waits for transcript sync and resumes it on the target host.")
        }
        .alert("Session is working — close anyway?", isPresented: .init(
            get: { pendingClose != nil },
            set: { if !$0 { pendingClose = nil } }
        )) {
            Button("Close", role: .destructive) {
                if let pendingClose {
                    startClose(pendingClose)
                }
                pendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                pendingClose = nil
            }
        } message: {
            Text("The session is mid-turn. Closing ends its process now — the transcript is kept, so you can resume it later.")
        }
        .alert("Rename session", isPresented: .init(
            get: { pendingRename != nil },
            set: { if !$0 { pendingRename = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let pendingRename {
                    startRename(pendingRename, to: renameText)
                }
                pendingRename = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRename = nil
            }
        } message: {
            Text("An empty title clears the override and restores the session's first prompt as its name.")
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

/// Off-screen fixture for visual verification without opening the status item.
enum DesktopMenuBarSnapshotCLI {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.dropFirst().first == "--menu-bar-snapshot" else { return }
        guard args.count == 3 else {
            print("{\"ok\":false,\"error\":\"usage: lfg --menu-bar-snapshot <output-file>\"}")
            Darwin.exit(1)
        }
        do {
            let output = URL(fileURLWithPath: args[2])
            try render(to: output)
            print("{\"ok\":true,\"snapshot\":\"\(output.path)\"}")
            fflush(stdout)
            Darwin.exit(0)
        } catch {
            print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
            fflush(stdout)
            Darwin.exit(1)
        }
    }

    @MainActor
    private static func render(to output: URL) throws {
        _ = NSApplication.shared
        let store = SessionStore()
        store.configuredHosts = [
            Config.HostEntry(url: "http://studio:8766", displayName: "Creative Studio")
        ]
        store.lastRefreshed = Date()
        store.hosts = [
            HostState(
                url: "http://studio:8766",
                sshTarget: nil,
                displayName: "Creative Studio",
                info: HostInfoResponse(hostId: "studio", hostName: "Studio.local"),
                sessions: [
                    session(
                        id: "needs-input",
                        title: "Choose the launch direction",
                        project: "lfg",
                        busy: true,
                        status: "blocked",
                        activity: 100
                    ),
                    session(
                        id: "working",
                        title: "Build menu-bar quick access",
                        project: "lfg",
                        busy: true,
                        activity: 300
                    ),
                    session(
                        id: "paused",
                        title: "Restore remote authentication",
                        project: "inbox",
                        status: "blocked",
                        activity: 250
                    ),
                    session(
                        id: "recent",
                        title: "Polish onboarding copy",
                        project: "studio",
                        activity: 200
                    ),
                ],
                needsInputSessionIds: ["needs-input"],
                isLocal: true
            )
        ]

        let content = MenuBarQuickAccessView(snapshotMode: true)
            .environmentObject(store)
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 380, height: 410)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotFailure("Could not render the menu-bar fixture")
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: output, options: .atomic)
    }

    private static func session(
        id: String,
        title: String,
        project: String,
        busy: Bool = false,
        status: String? = nil,
        activity: Double
    ) -> APISession {
        APISession(
            agent: "claude",
            pid: id.hashValue,
            cwd: "/Users/eugene/dev/\(project)",
            project: project,
            title: title,
            sessionId: id,
            busy: busy,
            lastActivityAt: activity,
            tmuxName: "lfg-\(id)",
            model: "opus",
            status: status,
            lastUserText: nil
        )
    }

    private struct SnapshotFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

@main
struct LFGSessionsApp: App {
    @StateObject private var store = SessionStore()
    init() {
        DesktopFeatureTestCLI.runIfRequested()
        DesktopStatusSnapshotCLI.runIfRequested()
        DesktopMenuBarSnapshotCLI.runIfRequested()
        MoveTestCLI.runIfRequested()
    }

    var body: some Scene {
        Window("lfg", id: "sessions") {
            ContentView()
                .environmentObject(store)
        }
        MenuBarExtra {
            MenuBarQuickAccessView()
                .environmentObject(store)
        } label: {
            let projection = MenuBarSessionProjection(items: store.items)
            HStack(spacing: 3) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                if projection.needsInputCount > 0 {
                    Text("\(projection.needsInputCount)")
                }
            }
            .accessibilityLabel(projection.needsInputCount > 0
                                ? "lfg, \(projection.needsInputCount) need input"
                                : "lfg")
            .accessibilityIdentifier("menu_bar_status_item")
        }
        .menuBarExtraStyle(.window)
        Settings {
            HostsSettingsView()
                .environmentObject(store)
        }
    }
}
