import SwiftUI
import LFGCore

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @State private var selection: String?
    private enum AppTab { case sessions, scheduledTasks }
    @State private var selectedTab = AppTab.sessions
    @State private var searchScope = AppTab.sessions
    @State private var sessionSearchText = ""
    @State private var taskSearchText = ""
    @State private var searchPresented = false
    @State private var searchActive = false
    @State private var bottomSafeArea: CGFloat = 0
    @State private var showNewTask = false
    @State private var focusNewTaskComposer = false
    @State private var taskPath: [ScheduledTaskRoute] = []
    /// Tasks waiting for an answer or with a failed latest run; the Tasks tab badge.
    @State private var taskNeedsInputCount = 0
    @State private var taskSessionID: String?
    @State private var showSettings = false
    @State private var showNewSession = false
    @State private var focusNewSessionComposer = false
    @State private var newSessionPrefill: NewSessionPrefill?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// True only where the split view actually shows two columns side by side
    /// (iPad full screen / wide multitasking). In compact it collapses to a
    /// navigation stack, where a "hide sidebar" control does nothing.
    private var isSideBySide: Bool { hSizeClass == .regular }
    private var usesSidebarDock: Bool { UIDevice.current.userInterfaceIdiom == .pad && isSideBySide }

    private var sidebarHidden: Bool { columnVisibility == .detailOnly }

    /// `lfg://new`: open New Session prefilled from the link. One main-actor hop
    /// first — on a cold launch the URL arrives during the initial render, and
    /// presenting the cover mid-update is the same hazard `openFromNotification`
    /// defers around.
    private func openNewSession(from link: NewSessionLink) {
        guard settings.hasConfiguredHost else { return }
        Task { @MainActor in
            await Task.yield()
            selectedTab = .sessions
            newSessionPrefill = NewSessionPrefill(link: link)
            focusNewSessionComposer = true
            showNewSession = true
        }
    }

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
                mainTabs
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
                selectedTab = .sessions
                selection = pending
                store.clearRequestedSelection()
            }
        }
        .onChange(of: store.requestedSelection) { _, requested in
            guard let requested else { return }
            selectedTab = .sessions
            selection = requested
            store.clearRequestedSelection()
        }
        .onChange(of: store.unreadCount, initial: true) { _, count in
            AppBadge.set(count)
        }
        .onOpenURL { url in
            switch LFGDeepLink.parse(url) {
            case .session(let sid):
                store.openFromNotification(sid)
            case .newSession(let link):
                openNewSession(from: link)
            case nil:
                break
            }
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

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Sessions", systemImage: "bubble.left.and.bubble.right", value: AppTab.sessions) {
                sessionsContent()
                    .toolbar(.hidden, for: .tabBar)
            }
            Tab("Tasks", systemImage: "calendar.badge.clock", value: AppTab.scheduledTasks) {
                tasksContent()
                    .toolbar(.hidden, for: .tabBar)
                    .newSessionPresentation(selection: $taskSessionID,
                        isPresented: $showNewTask, autofocusComposer: $focusNewTaskComposer,
                        prefill: .constant(nil), purpose: .scheduledTask)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .toolbar(.hidden, for: .tabBar)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeArea = $0 }
        .onChange(of: searchActive) { _, active in
            if !active { endSearch() }
        }
        .onChange(of: selectedTab) { _, _ in endSearch() }
        .onChange(of: selection) { _, id in
            if searchPresented, let id {
                store.focus(id)
                endSearch()
            }
        }
        .onChange(of: taskPath) { _, path in
            if !path.isEmpty { endSearch() }
        }
        .onChange(of: taskSessionID) { _, id in
            if id != nil { endSearch() }
        }
    }

    private var showsListDock: Bool {
        let showsSessionList = selection == nil && (!isSideBySide || !sidebarHidden)
        return !searchPresented && !showSettings && !showNewSession && !showNewTask
            && (selectedTab == .sessions ? showsSessionList : taskPath.isEmpty && taskSessionID == nil)
    }

    private var showsSidebarDock: Bool {
        usesSidebarDock && !sidebarHidden && !searchPresented
            && !showSettings && !showNewSession && !showNewTask
    }

    private var listFooter: AnyView? {
        guard usesSidebarDock ? showsSidebarDock : showsListDock else { return nil }
        // Preserve the dock's home-indicator spacing without shortening the
        // TabView and preventing rows from scrolling behind the controls.
        let lowering = UIDevice.current.userInterfaceIdiom == .phone
            ? min(16, max(0, bottomSafeArea - 16)) : 0
        return AnyView(listDock.padding(.bottom, -lowering))
    }

    private func searchFocus(for tab: AppTab) -> Binding<Bool> {
        Binding(get: { searchScope == tab && searchActive }, set: { focused in
            if searchScope == tab { searchActive = focused }
        })
    }

    private func beginSearch(_ scope: AppTab) {
        searchScope = scope
        searchPresented = true
        Task { @MainActor in
            await Task.yield()
            searchActive = true
        }
    }

    private func endSearch() {
        guard searchPresented else { return }
        searchActive = false
        searchPresented = false
        if searchScope == .sessions {
            sessionSearchText = ""
            store.setSearchQuery("")
        } else {
            taskSearchText = ""
        }
    }

    private var listDock: some View {
        GlassChromeContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    dockTab(.sessions, title: "Sessions", icon: "bubble.left.and.bubble.right.fill", id: "sessions_tab",
                            badge: needsInputCount)
                    dockTab(.scheduledTasks, title: "Tasks", icon: "calendar.badge.clock", id: "scheduled_tasks_tab",
                            badge: taskNeedsInputCount)
                }
                .padding(4)
                .glassOrRaised(in: Capsule(), interactive: true)
                Spacer(minLength: usesSidebarDock ? 0 : 12)
                Button {
                    if selectedTab == .scheduledTasks {
                        beginTaskCreation()
                    } else {
                        focusNewSessionComposer = true
                        showNewSession = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                // Glass wraps the button, as on the tab pill. Inside the list's
                // `safeAreaBar`, interactive glass on the label itself took
                // the touch and the button's action never ran.
                .glassOrRaised(in: Circle(), interactive: true)
                .accessibilityLabel(selectedTab == .scheduledTasks ? "New scheduled task" : "New session")
                .accessibilityIdentifier("list_create")
            }
        }
        // S2 board `s2-list`: the dock and plus sit 20 pt from the sides and
        // 28 pt from the bottom edge of the screen.
        .padding(.horizontal, usesSidebarDock ? 12 : 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("list_dock")
    }

    /// Amber Sessions badge (S2, canvas board `s2-list`): live sessions in Needs
    /// input, paused ones included. The Tasks badge is the task list's own count of
    /// tasks that need input or failed (`taskNeedsInputCount`).
    private var needsInputCount: Int {
        store.filteredSessions.filter {
            !$0.closed && SessionListSection(store.group(for: $0).rowGroup) == .needsInput
        }.count
    }

    private static let selectedTabInk = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x40 / 255, green: 0x9C / 255, blue: 0xFF / 255, alpha: 1)
        : UIColor(red: 0, green: 0x7A / 255, blue: 1, alpha: 1) })

    private func dockTab(_ tab: AppTab, title: String, icon: String, id: String, badge: Int = 0) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 3) {
                if tab == .scheduledTasks {
                    TasksTabGlyph().frame(width: 22, height: 20)
                } else if tab == .sessions {
                    SessionsTabGlyph().frame(width: 24, height: 20)
                } else {
                    Image(systemName: icon).font(.system(size: 20))
                }
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            // The board's selected blue (#409CFF), the same ink as "Mark all
            // read". accentColor resolves to iOS 26's #0091FF, a second blue.
            .foregroundStyle(selectedTab == tab ? Self.selectedTabInk : .primary)
            .frame(width: 88, height: 48)
            // The board's solid selected fill (#3A3A3C), not a tint on the glass.
            .background(selectedTab == tab ? S2.color(dark: 0x3A3A3C, light: 0xE5E5EA) : .clear, in: Capsule())
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255))
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255)))
                        .padding(.top, 4)
                        .padding(.trailing, 20)
                        .accessibilityIdentifier("\(id)_badge")
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) need input" : title)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func tasksContent() -> some View {
        ScheduledTasksView(hosts: settings.hosts.compactMap { host in
            guard let client = settings.client(for: host) else { return nil }
            return ScheduledTaskHost(id: host.id, name: host.label, baseURL: client.baseURL,
                headers: client.resourceRequest(for: client.baseURL).allHTTPHeaderFields ?? [:])
        }, searchQuery: $taskSearchText,
           navigationPath: $taskPath,
           showsSearchField: false,
           bottomSearchActive: searchFocus(for: .scheduledTasks),
           bottomSearchShown: searchPresented && searchScope == .scheduledTasks,
           sidebarVisibility: usesSidebarDock ? $columnVisibility : nil,
           listFooter: listFooter,
           connectionHeader: { width in AnyView(HostConnectionHeader(listWidth: width)) },
           connectionWarning: AnyView(HostConnectionWarning()),
           connectedHostIDs: Set(settings.hosts.filter { store.connectionStatus(forHost: $0.id) == .connected }.map(\.id)),
           usesBottomCreate: true,
           onSearch: { beginSearch(.scheduledTasks) },
           onCreate: beginTaskCreation,
           sessionSelection: $taskSessionID,
           sessionDestination: { AnyView(taskSessionView($0)) }, openSession: { hostID, id in
            taskSessionID = store.navID(id)
            Task { await store.prepareSessionForDisplay(id, sourceHostID: hostID) }
        }, onNeedsInputCountChange: { taskNeedsInputCount = $0 })
    }

    private func beginTaskCreation() {
        endSearch()
        selectedTab = .scheduledTasks
        taskPath = []
        focusNewTaskComposer = true
        showNewTask = true
    }

    @ViewBuilder
    private func taskSessionView(_ id: String) -> some View {
        if let session = store.session(id) {
            SessionDetailView(session: session,
                onEnded: { taskSessionID = nil },
                onMarkedUnread: { taskSessionID = nil })
                .id(id)
                .environment(\.hostFiles, store.host(forSession: session.sessionId ?? id)
                    .flatMap { settings.client(for: $0) }.map { HostFiles(client: $0) }
                    ?? settings.defaultClient.map { HostFiles(client: $0) })
                .toolbar(.hidden, for: .tabBar)
        } else {
            DetailLoading()
        }
    }

    private func sessionsContent() -> some View {
        let selectedSession = $selection
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            SessionListView(selection: selectedSession,
                            showSettings: $showSettings,
                            showNewSession: $showNewSession,
                            focusNewSessionComposer: $focusNewSessionComposer,
                            searchQuery: $sessionSearchText,
                            usesTabSearch: true,
                            onSearch: { beginSearch(.sessions) },
                            bottomSearchActive: searchFocus(for: .sessions),
                            bottomSearchShown: searchPresented && searchScope == .sessions,
                            listFooter: listFooter)
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
                .newSessionPresentation(selection: selectedSession,
                                        isPresented: $showNewSession,
                                        autofocusComposer: $focusNewSessionComposer,
                                        prefill: $newSessionPrefill)
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
                if let selection = selectedSession.wrappedValue {
                    if let session = store.session(selection) {
                        SessionDetailView(session: session,
                                          onEnded: { selectedSession.wrappedValue = nil },
                                          onMarkedUnread: { selectedSession.wrappedValue = nil })
                            .id(selection)
                            .toolbar {
                                if isSideBySide {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button("Sessions", systemImage: "chevron.left") {
                                            selectedSession.wrappedValue = nil
                                            setSidebar(hidden: false)
                                        }
                                        .accessibilityIdentifier("session_back_to_list")
                                    }
                                }
                            }
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

extension View {
    @ViewBuilder
    func scopedBottomSearch(text: Binding<String>, active: Binding<Bool>, shown: Bool,
                            prompt: String) -> some View {
        if !shown {
            self
        } else if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom != .pad {
            self
                .searchable(text: text, isPresented: active, placement: .toolbar, prompt: prompt)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
        } else {
            // iPad places SwiftUI search in the navigation bar even when a
            // bottom toolbar item is requested. Keep the system UISearchBar
            // at the bottom so the same action works in both layouts.
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                if shown {
                    HStack(spacing: 0) {
                        BottomNativeSearchField(text: text, active: active, prompt: prompt)
                            .frame(maxWidth: .infinity)
                        // UISearchBar ignores showsCancelButton on iPad.
                        Button("Cancel") { active.wrappedValue = false }
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.trailing, 8)
                            .accessibilityIdentifier("list_search_cancel")
                    }
                    .frame(height: 56)
                    .padding(.horizontal, 8)
                    .background(.bar)
                }
            }
        }
    }
}

private struct BottomNativeSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var active: Bool
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.delegate = context.coordinator
        bar.searchBarStyle = .minimal
        bar.showsCancelButton = false
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.autocapitalizationType = .none
        bar.autocorrectionType = .no
        bar.accessibilityIdentifier = "list_search_field"
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        bar.placeholder = prompt
        if bar.text != text { bar.text = text }
        if active, !context.coordinator.requestedFocus {
            context.coordinator.requestedFocus = true
            DispatchQueue.main.async { bar.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: BottomNativeSearchField
        var requestedFocus = false
        init(_ parent: BottomNativeSearchField) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.active = false
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
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
struct HostConnectionWarning: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        // Share Sessions' grace window and aggregate outage policy with Tasks.
        // Partial outages belong in the per-host header, not a fleet banner.
        if store.connectionStatus == .offline {
            ConnectionBanner(state: store.fleetState,
                offlineHosts: settings.hosts.count > 1
                    ? settings.hosts.filter { store.hostStateByHost[$0.id]?.isLive != true }.map(\.label)
                    : [])
        }
    }
}

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
        .accessibilityIdentifier("hostConnectionWarning")
    }
}

/// The Tasks tab icon, drawn from the S2 board's own SVG (outline calendar with
/// rings and a clock). SF Symbols' `calendar.badge.clock` is a solid calendar
/// with a dot grid, which the board does not use.
private struct TasksTabGlyph: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            // The SVG is 24×24 drawn into a 22×20 box: scale to fit the height
            // and center it horizontally, as the browser does.
            let k = geo.size.height / 24
            let dx = (geo.size.width - 24 * k) / 2
            let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: dx + x * k, y: y * k) }
            let stroke = StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, lineJoin: .round)
            ZStack {
                Path { p in
                    p.addRoundedRect(in: CGRect(origin: pt(2.5, 4.5), size: CGSize(width: 15 * k, height: 14 * k)),
                                     cornerSize: CGSize(width: 2 * k, height: 2 * k))
                    p.move(to: pt(2.5, 9)); p.addLine(to: pt(17.5, 9))
                    p.move(to: pt(6.5, 2.5)); p.addLine(to: pt(6.5, 6.5))
                    p.move(to: pt(13.5, 2.5)); p.addLine(to: pt(13.5, 6.5))
                }
                .stroke(style: stroke)
                // The clock knocks out the calendar corner it overlaps.
                Circle()
                    .fill(colorScheme == .dark ? Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x26 / 255) : Color(.systemBackground))
                    .frame(width: 8.4 * k, height: 8.4 * k)
                    .position(pt(18, 17))
                Path { p in
                    p.addEllipse(in: CGRect(origin: pt(13.8, 12.8), size: CGSize(width: 8.4 * k, height: 8.4 * k)))
                    p.move(to: pt(18, 15.3)); p.addLine(to: pt(18, 17)); p.addLine(to: pt(19.2, 18))
                }
                .stroke(style: stroke)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The board's Sessions tab glyph (`s2-list`): two filled speech bubbles, the
/// left one in front. Drawn from its SVG (26×22 box, fit into 24×20).
private struct SessionsTabGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / 26, geo.size.height / 22)
            let ox = (geo.size.width - 26 * k) / 2, oy = (geo.size.height - 22 * k) / 2
            let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: ox + x * k, y: oy + y * k) }
            Path { p in
                // Left bubble, tail at the bottom left.
                p.move(to: pt(3, 1))
                p.addLine(to: pt(15, 1))
                p.addArc(center: pt(15, 3.5), radius: 2.5 * k, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
                p.addLine(to: pt(17.5, 10.5))
                p.addArc(center: pt(15, 10.5), radius: 2.5 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                p.addLine(to: pt(8.5, 13))
                p.addLine(to: pt(4, 16.5))
                p.addLine(to: pt(4, 13))
                p.addLine(to: pt(3, 13))
                p.addArc(center: pt(3, 10.5), radius: 2.5 * k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                p.addLine(to: pt(0.5, 3.5))
                p.addArc(center: pt(3, 3.5), radius: 2.5 * k, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                p.closeSubpath()
                // Right bubble, notched around the left one's corner.
                p.move(to: pt(19.5, 6))
                p.addLine(to: pt(23, 6))
                p.addArc(center: pt(23, 8.5), radius: 2.5 * k, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
                p.addLine(to: pt(25.5, 15))
                p.addArc(center: pt(23, 15), radius: 2.5 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                p.addLine(to: pt(22, 17.5))
                p.addLine(to: pt(22, 21))
                p.addLine(to: pt(18, 17.5))
                p.addLine(to: pt(12, 17.5))
                p.addQuadCurve(to: pt(9.6, 15.2), control: pt(9.6, 17.5))
                p.addLine(to: pt(15.5, 15.2))
                p.addArc(center: pt(15.5, 11.2), radius: 4 * k, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
                p.closeSubpath()
            }
            .fill()
        }
        .accessibilityHidden(true)
    }
}
