import SwiftUI

struct ScheduledTasksPane: View {
    /// Where the pane opens. The `--window-shot` harness sets it to show a task or its edit page.
    @MainActor static var launchPath: [ScheduledTaskRoute] = []
    @EnvironmentObject private var store: SessionStore
    @State private var error: String?
    @State private var openingSession = false
    /// The host strip's "Hidden directories…" popover, the same panel Sessions uses.
    @State private var showDirectoryFilter = false
    @Binding var path: [ScheduledTaskRoute]
    /// Reported up for the switcher's Tasks badge.
    @Binding var taskNeedsInput: Int
    var body: some View {
        ScheduledTasksView(hosts: store.hosts.compactMap { host in
            guard let url = URL(string: host.url) else { return nil }
            return ScheduledTaskHost(id: host.id, name: host.label, baseURL: url,
                                     headers: DesktopAPI.request(url).allHTTPHeaderFields ?? [:])
        }, navigationPath: $path, connectionHeader: { width in
            let compact = width < 700 || !ContentView.hostLabelsFit(
                clusterWidth: DesktopConnectionStatusBar.labelledWidth(of: DesktopConnectionStatusBar.chips(store: store)),
                windowWidth: width)
            return AnyView(DesktopConnectionStatusBar(compact: compact))
        },
           connectionWarning: AnyView(DesktopConnectionWarning()),
           connectedHostIDs: Set(store.hosts.filter { $0.error == nil }.map(\.id)),
           hiddenDirectories: store.hiddenDirs,
           onHiddenDirectories: { showDirectoryFilter = true }) { hostID, sessionID in
            guard !openingSession else { return }
            openingSession = true
            Task {
                defer { openingSession = false }
                await store.refresh()
                // Prefer a live copy, even when the transcript has moved to another host.
                // Unfiltered: a task's edit chat is hidden from Sessions but must still open here.
                if let item = store.liveItem(sessionId: sessionID) {
                    error = await Task.detached { Opener.open(item) }.value
                    return
                }
                guard let host = store.hosts.first(where: { $0.id == hostID }) else {
                    error = "This task's host is no longer configured."
                    return
                }
                // Search by exact session ID, without the session list's hidden-directory
                // filter or newest-page limit. A historical run can be arbitrarily old.
                let page = await SessionStore.fetchSearchPage(
                    entry: Config.HostEntry(url: host.url), query: sessionID, before: nil)
                guard let item = ScheduledTaskSessionLookup.item(sessionID: sessionID, host: host, archived: page.sessions) else {
                    error = "This session is unavailable on \(host.label). Check the host connection and whether its transcript still exists."
                    return
                }
                error = await Task.detached { Opener.open(item) }.value
            }
        } onNeedsInputCountChange: { count in
            taskNeedsInput = count
        }
        .task { await store.refresh() }
        .popover(isPresented: $showDirectoryFilter, arrowEdge: .top) {
            HiddenDirectoriesSettingsView()
                .environmentObject(store)
        }
        .overlay(alignment: .bottom) {
            if openingSession {
                ProgressView("Opening session…").padding().background(.background)
                    .accessibilityIdentifier("task_opening_session")
            }
        }
        .alert("Could not open session", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

@MainActor
enum ScheduledTaskSessionLookup {
    static func item(sessionID: String, host: HostState, archived: [ResumableAPISession]) -> SessionItem? {
        guard let record = archived.first(where: { $0.sessionId == sessionID }) else { return nil }
        return SessionItem(session: SessionStore.closedSession(from: record),
            hostURL: host.url, hostId: host.info?.hostId ?? host.url, hostLabel: host.label,
            hostIsLocal: host.isLocal, hostSSHTarget: host.sshTarget,
            hostRemoteTransport: host.remoteTransport)
    }
}
