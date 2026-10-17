import Foundation

/// Only status-bearing journal events affect the desktop list. Messages and
/// heartbeat frames still advance the transport cursor without inventing state.
enum DesktopStatusEvent: Sendable {
    case busy(String, Bool)
    case prompt(String, DesktopPrompt?)
    case resync(Int64)

    var sessionID: String? {
        switch self {
        case .busy(let sid, _), .prompt(let sid, _): return sid
        case .resync: return nil
        }
    }

    static func decode(_ frame: SSEFrame) -> Self? {
        guard !frame.isComment, ["busy", "prompt", "resync"].contains(frame.event),
              let data = frame.data.data(using: .utf8) else { return nil }
        struct Busy: Decodable { let sid: String; let busy: Bool }
        struct Prompt: Decodable { let sid: String; let prompt: DesktopPrompt? }
        struct Resync: Decodable { let head: Int64 }
        let decoder = JSONDecoder()
        switch frame.event {
        case "busy":
            guard let value = try? decoder.decode(Busy.self, from: data), !value.sid.isEmpty else { return nil }
            return .busy(value.sid, value.busy)
        case "prompt":
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object.keys.contains("prompt"),
                  let value = try? decoder.decode(Prompt.self, from: data), !value.sid.isEmpty else { return nil }
            return .prompt(value.sid, value.prompt)
        case "resync":
            guard let value = try? decoder.decode(Resync.self, from: data), value.head >= 0 else { return nil }
            return .resync(value.head)
        default: return nil
        }
    }
}

/// Snapshot requests may finish after a newer journal edge. Preserve just those
/// newer fields; the next fresh snapshot can repair any missed journal events.
struct DesktopStatusReconciliation {
    struct Field<Value> { let value: Value; let revision: UInt64 }
    struct Delta {
        var busy: Field<Bool>?
        var prompt: Field<DesktopPrompt?>?
    }
    private(set) var revision: UInt64 = 0
    private var changes: [String: [String: Delta]] = [:]

    mutating func record(_ event: DesktopStatusEvent, host: String) {
        revision += 1
        switch event {
        case .busy(let sid, let value):
            changes[host, default: [:]][sid, default: Delta()].busy = Field(value: value, revision: revision)
        case .prompt(let sid, let value):
            changes[host, default: [:]][sid, default: Delta()].prompt = Field(value: value, revision: revision)
        case .resync:
            changes[host] = nil
        }
    }

    func apply(to host: inout HostState, after snapshotRevision: UInt64) {
        for index in host.sessions.indices {
            guard let sid = host.sessions[index].sessionId, let delta = changes[host.url]?[sid] else { continue }
            if let field = delta.busy, field.revision > snapshotRevision {
                host.sessions[index] = host.sessions[index].replacingBusy(field.value)
            }
            if let field = delta.prompt, field.revision > snapshotRevision {
                host.sessions[index].prompt = field.value
                if field.value != nil { host.needsInputSessionIds.insert(sid) }
                else { host.needsInputSessionIds.remove(sid) }
            }
        }
    }

    mutating func discard(host: String, through snapshotRevision: UInt64) {
        guard var pending = changes[host] else { return }
        for sid in pending.keys {
            if let field = pending[sid]?.busy, field.revision <= snapshotRevision { pending[sid]?.busy = nil }
            if let field = pending[sid]?.prompt, field.revision <= snapshotRevision { pending[sid]?.prompt = nil }
            if pending[sid]?.busy == nil && pending[sid]?.prompt == nil { pending[sid] = nil }
        }
        changes[host] = pending.isEmpty ? nil : pending
    }
}

extension APISession {
    func replacingBusy(_ busy: Bool) -> APISession {
        var copy = APISession(agent: agent, pid: pid, cwd: cwd, project: project, title: title,
            sessionId: sessionId, busy: busy, lastActivityAt: lastActivityAt, tmuxName: tmuxName,
            model: model, status: status, parentSessionId: parentSessionId,
            lastUserText: lastUserText, closed: closed, purpose: purpose)
        copy.prompt = prompt
        copy.task = task
        return copy
    }
}

/// One resumable connection per configured host, owned by the application store
/// rather than the lifetime of a window, a task page, or the menu-bar popover.
@MainActor
final class DesktopSessionStatusFeed {
    private var tasks: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private(set) var connected: Set<String> = []
    var onEvent: (String, DesktopStatusEvent) -> Void
    var snapshotNeeded: (String) async -> Void

    init(onEvent: @escaping (String, DesktopStatusEvent) -> Void,
         snapshotNeeded: @escaping (String) async -> Void) {
        self.onEvent = onEvent
        self.snapshotNeeded = snapshotNeeded
    }

    func configure(urls: [String]) {
        let wanted = Set(urls)
        for url in tasks.keys where !wanted.contains(url) {
            tasks.removeValue(forKey: url)?.cancel()
            connected.remove(url)
            generations[url] = nil
        }
        for url in wanted where tasks[url] == nil { connect(url) }
    }

    func stop() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        connected.removeAll()
        generations.removeAll()
    }

    deinit { for task in tasks.values { task.cancel() } }

    private func connect(_ base: String) {
        let generation = UUID()
        generations[base] = generation
        tasks[base] = Task.detached { [weak self] in
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 25
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            var retrySeconds: UInt64 = 1
            var cursor: Int64?
            while !Task.isCancelled, await self?.isCurrent(base, generation) == true {
                do {
                    if cursor == nil {
                        // Seed BEFORE the baseline. Any change during that
                        // request is replayed, including the very first turn.
                        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/events/page?since=0&limit=1") else { return }
                        let (data, response) = try await session.data(for: DesktopAPI.request(url))
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                        struct Head: Decodable { let head: Int64 }
                        let head = try JSONDecoder().decode(Head.self, from: data).head
                        guard !Task.isCancelled, head >= 0 else { return }
                        cursor = head
                    }
                    // Snapshot repair must not hold up the live connection
                    // behind a slow history page or another host's timeout.
                    Task { [weak self] in await self?.requestSnapshot(base, generation: generation) }
                    guard !Task.isCancelled, let since = cursor else { return }
                    guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/events?since=\(since)") else { return }
                    var request = DesktopAPI.request(url)
                    request.timeoutInterval = 25
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    guard !Task.isCancelled, await self?.setConnected(true, host: base, generation: generation) == true else { return }
                    retrySeconds = 1
                    var parser = SSEParser()
                    var line = [UInt8]()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 10 {
                            if let frame = parser.feedLine(String(decoding: line, as: UTF8.self)) {
                                let event = DesktopStatusEvent.decode(frame)
                                if let event, case .resync(let head) = event {
                                    cursor = head
                                    await self?.deliver(event, host: base, generation: generation)
                                } else if let id = frame.id.flatMap(Int64.init), id > (cursor ?? 0) {
                                    cursor = id
                                    if let event { await self?.deliver(event, host: base, generation: generation) }
                                }
                            }
                            line.removeAll(keepingCapacity: true)
                        } else { line.append(byte) }
                    }
                } catch {
                    // REST reconciliation remains active while this link is
                    // unavailable, including hosts without a journal endpoint.
                }
                _ = await self?.setConnected(false, host: base, generation: generation)
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: retrySeconds * 1_000_000_000)
                retrySeconds = min(retrySeconds * 2, 15)
            }
        }
    }

    private func isCurrent(_ host: String, _ generation: UUID) -> Bool {
        generations[host] == generation
    }

    private func requestSnapshot(_ host: String, generation: UUID) async {
        guard isCurrent(host, generation) else { return }
        await snapshotNeeded(host)
    }

    @discardableResult
    private func setConnected(_ value: Bool, host: String, generation: UUID) -> Bool {
        guard isCurrent(host, generation) else { return false }
        if value { connected.insert(host) } else { connected.remove(host) }
        return true
    }

    private func deliver(_ event: DesktopStatusEvent, host: String, generation: UUID) {
        guard isCurrent(host, generation) else { return }
        onEvent(host, event)
        if case .resync = event {
            Task { [weak self] in await self?.snapshotNeeded(host) }
        }
    }

}

extension SessionStore {
    func startStatusSync() {
        guard statusPollingTask == nil else { return }
        statusFeed = DesktopSessionStatusFeed(onEvent: { [weak self] host, event in
            self?.receiveStatus(event, host: host)
        }, snapshotNeeded: { [weak self] host in await self?.refresh(host: host) })
        statusFeed?.configure(urls: configuredHosts.map(\.url))
        statusPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                Task { [weak self] in await self?.refresh() }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func stopStatusSync() {
        statusPollingTask?.cancel()
        statusPollingTask = nil
        statusFeed?.stop()
        statusFeed = nil
    }

    func receiveStatus(_ event: DesktopStatusEvent, host url: String) {
        guard configuredHosts.contains(where: { $0.url == url }) else { return }
        statusReconciliation.record(event, host: url)
        if case .resync = event { return }
        if var snapshot = hostSnapshots[url] {
            statusReconciliation.apply(to: &snapshot, after: 0)
            snapshot.error = nil
            hostSnapshots[url] = snapshot
        }
        guard let index = hosts.firstIndex(where: { $0.url == url }) else {
            Task { [weak self] in await self?.refresh(host: url) }
            return
        }
        if let sid = event.sessionID, !hosts[index].sessions.contains(where: { $0.sessionId == sid && !$0.closed }) {
            Task { [weak self] in await self?.refresh(host: url) }
        }
        hosts[index].error = nil
        statusReconciliation.apply(to: &hosts[index], after: 0)
    }
}
