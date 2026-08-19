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
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// True only where the split view actually shows two columns side by side
    /// (iPad full screen / wide multitasking). In compact it collapses to a
    /// navigation stack, where a "hide sidebar" control does nothing.
    private var isSideBySide: Bool { hSizeClass == .regular }

    private var sidebarHidden: Bool { columnVisibility == .detailOnly }

    private func setSidebar(hidden: Bool) {
        guard sidebarHidden != hidden else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            columnVisibility = hidden ? .detailOnly : .doubleColumn
        }
    }

    /// Host-file base URL for inline media: the open session's owning host when
    /// known, else the default host. Lets files referenced by a session on the
    /// non-default machine still resolve.
    private var hostFilesForSelection: HostFiles? {
        if let selection, let h = store.host(forSession: selection), let c = settings.client(for: h) {
            return HostFiles(client: c)
        }
        return settings.defaultClient.map { HostFiles(client: $0) }
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
                        // SwiftUI's own sidebar toggle only appears while the sidebar
                        // is HIDDEN — the half of the job that already worked. Left in,
                        // it sits beside ours and duplicates it. Removed here (the
                        // toggle belongs to the sidebar column, wherever it renders) so
                        // one button owns both directions.
                        .toolbar(removing: .sidebarToggle)
                        // Attached INSIDE the sidebar column: the create surface is
                        // a full-screen cover, and presenting it from the column
                        // the user is actually looking at keeps it off the
                        // navigation stack the session detail is pushed onto.
                        .newSessionPresentation(selection: $selection,
                                                isPresented: $showNewSession,
                                                autofocusComposer: $focusNewSessionComposer)
                        // Swipe the list away, from anywhere on it. Simultaneous, so
                        // the List keeps its vertical scroll and its rows keep their
                        // own gestures; this only acts on a decisively horizontal
                        // leftward drag.
                        //
                        // Rows carry trailing `swipeActions` (hide-directory), so the
                        // two gestures share a direction. Measured on device, they
                        // separate cleanly by distance: a row reveals its action at
                        // ~55pt, and this fires at 60. Firing from `onChanged` rather
                        // than `onEnded` is what keeps that clean — it cancels the
                        // row's half-finished reveal mid-drag, so bringing the sidebar
                        // back doesn't surface a row sitting open on a Hide button.
                        .simultaneousGesture(
                            horizontalSwipe(.left) { setSidebar(hidden: true) },
                            // `.subviews` leaves the List's own gestures alone and
                            // switches mine off — there is nothing to close once the
                            // sidebar is already hidden, and in compact the list is
                            // the root of a stack, where "hide the sidebar" is not a
                            // move the user can make sense of.
                            including: (isSideBySide && !sidebarHidden) ? .all : .subviews
                        )
                } detail: {
                    Group {
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
                    // The toggle lives here, not inside SessionDetailView, so it is
                    // present for the placeholder/loading states too — otherwise
                    // hiding the sidebar and then ending a session would strand the
                    // user on a screen with no way to bring the list back.
                    .toolbar { sidebarToggle }
                    // Swipe in from the leading edge to bring the list back. Only
                    // mounted while the sidebar is hidden, so in the normal two-column
                    // state nothing sits over the transcript intercepting touches.
                    .overlay(alignment: .leading) {
                        if isSideBySide && sidebarHidden {
                            SwipeStrip(direction: .right) { setSidebar(hidden: false) }
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                ConnectView()
            }
        }
        // Full-screen a session by collapsing the list column, and bring it back
        // the same way. SwiftUI's built-in toggle only ever offered the "bring it
        // back" half — while the sidebar was showing there was no control at all,
        // so a session could never be read full width.
        .onChange(of: hSizeClass) { _, size in
            // Leaving side-by-side (Slide Over, a narrow multitasking split, or
            // an iPhone) collapses to a stack; a latched `.detailOnly` would then
            // survive the trip back to full width with no sidebar and — until the
            // user finds the button — no list.
            if size != .regular, columnVisibility == .detailOnly {
                columnVisibility = .automatic
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

    /// A drag that has committed to one horizontal direction — dominant in x and
    /// past a threshold wide enough that a lazy diagonal flick during scrolling
    /// can't trip it. Fires mid-drag rather than on release so the column starts
    /// moving under the finger.
    ///
    /// Deliberately has no "already fired" latch. The obvious one — a `@State`
    /// flag set in `onChanged` and cleared in `onEnded` — is a trap here: hiding
    /// the sidebar tears down the very view this gesture is attached to, so
    /// `onEnded` never arrives, the flag stays set, and every later swipe is
    /// silently ignored for the rest of the app's life. Re-entrancy is handled
    /// instead by `setSidebar` being a no-op when already in the target state.
    private func horizontalSwipe(_ direction: SwipeDirection,
                                 perform action: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) * 1.5 else { return }
                guard direction.matches(dx), abs(dx) >= 60 else { return }
                action()
            }
    }

    /// Show/hide the session list column. Only rendered side-by-side: in compact
    /// the split view is already a stack whose back button does this job.
    @ToolbarContentBuilder
    private var sidebarToggle: some ToolbarContent {
        if isSideBySide {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        columnVisibility = sidebarHidden ? .doubleColumn : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .accessibilityIdentifier("toggleSidebar")
                .accessibilityLabel(sidebarHidden ? "Show sessions" : "Hide sessions")
                .help(sidebarHidden ? "Show sessions" : "Hide sessions")
            }
        }
    }
}

enum SwipeDirection {
    case left, right

    func matches(_ dx: CGFloat) -> Bool {
        switch self {
        case .left:  return dx < 0
        case .right: return dx > 0
        }
    }
}

/// A narrow invisible strip pinned to the leading edge of the detail column that
/// turns a rightward drag into "bring the sidebar back" — the platform's
/// edge-swipe convention, and the mirror of the swipe that dismissed it.
///
/// Edge-only, and only mounted while the sidebar is hidden: a full-width
/// gesture would sit over the transcript intercepting drags meant for the code
/// blocks that scroll horizontally inside it.
struct SwipeStrip: View {
    var direction: SwipeDirection
    var width: CGFloat = 20
    var action: () -> Void

    var body: some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let dx = value.translation.width
                        guard abs(dx) > abs(value.translation.height),
                              direction.matches(dx), abs(dx) >= 32 else { return }
                        action()
                    }
            )
            .accessibilityHidden(true)   // the toolbar button is the labelled control
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
        // `noNetwork` renders as nothing: it is a path blip still inside the
        // grace window, and bannering those instantly is the bug this build
        // fixes. Only `noNetworkSustained` has earned the treatment.
        case .live, .none, .unknown, .connecting, .degraded, .noNetwork:
            EmptyView()
        case .noNetworkSustained:
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
