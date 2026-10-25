import SwiftUI
import LFGCore

/// Main-app recovery for shares saved by the extension. The host's normal
/// queue/transcript remains authoritative; this never invents a user bubble.
@MainActor @Observable
final class ShareAppBridge {
    static let shared = ShareAppBridge()
    private(set) var pending: [ShareJob] = []
    private var worker: Task<Void, Never>?

    func publish(settings: AppSettings, store: SessionStore) {
        guard let spool = ShareEnvironment.spool else { return }
        let rows = store.sessions.compactMap { session -> ShareRecipient? in
            guard !settings.hiddenDirs.hides(cwd: session.cwd), let id = session.sessionId,
                  let host = store.host(forSession: id) else { return nil }
            return ShareRecipient(host: host, session: session, isReachable: !store.isOffline(id))
        }
        let config = ShareConfiguration(hosts: settings.hosts, recipients: ShareRecipients.reconciled(rows),
                                        recentDirs: settings.recentDirs, agent: settings.lastNewSessionModelSelection.agent.rawValue,
                                        owner: settings.defaultOwner, hiddenDirs: settings.hiddenDirs.paths, model: settings.lastNewSessionModelSelection.model)
        try? spool.saveConfiguration(config)
    }

    func resume(settings: AppSettings, store: SessionStore) {
        guard worker == nil, let spool = ShareEnvironment.spool else { return }
        pending = spool.jobs().filter { $0.status != .sent }
        let hosts = settings.hosts
        guard !pending.isEmpty else { return }
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "Deliver shared messages")
        worker = Task {
            defer {
                pending = spool.jobs().filter { $0.status != .sent }
                worker = nil
                if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
            }
            let service = ShareDelivery(spool: spool, transport: ShareEnvironment.transport)
            for job in spool.jobs() where job.status != .sent {
                guard hosts.contains(where: { $0.id == job.host.id }) else { continue }
                _ = try? await service.deliver(job.id)
            }
        }
    }

    func retry(_ job: ShareJob, settings: AppSettings, store: SessionStore) {
        guard worker == nil, job.status == .failed, let spool = ShareEnvironment.spool,
              settings.hosts.contains(where: { $0.id == job.host.id }) else { return }
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "Retry shared message")
        worker = Task {
            defer {
                pending = spool.jobs().filter { $0.status != .sent }; worker = nil
                if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
            }
            _ = try? await ShareDelivery(spool: spool, transport: ShareEnvironment.transport).deliver(job.id, retryFailure: true)
            await store.refresh()
        }
    }
    func remove(_ job: ShareJob) {
        guard worker == nil, let spool = ShareEnvironment.spool else { return }
        try? spool.discard(job.id)
        pending = spool.jobs().filter { $0.status != .sent }
    }
}

struct PendingSharesView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var bridge = ShareAppBridge.shared
    @State private var removing: ShareJob?
    var body: some View {
        NavigationStack {
            List {
                ForEach(bridge.pending) { job in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(job.recipientTitle).font(.headline)
                        Text(job.text).font(.subheadline).lineLimit(4)
                        Text(job.host.label).font(.caption).foregroundStyle(.secondary)
                        Text(status(job)).font(.footnote).foregroundStyle(job.status == .failed ? .red : .secondary)
                        HStack {
                            if let id = job.sessionID {
                                Button("Open session") { store.openFromNotification(id); dismiss() }
                                    .accessibilityIdentifier("share_pending_open_\(job.id)")
                            }
                            if job.status == .failed {
                                Button("Retry") { bridge.retry(job, settings: settings, store: store) }
                                    .accessibilityIdentifier("share_pending_retry_\(job.id)")
                            }
                            Spacer()
                            Button("Remove", role: .destructive) { removing = job }
                                .accessibilityIdentifier("share_pending_remove_\(job.id)")
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 6)
                }
            }
            .overlay { if bridge.pending.isEmpty { ContentUnavailableView("No pending shares", systemImage: "checkmark.circle") } }
            .navigationTitle("Pending shares").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("share_pending_done") } }
            .confirmationDialog("Remove this saved share?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                if let job = removing { Button("Remove saved share", role: .destructive) { bridge.remove(job); removing = nil } }
            } message: { Text("This removes the local copy. It does not undo a message already received by the host.") }
            .accessibilityIdentifier("share_pending_list")
        }
    }
    private func status(_ job: ShareJob) -> String {
        switch job.status {
        case .uncertain, .creating, .sending: return "Delivery is unconfirmed. Check the session before sharing again."
        case .failed: return job.error ?? "Not sent. Retry when ready."
        default: return "Saved on this device. LFG retries when this computer is available."
        }
    }
}
