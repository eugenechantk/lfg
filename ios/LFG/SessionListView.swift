import SwiftUI
import LFGCore

struct SessionListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @Binding var selection: String?
    @Binding var showSettings: Bool
    @Binding var showNewSession: Bool
    @State private var searchText = ""

    /// Directory sections the user has expanded (keyed by section id). Directory
    /// sections are collapsed by default, so a section is open only while its id
    /// is in this set. In-memory per the current run; directory mode only.
    @State private var expandedDirs: Set<String> = []

    /// One rendered section of the list: a header title + its sessions, plus the
    /// running/idle tallies shown on a directory section's collapsible header.
    private struct ListSection: Identifiable {
        let id: String
        let title: String
        let items: [Session]
        var group: SessionStore.Group? = nil
        var running = 0
        var idle = 0
    }

    /// Sessions passing the user filter + host filter + search query.
    private var matchingSessions: [Session] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return store.filteredSessions.filter { s in
            // Host filter (multi-host): keep the selected host's live sessions;
            // closed sessions are host-agnostic, so they always pass.
            if let hf = settings.hostFilter, !s.closed, store.hostBySession[s.id] != hf {
                return false
            }
            guard !q.isEmpty else { return true }
            return [s.title, s.project, s.lastUserText, s.model, s.assignedUser]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(q) }
        }
    }

    /// The matching sessions grouped per the active `GroupMode`: by status
    /// (Needs you / Paused / Working / Idle) or by directory.
    private var visibleSections: [ListSection] {
        let base = matchingSessions
        switch settings.groupMode {
        case .status:
            return SessionStore.Group.allCases.compactMap { g in
                let items = base.filter { store.group(for: $0) == g }
                    .sorted { ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) }
                return items.isEmpty ? nil
                    : ListSection(id: "status-\(g.rawValue)", title: g.title, items: items, group: g)
            }
        case .directory:
            let byDir = Dictionary(grouping: base) { Self.dirKey(for: $0) }
            return byDir.map { key, items in
                let sorted = items.sorted { ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) }
                let running = sorted.filter { store.group(for: $0) == .working }.count
                let idle = sorted.filter { store.group(for: $0) == .idle }.count
                return ListSection(id: "dir-\(key)", title: Self.dirLabel(for: sorted[0]),
                                   items: sorted, running: running, idle: idle)
            }
            // Most-recently-active directory first, so where the action is floats up.
            .sorted { ($0.items.first?.lastActivityAt ?? 0) > ($1.items.first?.lastActivityAt ?? 0) }
        }
    }

    /// Stable grouping key for a session's directory: its working dir, else the
    /// friendly project name, else a shared "no directory" bucket.
    private static func dirKey(for s: Session) -> String {
        if let cwd = s.cwd, !cwd.isEmpty { return cwd }
        if let project = s.project, !project.isEmpty { return project }
        return ""
    }

    /// Human label for a directory section: the working dir's leaf component
    /// (cleanest "directory" name), else the friendly project name, else a
    /// placeholder.
    private static func dirLabel(for s: Session) -> String {
        if let cwd = s.cwd, !cwd.isEmpty,
           let leaf = cwd.split(separator: "/").last {
            return String(leaf)
        }
        if let project = s.project, !project.isEmpty { return project }
        return "No directory"
    }

    private func isCollapsed(_ section: ListSection) -> Bool {
        settings.groupMode == .directory && !expandedDirs.contains(section.id)
    }

    /// Directory headers are tappable to collapse/expand and carry running + idle
    /// tallies; status headers keep the plain title + total count.
    @ViewBuilder
    private func sectionHeader(_ section: ListSection) -> some View {
        if settings.groupMode == .directory {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedDirs.contains(section.id) { expandedDirs.remove(section.id) }
                    else { expandedDirs.insert(section.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expandedDirs.contains(section.id) ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(section.title.uppercased())
                    Spacer()
                    countBadge(.working, section.running)
                    countBadge(.idle, section.idle)
                }
                .font(.caption2.weight(.semibold))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text(section.title.uppercased())
                Spacer()
                if section.group == .unread {
                    Button("Mark all read") { store.markAllRead() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .textCase(nil)
                } else {
                    Text("\(section.items.count)").foregroundStyle(.tertiary)
                }
            }
            .font(.caption2.weight(.semibold))
        }
    }

    /// A small status-colored dot + count (running = green, idle = gray), dimmed
    /// when zero so a directory's live work reads at a glance.
    private func countBadge(_ group: SessionStore.Group, _ count: Int) -> some View {
        HStack(spacing: 3) {
            Circle().fill(Theme.statusColor(group)).frame(width: 6, height: 6)
                .opacity(count > 0 ? 1 : 0.35)
            Text("\(count)").foregroundStyle(count > 0 ? .secondary : .tertiary)
        }
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            // Search lives above the session list, in the content area — detached
            // from the nav-bar header (status badge) rather than docked into it.
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)

            Picker("Group by", selection: $settings.groupMode) {
                ForEach(GroupMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            List(selection: $selection) {
                // The banner only appears when the AGGREGATE is unhealthy — i.e.
                // every configured host is down. A single host being offline
                // leaves the aggregate `.ok` (some host still answers), so this
                // stays hidden and the app keeps working; the top-bar per-host
                // chips carry the partial-outage story instead.
                if store.reachability != .ok, store.reachability != nil {
                    Section {
                        // Name only the hosts that are actually down. When the
                        // aggregate is unhealthy that is every host — but deriving
                        // it rather than assuming it keeps the banner honest if the
                        // guard above ever loosens.
                        ConnectionBanner(reachability: store.reachability,
                                         offlineHosts: settings.hosts.count > 1
                                            ? settings.hosts.filter { store.reachabilityByHost[$0.id] != .ok }.map(\.label)
                                            : [])
                            .listRowInsets(EdgeInsets())
                    }
                    .listRowBackground(Color.clear)
                }

                let sections = visibleSections
                if sections.isEmpty {
                    Section {
                        EmptyListState(connected: store.isConnected) { showNewSession = true }
                            .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(sections) { section in
                        Section {
                            if !isCollapsed(section) {
                                ForEach(section.items) { session in
                                    SessionRow(session: session, group: store.group(for: session))
                                        .tag(session.sessionId ?? "")
                                }
                                if section.group == .closed, store.canLoadMoreClosed {
                                    Button {
                                        Task { await store.loadMoreClosed() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            if store.isLoadingMoreClosed {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Image(systemName: "chevron.down.circle")
                                            }
                                            Text(store.isLoadingMoreClosed ? "Loading more" : "Load more")
                                            Spacer()
                                        }
                                        .foregroundStyle(.tint)
                                        .padding(.vertical, 4)
                                        // Hit-test the whole row, Spacer included: a
                                        // plain button's default content shape skips
                                        // transparent space, so taps there fell through
                                        // to List selection with no valid tag (a stuck
                                        // "Opening session…" push).
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(store.isLoadingMoreClosed)
                                    .accessibilityIdentifier("loadMoreClosedButton")
                                }
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await store.refresh() }
        }
        // iPad sidebar: a tall native large-title header with the connection
        // status as a subtitle (iPadOS 26 `navigationSubtitle`). iPhone keeps the
        // compact centered status badge in the top bar.
        .navigationTitle(isPad ? "Sessions" : "")
        .navigationBarTitleDisplayMode(isPad ? .large : .inline)
        .sidebarStatusSubtitle(isPad ? statusSubtitle : nil)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            if !isPad {
                ToolbarItem(placement: .principal) { StatusBadge() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewSession = true } label: { Image(systemName: "plus") }
            }
        }
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var statusSubtitle: String {
        // Multi-host: name which hosts are online vs offline (the iPad sidebar has
        // no principal StatusBadge, so this subtitle carries the per-host status).
        if settings.hosts.count > 1 {
            let online = settings.hosts.filter { store.reachabilityByHost[$0.id] == .ok }
            let offline = settings.hosts.filter { store.reachabilityByHost[$0.id] != .ok }
            var parts: [String] = []
            if !online.isEmpty { parts.append("\(online.map(\.label).joined(separator: ", ")) online") }
            if !offline.isEmpty { parts.append("\(offline.map(\.label).joined(separator: ", ")) offline") }
            return parts.joined(separator: " · ")
        }
        guard store.isConnected else { return "Offline" }
        let n = store.runningCount
        return n > 0 ? "Connected · \(n) running" : "Connected"
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search sessions", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension View {
    /// Apply a navigation-bar subtitle where supported (iPadOS/iOS 26+), giving a
    /// taller two-line title; no-op on earlier OSes and when `text` is nil.
    @ViewBuilder
    func sidebarStatusSubtitle(_ text: String?) -> some View {
        if #available(iOS 26.0, *), let text {
            self.navigationSubtitle(text)
        } else {
            self
        }
    }
}

struct SessionRow: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    let session: Session
    let group: SessionStore.Group

    /// Owning host's short label, shown only in multi-host setups for live
    /// sessions (closed sessions are host-agnostic).
    private var hostLabel: String? {
        guard settings.hosts.count > 1 else { return nil }
        return store.host(forSession: session.id)?.label
    }

    /// Live on a host that is currently down — the session's agent is unreachable,
    /// so the row is dimmed and its host chip goes orange. Without this the row
    /// renders as a healthy Running session and tapping it opens a composer whose
    /// sends can never land.
    private var isOffline: Bool { store.isOffline(session.id) }

    var body: some View {
        HStack(spacing: 12) {
            AgentBadge(agent: session.agent)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title.isEmpty ? "Untitled session" : session.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusDot(group: group)
                    if let project = session.project, !project.isEmpty {
                        Text(project)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)   // ellipsis the start, keep the end visible
                    }
                    if let model = session.model { ModelBadge(model: model) }
                    if let hostLabel {
                        HStack(spacing: 3) {
                            if isOffline {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                            }
                            Text(hostLabel).lineLimit(1)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(isOffline ? Color.orange.opacity(0.15) : Color(.tertiarySystemFill),
                                    in: Capsule())
                        .foregroundStyle(isOffline ? Color.orange : Color.secondary)
                    }
                    Spacer(minLength: 0)
                    if let at = session.lastActivityAt {
                        Text(at.asRelativeFromMillis).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        // Dim the row so a stale (unreachable) session doesn't compete with live
        // ones. The orange host chip dims with it, but stays the only warm-colored
        // element in the row, so it still reads as the reason for the dimming.
        .opacity(isOffline ? 0.55 : 1)
    }
}

/// Top-bar connection status. Single host → a "Connected/Offline" badge plus the
/// running count. Multiple hosts → one dot+label chip per host so you can see at
/// a glance which host is online (green) and which is offline (orange).
struct StatusBadge: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.hosts.count > 1 {
            HStack(spacing: 12) {
                ForEach(settings.hosts) { host in
                    HostStatusChip(host: host,
                                   online: store.reachabilityByHost[host.id] == .ok)
                }
            }
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(store.isConnected ? "Connected" : "Offline")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(store.isConnected ? Color.primary : Color.orange)
                if store.runningCount > 0 {
                    Text("· \(store.runningCount) running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A single host's online/offline status: a colored dot (green online, orange
/// offline) + the host's short label. Offline labels go orange so the down host
/// stands out in the top bar.
private struct HostStatusChip: View {
    let host: Host
    let online: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(online ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(host.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(online ? Color.primary : Color.orange)
                .lineLimit(1)
        }
    }
}

struct EmptyListState: View {
    let connected: Bool
    let onNew: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: connected ? "tray" : "wifi.slash")
                .font(.system(size: 34)).foregroundStyle(.secondary)
            Text(connected ? "No running sessions" : "Not connected")
                .font(.headline)
            Text(connected ? "Start a session to drive an agent."
                           : "Set your host in Settings and make sure you're on the tailnet.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if connected {
                Button(action: onNew) {
                    Label("New session", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
