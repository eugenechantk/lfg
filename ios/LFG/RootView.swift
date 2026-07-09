import SwiftUI
import LFGCore

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @State private var selection: String?
    @State private var showSettings = false
    @State private var showNewSession = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @Environment(\.scenePhase) private var scenePhase

    /// Host-file base URL for inline media: the open session's owning host when
    /// known, else the default host. Lets files referenced by a session on the
    /// non-default machine still resolve.
    private var hostFilesForSelection: HostFiles? {
        if let selection, let h = store.host(forSession: selection), let c = settings.client(for: h) {
            return HostFiles(baseURL: c.baseURL)
        }
        return settings.defaultClient.map { HostFiles(baseURL: $0.baseURL) }
    }

    var body: some View {
        Group {
            if settings.hasConfiguredHost {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SessionListView(selection: $selection,
                                    showSettings: $showSettings,
                                    showNewSession: $showNewSession)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
                } detail: {
                    if let selection {
                        if let session = store.session(selection) {
                            SessionDetailView(session: session, onEnded: { self.selection = nil })
                                .id(selection)
                        } else {
                            // Selected (often via a notification tap) but not
                            // resolved yet — the live list is still loading or the
                            // session is being pulled from the resumable list.
                            // Show progress instead of the "nothing selected" empty
                            // state, which read as "session lost".
                            DetailLoading()
                        }
                    } else {
                        DetailPlaceholder()
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                ConnectView()
            }
        }
        // Inline host-file rendering resolves against the OPEN session's host
        // (multi-host), falling back to the default host.
        .environment(\.hostFiles, hostFilesForSelection)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewSession) {
            NewSessionView { newID in selection = newID }
        }
        .task(id: settings.hosts) {
            guard settings.hasConfiguredHost else { return }
            store.start()
            await store.resolveHostIdentities()
            await store.loadCreateMetadata()
            // Register for push once we have a host to register against.
            await PushManager.shared.requestAuthorizationIfNeeded()
        }
        .task {
            // Apply a selection requested *before* this view's observers were
            // watching — the cold-launch-from-notification case, where the tap is
            // routed during app startup. This runs AFTER the first render, so it
            // never mutates `selection` (which drives the NavigationSplitView)
            // during a view update — doing that is undefined behavior and renders
            // a blank/black screen. The plain onChange below covers taps that
            // arrive while the app is already running.
            if let pending = store.requestedSelection {
                selection = pending
                store.clearRequestedSelection()
            }
        }
        .onChange(of: store.requestedSelection) { _, requested in
            guard let requested else { return }
            selection = requested
            store.clearRequestedSelection()
        }
        // iOS can't hold an SSE stream while the process is suspended, so the app owns
        // an explicit teardown/reconnect around backgrounding rather than letting
        // orphaned tasks linger until their stale watchdog fires.
        //
        // Only `.background` tears down — `.inactive` also fires for the app switcher,
        // Control Center and incoming calls, where the streams are still perfectly good.
        .onChange(of: scenePhase) { _, phase in
            guard settings.hasConfiguredHost else { return }
            switch phase {
            case .active:
                store.start()                       // no-op if the poll loop is alive
                Task { await store.refresh() }      // coalesces onto the loop's in-flight refresh
            case .background:
                store.stop()
            default:
                break                                // .inactive — transient, keep streaming
            }
        }
    }
}

struct DetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "No session selected",
            systemImage: "sparkles",
            description: Text("Pick a session from the list, or start a new one.")
        )
    }
}

/// Shown while a deep-linked (e.g. notification-tapped) session is still being
/// resolved — the live list is loading or the session is being pulled from the
/// resumable list. Avoids the "No session selected" flash that read as a lost
/// session.
struct DetailLoading: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Opening session…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Reachability strip shown above the list when not healthy. This only renders
/// when the *aggregate* is unhealthy — meaning every configured host is down. In
/// a multi-host setup `offlineHosts` names them so the copy says "all hosts",
/// never a singular "host" that would misread one machine as the whole fleet.
struct ConnectionBanner: View {
    let reachability: Reachability?
    /// Labels of the down hosts, supplied only in multi-host setups (empty for a
    /// single host). Drives the "all N hosts" pluralization + naming.
    var offlineHosts: [String] = []

    /// Prefix naming every down host when more than one is configured, so the
    /// banner reads as a fleet-wide outage rather than a single machine.
    private var multiHostPrefix: String {
        guard offlineHosts.count > 1 else { return "" }
        return "\(offlineHosts.joined(separator: ", ")) are all unreachable. "
    }

    private var unreachableTitle: String {
        offlineHosts.count > 1 ? "All \(offlineHosts.count) hosts unreachable" : "Host unreachable"
    }

    var body: some View {
        switch reachability {
        case .ok, .none:
            EmptyView()
        case .hostUnreachable(let detail):
            banner(icon: "wifi.exclamationmark", tint: .orange,
                   title: unreachableTitle,
                   detail: multiHostPrefix + "Check that this device is on the same Tailscale tailnet and the host is running. \(detail)")
        case .badResponse(let detail):
            banner(icon: "exclamationmark.triangle.fill", tint: .red,
                   title: "Connection problem", detail: detail)
        }
    }

    private func banner(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
