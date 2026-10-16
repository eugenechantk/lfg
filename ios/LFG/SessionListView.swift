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
    /// The selected row's wash. The row's own `listRowBackground` replaces the
    /// system's selection highlight, so this is what "selected" looks like —
    /// accent at a low alpha, which reads as a state behind the row rather than
    /// as a filled control competing with the row's own text.
    static let selection = Color.accentColor.opacity(0.14)
    /// A plain white/black wash, NOT `Color(.separator)` — the system separator
    /// is blue-tinted `(84,84,88,0.65)` and read back `(42,42,44)` against the
    /// design's `(18,18,18)`.
    static let separator = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.07)
        : UIColor(white: 0, alpha: 0.07) })

    // S2 list (canvas board `s2-list`). The dark values are the design's exact
    // hexes; the light ones are the matching system shades, derived rather than
    // designed (decision D6 in .claude/feature/sessions-redesign-s2.md).
    private static func hex(dark: UInt32, light: UInt32) -> Color {
        func ui(_ v: UInt32) -> UIColor {
            UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    /// Needs-input amber: the header, the question line and its icon.
    static let attention = hex(dark: 0xFF9F0A, light: 0xC93400)
    /// Working green: the live dot and the "Working · 3m" line.
    static let live = hex(dark: 0x30D158, light: 0x248A3D)
    /// Near-white ink for an unread row's line.
    static let ink = hex(dark: 0xD1D1D6, light: 0x3A3A3C)
    /// Group titles and the idle/closed line.
    static let secondaryInk = hex(dark: 0xA1A1A6, light: 0x6C6C70)
    /// Counts and the meta line.
    static let metaInk = hex(dark: 0x8E8E93, light: 0x8E8E93)
    /// The hairline under each row's text.
    static let rowSeparator = hex(dark: 0x2C2C2E, light: 0xD1D1D6)
    /// "Mark all read".
    static let headerAction = hex(dark: 0x409CFF, light: 0x007AFF)
}

extension SessionStore.Group {
    /// The LFGCore twin the S2 list rules are written against.
    var rowGroup: SessionRowGroup {
        switch self {
        case .needsInput: return .needsInput
        case .blocked: return .paused
        case .restarting: return .restarting
        case .working: return .working
        case .unread: return .unread
        case .idle: return .idle
        case .closed: return .closed
        }
    }
}

struct SessionListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @Binding var selection: String?
    @Binding var showSettings: Bool
    @Binding var showNewSession: Bool
    @Binding var focusNewSessionComposer: Bool
    var searchQuery: Binding<String>? = nil
    var usesTabSearch = false
    var isSearchPresentation = false
    var onSearch: (() -> Void)? = nil
    var bottomSearchActive: Binding<Bool>? = nil
    var bottomSearchShown = false
    var listFooter: AnyView? = nil
    @State private var localSearchText = ""
    @State private var listWidth: CGFloat = 320
    private var searchText: String { searchQuery?.wrappedValue ?? localSearchText }
    private var searchBinding: Binding<String> { searchQuery ?? $localSearchText }
    /// Directory-filter panel. A sheet rather than a menu because the panel needs
    /// a text field for a path or pattern, which a `Menu` cannot host.
    @State private var showDirectoryFilter = false
    /// Full-screen shell on the default host (`TerminalScreen`).
    @State private var showTerminal = false

    /// Directory and host sections fold in memory for the current run. Status
    /// sections fold persistently (below): Idle and Closed start folded, and the
    /// user's own choice survives a relaunch.
    @State private var collapsedSections: Set<String> = []
    @AppStorage("sessionList.collapsedStatusSections") private var collapsedStatusStored = ""
    @State private var expandedAgentParents: Set<String> = []

    private var statusCollapse: SessionListCollapse {
        SessionListCollapse(stored: collapsedStatusStored.isEmpty ? nil : collapsedStatusStored)
    }

    /// One rendered section of the list: a header title + its sessions, plus the
    /// running/idle tallies shown on a directory section's collapsible header.
    private struct ListSection: Identifiable {
        let id: String
        let title: String
        let items: [Session]
        var group: SessionStore.Group? = nil
        /// Set for the S2 status sections (Needs input · Working · Unread · Idle · Closed).
        var statusSection: SessionListSection? = nil
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
            if !terms.isEmpty && s.closed { return false }
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
        // Re-apply the directory mute list at read time (the store filters it into
        // `searchResults` too). Both are needed: the store-side filter runs when a
        // search PAGE arrives, this one when the MUTE LIST changes — toggling a
        // directory while a search is on screen otherwise leaves stale rows up.
        for s in store.searchResults
        where !seen.contains(s.id) && !settings.hiddenDirs.hides(cwd: s.cwd) {
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
            // Child agents live inside their session (the Subagents pill and
            // sheet), not as list rows. A child that needs input stays: its
            // question must be answerable from the list.
            return statusSections(for: base.filter { statusAgentParentId(for: $0) == nil })
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
            .sorted {
                if isSearching && settings.sortMode == .recentActivity {
                    return (store.searchRankByID[$0.items.first?.id ?? ""] ?? 0)
                        > (store.searchRankByID[$1.items.first?.id ?? ""] ?? 0)
                }
                return ($0.items.first?.lastActivityAt ?? 0) > ($1.items.first?.lastActivityAt ?? 0)
            }
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

    /// The Closed group is folded (status mode only). Its pager stays hidden
    /// then: the board shows nothing under a folded group, and auto-paging
    /// sessions nobody can see is wasted host work.
    private var closedFolded: Bool {
        effectiveGroupMode == .status && statusCollapse.isCollapsed(.closed)
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
        if isSearching && settings.sortMode == .recentActivity {
            return sessions.sorted {
                let lhs = store.searchRankByID[$0.id] ?? 0
                let rhs = store.searchRankByID[$1.id] ?? 0
                return lhs == rhs ? ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) : lhs > rhs
            }
        }
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

    /// The S2 sections, in design order. Paused folds into Needs input and
    /// Restarting into Working (`SessionListSection`).
    private func statusSections(for sessions: [Session]) -> [ListSection] {
        let bySection = Dictionary(grouping: sessions) { SessionListSection(store.group(for: $0).rowGroup) }
        return SessionListSection.allCases.compactMap { section in
            let sorted = sortedSessions(bySection[section] ?? [])
            return sorted.isEmpty ? nil
                : ListSection(id: "status-\(section.rawValue)", title: section.title, items: sorted,
                              statusSection: section)
        }
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

    /// Search shows every match: Idle and Closed start folded, and most search
    /// hits are closed sessions, so honouring the fold there hid the results.
    private func isCollapsed(_ section: ListSection) -> Bool {
        if isSearching { return false }
        if let status = section.statusSection { return statusCollapse.isCollapsed(status) }
        return collapsedSections.contains(section.id)
    }

    private func toggleSection(_ section: ListSection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let status = section.statusSection {
                var collapse = statusCollapse
                collapse.toggle(status)
                collapsedStatusStored = collapse.stored
            } else if collapsedSections.contains(section.id) {
                collapsedSections.remove(section.id)
            } else {
                collapsedSections.insert(section.id)
            }
        }
    }

    /// One header for every section, folded or open (canvas board `s2-list`):
    /// chevron, title (amber for Needs input), count, and "Mark all read" on an
    /// open Unread section. A folded section keeps the same header with a right
    /// chevron instead of switching to a different row style.
    private func sectionHeader(_ section: ListSection, collapsed: Bool) -> some View {
        HStack(spacing: 8) {
            Button { toggleSection(section) } label: {
                HStack(spacing: 8) {
                    BoardGlyph(kind: collapsed ? .chevronRight : .chevronDown, lineWidth: 3)
                        .foregroundStyle(Tokens.secondaryInk)
                        .frame(width: 13, height: 13)
                    Text(section.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(section.statusSection == .needsInput ? Tokens.attention : Tokens.secondaryInk)
                        .lineLimit(1)
                    Text("\(section.items.count)")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.metaInk)
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
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            if section.statusSection == .unread, !collapsed {
                Button("Mark all read") { store.markAllRead() }
                    .font(.system(size: 15))
                    .buttonStyle(.plain)
                    .foregroundStyle(Tokens.headerAction)
                    .accessibilityIdentifier("markAllReadButton")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .textCase(nil)
        .listRowSeparator(.hidden)
        // Section headers do NOT inherit the zero row insets the rows get, so
        // without this the header sits ~15pt further right than its own rows
        // and carries extra vertical padding of its own.
        .accessibilityIdentifier("sessionGroupHeader-\(section.id)")
        .listRowInsets(EdgeInsets())
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

    /// The row currently open in the detail column. Compared against the same
    /// nav id the row is `.tag`ged with, so a session created in this run stays
    /// selected across the create remap.
    private func isSelected(_ row: RenderedSessionRow) -> Bool {
        guard let selection else { return false }
        return selection == store.navID(row.session.sessionId ?? "")
    }

    /// The selected row's tinted pill, inset from the column edges (and past the
    /// agent indent) so it reads as a rounded chip around the row rather than a
    /// full-bleed band.
    ///
    /// Drawn as a `background` on the row's CONTENT, deliberately not as
    /// `listRowBackground`. A `listRowBackground` that varies with the selection
    /// rebuilds the cell's background configuration on every selection change,
    /// and a row that re-sections in the same update (an unread row becomes read
    /// the moment you open it, so it moves out of Unread) then loses its tag —
    /// the List clears `selection` and the detail empties. Measured: with the
    /// dynamic `listRowBackground`, tapping an unread row opened it and then
    /// immediately deselected it; the same tap on the unmodified build stayed put.
    @ViewBuilder
    private func selectionPill(selected: Bool, indent: CGFloat) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Tokens.selection)
                .padding(.leading, indent + 8)
                .padding(.trailing, 8)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func sessionRow(_ row: RenderedSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SessionRow(session: row.session, group: store.group(for: row.session))
                    .padding(.leading, row.indent)
                if !row.children.isEmpty, let parentId = normalizedId(row.session.sessionId) {
                    agentDisclosure(parentId: parentId, children: row.children)
                        .padding(.leading, row.indent)
                }
            }
            .background { selectionPill(selected: isSelected(row), indent: row.indent) }
            // The hairline would cut across the bottom of the selection pill and
            // undo its rounded corners, so the selected row drops it.
            Rectangle()
                .fill(isSelected(row) ? Color.clear : Tokens.rowSeparator)
                .frame(height: 0.5)
                .padding(.leading, row.indent + 40)
        }
        .contentShape(Rectangle())
        // Tagged by NAV id, not session id: a session created in this run keeps
        // the placeholder tag its detail was pushed under, so the create remap
        // doesn't yank the tag out from under a live selection (which made the
        // list clear the selection and the split view push a second detail).
        .tag(store.navID(row.session.sessionId ?? ""))
        .accessibilityIdentifier("sessionRow-\(row.session.id)")
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Tokens.screen)
        // Mail's gesture: flag "come back to this" without opening the session
        // (opening marks it read) or digging into the detail's ⋯ menu. The verb
        // toggles with the row's state so a stray flag has a list-level undo.
        // Full swipe commits without a tap (Mail again): drag past the threshold
        // and the single action fires. Explicit so nobody "tidies" it to false.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            let sid = row.session.sessionId ?? ""
            let group = store.group(for: row.session)
            if let action = ManualUnread.listAction(sessionID: sid,
                                                    isUnread: group == .unread,
                                                    isClosed: group == .closed) {
                switch action {
                case .markUnread:
                    Button {
                        store.markUnread(sid)
                        // Same exit the detail view takes: an unread row is one
                        // you are not reading, so the split view drops it.
                        if isSelected(row) { selection = nil }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Mark Unread", systemImage: "envelope.badge")
                    }
                    .tint(.blue)
                    .accessibilityIdentifier("markUnread-\(row.session.id)")
                case .markRead:
                    Button {
                        store.markRead(sid)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Mark Read", systemImage: "envelope.open")
                    }
                    .tint(.blue)
                    .accessibilityIdentifier("markRead-\(row.session.id)")
                }
            }
        }
        // Build the mute list from the thing that's annoying you, in one gesture.
        // Typing `/Users/…/.gbrain` into Settings is the same operation, but no
        // one does it — this is where you actually notice the noise.
        .swipeActions(edge: .trailing) {
            if let dir = row.session.cwd.flatMap(HiddenDirs.normalize) {
                Button {
                    settings.hideDirectory(dir)
                } label: {
                    Label("Hide \(HiddenDirs.displayName(for: dir))", systemImage: "eye.slash")
                }
                .tint(.secondary)
                .accessibilityIdentifier("hideDirectory-\(row.session.id)")

                // A scratch directory whose name ends in a pid — `gbrain` autopilot
                // works out of `$TMPDIR/gbrain-claude-cli-cwd-<pid>`. Hiding the
                // literal path would mute exactly one run, so offer the pattern
                // that mutes the whole family. Only ever offered, never applied.
                if let pattern = HiddenDirs.suggestedPattern(for: dir) {
                    Button {
                        settings.hideDirectory(pattern)
                    } label: {
                        Label("Hide all like this", systemImage: "eye.slash.circle")
                    }
                    .tint(.orange)
                    .accessibilityIdentifier("hideDirectoryPattern-\(row.session.id)")
                }
            }
        }
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
            .foregroundStyle(Tokens.headerAction)
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
        List(selection: $selection) {
            if store.connectionStatus == .offline {
                Section {
                    HostConnectionWarning()
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
                    let collapsed = isCollapsed(section)
                    Section {
                        // The group header is a normal ROW, not a
                        // `Section(header:)`. A plain List pins section
                        // headers, and these headers are transparent —
                        // so rows scrolled underneath drew straight
                        // through the header text. The design shows
                        // groups scrolling away as a unit, so making it
                        // a row fixes the collision and the header's
                        // extra built-in top padding at the same time.
                        sectionHeader(section, collapsed: collapsed)
                        if !collapsed {
                            ForEach(renderedRows(for: section)) { row in
                                sessionRow(row)
                            }
                        }
                    }
                }
                // Both cursors belong to the WHOLE rendered list rather than a
                // status section. Directory/host grouping does not mark any
                // section `.closed`, so nesting either footer inside that
                // section silently disabled paging in those modes.
                if !isSearching, store.canLoadMoreClosed, !closedFolded {
                    loadMoreRow(title: "Load more",
                                loading: store.isLoadingMoreClosed,
                                identifier: "loadMoreClosedButton") {
                        await store.loadMoreClosed()
                    }
                    .onAppear {
                        Task { await store.loadMoreClosed() }
                    }
                } else if isSearching, store.canLoadMoreSearch {
                    loadMoreRow(title: "Load more results",
                                loading: store.isLoadingMoreSearch,
                                identifier: "loadMoreSearchButton") {
                        await store.loadMoreSearchResults()
                    }
                    .onAppear {
                        Task { await store.loadMoreSearchResults() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(Tokens.screen)
        .refreshable { await store.refresh() }
        .listSectionSpacing(0)
        .background(Tokens.screen.ignoresSafeArea())
        .listScrollChrome(footer: listFooter)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(isSearchPresentation ? "Search sessions" : "")
        .navigationBarTitleDisplayMode(.inline)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        .toolbar {
            if !isSearchPresentation {
                statusToolbar
                if let onSearch {
                    ToolbarItem(placement: .primaryAction) {
                        // The board's glyph (21pt box), not the larger SF symbol.
                        Button(action: onSearch) {
                            BoardGlyph(kind: .search, lineWidth: 2).frame(width: 21, height: 21)
                        }
                        .accessibilityLabel("Search sessions")
                        .accessibilityIdentifier("sessions_search")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    moreMenu(groupMode: $settings.groupMode, sortMode: $settings.sortMode)
                }
            }
        }
        .fullScreenCover(isPresented: $showTerminal) { TerminalScreen() }
        .bottomSearchChrome(text: searchBinding, enabled: !usesTabSearch) {
            openNewSession(focusComposer: false)
        }
        .scopedBottomSearch(text: searchBinding, active: bottomSearchActive ?? .constant(false),
            shown: bottomSearchShown, prompt: "Search sessions")
        // Hand every keystroke to the store, which debounces and queries the
        // hosts. Local filtering alone can't answer "search all my sessions" —
        // it only ever sees what pagination has loaded.
        .onChange(of: searchText) { _, q in store.setSearchQuery(q) }
        // Re-sync rather than clear: on iPhone this view disappears whenever a
        // session is pushed, and clearing there would strand a still-populated
        // field with no results and no keystroke left to trigger a re-query.
        // `setSearchQuery` no-ops when the query is unchanged.
        .onAppear { store.setSearchQuery(searchText) }
        .sheet(isPresented: $showDirectoryFilter) {
            NavigationStack {
                HiddenDirectoriesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDirectoryFilter = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func openNewSession(focusComposer: Bool) {
        focusNewSessionComposer = focusComposer
        showNewSession = true
    }

    @ToolbarContentBuilder
    private var statusToolbar: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { headerStatus }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { headerStatus }
        }
    }

    private var headerStatus: some View {
        // The system puts a leading toolbar item at x=20; the board's first
        // host dot sits at x=16.
        HostConnectionHeader(listWidth: listWidth)
            .padding(.leading, -4)
            .accessibilityIdentifier("sessionListHeader")
    }

    private func moreMenu(
        groupMode: Binding<GroupMode>,
        sortMode: Binding<SortMode>
    ) -> some View {
        Menu {
            Section {
                Button {
                    showDirectoryFilter = true
                } label: {
                    let indicator = DirectoryFilterIndicator.resolve(
                        hasHiddenDirectories: !settings.hiddenDirs.isEmpty,
                        hiddenLiveSessionCount: store.hiddenLiveSessionCount)
                    Label(indicator.isActive ? "Directory filter (on)" : "Filter directories",
                          systemImage: indicator.isActive ? "eye.slash.fill" : "eye.slash")
                }.accessibilityIdentifier("directoryFilterButton")
                Button("Terminal", systemImage: "apple.terminal") { showTerminal = true }
                    .accessibilityIdentifier("terminalButton")
                Button("Settings", systemImage: "gearshape") { showSettings = true }
                    .accessibilityIdentifier("sessionSettingsButton")
            }
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
            BoardGlyph(kind: .more).frame(width: 20, height: 20)
                .foregroundStyle(Tokens.label)
                .accessibilityLabel("More session options")
        }
        .tint(Tokens.label)
        .accessibilityIdentifier("sessions_more")
    }

}

/// Shared list chrome, including the room reserved for Search and More.
struct HostConnectionHeader: View {
    let listWidth: CGFloat

    var body: some View {
        HeaderStatusLine()
            .frame(width: max(80, min(240, listWidth - 164)))
            .accessibilityIdentifier("hostConnectionHeader")
    }
}

private struct HeaderStatusLine: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    /// S2 (canvas board `s2-list`): "● Pro  ● Air" — every host as a dot and its
    /// label, one host included. Working counts live on the rows now, so the
    /// header no longer says "Connected · N running". When the labels don't fit,
    /// it falls back to one summary dot.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                // Iterate the ELEMENTS, keyed by host id — never `hosts.indices`
                // with a `hosts[index]` lookup inside. SwiftUI evaluates a row's
                // body against the identity it already has, so when the array
                // shrinks (removing a host in Settings) an index-keyed ForEach
                // re-runs the body for the departing index and subscripts past
                // the end: `Array._checkSubscript` trap, app gone. Removing the
                // second of two hosts crashed reliably this way.
                ForEach(settings.hosts, id: \.id) { host in
                    HostHeaderToken(host: host, status: store.connectionStatus(forHost: host.id))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            compactHostStatus
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var compactHostStatus: some View {
        let connected = settings.hosts.filter { store.connectionStatus(forHost: $0.id) == .connected }.count
        let total = settings.hosts.count
        let allConnected = connected == total
        return HStack(spacing: 6) {
            Circle()
                .fill(allConnected ? Color(.systemGreen) : Color(.systemOrange))
                .frame(width: 8, height: 8)
            Text(allConnected ? "\(total) hosts" : "\(connected)/\(total) hosts")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Tokens.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.hosts.map {
            "\($0.label) \(store.connectionStatus(forHost: $0.id).accessibilityLabel)"
        }.joined(separator: ", "))
    }
}

private struct HostHeaderToken: View {
    let host: Host
    let status: HostConnectionPresentation

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.dotColor)
                .frame(width: 8, height: 8)
                .fixedSize()
                .accessibilityHidden(true)
            Text(host.label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(status.textColor(connected: Tokens.label,
                                                   reconnecting: Tokens.labelSecondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.82)
        }
        .frame(minWidth: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(host.label) \(status.accessibilityLabel)")
    }
}

/// Hand-built stand-in for the system bottom search toolbar: the same two
/// controls (search field + plus), in the same place.
///
/// Two audiences, for different reasons:
/// * **Pre-iOS-26**, because `DefaultToolbarItem(kind: .search)` and the
///   automatic bottom placement of `.searchable` are 26-only.
/// * **iPadOS at every version**, because there `.searchable` resolves into the
///   sidebar's *navigation* bar, which this screen hides — see
///   `bottomSearchChrome`.
///
/// On 26 it takes Liquid Glass so it reads as chrome rather than as a
/// look-alike; below that it falls back to the raised fill.
private struct BottomSearchBar: View {
    @Binding var text: String
    let onNewSession: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        GlassChromeContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Tokens.labelSecondary)
                    TextField("Search sessions", text: $text)
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
                        .accessibilityIdentifier("clearSearchButton")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .glassOrRaised(in: Capsule(), fallback: Tokens.raised)

                Button(action: onNewSession) {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Tokens.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassOrRaised(in: Circle(), fallback: Tokens.raised, interactive: true)
                .accessibilityLabel("New session")
                .accessibilityIdentifier("newSessionBar")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(barBackground)
    }

    /// Glass floats over the list on 26; older OSes need an opaque bar behind
    /// the two controls or rows scroll visibly under them.
    @ViewBuilder
    private var barBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
        } else {
            Rectangle().fill(.bar)
        }
    }
}

private extension View {
    /// The bottom chrome for the session list: a search field plus a "new
    /// session" button.
    ///
    /// On iPhone/iOS 26 this is literally Apple's own setup — `.searchable`
    /// supplies the field and `DefaultToolbarItem(kind: .search, placement:
    /// .bottomBar)` pins it into the bottom toolbar next to the plus, so the
    /// field gets the system's expand/minimize behaviour, Liquid Glass, and
    /// keyboard handling for free rather than a look-alike. The nav bar is
    /// hidden on this screen; the bottom bar is a separate bar and is
    /// unaffected.
    ///
    /// **iPadOS is excluded on purpose, and this is not a style call.** There
    /// `.searchable(placement: .toolbar)` resolves into the sidebar column's
    /// *navigation* bar — `DefaultToolbarItem(kind: .search, placement:
    /// .bottomBar)` is a no-op — so with the nav bar hidden the field had
    /// nowhere to render and iPad simply had no search at all, while the plus
    /// (an ordinary `.bottomBar` item) kept showing and made the bar look
    /// intact. Verified on iPad Pro 11-inch, iPadOS 26.3: unhiding the nav bar
    /// made the same `.searchable` appear at the TOP of the sidebar. Rather
    /// than surrender the top chrome to it, iPad takes the hand-built bar, so
    /// search sits where it does on iPhone. Keyed on the idiom, not the size
    /// class: an iPad in Slide Over is compact-width and must not silently lose
    /// its search field again.
    @ViewBuilder
    func bottomSearchChrome(text: Binding<String>, enabled: Bool = true,
                            onNewSession: @escaping () -> Void) -> some View {
        if !enabled {
            self
        } else if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom != .pad {
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
                BottomSearchBar(text: text, onNewSession: onNewSession)
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

/// One S2 list row (canvas board `s2-list`): status dot, then three lines —
/// title (bold when it needs you or is unread), what state the session is in,
/// and project · model · subagents · time · host. No buttons: the row is the
/// tap target.
struct SessionRow: View {
    @Environment(SessionStore.self) private var store
    let session: Session
    let group: SessionStore.Group

    /// The owning host's label, when known. Shown on every row (the design puts
    /// the host in the meta line even with one host).
    private var hostLabel: String? { store.host(forSession: session.id)?.label }

    /// Live on a host that is currently down — the session's agent is unreachable,
    /// so the row is dimmed and its host label goes orange. Without this the row
    /// renders as a healthy session and tapping it opens a composer whose sends
    /// can never land.
    private var isOffline: Bool { store.isOffline(session.id) }

    private var isEmphasized: Bool {
        group == .needsInput || group == .blocked || group == .unread
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(Theme.statusColor(group))
                .frame(width: 8, height: 8)
                .padding(.top, 18)
                .frame(width: 20, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let nowMs = context.date.timeIntervalSince1970 * 1_000
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: isEmphasized ? .semibold : .regular))
                        .foregroundStyle(Tokens.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 22, alignment: .leading)
                    stateLine(SessionRowLine.resolve(lineState, nowMs: nowMs))
                    metaLine(nowMs: nowMs)
                }
                .padding(.top, 11)
                .padding(.bottom, 12)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 20)
        // Dim the row so a stale (unreachable) session doesn't compete with live
        // ones. The orange host label dims with it, but stays the only warm-colored
        // element in the row, so it still reads as the reason for the dimming.
        .opacity(isOffline ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        session.title.isEmpty ? "Untitled session" : session.title
    }

    private var lineState: SessionRowLine.State {
        switch group {
        case .needsInput:
            let prompt = session.sessionId.flatMap { store.prompts[$0] }
            return .needsInput(question: prompt?.question, signInSite: prompt?.signIn?.website)
        case .blocked: return .paused(reason: session.statusReason)
        case .restarting: return .restarting
        case .working:
            // Timed from the turn's start (the newest genuine user turn), the
            // same anchor as the session view's status line. Hosts without
            // `lastUserAt` fall back to the process start.
            if let since = store.turnStartedAt(session) { return .working(runningSinceMs: since) }
            if case .runningSince(let since) = SessionListTime.resolve(session: session, isWorking: true) {
                return .working(runningSinceMs: since)
            }
            return .working(runningSinceMs: nil)
        case .unread: return .unread
        case .idle: return .idle
        case .closed: return .closed(lastActivityMs: session.lastActivityAt)
        }
    }

    private func stateLine(_ line: SessionRowLine) -> some View {
        HStack(spacing: 5) {
            switch line.icon {
            case .question:
                BoardGlyph(kind: .question).frame(width: 14, height: 14)
            case .signIn:
                BoardGlyph(kind: .key).frame(width: 14, height: 14)
            case .liveDot:
                Circle()
                    .fill(Tokens.live)
                    .frame(width: 7, height: 7)
                    .background(Circle().fill(Tokens.live.opacity(0.25)).frame(width: 13, height: 13))
            case .none:
                EmptyView()
            }
            Text(line.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 15))
        .foregroundStyle(color(for: line.tone))
        .frame(height: 20, alignment: .leading)
    }

    private func color(for tone: SessionRowLine.Tone) -> Color {
        switch tone {
        case .attention: return Tokens.attention
        case .live: return Tokens.live
        case .primary: return Tokens.ink
        case .secondary: return Tokens.secondaryInk
        }
    }

    private func metaLine(nowMs: Double) -> some View {
        // Working rows carry their time on line 2; every other row shows the
        // age of its last activity here.
        let showsTime = group != .working && group != .restarting
        let time = showsTime ? session.lastActivityAt.map {
            SessionRowLine.compactDuration(from: $0, to: nowMs)
        } : nil
        let meta = SessionRowMeta.text(
            project: SessionRowMeta.projectLabel(cwd: session.cwd, project: session.project),
            model: session.model,
            subagents: session.runningChildAgentCount,
            backgroundProcesses: session.runningBackgroundProcessCount,
            time: time)
        return HStack(spacing: 5) {
            if session.task != nil {
                BoardGlyph(kind: .repeat).frame(width: 13, height: 13)
                    .accessibilityHidden(false)
                    .accessibilityLabel("Started by a scheduled task")
            }
            Text(hostLabel == nil ? meta : meta + " ·")
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let hostLabel {
                HStack(spacing: 4) {
                    BoardGlyph(kind: .monitor, lineWidth: 1.8).frame(width: 13, height: 13)
                    Text(hostLabel).lineLimit(1)
                }
                .foregroundStyle(isOffline ? Color(.systemOrange) : Tokens.metaInk)
                .fixedSize()
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Tokens.metaInk)
        .frame(height: 18, alignment: .leading)
    }
}

/// Small glyphs drawn from the board's own 24×24 SVG paths (canvas board
/// `s2-list`). The nearest SF Symbols were filled, rounded or mirrored, and
/// their wider footprint pushed the text after them 3–4 pt to the right.
struct BoardGlyph: View {
    enum Kind { case question, key, monitor, `repeat`, search, more, chevronDown, chevronRight }
    let kind: Kind
    var lineWidth: CGFloat = 2.2

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            let stroke = StrokeStyle(lineWidth: lineWidth * k, lineCap: .round, lineJoin: .round)
            ZStack {
                switch kind {
                case .question:
                    Path { p in
                        p.move(to: CGPoint(x: 4 * k, y: 5 * k))
                        p.addLine(to: CGPoint(x: 20 * k, y: 5 * k))
                        p.addLine(to: CGPoint(x: 20 * k, y: 16 * k))
                        p.addLine(to: CGPoint(x: 9 * k, y: 16 * k))
                        p.addLine(to: CGPoint(x: 4 * k, y: 20 * k))
                        p.closeSubpath()
                        // "M10 9 a2 2 0 1 1 3 1.7 c-.6.4-1 .8-1 1.5"
                        p.move(to: CGPoint(x: 10 * k, y: 9 * k))
                        p.addArc(center: CGPoint(x: 12 * k, y: 9 * k), radius: 2 * k,
                                 startAngle: .degrees(180), endAngle: .degrees(59.5), clockwise: false)
                        p.addCurve(to: CGPoint(x: 12 * k, y: 12.2 * k),
                                   control1: CGPoint(x: 12.4 * k, y: 11.1 * k),
                                   control2: CGPoint(x: 12 * k, y: 11.5 * k))
                    }
                    .stroke(style: stroke)
                    Circle()
                        .frame(width: 1.6 * k, height: 1.6 * k)
                        .position(x: 12 * k, y: 14.4 * k)
                case .key:
                    Path { p in
                        p.addEllipse(in: CGRect(x: 4 * k, y: 11 * k, width: 8 * k, height: 8 * k))
                        p.move(to: CGPoint(x: 11 * k, y: 12 * k))
                        p.addLine(to: CGPoint(x: 20 * k, y: 3 * k))
                        p.move(to: CGPoint(x: 16 * k, y: 7 * k))
                        p.addLine(to: CGPoint(x: 19 * k, y: 10 * k))
                    }
                    .stroke(style: stroke)
                case .repeat:
                    // "M17 2.5l3 3-3 3 M4 11.5v-1a5 5 0 0 1 5-5h11
                    //  M7 21.5l-3-3 3-3 M20 12.5v1a5 5 0 0 1-5 5H4"
                    Path { p in
                        p.move(to: CGPoint(x: 17 * k, y: 2.5 * k))
                        p.addLine(to: CGPoint(x: 20 * k, y: 5.5 * k))
                        p.addLine(to: CGPoint(x: 17 * k, y: 8.5 * k))
                        p.move(to: CGPoint(x: 4 * k, y: 11.5 * k))
                        p.addLine(to: CGPoint(x: 4 * k, y: 10.5 * k))
                        p.addArc(center: CGPoint(x: 9 * k, y: 10.5 * k), radius: 5 * k,
                                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                        p.addLine(to: CGPoint(x: 20 * k, y: 5.5 * k))
                        p.move(to: CGPoint(x: 7 * k, y: 21.5 * k))
                        p.addLine(to: CGPoint(x: 4 * k, y: 18.5 * k))
                        p.addLine(to: CGPoint(x: 7 * k, y: 15.5 * k))
                        p.move(to: CGPoint(x: 20 * k, y: 12.5 * k))
                        p.addLine(to: CGPoint(x: 20 * k, y: 13.5 * k))
                        p.addArc(center: CGPoint(x: 15 * k, y: 13.5 * k), radius: 5 * k,
                                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                        p.addLine(to: CGPoint(x: 4 * k, y: 18.5 * k))
                    }
                    .stroke(style: stroke)
                case .search:
                    // "circle 11,11 r6.5; M16 16l4.5 4.5"
                    Path { p in
                        p.addEllipse(in: CGRect(x: 4.5 * k, y: 4.5 * k, width: 13 * k, height: 13 * k))
                        p.move(to: CGPoint(x: 16 * k, y: 16 * k))
                        p.addLine(to: CGPoint(x: 20.5 * k, y: 20.5 * k))
                    }
                    .stroke(style: stroke)
                case .more:
                    // Three filled dots, r1.9 at x 5 / 12 / 19.
                    Path { p in
                        for x in [5.0, 12.0, 19.0] {
                            p.addEllipse(in: CGRect(x: (x - 1.9) * k, y: (12 - 1.9) * k, width: 3.8 * k, height: 3.8 * k))
                        }
                    }
                    .fill()
                case .chevronDown:
                    Path { p in
                        p.move(to: CGPoint(x: 6 * k, y: 9 * k))
                        p.addLine(to: CGPoint(x: 12 * k, y: 15 * k))
                        p.addLine(to: CGPoint(x: 18 * k, y: 9 * k))
                    }
                    .stroke(style: stroke)
                case .chevronRight:
                    Path { p in
                        p.move(to: CGPoint(x: 9 * k, y: 6 * k))
                        p.addLine(to: CGPoint(x: 15 * k, y: 12 * k))
                        p.addLine(to: CGPoint(x: 9 * k, y: 18 * k))
                    }
                    .stroke(style: stroke)
                case .monitor:
                    Path { p in
                        p.addRoundedRect(in: CGRect(x: 3 * k, y: 4 * k, width: 18 * k, height: 12 * k),
                                         cornerSize: CGSize(width: 1.5 * k, height: 1.5 * k))
                        p.move(to: CGPoint(x: 9 * k, y: 20 * k))
                        p.addLine(to: CGPoint(x: 15 * k, y: 20 * k))
                        p.move(to: CGPoint(x: 12 * k, y: 16 * k))
                        p.addLine(to: CGPoint(x: 12 * k, y: 20 * k))
                    }
                    .stroke(style: stroke)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// Network-free rows for verifying the clock selected by each list state.
/// Launch with `LFG_SESSION_LIST_TIME_FIXTURE=1`.
struct SessionListTimeFixture: View {
    @State private var nowMs = Date().timeIntervalSince1970 * 1_000

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Working").font(.caption).padding(.horizontal, 20)
                SessionRow(
                    session: Session(sessionId: "time-working", title: "Working since start",
                                     cwd: "/tmp/work", startedAt: nowMs - 45_000,
                                     lastActivityAt: nowMs - 5_000),
                    group: .working
                )
                Divider()
                Text("Idle").font(.caption).padding(.horizontal, 20)
                SessionRow(
                    session: Session(sessionId: "time-idle", title: "Idle since activity",
                                     cwd: "/tmp/idle", startedAt: nowMs - 120_000,
                                     lastActivityAt: nowMs - 30_000),
                    group: .idle
                )
                Divider()
                Text("Closed").font(.caption).padding(.horizontal, 20)
                SessionRow(
                    session: Session(sessionId: "time-closed", title: "Closed since activity",
                                     cwd: "/tmp/closed", lastActivityAt: nowMs - 90_000,
                                     closed: true),
                    group: .closed
                )
                Spacer()
            }
            .navigationTitle("Session times")
            .accessibilityIdentifier("sessionListTimeFixture")
        }
    }
}
#endif

/// Presentation for the tri-state connection status. "Reconnecting…" is its own
/// state on purpose: an unknown or still-being-established connection is not an
/// outage, and painting it orange made every cold launch look like one.
extension HostConnectionPresentation {
    var label: String {
        switch self {
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .offline: return "Offline"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .connected: return "online"
        case .reconnecting: return "reconnecting"
        case .offline: return "offline"
        }
    }

    var dotColor: Color {
        switch self {
        case .connected: return Color(.systemGreen)
        case .reconnecting: return Color(.systemGray)
        case .offline: return Color(.systemOrange)
        }
    }

    /// Offline is always orange; the other two take the caller's palette (the
    /// list header and the toolbar badge use different label tokens).
    func textColor(connected: Color, reconnecting: Color) -> Color {
        switch self {
        case .connected: return connected
        case .reconnecting: return reconnecting
        case .offline: return Color(.systemOrange)
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
