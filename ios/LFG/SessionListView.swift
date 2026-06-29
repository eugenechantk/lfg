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
        var running = 0
        var idle = 0
    }

    /// Sessions passing the user filter + search query.
    private var matchingSessions: [Session] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return store.filteredSessions.filter { s in
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
                    : ListSection(id: "status-\(g.rawValue)", title: g.title, items: items)
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
                Text("\(section.items.count)").foregroundStyle(.tertiary)
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
                if store.reachability != .ok, store.reachability != nil {
                    Section { ConnectionBanner(reachability: store.reachability).listRowInsets(EdgeInsets()) }
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
    let session: Session
    let group: SessionStore.Group

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
                    Spacer(minLength: 0)
                    if let at = session.lastActivityAt {
                        Text(at.asRelativeFromMillis).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Top-bar connection status + count of currently-running sessions.
struct StatusBadge: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
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
