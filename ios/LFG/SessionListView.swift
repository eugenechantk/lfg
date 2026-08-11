import SwiftUI
import LFGCore

/// The screen's palette: semantic where the design value genuinely IS a system
/// color, explicitly adaptive where it isn't.
///
/// Some of the design's values are exactly the dark variant of a UIKit semantic
/// color — measured back byte-for-byte: `#000000` = systemBackground, `#1C1C1E`
/// = secondarySystemBackground, `rgba(235,235,245,0.60)` = secondaryLabel,
/// `0.30` = tertiaryLabel. Those bind to the semantic name and are exact.
///
/// But the design ALSO uses `0.50`, `0.45`, `0.40` label inks and a `0.07` white
/// hairline, and none of those has a semantic equivalent. An earlier version of
/// this file assumed they all did and rounded each to the nearest system color,
/// which shifted four inks (meta text read 0.60 instead of 0.50, the chevron
/// 0.30 instead of 0.40, the placeholder 0.30 instead of 0.45, and the
/// separator picked up systemSeparator's blue tint). Those are built explicitly
/// below, off Apple's own label base colors, so they stay exact in dark and
/// still adapt to light.
private enum Tokens {
    /// Apple's label ink at an arbitrary alpha: `(235,235,245)` on dark,
    /// `(60,60,67)` on light — the same bases the semantic label colors use, so
    /// an explicit alpha lands on the same ramp rather than beside it.
    private static func labelInk(_ alpha: CGFloat) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: alpha)
            : UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: alpha) })
    }

    // Exact semantic matches.
    static let screen = Color(.systemBackground)
    static let raised = Color(.secondarySystemBackground)
    static let labelSecondary = Color(.secondaryLabel)   // 0.60
    static let tertiary = Color(.tertiaryLabel)          // 0.30
    static let label = Color(.label)
    static let accent = Color.accentColor

    // No semantic equivalent — built to the design's exact alpha.
    static let meta = labelInk(0.50)
    static let host = labelInk(0.40)
    /// A plain white/black wash, NOT `Color(.separator)` — the system separator
    /// is blue-tinted `(84,84,88,0.65)` and read back `(42,42,44)` against the
    /// design's `(18,18,18)`.
    static let separator = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.07)
        : UIColor(white: 0, alpha: 0.07) })
}

struct SessionListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @Binding var selection: String?
    @Binding var showSettings: Bool
    @Binding var showNewSession: Bool
    @Binding var focusNewSessionComposer: Bool
    @State private var searchText = ""
    @State private var sortMenuHighlight = false

    /// Collapsible UI state is in-memory per the current run. Sections default
    /// expanded, and only store their id here after the user collapses them.
    @State private var collapsedSections: Set<String> = []
    @State private var expandedAgentParents: Set<String> = []

    /// One rendered section of the list: a header title + its sessions, plus the
    /// running/idle tallies shown on a directory section's collapsible header.
    private struct ListSection: Identifiable {
        let id: String
        let title: String
        let items: [Session]
        var group: SessionStore.Group? = nil
        var isAgents = false
        var childrenByParentId: [String: [Session]] = [:]
        var running = 0
        var idle = 0
    }

    private struct RenderedSessionRow: Identifiable {
        let id: String
        let session: Session
        let children: [Session]
        let indent: CGFloat
    }

    /// Sessions passing the user filter + host filter + search query.
    ///
    /// While searching this is a UNION of two sources, because the loaded list is
    /// not the whole population. Live sessions are matched here — the client
    /// holds all of them — and closed ones come from `store.searchResults`, which
    /// the host matched across every transcript it has rather than across the
    /// pages that happen to be in memory. Before that, typing a word only ever
    /// searched the ~60 closed sessions per host the user had already paged in.
    private var matchingSessions: [Session] {
        let terms = SessionSearch.terms(searchText)
        let local = store.filteredSessions.filter { s in
            // Host filter (multi-host): keep the selected host's live sessions;
            // closed sessions are host-agnostic, so they always pass.
            if let hf = settings.hostFilter, !s.closed, store.hostBySession[s.id] != hf {
                return false
            }
            return SessionSearch.matches(
                terms: terms,
                fields: [s.title, s.project, s.cwd, s.lastUserText, s.model, s.assignedUser])
        }
        guard !terms.isEmpty else { return local }

        // Dedupe by id: a match the host returned may already be on screen as a
        // loaded closed row, and two rows for one conversation would break List
        // selection as well as looking wrong.
        var seen = Set(local.map(\.id))
        var out = local
        for s in store.searchResults where !seen.contains(s.id) {
            seen.insert(s.id)
            out.append(s)
        }
        return out
    }

    /// The matching sessions grouped per the active `GroupMode`.
    private var visibleSections: [ListSection] {
        let base = matchingSessions
        switch effectiveGroupMode {
        case .status:
            if isSearching {
                return statusSections(for: base)
            }
            let grouped = statusAgentGrouping(for: base)
            var sections = statusSections(for: grouped.regular,
                                          childrenByParentId: grouped.childrenByParentId)
            if !grouped.orphanAgents.isEmpty {
                sections.append(ListSection(id: "status-agents", title: "Agents",
                                            items: grouped.orphanAgents, isAgents: true))
            }
            return sections
        case .directory:
            let byDir = Dictionary(grouping: base) { Self.dirKey(for: $0) }
            return byDir.map { key, items in
                let sorted = sortedSessions(items)
                let running = sorted.filter { store.group(for: $0) == .working }.count
                let idle = sorted.filter { store.group(for: $0) == .idle }.count
                return ListSection(id: "dir-\(key)", title: Self.dirLabel(for: sorted[0]),
                                   items: sorted, running: running, idle: idle)
            }
            // Most-recently-active directory first, so where the action is floats up.
            .sorted { ($0.items.first?.lastActivityAt ?? 0) > ($1.items.first?.lastActivityAt ?? 0) }
        case .host:
            let byHost = Dictionary(grouping: base) { session in
                store.host(forSession: session.id)?.id ?? "unknown"
            }
            var sections: [ListSection] = settings.hosts.compactMap { host in
                guard let items = byHost[host.id], !items.isEmpty else { return nil }
                return ListSection(id: "host-\(host.id)", title: host.label,
                                   items: sortedSessions(items))
            }
            if let unknown = byHost["unknown"], !unknown.isEmpty {
                sections.append(ListSection(id: "host-unknown", title: "Unknown host",
                                            items: sortedSessions(unknown)))
            }
            return sections
        }
    }

    private var effectiveGroupMode: GroupMode {
        settings.groupMode == .host && settings.hosts.count <= 1 ? .status : settings.groupMode
    }

    private var groupModeOptions: [GroupMode] {
        settings.hosts.count > 1 ? GroupMode.allCases : GroupMode.allCases.filter { $0 != .host }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sortedSessions(_ sessions: [Session]) -> [Session] {
        switch settings.sortMode {
        case .recentActivity:
            return sessions.sorted {
                if ($0.lastActivityAt ?? 0) == ($1.lastActivityAt ?? 0) {
                    return $0.id < $1.id
                }
                return ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0)
            }
        case .name:
            return sessions.sorted {
                let lhs = title(for: $0).localizedCaseInsensitiveCompare(title(for: $1))
                if lhs == .orderedSame {
                    return ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0)
                }
                return lhs == .orderedAscending
            }
        }
    }

    private func title(for session: Session) -> String {
        session.title.isEmpty ? "Untitled session" : session.title
    }

    private func statusSections(
        for sessions: [Session],
        childrenByParentId: [String: [Session]] = [:]
    ) -> [ListSection] {
        SessionStore.Group.allCases.compactMap { g in
            let items = sessions.filter { store.group(for: $0) == g }
            let sorted = sortedSessions(items)
            return sorted.isEmpty ? nil
                : ListSection(id: "status-\(g.rawValue)", title: g.title, items: sorted,
                              group: g, childrenByParentId: childrenByParentId)
        }
    }

    private func statusAgentGrouping(
        for sessions: [Session]
    ) -> (regular: [Session], childrenByParentId: [String: [Session]], orphanAgents: [Session]) {
        let visibleParentIds = Set(sessions.compactMap { normalizedId($0.sessionId) })
        let agentCandidates = sessions.filter { statusAgentParentId(for: $0) != nil }
        let candidateIds = Set(agentCandidates.map(\.id))
        let childAgents = agentCandidates.filter { session in
            guard let parentId = statusAgentParentId(for: session) else { return false }
            return visibleParentIds.contains(parentId)
        }
        let orphanAgents = agentCandidates.filter { session in
            guard let parentId = statusAgentParentId(for: session) else { return false }
            return !visibleParentIds.contains(parentId)
        }
        let childrenByParentId = Dictionary(grouping: childAgents) { session in
            statusAgentParentId(for: session) ?? ""
        }
        .mapValues { items in
            sortedSessions(items)
        }
        let regular = sessions.filter { !candidateIds.contains($0.id) }
        return (regular,
                childrenByParentId,
                sortedSessions(orphanAgents))
    }

    private func statusAgentParentId(for session: Session) -> String? {
        guard store.group(for: session) != .needsInput else { return nil }
        return normalizedId(session.parentSessionId)
    }

    private func normalizedId(_ value: String?) -> String? {
        guard let id = value?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        return id
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
        collapsedSections.contains(section.id)
    }

    private func toggleSection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if collapsedSections.contains(id) {
                collapsedSections.remove(id)
            } else {
                collapsedSections.insert(id)
            }
        }
    }

    /// Section headers are collapsible in every grouping mode. The Unread
    /// section keeps its mark-all-read action because the design mock lacked
    /// unread data, not because the workflow should disappear.
    @ViewBuilder
    private func expandedSectionHeader(_ section: ListSection) -> some View {
        HStack(spacing: 0) {
            Button { toggleSection(section.id) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Tokens.host)
                        .frame(width: 13, height: 13)
                    Text(section.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.labelSecondary)
                        .lineLimit(1)
                    Text("\(section.items.count)")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.tertiary)
                    // The trailing spacer lives INSIDE the button's label so the
                    // whole header row toggles, not just the text. With the
                    // spacer outside, the row's accessibility frame spans the
                    // full width while the hit area covers only the leading
                    // text — a tap anywhere right of the count (including the
                    // centre, where synthetic taps land) silently did nothing.
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if section.group == .unread {
                Button("Mark all read") { store.markAllRead() }
                    .font(.system(size: 13, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Tokens.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .textCase(nil)
        .listRowSeparator(.hidden)
        .listRowBackground(Tokens.screen)
        // Section headers do NOT inherit the zero row insets the rows get, so
        // without this the header sits ~15pt further right than its own rows
        // (measured: chevron at x=36.7 against the design's x=22) and carries
        // extra vertical padding of its own.
        .accessibilityIdentifier("sessionGroupHeader-\(section.id)")
        .listRowInsets(EdgeInsets())
        .listRowBackground(Tokens.screen)
    }

    private func collapsedSectionRow(_ section: ListSection) -> some View {
        Button { toggleSection(section.id) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Tokens.host)
                        .frame(width: 13, height: 13)
                    Text(section.title)
                        .font(.system(size: 17))
                        .foregroundStyle(Tokens.label)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(section.items.count)")
                        .font(.system(size: 17))
                        .foregroundStyle(Tokens.tertiary)
                }
                .frame(height: 54)
                .padding(.horizontal, 20)
                Rectangle()
                    .fill(Tokens.separator)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sessionGroupHeader-\(section.id)")
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Tokens.screen)
    }

    private func renderedRows(for section: ListSection) -> [RenderedSessionRow] {
        guard effectiveGroupMode == .status,
              !section.isAgents,
              !section.childrenByParentId.isEmpty else {
            return section.items.map {
                RenderedSessionRow(id: $0.id, session: $0, children: [], indent: 0)
            }
        }

        var rows: [RenderedSessionRow] = []
        var path: Set<String> = []
        for session in section.items {
            appendRenderedRows(for: session, depth: 0, section: section, path: &path, rows: &rows)
        }
        return rows
    }

    private func appendRenderedRows(
        for session: Session,
        depth: Int,
        section: ListSection,
        path: inout Set<String>,
        rows: inout [RenderedSessionRow]
    ) {
        let parentId = normalizedId(session.sessionId)
        let children: [Session]
        if let parentId, !path.contains(parentId) {
            children = section.childrenByParentId[parentId] ?? []
        } else {
            children = []
        }

        rows.append(RenderedSessionRow(id: "\(depth)-\(session.id)",
                                       session: session,
                                       children: children,
                                       indent: CGFloat(depth) * 24))

        guard let parentId,
              expandedAgentParents.contains(parentId),
              !children.isEmpty,
              !path.contains(parentId) else { return }
        path.insert(parentId)
        for child in children {
            appendRenderedRows(for: child, depth: depth + 1, section: section, path: &path, rows: &rows)
        }
        path.remove(parentId)
    }

    @ViewBuilder
    private func sessionRow(_ row: RenderedSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionRow(session: row.session, group: store.group(for: row.session))
                .padding(.leading, row.indent)
            if !row.children.isEmpty, let parentId = normalizedId(row.session.sessionId) {
                agentDisclosure(parentId: parentId, children: row.children)
                    .padding(.leading, row.indent)
            }
            Rectangle()
                .fill(Tokens.separator)
                .frame(height: 1)
                .padding(.leading, row.indent + 39)
        }
        .contentShape(Rectangle())
        .tag(row.session.sessionId ?? "")
        .accessibilityIdentifier("sessionRow-\(row.session.id)")
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Tokens.screen)
    }

    private func agentDisclosure(parentId: String, children: [Session]) -> some View {
        let isExpanded = expandedAgentParents.contains(parentId)
        let running = children.filter { store.group(for: $0) == .working }.count
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedAgentParents.contains(parentId) { expandedAgentParents.remove(parentId) }
                else { expandedAgentParents.insert(parentId) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text(agentCountText(children.count))
                if running > 0 {
                    Text("· \(running) running")
                }
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func agentCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "agent" : "agents")"
    }

    /// The footer that pulls another page — shared by the closed list and by
    /// search, which paginate independently of each other.
    @ViewBuilder
    private func loadMoreRow(title: String,
                             loading: Bool,
                             identifier: String,
                             action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.down.circle")
                }
                Text(loading ? "Loading more" : title)
                Spacer()
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            // Hit-test the whole row, Spacer included: a plain button's default
            // content shape skips transparent space, so taps there fell through
            // to List selection with no valid tag (a stuck "Opening session…"
            // push).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityIdentifier(identifier)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Tokens.screen)
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            customHeader(groupMode: $settings.groupMode, sortMode: $settings.sortMode)

            List(selection: $selection) {
                // The banner only appears when the AGGREGATE is unhealthy — i.e.
                // every configured host is down. A single host being offline
                // leaves the aggregate `.ok` (some host still answers), so this
                // stays hidden and the app keeps working; the top-bar per-host
                // chips carry the partial-outage story instead.
                // …and never while a launch/foreground reconnect burst is still
                // running: a probe that hasn't been retried yet is not an outage,
                // and a banner that appears for a second on every cold launch
                // trains you to ignore it.
                if store.connectionStatus == .offline {
                    Section {
                        // Name only the hosts that are actually down. When the
                        // aggregate is unhealthy that is every host — but deriving
                        // it rather than assuming it keeps the banner honest if the
                        // guard above ever loosens.
                        ConnectionBanner(state: store.fleetState,
                                         offlineHosts: settings.hosts.count > 1
                                            ? settings.hosts.filter { store.hostStateByHost[$0.id]?.isLive != true }.map(\.label)
                                            : [])
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Tokens.screen)
                    }
                }

                let sections = visibleSections
                if sections.isEmpty, isSearching, store.isSearchLoading {
                    // The host is still walking its transcripts. "No sessions"
                    // here would be a lie — the answer just hasn't landed.
                    Section {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Searching all sessions…")
                                .foregroundStyle(Tokens.meta)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .accessibilityIdentifier("searchInFlight")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Tokens.screen)
                    }
                } else if sections.isEmpty, isSearching {
                    Section {
                        VStack(spacing: 6) {
                            Text("No matching sessions")
                                .font(.headline)
                                .foregroundStyle(Tokens.label)
                            Text("Searched every session on your hosts.")
                                .font(.subheadline)
                                .foregroundStyle(Tokens.meta)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .accessibilityIdentifier("searchNoResults")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Tokens.screen)
                    }
                } else if sections.isEmpty {
                    Section {
                        EmptyListState(connected: store.isConnected) {
                            openNewSession(focusComposer: false)
                        }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Tokens.screen)
                    }
                } else {
                    ForEach(sections) { section in
                        if isCollapsed(section) {
                            Section {
                                collapsedSectionRow(section)
                            }
                        } else {
                            Section {
                                // The group header is a normal ROW, not a
                                // `Section(header:)`. A plain List pins section
                                // headers, and these headers are transparent —
                                // so rows scrolled underneath drew straight
                                // through the header text. The design shows
                                // groups scrolling away as a unit, so making it
                                // a row fixes the collision and the header's
                                // extra built-in top padding at the same time.
                                expandedSectionHeader(section)
                                ForEach(renderedRows(for: section)) { row in
                                    sessionRow(row)
                                }
                                // Search has its OWN pagination — the host is
                                // walking every transcript it has, not the list's
                                // loaded pages — so while searching this footer
                                // pulls the next page of MATCHES, not the next
                                // page of closed sessions.
                                if section.group == .closed {
                                    if isSearching {
                                        if store.canLoadMoreSearch {
                                            loadMoreRow(title: "Load more results",
                                                        loading: store.isLoadingMoreSearch,
                                                        identifier: "loadMoreSearchButton") {
                                                await store.loadMoreSearchResults()
                                            }
                                        }
                                    } else if store.canLoadMoreClosed {
                                        loadMoreRow(title: "Load more",
                                                    loading: store.isLoadingMoreClosed,
                                                    identifier: "loadMoreClosedButton") {
                                            await store.loadMoreClosed()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Tokens.screen)
            .refreshable { await store.refresh() }
            .listSectionSpacing(0)
        }
        .background(Tokens.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // The bottom chrome is now the system search field + a plus button, not
        // the old faux-composer capsule. On iOS 26 that is Apple's own bottom
        // search toolbar (`.searchable` + `DefaultToolbarItem(kind: .search)`),
        // so it gets the platform's minimize/expand behaviour for free; older
        // OSes have no such API and fall back to a hand-built equivalent.
        .bottomSearchChrome(text: $searchText) { openNewSession(focusComposer: false) }
        // Hand every keystroke to the store, which debounces and queries the
        // hosts. Local filtering alone can't answer "search all my sessions" —
        // it only ever sees what pagination has loaded.
        .onChange(of: searchText) { _, q in store.setSearchQuery(q) }
        // Re-sync rather than clear: on iPhone this view disappears whenever a
        // session is pushed, and clearing there would strand a still-populated
        // field with no results and no keystroke left to trigger a re-query.
        // `setSearchQuery` no-ops when the query is unchanged.
        .onAppear { store.setSearchQuery(searchText) }
    }

    private func openNewSession(focusComposer: Bool) {
        focusNewSessionComposer = focusComposer
        showNewSession = true
    }

    private func customHeader(
        groupMode: Binding<GroupMode>,
        sortMode: Binding<SortMode>
    ) -> some View {
        HStack(alignment: .center) {
            // The title slot carries host status rather than a static "All
            // sessions": the label the design showed is the one thing on this
            // screen that never tells you anything, and replacing the nav bar
            // had otherwise dropped the connection state entirely on iPhone.
            HeaderStatusLine()
                .layoutPriority(1)
            .accessibilityIdentifier("sessionListHeader")
            Spacer(minLength: 12)
            GlassChromeContainer(spacing: 10) {
                HStack(spacing: 10) {
                    // No search toggle here anymore — search lives in the bottom
                    // bar, where the system puts it on iOS 26.
                    groupSortMenu(groupMode: groupMode, sortMode: sortMode)
                    headerButton("gearshape", size: 16, weight: .regular) { showSettings = true }
                        .accessibilityIdentifier("sessionSettingsButton")
                }
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private func headerButton(
        _ systemName: String,
        size: CGFloat,
        weight: Font.Weight = .medium,
        background: Color = Tokens.raised,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(Tokens.label)
                .frame(width: 38, height: 38)
                .glassOrRaised(in: Circle(), fallback: background, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func groupSortMenu(
        groupMode: Binding<GroupMode>,
        sortMode: Binding<SortMode>
    ) -> some View {
        Menu {
            // Plain buttons inside a titled `Section`, NOT a `Picker`. UIKit
            // renders a menu section's header only when its children are menu
            // elements it owns; an inline `Picker` (either bare or wrapped in a
            // Section) produces the right options and checkmarks but silently
            // drops both "GROUP BY" and "SORT BY" titles. The design leans on
            // those titles to tell two adjacent option groups apart, so we
            // build the rows ourselves and carry the checkmark explicitly.
            Section("GROUP BY") {
                ForEach(groupModeOptions) { mode in
                    Button { groupMode.wrappedValue = mode } label: {
                        Label(mode.label,
                              systemImage: groupMode.wrappedValue == mode ? "checkmark" : "")
                    }
                    .accessibilityIdentifier("groupModeOption-\(mode.rawValue)")
                }
            }
            Section("SORT BY") {
                ForEach(SortMode.allCases) { mode in
                    Button { sortMode.wrappedValue = mode } label: {
                        Label(mode.label,
                              systemImage: sortMode.wrappedValue == mode ? "checkmark" : "")
                    }
                    .accessibilityIdentifier("sortModeOption-\(mode.rawValue)")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.label)
                .frame(width: 38, height: 38)
                .glassOrRaised(
                    in: Circle(),
                    fallback: sortMenuHighlight ? Tokens.accent : Tokens.raised,
                    tint: sortMenuHighlight ? Tokens.accent : nil,
                    interactive: true
                )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            sortMenuHighlight = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                sortMenuHighlight = false
            }
        })
        .accessibilityIdentifier("sessionSortMenu")
    }

}

private struct HeaderStatusLine: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 6) {
            if settings.hosts.count > 1 {
                ForEach(settings.hosts.indices, id: \.self) { index in
                    let host = settings.hosts[index]
                    if index > 0 {
                        Text("·")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tokens.labelSecondary)
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                    HostHeaderToken(host: host, online: store.hostStateByHost[host.id]?.isLive == true)
                }
            } else {
                let status = store.connectionStatus
                Circle()
                    .fill(status.dotColor)
                    .frame(width: 7, height: 7)
                    .fixedSize()
                Text(status.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(status.textColor(connected: Tokens.label,
                                                      connecting: Tokens.labelSecondary))
                    .lineLimit(1)
                if store.runningCount > 0 {
                    Text("·")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.labelSecondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                    Text("\(store.runningCount) running")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private struct HostHeaderToken: View {
    let host: Host
    let online: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(online ? Color(.systemGreen) : Color(.systemOrange))
                .frame(width: 7, height: 7)
                .fixedSize()
                .accessibilityHidden(true)
            Text(host.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(online ? Tokens.label : Color(.systemOrange))
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.82)
        }
        .frame(minWidth: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(host.label) \(online ? "online" : "offline")")
    }
}

/// Pre-iOS-26 stand-in for the system bottom search toolbar: the same two
/// controls (search field + plus), hand-built, because `DefaultToolbarItem(kind:
/// .search)` and the automatic bottom placement of `.searchable` are 26-only.
/// Deliberately plain — it is a floor, not a design; on 26 nobody sees it.
private struct LegacyBottomSearchBar: View {
    @Binding var text: String
    let onNewSession: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Tokens.labelSecondary)
                TextField("Search", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(Tokens.label)
                    .tint(Tokens.accent)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("sessionSearchField")
                if !text.isEmpty {
                    Button {
                        text = ""
                        isFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Tokens.labelSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(Tokens.raised, in: Capsule())

            Button(action: onNewSession) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Tokens.label)
                    .frame(width: 44, height: 44)
                    .background(Tokens.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New session")
            .accessibilityIdentifier("newSessionBar")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }
}

private extension View {
    /// The bottom chrome for the session list: a search field plus a "new
    /// session" button.
    ///
    /// On iOS 26 this is literally Apple's own setup — `.searchable` supplies the
    /// field and `DefaultToolbarItem(kind: .search, placement: .bottomBar)` pins
    /// it into the bottom toolbar next to the plus, so the field gets the
    /// system's expand/minimize behaviour, Liquid Glass, and keyboard handling
    /// for free rather than a look-alike. The nav bar is hidden on this screen;
    /// the bottom bar is a separate bar and is unaffected.
    @ViewBuilder
    func bottomSearchChrome(text: Binding<String>,
                            onNewSession: @escaping () -> Void) -> some View {
        if #available(iOS 26.0, *) {
            self
                .searchable(text: text, placement: .toolbar, prompt: "Search sessions")
                // Session titles are lowercase prompts and paths — the system
                // field otherwise sentence-cases the first letter and offers
                // corrections mid-query.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: onNewSession) {
                            Label("New session", systemImage: "plus")
                        }
                        .accessibilityIdentifier("newSessionBar")
                    }
                }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                LegacyBottomSearchBar(text: text, onNewSession: onNewSession)
            }
        }
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
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(Theme.statusColor(group))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Tokens.label)
                    .lineSpacing(0)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 22, alignment: .leading)
                HStack(spacing: 7) {
                    Text(metaText)
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.meta)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 20, alignment: .leading)
                    if let hostLabel {
                        HStack(spacing: 4) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 12))
                            Text(hostLabel).lineLimit(1)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(isOffline ? Color(.systemOrange) : Tokens.host)
                        .frame(height: 20)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 15)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        // Dim the row so a stale (unreachable) session doesn't compete with live
        // ones. The orange host label dims with it, but stays the only warm-colored
        // element in the row, so it still reads as the reason for the dimming.
        .opacity(isOffline ? 0.55 : 1)
    }

    private var title: String {
        session.title.isEmpty ? "Untitled session" : session.title
    }

    private var metaText: String {
        var parts: [String] = [directoryText]
        if !session.closed, let model = session.model, !model.isEmpty {
            parts.append(model)
        }
        if let at = session.lastActivityAt {
            parts.append(at.asCompactRelativeFromMillis)
        }
        return parts.joined(separator: " · ")
    }

    private var directoryText: String {
        if let cwd = session.cwd, !cwd.isEmpty,
           let leaf = cwd.split(separator: "/").last {
            return String(leaf)
        }
        if let project = session.project, !project.isEmpty { return project }
        return "No directory"
    }
}

/// Presentation for the tri-state connection status. "Connecting…" is its own
/// state on purpose: an unknown or still-being-established connection is not an
/// outage, and painting it orange made every cold launch look like one.
extension SessionStore.ConnectionStatus {
    var label: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .offline: return "Offline"
        }
    }

    var dotColor: Color {
        switch self {
        case .connected: return Color(.systemGreen)
        case .connecting: return Color(.systemGray)
        case .offline: return Color(.systemOrange)
        }
    }

    /// Offline is always orange; the other two take the caller's palette (the
    /// list header and the toolbar badge use different label tokens).
    func textColor(connected: Color, connecting: Color) -> Color {
        switch self {
        case .connected: return connected
        case .connecting: return connecting
        case .offline: return Color(.systemOrange)
        }
    }
}

/// Top-bar connection status. Single host → a "Connected/Connecting/Offline"
/// badge plus the running count. Multiple hosts → one dot+label chip per host so
/// you can see at a glance which host is online (green) and which is offline
/// (orange).
struct StatusBadge: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.hosts.count > 1 {
            HStack(spacing: 12) {
                ForEach(settings.hosts) { host in
                    HostStatusChip(host: host,
                                   online: store.hostStateByHost[host.id]?.isLive == true)
                }
            }
        } else {
            let status = store.connectionStatus
            HStack(spacing: 6) {
                Circle()
                    .fill(status.dotColor)
                    .frame(width: 7, height: 7)
                Text(status.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(status.textColor(connected: .primary, connecting: .secondary))
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
                .fill(online ? Color(.systemGreen) : Color(.systemOrange))
                .frame(width: 7, height: 7)
            Text(host.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(online ? Color.primary : Color(.systemOrange))
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
