import Foundation
import Observation
import LFGCore

@MainActor @Observable
final class ShareComposerModel {
    let spool: ShareSpool
    var configuration: ShareConfiguration
    var recipients: [ShareRecipient]
    var query = ""
    var selectedID: String?
    var inputID = UUID().uuidString
    var text = ""
    var previewTitle: String?
    var files: [ShareFile] = []
    var loadingInput = true
    var refreshing = false
    var reachableHostIDs = Set<String>()
    var sending = false
    var inputError: String?
    var delivery: ShareJob?
    var hostID: String
    var cwd: String
    var agent: String
    var directories: [String] = []
    var showingOptions = false
    var refreshError: String?

    init(spool: ShareSpool) {
        self.spool = spool
        let config = spool.configuration()
        configuration = config
        // Cached state is useful offline; only a fresh response can assert a
        // live host. This avoids claiming a stale Working session is connected.
        recipients = config.recipients.map { var r = $0; r.isReachable = false; return r }
        hostID = (config.hosts.first(where: \.isDefault) ?? config.hosts.first)?.id ?? ""
        cwd = config.recentDirs.first ?? ""
        agent = config.agent == "codex" ? "codex" : "claude"
    }
    var host: Host? { configuration.hosts.first { $0.id == hostID } }
    var selected: ShareRecipient? { recipients.first { $0.id == selectedID } }
    var isNew: Bool { selectedID == "new" }
    var canSend: Bool {
        !loadingInput && !sending && inputError == nil && (isNew ? host != nil && !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selected != nil)
        && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty)
        && delivery?.status != .uncertain && delivery?.status != .sent && delivery?.status != .queued
    }
    var effect: String { isNew ? "Starts a new session" : selected?.sendEffect ?? "" }
    var recipientTitle: String { isNew ? "New session" : selected?.session.title ?? "" }
    var confirmation: String {
        if isNew { return "Session started" }
        guard let selected else { return "Sent" }
        if selected.isChat { return "Sent" }
        if selected.session.closed { return "Session resumed" }
        if selected.session.prompt != nil { return "Saved. Runs after you answer its question." }
        return selected.session.busy == true ? "Added to its current turn" : "Sent"
    }
    var locksDraft: Bool { sending || delivery != nil }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        reachableHostIDs.removeAll()
        recipients = recipients.map { var row = $0; row.isReachable = false; return row }
        let hosts = configuration.hosts
        await withTaskGroup(of: (Host, [Session]?, [ResumableSession]).self) { group in
            for host in hosts {
                group.addTask {
                    guard let client = HostCredentialStore.shared.client(forHostURL: host.url) else { return (host, nil, []) }
                    do {
                        let live = try await client.sessions(timeout: 6)
                        let closed = (try? await client.resumable(limit: 60, timeout: 6).sessions) ?? []
                        return (host, live, closed)
                    } catch { return (host, nil, []) }
                }
            }
            for await (host, live, closed) in group {
                guard let live else { continue }
                reachableHostIDs.insert(host.id)
                recipients.removeAll { $0.host.id == host.id }
                recipients += live.map { ShareRecipient(host: host, session: $0) }
                recipients += closed.map {
                    var session = Session(sessionId: $0.sessionId, title: $0.title ?? "Untitled session", agent: $0.agent ?? "claude",
                        project: $0.project, cwd: $0.cwd, lastActivityAt: $0.mtime, closed: true)
                    session.purpose = $0.purpose
                    return ShareRecipient(host: host, session: session)
                }
            }
        }
        recipients = ShareRecipients.reconciled(recipients).filter { !HiddenDirs(configuration.hiddenDirs).hides(cwd: $0.session.cwd) }
        refreshError = !reachableHostIDs.isEmpty ? nil : "Hosts are offline. Cached sessions are available; shares wait for LFG to reconnect."
        await loadDirectories()
    }
    /// Search older conversations on the hosts as well as the instant cache.
    /// The query check prevents a slow answer from replacing a newer search.
    func searchHistory() async {
        let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { return }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        await withTaskGroup(of: [ShareRecipient].self) { group in
            for host in configuration.hosts {
                group.addTask {
                    guard let client = HostCredentialStore.shared.client(forHostURL: host.url),
                          let page = try? await client.resumable(limit: 60, q: requested, timeout: 6) else { return [] }
                    return page.sessions.map { row in
                        var session = Session(sessionId: row.sessionId, title: row.title ?? "Untitled session", agent: row.agent ?? "claude",
                            project: row.project, cwd: row.cwd, lastActivityAt: row.mtime, closed: row.closed)
                        session.purpose = row.purpose
                        return ShareRecipient(host: host, session: session)
                    }
                }
            }
            for await rows in group {
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == requested else { continue }
                let existing = Set(recipients.map { $0.session.id })
                recipients += rows.filter { !existing.contains($0.session.id) && !HiddenDirs(configuration.hiddenDirs).hides(cwd: $0.session.cwd) }
                recipients = ShareRecipients.reconciled(recipients)
            }
        }
    }

    func loadDirectories() async {
        guard let host, let client = HostCredentialStore.shared.client(forHostURL: host.url),
              let dirs = try? await client.dirs() else { return }
        reachableHostIDs.insert(host.id)
        directories = Array(Set([dirs.inbox, dirs.root] + dirs.repos.map(\.cwd))).filter { !$0.isEmpty }.sorted()
        if cwd.isEmpty { cwd = dirs.inbox }
    }
    func select(_ id: String) { guard !locksDraft else { return }; selectedID = selectedID == id ? nil : id }

    func send() async {
        guard canSend, let host = isNew ? host : selected?.host else { return }
        sending = true; defer { sending = false }
        do {
            if delivery == nil {
                let request = isNew ? NewSessionRequest(cwd: cwd, prompt: "", agent: agent, model: agent == configuration.agent ? configuration.model : nil, user: configuration.owner) : nil
                let job = ShareJob(id: inputID, host: host, sessionID: selected?.session.sessionId, recipientTitle: recipientTitle,
                                   newSession: request, text: text, files: files)
                try spool.save(job)
                delivery = job
                if !reachableHostIDs.contains(host.id) { return }
            }
            delivery = try await ShareDelivery(spool: spool, transport: ShareEnvironment.transport).deliver(inputID, retryFailure: true)
        } catch { inputError = error.localizedDescription }
    }
    func cancel() {
        guard !sending else { return }
        // Once submitted, leave the durable job for the app. A pre-send cancel
        // removes only the unsubmitted provider copies.
        if delivery == nil { try? spool.discard(inputID) }
    }
}
