import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

@MainActor @Observable final class ScheduledTasksModel {
    var tasks: [HostedScheduledTask] = []
    var hosts: [ScheduledTaskHost] = []
    var loading = false
    var error: String?
    var loadErrors: [String: String] = [:]
    var changing = false

    func refresh() async {
        let snapshot = hosts
        loading = tasks.isEmpty
        defer { loading = false }
        var updated: [HostedScheduledTask] = []
        var failures: [String: String] = [:]
        await withTaskGroup(of: (String, [ScheduledTaskRecord]?, String?).self) { group in
            for host in snapshot {
                group.addTask {
                    do { return (host.id, try await ScheduledTasksClient(host: host).list(), nil) }
                    catch {
                        // Host reachability already has shared, debounced UI.
                        // Only task API failures need separate task feedback.
                        let failure = error is URLError || error is CancellationError
                            ? nil : "\(host.name): \(error.localizedDescription)"
                        return (host.id, nil, failure)
                    }
                }
            }
            for await (id, records, failure) in group {
                guard let host = snapshot.first(where: { $0.id == id }) else { continue }
                if let records { updated += records.map { HostedScheduledTask(task: $0, host: host) } }
                else {
                    updated += tasks.filter { $0.host.id == id }
                    if let failure { failures[id] = failure }
                }
            }
        }
        guard !Task.isCancelled, hosts.map(\.id) == snapshot.map(\.id) else { return }
        tasks = updated
        loadErrors = failures
    }
    func act(_ item: HostedScheduledTask, _ action: String, enabled: Bool? = nil) async {
        guard !changing else { return }
        error = nil
        changing = true; defer { changing = false }
        do {
            try await ScheduledTasksClient(host: item.host).action(item.task.id, action, enabled: enabled)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}

enum ScheduledTaskRoute: Hashable {
    case task(String)
    case session(String)
}

struct ScheduledTasksView: View {
    let hosts: [ScheduledTaskHost]
    var searchQuery: Binding<String>? = nil
    var navigationPath: Binding<[ScheduledTaskRoute]>? = nil
    var showsSearchField = true
    var bottomSearchActive: Binding<Bool>? = nil
    var bottomSearchShown = false
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>? = nil
    var sidebarFooter: AnyView? = nil
    var connectionHeader: ((CGFloat) -> AnyView)? = nil
    var connectionWarning: AnyView? = nil
    var connectedHostIDs: Set<String>? = nil
    var embedsInNavigationStack = true
    var showsListActions = true
    var usesBottomCreate = false
    var onSearch: (() -> Void)? = nil
    var onCreate: (() -> Void)? = nil
    var sessionSelection: Binding<String?>? = nil
    var sessionDestination: ((String) -> AnyView)? = nil
    var openSession: (String, String) -> Void
    @State private var model = ScheduledTasksModel()
    @State private var path: [ScheduledTaskRoute] = []
    @State private var collapsedGroups: Set<ScheduledTaskGroup> = [.completed]
    @State private var localSearch = ""
    @State private var listWidth: CGFloat = 320
    @State private var pendingSession: (hostID: String, sessionID: String)?
    private var search: String { searchQuery?.wrappedValue ?? localSearch }
    private var searchBinding: Binding<String> { searchQuery ?? $localSearch }
    private var pathBinding: Binding<[ScheduledTaskRoute]> { navigationPath ?? $path }
    @State private var sheet: TaskSheet?
    private enum TaskSheet: Identifiable {
        case manual(ScheduledTaskHost), edit(HostedScheduledTask), chat
        var id: String {
            switch self {
            case .manual(let h): "manual-\(h.id)"
            case .edit(let t): "edit-\(t.id)"
            case .chat: "chat"
            }
        }
    }
    private var filtered: [HostedScheduledTask] {
        model.tasks.filter { item in
            let task = item.task
            return (search.isEmpty || task.name.localizedCaseInsensitiveContains(search)
                    || task.prompt.localizedCaseInsensitiveContains(search)
                    || item.host.name.localizedCaseInsensitiveContains(search)
                    || task.modelLabel.localizedCaseInsensitiveContains(search))
        }.sorted {
            let lhs = $0.task.nextRunAt ?? .greatestFiniteMagnitude
            let rhs = $1.task.nextRunAt ?? .greatestFiniteMagnitude
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }
    var body: some View {
        taskNavigation
        .onChange(of: search, initial: true) { _, query in
            if !query.isEmpty { collapsedGroups.removeAll() }
        }
        .onChange(of: sessionSelection?.wrappedValue) { _, id in
            if let id {
                if pathBinding.wrappedValue.last != .session(id) {
                    pathBinding.wrappedValue.append(.session(id))
                }
            } else {
                pathBinding.wrappedValue.removeAll { if case .session = $0 { return true }; return false }
            }
        }
        .onChange(of: pathBinding.wrappedValue) { _, routes in
            // Task details and their sessions share one path. Mixing an item
            // destination with a value path discarded the task on Back.
            if case .session(let id) = routes.last {
                sessionSelection?.wrappedValue = id
            } else {
                sessionSelection?.wrappedValue = nil
            }
        }
        .task(id: hosts.map(\.id)) {
            model.hosts = hosts
            while !Task.isCancelled { await model.refresh(); try? await Task.sleep(for: .seconds(5)) }
        }
        .sheet(item: $sheet, onDismiss: {
            if let pending = pendingSession {
                pendingSession = nil
                Task { @MainActor in
                    await Task.yield()
                    openSession(pending.hostID, pending.sessionID)
                }
            }
            Task { await model.refresh() }
        }) { destination in
            switch destination {
            case .manual(let host): ScheduledTaskEditor(client: .init(host: host), task: nil)
            case .edit(let item):
                ScheduledTaskEditor(client: .init(host: item.host), task: item.task) { hostID, sessionID in
                    pendingSession = (hostID, sessionID); sheet = nil
                }
            case .chat:
                if let host = hosts.first {
                    ScheduledTaskChat(hosts: hosts, initialHost: host) { hostID, sessionID in
                        pendingSession = (hostID, sessionID); sheet = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var taskNavigation: some View {
        if let sidebarVisibility {
            NavigationSplitView(columnVisibility: sidebarVisibility) {
                navigableTaskList
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
                    .toolbar(removing: .sidebarToggle)
                    .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
            } detail: {
                NavigationStack(path: sidebarDetailPath) {
                    Group {
                        if let selectedTaskID {
                            routeDestination(.task(selectedTaskID))
                        } else {
                            ContentUnavailableView("No task selected", systemImage: "calendar.badge.clock",
                                description: Text("Pick a task from the sidebar."))
                        }
                    }
                    .navigationDestination(for: ScheduledTaskRoute.self, destination: routeDestination)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    sidebarVisibility.wrappedValue = sidebarVisibility.wrappedValue == .detailOnly
                                        ? .doubleColumn : .detailOnly
                                }
                            } label: { Image(systemName: "sidebar.leading") }
                            .accessibilityLabel(sidebarVisibility.wrappedValue == .detailOnly ? "Show tasks" : "Hide tasks")
                            .accessibilityIdentifier("toggleTaskSidebar")
                        }
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else if embedsInNavigationStack {
            NavigationStack(path: pathBinding) {
                navigableTaskList.navigationDestination(for: ScheduledTaskRoute.self, destination: routeDestination)
            }
        } else {
            navigableTaskList.navigationDestination(for: ScheduledTaskRoute.self, destination: routeDestination)
        }
    }

    private var selectedTaskID: String? {
        pathBinding.wrappedValue.compactMap { route in
            if case .task(let id) = route { return id }; return nil
        }.first
    }

    private var sidebarDetailPath: Binding<[ScheduledTaskRoute]> {
        Binding(get: {
            pathBinding.wrappedValue.filter { if case .session = $0 { return true }; return false }
        }, set: { routes in
            let taskRoute: [ScheduledTaskRoute] = selectedTaskID.map { [.task($0)] } ?? []
            pathBinding.wrappedValue = taskRoute + routes
        })
    }

    @ViewBuilder
    private func routeDestination(_ route: ScheduledTaskRoute) -> some View {
        Group {
            switch route {
            case .session(let id):
                if let sessionDestination { sessionDestination(id) }
            case .task(let id):
                if let item = model.tasks.first(where: { $0.id == id }) {
                    ScheduledTaskDetail(task: item.task, client: .init(host: item.host), changing: model.changing,
                        edit: { sheet = .edit(item) },
                        action: { action, enabled in Task { await model.act(item, action, enabled: enabled) } },
                        openSession: { openSession(item.host.id, $0) })
                        .id(item.id)
                } else {
                    ContentUnavailableView("Task unavailable", systemImage: "calendar.badge.exclamationmark",
                        description: Text("Return to Scheduled Tasks and refresh the list."))
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
    }

    private var navigableTaskList: some View {
        searchableTaskList
                #if os(macOS)
                .navigationTitle("")
                #else
                .navigationTitle(showsListActions ? "" : "Search tasks")
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
                .toolbar {
                    if showsListActions, sidebarVisibility != nil || pathBinding.wrappedValue.isEmpty {
                        connectionToolbar
                    }
                    if let onSearch {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Search tasks", systemImage: "magnifyingglass", action: onSearch)
                                .accessibilityIdentifier("tasks_search")
                        }
                    }
                    if showsListActions {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(hosts) { host in
                                Button("Set up manually on \(host.name)") { sheet = .manual(host) }
                                    .accessibilityIdentifier("tasks_create_manual_\(host.id)")
                            }
                        } label: { Label("More task options", systemImage: "ellipsis") }
                        .disabled(hosts.isEmpty).accessibilityIdentifier("tasks_more")
                    }
                    }
                    if showsListActions, !usesBottomCreate {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: createTask) { Label("New scheduled task", systemImage: "plus") }
                            .disabled(hosts.isEmpty).accessibilityIdentifier("tasks_add")
                    }
                    }
                }
    }

    @ToolbarContentBuilder
    private var connectionToolbar: some ToolbarContent {
        if let connectionHeader {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { connectionHeader(listWidth) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { connectionHeader(listWidth) }
        }
        #else
        ToolbarItem(placement: .navigation) { connectionHeader(listWidth) }
            .sharedBackgroundVisibility(.hidden)
        #endif
        }
    }

    @ViewBuilder
    private var searchableTaskList: some View {
        if showsSearchField {
            taskList.searchable(text: searchBinding, prompt: "Search tasks")
        } else {
            #if os(iOS)
            taskList.scopedBottomSearch(text: searchBinding, active: bottomSearchActive ?? .constant(false),
                shown: bottomSearchShown, prompt: "Search tasks")
            #else
            taskList
            #endif
        }
    }

    private func createTask() {
        if let onCreate { onCreate() } else { sheet = .chat }
    }

    private var taskRequestError: String? {
        let failures = model.loadErrors.filter { connectedHostIDs?.contains($0.key) ?? true }
            .values.sorted()
        let messages = [model.error].compactMap { $0 } + failures
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            connectionWarning
            if let error = taskRequestError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                    Button("Try again") { Task { await model.refresh() } }.accessibilityIdentifier("tasks_retry")
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("tasks_request_error")
            }
            if model.loading {
                ProgressView("Loading tasks…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "Your next task starts here" : "No matching tasks", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Tell your agent what you want done and when. Work out the details together.")
                } actions: {
                    Button("Create task", systemImage: "plus", action: createTask)
                        .buttonStyle(.borderedProminent).disabled(hosts.isEmpty).accessibilityIdentifier("tasks_empty_chat")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(ScheduledTaskGroup.allCases, id: \.self) { group in
                        let items = filtered.filter { $0.task.listGroup == group }
                        if !items.isEmpty {
                            Section {
                                groupHeader(group, count: items.count)
                                if !collapsedGroups.contains(group) {
                                    ForEach(items) { item in
                                        taskRow(item)
                                            .accessibilityIdentifier("task_row_\(item.task.id)")
                                            #if os(iOS)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                            #endif
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier("tasks_list")
            }
            Text("Tasks run while their host is awake and LFG is running.")
                .font(.caption).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func taskRow(_ item: HostedScheduledTask) -> some View {
        if sidebarVisibility != nil {
            Button {
                bottomSearchActive?.wrappedValue = false
                pathBinding.wrappedValue = [.task(item.id)]
            } label: { TaskListSummary(item: item) }
            .buttonStyle(.plain)
            .listRowBackground(selectedTaskID == item.id ? Color.accentColor.opacity(0.12) : Color.clear)
            .accessibilityAddTraits(selectedTaskID == item.id ? .isSelected : [])
        } else {
            NavigationLink(value: ScheduledTaskRoute.task(item.id)) { TaskListSummary(item: item) }
        }
    }

    private func groupHeader(_ group: ScheduledTaskGroup, count: Int) -> some View {
        let collapsed = collapsedGroups.contains(group)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed { collapsedGroups.remove(group) }
                else { collapsedGroups.insert(group) }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 13)
                Text(group.title)
                if collapsed { Spacer(minLength: 0) }
                Text("\(count)").foregroundStyle(.tertiary)
                if !collapsed { Spacer(minLength: 0) }
            }
            .foregroundStyle(collapsed ? .primary : .secondary)
            .contentShape(Rectangle())
            #if os(iOS)
            .font(.system(size: collapsed ? 17 : 15))
            .padding(.horizontal, 20)
            .padding(.top, collapsed ? 18 : 20)
            .padding(.bottom, collapsed ? 18 : 8)
            #else
            .font(.system(size: 12))
            .padding(.vertical, 6)
            #endif
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task_group_\(group.rawValue)")
        .accessibilityLabel("\(group.title), \(count) tasks")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityHint("Double tap to \(collapsed ? "expand" : "collapse") this group")
        .listRowSeparator(.hidden)
        #if os(iOS)
        .listRowInsets(EdgeInsets())
        #endif
    }
}

/// The same two-line hierarchy and status dot used by the native session lists.
private struct ScheduledSessionRow: View {
    let title: String
    let subtitle: String
    let status: String
    var metadata: String? = nil
    private var textSpacing: CGFloat {
        #if os(macOS)
        2
        #else
        4
        #endif
    }
    private var dotColor: Color {
        switch status {
        case "Running", "Starting", "Scheduled": .green
        case "Needs input", "Paused": .orange
        case "Failed", "Interrupted": .red
        default: .secondary.opacity(0.35)
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(dotColor).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: textSpacing) {
                Text(title).foregroundStyle(.primary).lineLimit(1)
                    #if os(macOS)
                    .font(.system(size: 13, weight: .medium))
                    #else
                    .font(.system(size: 17))
                    #endif
                Text(subtitle).foregroundStyle(.secondary).lineLimit(metadata == nil ? 1 : nil)
                    #if os(macOS)
                    .font(.system(size: 11))
                    #else
                    .font(.system(size: 15))
                    #endif
                if let metadata {
                    Text(metadata).foregroundStyle(.secondary).lineLimit(1)
                        #if os(macOS)
                        .font(.system(size: 11))
                        #else
                        .font(.system(size: 13))
                        #endif
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(macOS)
        .padding(.vertical, 3)
        #else
        .padding(.vertical, 15)
        #endif
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, subtitle, metadata, status].compactMap { $0 }.joined(separator: ", "))
    }
}

private struct TaskListSummary: View {
    let item: HostedScheduledTask
    var body: some View {
        ScheduledSessionRow(title: item.task.name,
            subtitle: item.task.schedule.description(nextRunAt: item.task.nextRunAt),
            status: item.task.statusLabel,
            metadata: "\(item.host.name) · \(item.task.modelLabel)")
    }
}

private struct TaskInstructions: View {
    let text: String
    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            instructions(lineLimit: isExpanded ? nil : 3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("task_instructions")
                .background(alignment: .topLeading) {
                    instructions(lineLimit: 3)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { collapsedHeight = $0 }
                        .accessibilityHidden(true)
                }
                .background(alignment: .topLeading) {
                    instructions(lineLimit: nil)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { fullHeight = $0 }
                        .accessibilityHidden(true)
                }
            if fullHeight > collapsedHeight + 0.5 {
                Button(isExpanded ? "Show less" : "Show more") {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("task_instructions_toggle")
                .accessibilityLabel(isExpanded ? "Show fewer instructions" : "Show all instructions")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }
        }
        .onChange(of: text) { isExpanded = false }
    }

    private func instructions(lineLimit: Int?) -> some View {
        Text(text)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduledTaskDetail: View {
    let task: ScheduledTaskRecord
    let client: ScheduledTasksClient
    let changing: Bool
    let edit: () -> Void
    let action: (String, Bool?) -> Void
    let openSession: (String) -> Void
    @State private var runs: [ScheduledTaskRun] = []
    @State private var total = 0
    @State private var historyLoaded = false
    @State private var error: String?
    @State private var confirmCancel = false
    @State private var selectedRun: ScheduledTaskRun?
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.name)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("task_title")
                Text(task.schedule.description(nextRunAt: task.nextRunAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("task_schedule")
                TaskInstructions(text: task.prompt)
                    .id(task.id)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            #if os(iOS)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            #endif
            Text("SESSIONS")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("task_sessions_heading")
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
            if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("task_history_error") }
            if !historyLoaded, error == nil { ProgressView("Loading run history…").accessibilityIdentifier("task_history_loading") }
            else if runs.isEmpty, error == nil { Text("Sessions will appear here when this task runs.").foregroundStyle(.secondary).accessibilityIdentifier("task_history_empty") }
            ForEach(runs) { run in
                Button {
                    if let sessionID = run.sessionId { openSession(sessionID) }
                    else { selectedRun = run }
                } label: {
                    HStack(spacing: 8) {
                        ScheduledSessionRow(title: run.summary ?? run.error ?? run.taskName ?? task.name,
                            subtitle: runSubtitle(run), status: run.statusLabel)
                        Image(systemName: run.sessionId == nil ? "info.circle" : "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                #endif
                .accessibilityIdentifier("task_run_\(run.id)")
                .accessibilityHint(run.sessionId == nil ? "Shows why no session started" :
                    "Opens this session")
                .contextMenu {
                    Button("Run details") { selectedRun = run }
                        .accessibilityIdentifier("task_run_details_\(run.id)")
                }
            }
            if runs.count < total { Button("Load older runs") { Task { await load(more: true) } }.accessibilityIdentifier("task_runs_more") }
        }
        .listStyle(.plain)
        #if os(iOS)
        .environment(\.defaultMinListRowHeight, 0)
        #endif
        .accessibilityIdentifier("task_detail")
        #if os(iOS)
        .navigationTitle("Scheduled Task")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .navigationTitle("")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Task settings", systemImage: "slider.horizontal.3", action: edit)
                        .disabled(task.cancelledAt != nil).accessibilityIdentifier("task_edit")
                    if task.cancelledAt == nil {
                        Divider()
                        Button("Run now", systemImage: "play.fill") { action("run", nil) }
                            .disabled(changing || task.currentRun != nil).accessibilityIdentifier("task_run_now")
                        if task.canResume {
                            Button(task.enabled ? "Pause schedule" : "Resume schedule", systemImage: task.enabled ? "pause" : "play") { action("", !task.enabled) }
                                .disabled(changing).accessibilityIdentifier("task_pause_resume")
                        }
                        Button("Cancel future runs", systemImage: "xmark.circle", role: .destructive) { confirmCancel = true }
                            .disabled(changing).accessibilityIdentifier("task_cancel")
                    }
                } label: { Label("Task options", systemImage: "ellipsis") }
                .accessibilityIdentifier("task_options")
            }
        }
        .confirmationDialog("Cancel future runs?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel future runs", role: .destructive) { action("cancel", nil) }
        } message: { Text("Previous runs stay in history. Any running session will continue.") }
        .sheet(item: $selectedRun) { run in
            NavigationStack {
                ScheduledRunDetail(run: run, client: client) { sessionID in
                    selectedRun = nil; openSession(sessionID)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { selectedRun = nil }.accessibilityIdentifier("task_run_done")
                } }
            }
            #if os(macOS)
            .frame(width: 650, height: 650)
            #endif
        }
        .task(id: task.id) { runs = []; historyLoaded = false; while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(5)) } }
    }
    private func runSubtitle(_ run: ScheduledTaskRun) -> String {
        var parts = [run.statusLabel]
        if let at = run.startedAt ?? run.scheduledFor {
            parts.append(Date(timeIntervalSince1970: at / 1000).formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        }
        if run.sessionId == nil { parts.append("No session started") }
        return parts.joined(separator: " · ")
    }
    private func load(more: Bool = false) async {
        do {
            let page = try await client.runs(task.id, offset: more ? runs.count : 0)
            if more { runs += page.runs }
            else {
                let refreshedIDs = Set(page.runs.map(\.id))
                runs = page.runs + runs.filter { !refreshedIDs.contains($0.id) }
            }
            total = page.total; historyLoaded = true; error = nil
        }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct ScheduledRunDetail: View {
    let run: ScheduledTaskRun
    let client: ScheduledTasksClient
    let openSession: (String) -> Void
    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: run.statusLabel)
                if let start = run.startedAt { LabeledContent("Started") { Text(Date(timeIntervalSince1970: start / 1000), format: .dateTime) } }
                if let end = run.finishedAt { LabeledContent("Finished") { Text(Date(timeIntervalSince1970: end / 1000), format: .dateTime) } }
                if let sid = run.sessionId {
                    #if os(macOS)
                    Button("Open in iTerm") { openSession(sid) }.accessibilityIdentifier("task_run_open_session")
                    #else
                    Button("Open in Sessions") { openSession(sid) }.accessibilityIdentifier("task_run_open_session")
                    #endif
                }
            }
            if let error = run.error { Section("What happened") { Text(error).textSelection(.enabled) } }
            if let summary = run.summary { Section("Result") { Text(summary).textSelection(.enabled).accessibilityIdentifier("task_run_result") } }
        }.navigationTitle("Run details")
    }
}

private struct TaskRepo: Decodable, Identifiable, Sendable { var cwd: String; var name: String?; var id: String { cwd } }
private struct TaskRepos: Decodable, Sendable { var repos: [TaskRepo] }

private struct TaskChatDraft {
    var prompt = ""
    var cwd = ""
    var sessionID: String?
    var starting = false
    var error: String?
}

private enum TaskEditorPicker: String, Identifiable {
    case directory, timezone
    var id: String { rawValue }
}

private struct TaskDirectories: Decodable, Sendable { var root: String?; var inbox: String? }

private struct TaskDirectory: Identifiable {
    let name: String
    let path: String
    var id: String { path }
    init(name: String? = nil, path: String) {
        self.path = path
        self.name = name ?? ((path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent)
    }
}

private struct TaskDirectoryPicker: View {
    let entries: [TaskDirectory]
    let recents: [TaskDirectory]
    let selectedPath: String
    let onSelect: (String) -> Void
    @State private var addingPath = false
    @State private var path = ""
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            #if os(iOS)
            DirectorySheet(
                recents: recents.map { .init(name: $0.name, path: $0.path) },
                all: entries.map { .init(name: $0.name, path: $0.path) },
                selectedPath: selectedPath,
                onSelect: { onSelect($0.path) },
                onAddByPath: { addingPath = true },
                onConfirm: { dismiss() },
                onCancel: { dismiss() }
            )
            .presentationDetents([.large])
            #else
            NavigationStack {
                List {
                    ForEach(entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) }) { entry in
                        Button { onSelect(entry.path) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.name)
                                    Text(entry.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedPath == entry.path { Image(systemName: "checkmark") }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("task_directory_option_\(entry.path)")
                    }
                    Button("Add directory by path…") { addingPath = true }
                        .accessibilityIdentifier("task_directory_add")
                }
                .searchable(text: $query, prompt: "Search directories")
                .navigationTitle("Directory")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }.frame(width: 520, height: 540)
            #endif
        }
        .alert("Add directory", isPresented: $addingPath) {
            TextField("Absolute path on host", text: $path)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled().accessibilityIdentifier("task_directory_path")
            Button("Add") { onSelect(path.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .disabled(!path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/"))
                .accessibilityIdentifier("task_directory_confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("Enter an absolute directory path on the task's host.") }
    }
}

private struct TaskTimezonePicker: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var identifiers: [String] {
        Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", selection])).sorted().filter {
            query.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(identifiers, id: \.self) { identifier in
                Button {
                    selection = identifier
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(identifier.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.primary)
                            if let zone = TimeZone(identifier: identifier) {
                                Text(zone.localizedName(for: .shortGeneric, locale: .current) ?? identifier)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selection == identifier { Image(systemName: "checkmark") }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("task_timezone_\(identifier)")
            }
            .searchable(text: $query, prompt: "Search timezones")
            .navigationTitle("Timezone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("task_timezone_cancel")
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 580)
        #else
        .presentationDetents([.large])
        #endif
    }
}

private struct ScheduledTaskEditor: View {
    let client: ScheduledTasksClient
    let task: ScheduledTaskRecord?
    let openSession: (String, String) -> Void
    @State private var currentTask: ScheduledTaskRecord?
    @State private var draft: ScheduledTaskDraft
    @State private var startingChat = false
    @State private var chatError: String?
    @State private var directories: [TaskDirectory] = []
    @State private var catalog = ModelCatalogResponse.fallback
    @State private var activePicker: TaskEditorPicker?
    #if os(iOS)
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    #endif
    @State private var saving = false
    @State private var refreshing = false
    @State private var refreshFailed = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(client: ScheduledTasksClient, task: ScheduledTaskRecord?, openSession: @escaping (String, String) -> Void = { _, _ in }) {
        self.client = client; self.task = task; self.openSession = openSession
        _currentTask = State(initialValue: task)
        _draft = State(initialValue: .init(task: task))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if refreshing {
                    ProgressView("Loading task settings…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("task_editor_loading")
                } else {
                    taskForm
                }
            }
            .navigationTitle(task == nil ? "New task" : "Edit task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving || startingChat).accessibilityIdentifier("task_editor_cancel")
                }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            saving = true
                            Task {
                                do { try await client.save(draft, id: task?.id); dismiss() }
                                catch { self.error = error.localizedDescription }
                                saving = false
                            }
                        }
                        .disabled(saving || startingChat || refreshing || refreshFailed || !draft.isValid || currentTask?.cancelledAt != nil)
                        .accessibilityIdentifier("task_save")
                    }
            }
            .task { await loadChoices() }
            .sheet(item: $activePicker) { picker in
                switch picker {
                case .directory:
                    TaskDirectoryPicker(entries: directoryChoices, recents: recentDirectoryChoices, selectedPath: draft.cwd) {
                        draft.cwd = $0
                        activePicker = nil
                    }
                case .timezone:
                    TaskTimezonePicker(selection: $draft.timezone)
                }
            }
            .task(id: task?.id) {
                guard let task else { return }
                await reloadTask(task.id)
            }
        }
        .interactiveDismissDisabled(saving || startingChat)
        #if os(macOS)
        .frame(width: 650, height: 720)
        #endif
    }

    private var taskForm: some View {
            Form {
                if currentTask != nil {
                    Section {
                        Button(action: startEditingChat) {
                            HStack {
                                Label(startingChat ? "Starting chat…" : "Edit with chat", systemImage: "bubble.left.and.bubble.right")
                                if startingChat { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(refreshFailed || currentTask?.cancelledAt != nil)
                        .accessibilityIdentifier("task_edit_chat")
                        if let chatError {
                            Text(chatError).foregroundStyle(.red).accessibilityIdentifier("task_edit_chat_error")
                        }
                    } footer: {
                        Text("Start a new Claude Code session using the saved task settings.")
                    }
                }
                Section("Task") {
                    TextField("Name", text: $draft.name).accessibilityIdentifier("task_name")
                    TextField("What should the agent do?", text: $draft.prompt, axis: .vertical).lineLimit(4...10).accessibilityIdentifier("task_prompt")
                }
                Section("When") {
                    Picker("Schedule", selection: $draft.kind) { Text("One time").tag("once"); Text("Repeating interval").tag("interval"); Text("Custom cron").tag("cron") }.accessibilityIdentifier("task_schedule_kind")
                    if draft.kind == "once" {
                        DatePicker("Run at", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, TimeZone(identifier: draft.timezone) ?? .current).accessibilityIdentifier("task_date")
                    } else if draft.kind == "interval" {
                        TextField("Every (minutes)", text: $draft.intervalMinutes).accessibilityIdentifier("task_interval")
                    } else {
                        ForEach(ScheduledTaskCronField.allCases) { field in
                            cronField(field)
                        }
                        Text("* means every value. Weekdays: 0 or 7 is Sunday, 1 is Monday. Existing ranges and steps stay unchanged until you replace them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { activePicker = .timezone } label: {
                        LabeledContent("Timezone") {
                            HStack(spacing: 6) {
                                Text(draft.timezone.replacingOccurrences(of: "_", with: " "))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("task_timezone")
                    if currentTask == nil || currentTask?.canResume == true { Toggle("Enabled", isOn: $draft.enabled).accessibilityIdentifier("task_enabled") }
                }
                Section("Where and how") {
                    LabeledContent("Host", value: client.host.name)
                    modelPicker
                    Button { activePicker = .directory } label: {
                        LabeledContent("Directory") {
                            HStack(spacing: 6) {
                                Text(draft.cwd.isEmpty ? "Choose a directory" : draft.cwd)
                                    .font(.body.monospaced()).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("task_directory")
                }
                Section { Text("Each run starts a new conversation. If the host is offline, the task runs when it returns. Missed repeating runs are combined into one.").font(.footnote).foregroundStyle(.secondary) }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("task_editor_error")
                        if refreshFailed, let task {
                            Button("Try again") { Task { await reloadTask(task.id) } }
                                .accessibilityIdentifier("task_editor_retry")
                        }
                    }
                }
            }.formStyle(.grouped)
            .disabled(saving || startingChat)
    }

    private var modelPicker: some View {
        Picker("Model", selection: Binding(
            get: { "\(draft.agent)|\(draft.model)" },
            set: { choice in
                let parts = choice.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                draft.agent = String(parts[0]); draft.model = String(parts[1])
            }
        )) {
            ForEach(AgentKind.allCases) { agent in
                Section(agent.displayName) {
                    Text("\(agent.displayName) default").tag("\(agent.rawValue)|")
                    ForEach(catalog.models(for: agent), id: \.self) { model in
                        Text(model).tag("\(agent.rawValue)|\(model)")
                    }
                    if draft.agent == agent.rawValue, !draft.model.isEmpty,
                       !catalog.models(for: agent).contains(draft.model) {
                        Text("\(draft.model) (saved)").tag("\(agent.rawValue)|\(draft.model)")
                    }
                }
            }
        }.pickerStyle(.menu).accessibilityIdentifier("task_model")
    }

    private func cronField(_ field: ScheduledTaskCronField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.title)
                    Text("\(field.range.lowerBound)–\(field.range.upperBound), or *")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("*", text: Binding(
                    get: { draft.cronValue(for: field) },
                    set: { draft.setCronValue($0, for: field) }
                ))
                .labelsHidden()
                .font(.body.monospaced()).multilineTextAlignment(.trailing)
                .frame(width: 90)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .autocorrectionDisabled()
                .accessibilityLabel(field.title)
                .accessibilityIdentifier("task_cron_\(field.rawValue)")
                Button { draft.setCronValue("*", for: field) } label: {
                    Text("*").font(.body.monospaced()).frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Every value for \(field.title.lowercased())")
                .accessibilityIdentifier("task_cron_every_\(field.rawValue)")
            }
            if !draft.isCronFieldValid(field) {
                Text("Enter \(field.range.lowerBound)–\(field.range.upperBound), or choose *.")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("task_cron_error_\(field.rawValue)")
            }
        }
    }

    private var directoryChoices: [TaskDirectory] {
        var choices = directories
        #if os(iOS)
        choices += store.sessions.compactMap { session in
            guard let path = session.cwd, path.hasPrefix("/") else { return nil }
            return TaskDirectory(path: path)
        }
        #endif
        if !draft.cwd.isEmpty { choices.append(TaskDirectory(path: draft.cwd)) }
        var seen = Set<String>()
        return choices.filter { seen.insert($0.path).inserted }
    }

    private var recentDirectoryChoices: [TaskDirectory] {
        #if os(iOS)
        return settings.recentDirs.map { path in
            directoryChoices.first { $0.path == path } ?? TaskDirectory(path: path)
        }
        #else
        return []
        #endif
    }

    private func loadChoices() async {
        async let repos = try? client.call("/api/repos", as: TaskRepos.self)
        async let dirs = try? client.call("/api/dirs", as: TaskDirectories.self)
        #if os(iOS)
        if let host = settings.hosts.first(where: { $0.id == client.host.id }) {
            catalog = store.modelCatalog(for: host)
            await store.loadModelCatalog(for: host)
            catalog = store.modelCatalog(for: host)
        } else {
            catalog = (try? await client.call("/api/models", as: ModelCatalogResponse.self)) ?? .fallback
        }
        #else
        catalog = (try? await client.call("/api/models", as: ModelCatalogResponse.self)) ?? .fallback
        #endif
        let (loadedRepos, loadedDirs) = await (repos, dirs)
        var choices: [TaskDirectory] = []
        if let root = loadedDirs?.root, !root.isEmpty { choices.append(.init(name: "Root", path: root)) }
        if let inbox = loadedDirs?.inbox, !inbox.isEmpty { choices.append(.init(name: "Inbox", path: inbox)) }
        choices += (loadedRepos?.repos ?? []).map { TaskDirectory(name: $0.name, path: $0.cwd) }
        directories = choices
    }

    private func startEditingChat() {
        guard let currentTask, !startingChat, !saving, !refreshing, !refreshFailed,
              currentTask.cancelledAt == nil else { return }
        startingChat = true; chatError = nil
        Task {
            defer { startingChat = false }
            do {
                let sessionID = try await client.startEditingChat(currentTask.id)
                openSession(client.host.id, sessionID)
            } catch { chatError = error.localizedDescription }
        }
    }

    private func reloadTask(_ id: String) async {
        refreshing = true; refreshFailed = true; error = nil
        defer { refreshing = false }
        do {
            let saved = try await client.task(id)
            currentTask = saved; draft = .init(task: saved); refreshFailed = false
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct TaskChatStart: Encodable { let prompt: String; let cwd: String; let agent: String; let timezone: String }
private struct TaskChatCreated: Decodable, Sendable { let sessionId: String? }
private struct ScheduledTaskChat: View {
    let hosts: [ScheduledTaskHost]
    let initialHost: ScheduledTaskHost
    let openSession: (String, String) -> Void
    @State private var draft = TaskChatDraft()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScheduledTaskChatContent(hosts: hosts, initialHost: initialHost, task: nil,
                draft: $draft, openSession: openSession)
                .navigationTitle("New scheduled task")
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(draft.starting).accessibilityIdentifier("task_chat_done")
                } }
        }
        #if os(macOS)
        .frame(width: 650, height: 720)
        #endif
    }
}

private struct ScheduledTaskChatContent: View {
    let hosts: [ScheduledTaskHost]
    let initialHost: ScheduledTaskHost
    let task: ScheduledTaskRecord?
    @Binding var draft: TaskChatDraft
    let openSession: (String, String) -> Void
    @State private var hostID: String
    @State private var repos: [TaskRepo] = []
    private var client: ScheduledTasksClient { .init(host: hosts.first(where: { $0.id == hostID }) ?? initialHost) }
    private var context: ScheduledTaskChatContext { .init(taskID: task?.id) }
    private var savedChatKey: String { context.savedSessionKey(hostID: client.host.id) }

    init(hosts: [ScheduledTaskHost], initialHost: ScheduledTaskHost, task: ScheduledTaskRecord?,
         draft: Binding<TaskChatDraft>, openSession: @escaping (String, String) -> Void) {
        self.hosts = hosts; self.initialHost = initialHost; self.task = task
        self._draft = draft; self.openSession = openSession
        _hostID = State(initialValue: initialHost.id)
    }

    var body: some View {
        Group {
                Form {
                    Section {
                        if let task {
                            Text(task.name).font(.headline).accessibilityIdentifier("task_chat_edit_title")
                            Text("Tell Claude Code what to change. It will update this task and keep its session history.")
                                .foregroundStyle(.secondary)
                            TextField("What would you like to change?", text: $draft.prompt, axis: .vertical)
                                .lineLimit(4...8).accessibilityIdentifier("task_chat_request")
                        } else {
                            Label("Describe it. Work out the details together.", systemImage: "bubble.left.and.bubble.right").font(.headline)
                            Text("Claude Code will help choose the timing, model, and instructions, then save your task.").foregroundStyle(.secondary)
                            TextField("Tomorrow morning, review changes in…", text: $draft.prompt, axis: .vertical)
                                .lineLimit(4...8).accessibilityIdentifier("task_chat_request")
                        }
                    }
                    if let task {
                        Section("Current task") {
                            LabeledContent("Host", value: client.host.name)
                            LabeledContent("Schedule", value: task.schedule.label)
                            LabeledContent("Timezone", value: task.schedule.timezone)
                            LabeledContent("Model", value: task.modelLabel)
                            Text(task.prompt).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } else {
                        Section("On this host") {
                            Picker("Host", selection: $hostID) { ForEach(hosts) { Text($0.name).tag($0.id) } }
                                .disabled(draft.starting).accessibilityIdentifier("task_chat_host")
                            LabeledContent("Setup agent", value: "Claude Code")
                            if !repos.isEmpty {
                                Menu("Choose a directory") { ForEach(repos) { repo in Button(repo.name ?? repo.cwd) { draft.cwd = repo.cwd } } }
                                    .accessibilityIdentifier("task_chat_directory_picker")
                            }
                            TextField("Directory (optional)", text: $draft.cwd).accessibilityIdentifier("task_chat_directory")
                        }
                    }
                    Section {
                        Button(draft.starting ? "Starting conversation…" : "Start conversation", systemImage: "arrow.up.message") { start() }
                            .disabled(draft.starting || draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("task_chat_start")
                        if let saved = UserDefaults.standard.string(forKey: savedChatKey) {
                            Button(task == nil ? "Continue previous setup" : "Continue editing conversation") { openSession(client.host.id, saved) }
                                .accessibilityIdentifier("task_chat_continue")
                        }
                    }
                    if let error = draft.error {
                        Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("task_chat_error") }
                    }
                }.formStyle(.grouped)
        }
        .task(id: client.host.id) {
            guard task == nil else { return }
            draft.cwd = ""
            repos = (try? await client.call("/api/repos", as: TaskRepos.self))?.repos ?? []
        }
    }

    private func start() {
        draft.starting = true; draft.error = nil
        Task {
            do {
                let result: TaskChatCreated = try await client.call(context.endpoint,
                    body: JSONEncoder().encode(TaskChatStart(prompt: draft.prompt, cwd: task?.cwd ?? draft.cwd,
                        agent: "claude", timezone: task?.schedule.timezone ?? TimeZone.current.identifier)))
                guard let id = result.sessionId else { throw ScheduledTaskClientError(message: "The conversation started without an ID. Check Sessions before starting again.") }
                UserDefaults.standard.set(id, forKey: savedChatKey); draft.sessionID = id
                openSession(client.host.id, id)
            } catch { draft.error = error.localizedDescription }
            draft.starting = false
        }
    }
}
