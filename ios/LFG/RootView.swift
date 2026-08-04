import SwiftUI
import LFGCore

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @State private var selection: String?
    @State private var showSettings = false
    @State private var showNewSession = false
    @State private var focusNewSessionComposer = false
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
                                    showNewSession: $showNewSession,
                                    focusNewSessionComposer: $focusNewSessionComposer)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
                        // Attached INSIDE the sidebar column so the compact-width
                        // `.navigationDestination` resolves against that column's
                        // navigation stack — on the Group it would have none.
                        .newSessionPresentation(selection: $selection,
                                                isPresented: $showNewSession,
                                                autofocusComposer: $focusNewSessionComposer)
                } detail: {
                    if let selection {
                        if let session = store.session(selection) {
                            SessionDetailView(session: session,
                                              onEnded: { self.selection = nil },
                                              onMarkedUnread: { self.selection = nil })
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
        .onChange(of: store.unreadCount, initial: true) { _, count in
            AppBadge.set(count)
        }
        .onOpenURL { url in
            let path = url.path.split(separator: "/", omittingEmptySubsequences: true)
            guard url.scheme?.lowercased() == "lfg",
                  url.host?.lowercased() == "session",
                  path.count == 1,
                  let sid = String(path[0]).removingPercentEncoding,
                  !sid.isEmpty else { return }
            store.openFromNotification(sid)
        }
        // iOS can't hold a socket while suspended, so the app owns an explicit
        // linger/reconnect around backgrounding: `.background` holds every host
        // link open through a ~25s background-task grace (a quick app-switch
        // drops nothing), then tears down; `.active` cancels the grace and
        // resumes — each link reconnects with its journal cursor, so the resume
        // is one lossless round-trip per host.
        //
        // `.inactive` deliberately does nothing — it also fires for the app
        // switcher, Control Center and incoming calls, where streams are fine.
        .onChange(of: scenePhase) { _, phase in
            guard settings.hasConfiguredHost else { return }
            switch phase {
            case .active:
                store.enterForeground()
                FleetActivityController.shared.syncNow()
            case .background:
                store.enterBackground()
                AppDelegate.scheduleAppRefresh()   // keep a periodic delta sync queued
            default:
                break
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
    /// The host's real state, not a projection of it. `degraded` deliberately
    /// renders nothing: a host inside its grace window is a blip, and the whole
    /// point of the window is not to alarm the user about one.
    let state: HostState?
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
        switch state {
        case .live, .none, .unknown, .connecting, .degraded:
            EmptyView()
        case .noNetwork:
            banner(icon: "wifi.slash", tint: .orange,
                   title: "No network connection",
                   detail: "This device has no network path. Reconnect to Wi-Fi or cellular.")
        case .offline(_, let detail):
            banner(icon: "wifi.exclamationmark", tint: .orange,
                   title: unreachableTitle,
                   detail: multiHostPrefix + "Check that this device is on the same Tailscale tailnet and the host is running. \(detail)")
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
