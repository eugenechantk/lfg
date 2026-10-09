import SwiftUI

struct ScheduledTasksPane: View {
    @EnvironmentObject private var store: SessionStore
    @State private var error: String?
    var body: some View {
        ScheduledTasksView(hosts: store.hosts.compactMap { host in
            guard let url = URL(string: host.url) else { return nil }
            return ScheduledTaskHost(id: host.id, name: host.label, baseURL: url,
                                     headers: DesktopAPI.request(url).allHTTPHeaderFields ?? [:])
        }) { hostID, sessionID in
            Task {
                await store.refresh()
                if let item = store.items.first(where: { $0.hostURL == hostID && $0.session.sessionId == sessionID }) {
                    error = await Task.detached { Opener.open(item) }.value
                } else { error = "This session is not in the current list. Read its conversation from Run details, or find it in All Sessions." }
            }
        }
        .task { await store.refresh() }
        .alert("Could not open session", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
