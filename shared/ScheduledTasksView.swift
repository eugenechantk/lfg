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
    /// The Mac pushes the edit form as a page; iOS presents it as a sheet.
    case edit(String)
    #if os(macOS)
    case create(String)
    case createChat(String)
    #endif
}

private var scheduledTaskActionPlacement: ToolbarItemPlacement {
    #if os(macOS)
    .automatic
    #else
    .primaryAction
    #endif
}

struct ScheduledTasksView: View {
    let hosts: [ScheduledTaskHost]
    var searchQuery: Binding<String>? = nil
    var navigationPath: Binding<[ScheduledTaskRoute]>? = nil
    var showsSearchField = true
    var bottomSearchActive: Binding<Bool>? = nil
    var bottomSearchShown = false
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>? = nil
    var listFooter: AnyView? = nil
    var connectionHeader: ((CGFloat) -> AnyView)? = nil
    var connectionWarning: AnyView? = nil
    var connectedHostIDs: Set<String>? = nil
    #if os(macOS)
    /// The Sessions list's hidden-directory rule, applied to tasks' folders.
    var hiddenDirectories = HiddenDirs()
    /// Opens the hidden-directories panel from the host strip's menu.
    var onHiddenDirectories: (() -> Void)? = nil
    #endif
    var embedsInNavigationStack = true
    var showsListActions = true
    var usesBottomCreate = false
    var onSearch: (() -> Void)? = nil
    var onCreate: (() -> Void)? = nil
    var sessionSelection: Binding<String?>? = nil
    var sessionDestination: ((String) -> AnyView)? = nil
    var openSession: (String, String) -> Void
    /// Reports the Needs input count for the Tasks tab badge.
    var onNeedsInputCountChange: ((Int) -> Void)? = nil
    @State private var model = ScheduledTasksModel()
    @State private var path: [ScheduledTaskRoute] = []
    /// The task whose edit chat is starting (Mac), so its button can show progress.
    @State private var chatOpeningTaskID: String?
    /// Group ids: a status section's raw value, or "dir:<folder>" in directory mode.
    @State private var collapsedGroups: Set<String> = [TaskListSection.closed.rawValue]
    /// nil shows every host.
    @State private var hostFilter: String?
    #if os(macOS)
    /// The host strip's Group by, the same control as on Sessions.
    @State private var groupMode: GroupMode = .status
    #endif
    @State private var localSearch = ""
    @State private var listWidth: CGFloat = 320
    @State private var desktopSearchShown = false
    @FocusState private var desktopSearchFocused: Bool
    @State private var pendingSession: (hostID: String, sessionID: String)?
    private var search: String { searchQuery?.wrappedValue ?? localSearch }
    private var searchBinding: Binding<String> { searchQuery ?? $localSearch }
    private var pathBinding: Binding<[ScheduledTaskRoute]> { navigationPath ?? $path }
    @State private var sheet: TaskSheet?
    private enum TaskSheet: Identifiable {
        case manual(ScheduledTaskHost), edit(HostedScheduledTask), chat
        /// The task's "Change task" chat, with an optional first message (Ask to fix).
        case taskChat(HostedScheduledTask, String?)
        var id: String {
            switch self {
            case .manual(let h): "manual-\(h.id)"
            case .edit(let t): "edit-\(t.id)"
            case .chat: "chat"
            case .taskChat(let t, _): "taskchat-\(t.id)"
            }
        }
    }
    private var filtered: [HostedScheduledTask] {
        let items = model.tasks.filter { item in
            let task = item.task
            guard hostFilter == nil || item.host.id == hostFilter else { return false }
            return (search.isEmpty || task.name.localizedCaseInsensitiveContains(search)
                    || task.prompt.localizedCaseInsensitiveContains(search)
                    || item.host.name.localizedCaseInsensitiveContains(search)
                    || task.modelLabel.localizedCaseInsensitiveContains(search))
        }.sorted {
            let lhs = $0.task.nextRunAt ?? .greatestFiniteMagnitude
            let rhs = $1.task.nextRunAt ?? .greatestFiniteMagnitude
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        #if os(macOS)
        return TaskDirectoryGrouping.visible(items, hidden: hiddenDirectories) { $0.task }
        #else
        return items
        #endif
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
            if let hostFilter, !hosts.contains(where: { $0.id == hostFilter }) { self.hostFilter = nil }
            while !Task.isCancelled { await model.refresh(); try? await Task.sleep(for: .seconds(5)) }
        }
        .onChange(of: TaskListGrouping.needsInputCount(model.tasks.map(\.task)), initial: true) { _, count in
            onNeedsInputCountChange?(count)
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
        }, content: sheetContent)
    }

    @ViewBuilder
    private func sheetContent(_ destination: TaskSheet) -> some View {
        switch destination {
        case .manual(let host): ScheduledTaskEditor(client: .init(host: host), hosts: hosts, task: nil)
        case .edit(let item):
            ScheduledTaskEditor(client: .init(host: item.host), hosts: hosts, task: item.task,
                                onMoved: { newID, warning in taskMoved(from: item.id, to: newID, warning: warning) },
                                openSession: { hostID, sessionID in
                pendingSession = (hostID, sessionID); sheet = nil
            })
        case .taskChat(let item, let first):
            #if os(iOS)
            TaskChatSheet(client: .init(host: item.host),
                          task: { model.tasks.first(where: { $0.id == item.id })?.task },
                          refresh: { await model.refresh() },
                          firstMessage: first)
                .presentationDetents([.large])
            #else
            EmptyView()
            #endif
        case .chat:
            if let host = hosts.first {
                ScheduledTaskChat(hosts: hosts, initialHost: host) { hostID, sessionID in
                    pendingSession = (hostID, sessionID); sheet = nil
                }
            }
        }
    }

    /// A task moved to another host has a new id there: the open task page follows it.
    private func taskMoved(from oldID: String, to newID: String, warning: String?) {
        Task {
            await model.refresh()
            if let warning { model.error = warning }
            pathBinding.wrappedValue = pathBinding.wrappedValue.compactMap { route in
                switch route {
                case .task(oldID): .task(newID)
                case .edit(oldID): nil
                default: route
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
            pathBinding.wrappedValue.filter { if case .task = $0 { return false }; return true }
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
                    ScheduledTaskDetail(task: item.task, hostName: item.host.name, client: .init(host: item.host), changing: model.changing,
                        edit: {
                            #if os(macOS)
                            pathBinding.wrappedValue.append(.edit(item.id))
                            #else
                            sheet = .edit(item)
                            #endif
                        },
                        action: { action, enabled in Task { await model.act(item, action, enabled: enabled) } },
                        openSession: { openSession(item.host.id, $0) },
                        askToChange: { first in openTaskChat(item, first: first) },
                        refresh: { await model.refresh() },
                        chatOpening: chatOpeningTaskID == item.id)
                        .id(item.id)
                } else {
                    ContentUnavailableView("Task unavailable", systemImage: "calendar.badge.exclamationmark",
                        description: Text("Return to Scheduled Tasks and refresh the list."))
                }
            case .edit(let id):
                if let item = model.tasks.first(where: { $0.id == id }) {
                    ScheduledTaskEditor(client: .init(host: item.host), hosts: hosts, task: item.task, embedded: true, onClose: {
                        if pathBinding.wrappedValue.last == .edit(id) { pathBinding.wrappedValue.removeLast() }
                        Task { await model.refresh() }
                    }, onMoved: { newID, warning in taskMoved(from: id, to: newID, warning: warning) }) { hostID, sessionID in openSession(hostID, sessionID) }
                    .id("edit-\(item.id)")
                } else {
                    ContentUnavailableView("Task unavailable", systemImage: "calendar.badge.exclamationmark",
                        description: Text("Return to Scheduled Tasks and refresh the list."))
                }
            #if os(macOS)
            case .create(let hostID):
                if let host = hosts.first(where: { $0.id == hostID }) {
                    ScheduledTaskEditor(client: .init(host: host), hosts: hosts, task: nil,
                        embedded: true, onClose: { closeCreation(route) })
                        .id("create-\(hostID)")
                } else {
                    unavailableCreationHost(route)
                }
            case .createChat(let hostID):
                if let host = hosts.first(where: { $0.id == hostID }) {
                    ScheduledTaskChat(hosts: hosts, initialHost: host, embedded: true,
                        onClose: { closeCreation(route) }) { hostID, sessionID in
                            closeCreation(route)
                            openSession(hostID, sessionID)
                        }
                        .id("create-chat-\(hostID)")
                } else {
                    unavailableCreationHost(route)
                }
            #endif
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
                    #if os(macOS)
                    if showsListActions { desktopListActions }
                    #else
                    if let onSearch {
                        ToolbarItem(placement: scheduledTaskActionPlacement) {
                            Button("Search tasks", systemImage: "magnifyingglass", action: onSearch)
                                .accessibilityIdentifier("tasks_search")
                        }
                    }
                    if showsListActions {
                    ToolbarItem(placement: scheduledTaskActionPlacement) {
                        Menu {
                            hostFilterMenu
                            ForEach(hosts) { host in
                                Button("Set up manually on \(host.name)") { sheet = .manual(host) }
                                    .accessibilityIdentifier("tasks_create_manual_\(host.id)")
                            }
                        } label: { Label("More task options", systemImage: "ellipsis") }
                        .disabled(hosts.isEmpty).accessibilityIdentifier("tasks_more")
                    }
                    }
                    if showsListActions, !usesBottomCreate {
                    ToolbarItem(placement: scheduledTaskActionPlacement) {
                        Button(action: createTask) { Label("New scheduled task", systemImage: "plus") }
                            .disabled(hosts.isEmpty).accessibilityIdentifier("tasks_add")
                    }
                    }
                    #endif
                }
    }

    /// Shows one host's tasks, or every host's. Only offered when there is more than one host.
    @ViewBuilder
    private var hostFilterMenu: some View {
        if hosts.count > 1 {
            Picker("Show tasks on", selection: $hostFilter) {
                Text("All hosts").tag(String?.none)
                ForEach(hosts) { host in Text(host.name).tag(Optional(host.id)) }
            }
            .accessibilityIdentifier("tasks_host_filter")
            Divider()
        }
    }

    #if os(macOS)
    /// The Sessions list's strip (board dA2-sessions): a dot per host, how many
    /// run, and the capsule whose menu holds the host filter, Group by and
    /// Hidden directories. Replaced the thin pre-S2 band on 2026-10-16.
    private var desktopHostStrip: some View {
        let running = model.tasks.filter { ["starting", "running"].contains($0.task.currentRun?.status ?? "") }.count
        return S2DeskHostStrip(
            hosts: hosts.map { host in
                S2DeskHostStrip.HostDot(id: host.id, label: host.name,
                                        online: connectedHostIDs?.contains(host.id) ?? true)
            },
            workingCount: running,
            workingLabel: "running",
            groupMode: $groupMode,
            onHiddenDirectories: { onHiddenDirectories?() },
            leadingMenu: hosts.count > 1 ? AnyView(
                Picker("Show tasks on", selection: $hostFilter) {
                    Text("All hosts").tag(String?.none)
                    ForEach(hosts) { host in Text(host.name).tag(Optional(host.id)) }
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier("tasks_host_strip_filter")
            ) : nil
        )
        .background(S2Desk.background)
        .accessibilityIdentifier("tasks_host_strip")
    }

    /// Task creation lives in More; the desktop list has no standalone add button.
    @ToolbarContentBuilder
    private var desktopListActions: some ToolbarContent {
        ToolbarItem(placement: scheduledTaskActionPlacement) {
            Menu {
                Button("New scheduled task", systemImage: "plus", action: createTask)
                    .accessibilityIdentifier("tasks_add")
                Button("Create with chat", systemImage: "bubble.left.and.bubble.right") {
                    if let host = creationHost { pathBinding.wrappedValue.append(.createChat(host.id)) }
                }
                .accessibilityIdentifier("tasks_create_chat")
                if listWidth < 360 {
                    Button("Search tasks", systemImage: "magnifyingglass") { toggleDesktopSearch() }
                        .accessibilityIdentifier("tasks_search")
                }
                Divider()
                hostFilterMenu
                ForEach(hosts) { host in
                    Button("Set up manually on \(host.name)") { pathBinding.wrappedValue.append(.create(host.id)) }
                        .accessibilityIdentifier("tasks_create_manual_\(host.id)")
                }
            } label: { Label("More task options", systemImage: "ellipsis") }
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .labelStyle(.iconOnly)
            .disabled(hosts.isEmpty).accessibilityIdentifier("tasks_more")
        }
        .sharedBackgroundVisibility(.hidden)
        if listWidth >= 360 {
        ToolbarItem(placement: scheduledTaskActionPlacement) {
            if listWidth < 1200 {
                Button(action: toggleDesktopSearch) { Label("Search tasks", systemImage: "magnifyingglass") }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("tasks_search")
            } else {
                desktopSearchField.frame(width: 150, height: 30)
            }
        }
        .sharedBackgroundVisibility(.hidden)
        }
    }

    private func toggleDesktopSearch() {
        desktopSearchShown.toggle()
        desktopSearchFocused = desktopSearchShown
        if !desktopSearchShown { searchBinding.wrappedValue = "" }
    }

    private var desktopSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search tasks", text: searchBinding)
                .textFieldStyle(.plain)
                .focused($desktopSearchFocused)
                .accessibilityIdentifier("tasks_search_field")
                .onSubmit { desktopSearchFocused = false }
        }
        .padding(.horizontal, 12)
    }
    #endif

    #if os(macOS)
    private var hostStatusInToolbar: Bool { false }
    #endif

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
        // Host status lives in the strip under the toolbar at every width, as on Sessions.
        if hostStatusInToolbar {
        ToolbarItem(id: listWidth < 700 ? "compact_task_connection" : "labelled_task_connection", placement: .navigation) {
            connectionHeader(listWidth)
        }
            .sharedBackgroundVisibility(.hidden)
        }
        #endif
        }
    }

    @ViewBuilder
    private var searchableTaskList: some View {
        if showsSearchField {
            #if os(macOS)
            taskList.safeAreaInset(edge: .top, spacing: 0) {
                if desktopSearchShown, listWidth < 1200 {
                    desktopSearchField.padding(.vertical, 7).background(.bar)
                }
            }
            #else
            taskList.searchable(text: searchBinding, prompt: "Search tasks")
            #endif
        } else {
            #if os(iOS)
            taskList.scopedBottomSearch(text: searchBinding, active: bottomSearchActive ?? .constant(false),
                shown: bottomSearchShown, prompt: "Search tasks")
            #else
            taskList
            #endif
        }
    }

    /// The phone opens the task's chat sheet; the Mac opens the chat in iTerm (desktop scope).
    private func openTaskChat(_ item: HostedScheduledTask, first: String?) {
        #if os(iOS)
        sheet = .taskChat(item, first)
        #else
        startTaskChat(item, first: first)
        #endif
    }

    /// Starts (or reuses) the task's edit chat and opens it as a session.
    private func startTaskChat(_ item: HostedScheduledTask, first: String? = nil) {
        guard chatOpeningTaskID == nil else { return }
        chatOpeningTaskID = item.id
        Task {
            defer { chatOpeningTaskID = nil }
            do {
                let client = ScheduledTasksClient(host: item.host)
                let sessionID = if let first { try await client.startChat(item.task.id, prompt: first) }
                    else { try await client.startEditingChat(item.task.id) }
                openSession(item.host.id, sessionID)
            } catch { model.error = error.localizedDescription }
        }
    }

    private func createTask() {
        if let onCreate { onCreate(); return }
        #if os(macOS)
        if let host = creationHost { pathBinding.wrappedValue.append(.create(host.id)) }
        #else
        sheet = .chat
        #endif
    }

    #if os(macOS)
    private var creationHost: ScheduledTaskHost? {
        hosts.first(where: { $0.id == hostFilter }) ?? hosts.first
    }

    private func closeCreation(_ route: ScheduledTaskRoute) {
        if pathBinding.wrappedValue.last == route { pathBinding.wrappedValue.removeLast() }
        Task { await model.refresh() }
    }

    private func unavailableCreationHost(_ route: ScheduledTaskRoute) -> some View {
        ContentUnavailableView {
            Label("Host unavailable", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
        } description: {
            Text("This host is no longer configured. Return to Tasks and choose another host.")
        } actions: {
            Button("Back to Tasks") { closeCreation(route) }
                .accessibilityIdentifier("task_create_host_unavailable_back")
        }
    }
    #endif

    private var taskRequestError: String? {
        let failures = model.loadErrors.filter { connectedHostIDs?.contains($0.key) ?? true }
            .values.sorted()
        let messages = [model.error].compactMap { $0 } + failures
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // Below 500pt the toolbar has no room for host status; the board puts it in a strip instead.
            if connectionHeader != nil { desktopHostStrip }
            taskFeedback
            #else
            if model.loading || filtered.isEmpty { taskFeedback }
            #endif
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
                    #if os(iOS)
                    taskFeedback
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    #endif
                    ForEach(taskGroups) { group in
                        Section {
                            sectionHeader(group)
                            if !collapsedGroups.contains(group.id) {
                                ForEach(group.items) { item in
                                    taskRow(item)
                                        .accessibilityIdentifier("task_row_\(item.task.id)")
                                        #if os(iOS)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                        // The board's hairline runs to the screen edge.
                                        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] + 16 }
                                        #else
                                        // AppKit's table adds its own 8pt on each side of these insets.
                                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 9))
                                        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] + 40 }
                                        .listRowBackground(Color.clear)
                                        #endif
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                // Group headers are rows; the default row minimum made each one taller than the board.
                #if os(macOS)
                .environment(\.defaultMinListRowHeight, 1) // AppKit rejects 0
                #else
                .environment(\.defaultMinListRowHeight, 0)
                #endif
                #if os(macOS)
                .scrollContentBackground(.hidden)
                .background(TaskColors.page)
                #endif
                .accessibilityIdentifier("tasks_list")
            }
            if model.loading || filtered.isEmpty { taskHostRequirement.padding() }
        }
        #if os(iOS)
        .listScrollChrome(footer: listFooter)
        #endif
    }

    private var taskFeedback: some View {
        Group {
            connectionWarning
            if let error = taskRequestError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                    Button("Try again") { Task { await model.refresh() } }.accessibilityIdentifier("tasks_retry")
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("tasks_request_error")
            }
        }
    }

    private var taskHostRequirement: some View {
        Text("Tasks run while their host is awake and LFG is running.")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct TaskGroup: Identifiable {
        let id: String
        let title: String
        let hint: String?
        let warning: Bool
        let items: [HostedScheduledTask]
    }

    private var taskGroups: [TaskGroup] {
        #if os(macOS)
        if groupMode == .directory {
            return TaskDirectoryGrouping.sections(filtered) { $0.task }.map {
                TaskGroup(id: "dir:\($0.directory)", title: $0.directory, hint: nil, warning: false, items: $0.items)
            }
        }
        #endif
        return TaskListGrouping.sections(filtered) { $0.task }.map {
            TaskGroup(id: $0.section.rawValue, title: $0.section.title, hint: $0.section.hint,
                      warning: $0.section == .needsInput, items: $0.items)
        }
    }

    @ViewBuilder
    private func taskRow(_ item: HostedScheduledTask) -> some View {
        let row = TaskRowView(model: TaskRowModel.make(task: item.task, hostName: item.host.name))
        if sidebarVisibility != nil {
            Button {
                bottomSearchActive?.wrappedValue = false
                pathBinding.wrappedValue = [.task(item.id)]
            } label: { row }
            .buttonStyle(.plain)
            .listRowBackground(selectedTaskID == item.id ? Color.accentColor.opacity(0.12) : Color.clear)
            .accessibilityAddTraits(selectedTaskID == item.id ? .isSelected : [])
        } else {
            NavigationLink(value: ScheduledTaskRoute.task(item.id)) { row }
                #if os(iOS)
                .navigationLinkIndicatorVisibility(.hidden)
                #endif
        }
    }

    private func sectionHeader(_ group: TaskGroup) -> some View {
        let collapsed = collapsedGroups.contains(group.id)
        return TaskSectionHeader(title: group.title, count: group.items.count, collapsed: collapsed,
                                 hint: group.hint, warning: group.warning, identifier: "task_group_\(group.id)") {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed { collapsedGroups.remove(group.id) } else { collapsedGroups.insert(group.id) }
            }
        }
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

private struct TaskInstructions: View {
    let text: String
    /// Lines shown while collapsed; nil shows everything.
    var clamp: Int? = 3
    /// Whether "Show more" appears when the text is longer than the clamp.
    var expandable = true
    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            instructions(lineLimit: isExpanded ? nil : clamp)
                .font(.system(size: TaskDetailMetrics.body))
                .foregroundStyle(TaskColors.body)
                .textSelection(.enabled)
                .accessibilityIdentifier("task_instructions")
                .background(alignment: .topLeading) {
                    instructions(lineLimit: clamp)
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
            // Only when a whole line is hidden: equal texts can measure a point apart.
            if expandable, fullHeight > collapsedHeight + 8 {
                Button(isExpanded ? "Show less" : "Show more") {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: TaskDetailMetrics.section))
                .foregroundStyle(TaskColors.accent)
                .accessibilityIdentifier("task_instructions_toggle")
                .accessibilityLabel(isExpanded ? "Show fewer instructions" : "Show all instructions")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }
        }
        .onChange(of: text) { isExpanded = false }
    }

    private func instructions(lineLimit: Int?) -> some View {
        Text(text)
            .lineSpacing(3)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduledTaskDetail: View {
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    /// Starts wide: hiding Back on the first frame (width 0) keeps AppKit from showing it again.
    @State private var detailWidth: CGFloat = .greatestFiniteMagnitude
    #endif
    let task: ScheduledTaskRecord
    let hostName: String
    let client: ScheduledTasksClient
    let changing: Bool
    let edit: () -> Void
    let action: (String, Bool?) -> Void
    let openSession: (String) -> Void
    /// Opens the task's chat; the text, when set, is the first message.
    let askToChange: (String?) -> Void
    let refresh: () async -> Void
    var chatOpening = false
    @State private var runs: [ScheduledTaskRun] = []
    @State private var total = 0
    @State private var historyLoaded = false
    @State private var error: String?
    @State private var confirmCancel = false
    @State private var selectedRun: ScheduledTaskRun?
    /// The answer just sent, kept until the host reports the run moving on.
    @State private var answered: (runID: String, label: String)?
    @State private var answering = false
    /// A retry waiting for its session to open.
    @State private var retrying = false
    /// Past runs the viewer has opened (two, then ten more per Show more).
    @State private var olderRequested = 2
    @State private var showsLaterRuns = false
    /// The Mac hides the switcher on task pages, so Back fits the toolbar down to this width; below it Back moves into •••.
    private static let backInMenuBelow: CGFloat = 300
    #if os(macOS)
    private static let runsHeaderGap: CGFloat = 12
    private static let bottomPadding: CGFloat = 24
    private static let pageInset: CGFloat = 18
    #else
    private static let runsHeaderGap: CGFloat = 8
    private static let bottomPadding: CGFloat = 64
    private static let pageInset: CGFloat = 20
    #endif

    private var answeredLabel: String? {
        guard let answered, task.currentRun?.id == answered.runID, task.currentRun?.status == "needs_input" else { return nil }
        return answered.label
    }

    var body: some View {
        let card = TaskStatusCardModel.make(task: task)
        let entries = RunTimelineEntry.entries(task: task, runs: runs)
        let upcoming = entries.filter { $0.node == .upcoming }
        let past = entries.filter { $0.node != .upcoming }
        // Upcoming runs are furthest first, so the folded view keeps the nearest ones.
        let laterFold = RunGroupFold.upcoming(count: upcoming.count, open: showsLaterRuns)
        // Runs the host has not sent yet count as hidden past runs.
        let earlierFold = RunGroupFold.past(loaded: past.count, total: past.count + max(0, total - runs.count), requested: olderRequested)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TaskDetailHeader(task: task, hostName: hostName)
                TaskStatusCard(model: card, prompt: task.currentRun?.prompt, busy: changing || answering || retrying,
                               answered: answeredLabel, hostName: hostName, perform: perform)
                    .padding(.top, 10)
                if task.schedule.kind == "once", card.kind == .waiting || card.kind == .running {
                    Label("One-time task. It moves to Closed when this run ends.", systemImage: "exclamationmark.circle")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .labelStyle(TaskIconLabelStyle(spacing: 6))
                        .padding(.horizontal, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instructions")
                        .font(.system(size: TaskDetailMetrics.section, weight: .semibold)).foregroundStyle(TaskColors.grey)
                    // When a run needs attention (failed, waiting, retrying) the card leads; the instructions shrink to two fixed lines.
                    let attention = card.kind == .failed || card.kind == .waiting
                        || (card.kind == .running && task.consecutiveFailures > 0)
                    // Keyed on the clamp too, so a state change re-measures instead of comparing against stale heights.
                    // The Mac boards show the whole text in these states; the phone boards cut it to two lines.
                    #if os(macOS)
                    TaskInstructions(text: task.prompt, clamp: attention ? nil : 3, expandable: !attention).id("\(task.id)-\(attention)")
                    #else
                    TaskInstructions(text: task.prompt, clamp: attention ? 2 : 3, expandable: !attention).id("\(task.id)-\(attention)")
                    #endif
                }
                .padding(.top, 12)
                // A waiting run lives in the card; with nothing else to list, the section is left out.
                let runsHidden = historyLoaded && error == nil && entries.isEmpty && task.currentRun != nil
                if !runsHidden {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Runs").font(.system(size: TaskDetailMetrics.section, weight: .semibold)).foregroundStyle(TaskColors.grey)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("task_sessions_heading")
                        Spacer()
                        Text(RunTimelineEntry.countLine(task)).font(.system(size: TaskDetailMetrics.runTail)).foregroundStyle(TaskColors.grey)
                    }
                    .padding(.top, Self.runsHeaderGap)
                }
                if let error { Text(error).foregroundStyle(TaskColors.warning).accessibilityIdentifier("task_history_error") }
                if !historyLoaded, error == nil {
                    ProgressView("Loading run history…").accessibilityIdentifier("task_history_loading")
                } else if entries.isEmpty, error == nil, !runsHidden {
                    Text("Runs will appear here when this task runs.").foregroundStyle(.secondary).accessibilityIdentifier("task_history_empty")
                }
                RunTimelineView(
                    entries: Array(upcoming.suffix(laterFold.shown)) + Array(past.prefix(earlierFold.shown)), open: open,
                    later: laterFold.hasToggle ? RunsToggle(label: laterFold.label, count: laterFold.count(upcoming: true),
                                                            opensUp: true, opens: laterFold.opens, identifier: "task_runs_later") {
                        showsLaterRuns.toggle()
                    } : nil,
                    earlier: earlierFold.hasToggle ? RunsToggle(label: earlierFold.label, count: earlierFold.count(upcoming: false),
                                                                opensUp: false, opens: earlierFold.opens, identifier: "task_runs_more") {
                        showEarlier(earlierFold, loaded: past.count)
                    } : nil,
                    retry: { _ in retry() })
            }
            .padding(.horizontal, Self.pageInset)
            .padding(.top, 8)
            // The phone's last row must scroll clear of the Ask bar's fade, as on the board.
            .padding(.bottom, Self.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("task_detail")
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if task.cancelledAt == nil {
                // A retry after a failure keeps the failure wording.
                let afterFailure = card.kind == .failed || (card.kind == .running && task.consecutiveFailures > 0)
                TaskAskBar(placeholder: afterFailure ? "Ask why it failed, or change it…" : "Ask to change this task…") { askToChange(nil) }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                    // As on the board: clear 50pt above the bar, 96% by 15pt below its top, then solid
                    // down to the screen edge, so nothing shows at full strength beside the home indicator.
                    .background(alignment: .top) {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.96)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 65)
                            Color(.systemBackground).opacity(0.96)
                        }
                        .padding(.top, -38)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if task.cancelledAt == nil {
                TaskChatButton(title: card.kind == .failed ? "Fix or change with chat" : "Change with chat", busy: chatOpening) { askToChange(nil) }
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 16)
                    .background(TaskColors.page)
            }
        }
        .background(TaskColors.page)
        .navigationTitle("")
        // AppKit's own Back never appears for this stack, so the page draws its own.
        .navigationBarBackButtonHidden(true)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
        #endif
        .toolbar {
            #if os(macOS)
            if detailWidth >= Self.backInMenuBelow {
                ToolbarItem(placement: .navigation) {
                    Button { dismiss() } label: { Label("Back to tasks", systemImage: "chevron.left") }
                        .labelStyle(.iconOnly).help("Back to tasks")
                        .accessibilityIdentifier("task_back_button")
                }
            }
            ToolbarSpacer(.flexible)
            #endif
            ToolbarItemGroup(placement: scheduledTaskActionPlacement) {
                Button(action: edit) { Label("Edit task", systemImage: "pencil") }
                    .disabled(task.cancelledAt != nil).accessibilityIdentifier("task_edit")
                Menu {
                    #if os(macOS)
                    if detailWidth < Self.backInMenuBelow {
                        Button("Back to tasks", systemImage: "chevron.left") { dismiss() }
                            .accessibilityIdentifier("task_back")
                        Divider()
                    }
                    #endif
                    if task.cancelledAt == nil {
                        Button("Run now", systemImage: "play.fill") { action("run", nil) }
                            .disabled(changing || task.currentRun != nil).accessibilityIdentifier("task_menu_run_now")
                        if task.canResume {
                            Button(task.enabled ? "Pause" : "Resume", systemImage: task.enabled ? "pause" : "play") { action("", !task.enabled) }
                                .disabled(changing).accessibilityIdentifier("task_menu_pause_resume")
                        }
                        Divider()
                        Button("Stop future runs", systemImage: "xmark.circle", role: .destructive) { confirmCancel = true }
                            .disabled(changing).accessibilityIdentifier("task_cancel")
                    }
                } label: { Label("Task options", systemImage: "ellipsis") }
                .accessibilityIdentifier("task_options")
                #if os(macOS)
                .menuIndicator(.hidden)
                #endif
            }
        }
        .confirmationDialog("Stop future runs?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Stop future runs", role: .destructive) { action("cancel", nil) }
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

    private func perform(_ intent: TaskCardIntent) {
        switch intent {
        case .action(.runNow): action("run", nil)
        case .action(.retry): retry()
        case .action(.pause): action("", false)
        case .action(.resume): action("", true)
        case .action(.askToFix): askToChange("Why did the last run fail? Fix the task if you can.")
        case .openSession(let id): openSession(id)
        case .answer(let sid, let option): reply(sid) { try await client.answer(sessionID: sid, index: option.index); return option.label }
        case .reply(let sid, let text): reply(sid) { try await client.send(sessionID: sid, text: text); return text }
        }
    }

    private func reply(_ sessionID: String, _ send: @escaping () async throws -> String) {
        guard !answering, let runID = task.currentRun?.id else { return }
        answering = true; error = nil
        Task {
            defer { answering = false }
            do { answered = (runID, try await send()); await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }

    /// Ten more past runs per tap, fetching the next page when the client runs out; Show less folds back to two.
    private func showEarlier(_ fold: RunGroupFold, loaded: Int) {
        guard fold.opens else { olderRequested = RunGroupFold.maxRows - 1; return }
        olderRequested = fold.shown + RunGroupFold.pastStep
        if olderRequested > loaded, runs.count < total { Task { await load(more: true) } }
    }

    /// A run row opens its session, or its details when no session started. Retry is its own button.
    private func open(_ entry: RunTimelineEntry) {
        if let sid = entry.sessionID { openSession(sid) }
        else if let id = entry.runID, let run = runs.first(where: { $0.id == id }) { selectedRun = run }
    }

    /// Retry shows the retry happening: it starts the run, then opens the run's session as soon as
    /// the host launches it (in iTerm on the Mac, the session view on the phone).
    private func retry() {
        guard !retrying else { return }
        retrying = true; error = nil
        Task {
            defer { retrying = false }
            do {
                guard let run = try await client.runNow(task.id) else { await refresh(); return }
                await refresh()
                // The host launches the agent after replying; its session ID lands in the run a few seconds later.
                for _ in 0..<45 {
                    try await Task.sleep(for: .seconds(1))
                    guard let current = try await client.runs(task.id).runs.first(where: { $0.id == run.id }) else { continue }
                    if let sid = current.sessionId, !sid.isEmpty { openSession(sid); break }
                    if current.status == "failed" { break }
                }
                await refresh()
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
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
    /// The host the task lives on (or the one picked from +). Changing Host in the form moves it.
    let origin: ScheduledTasksClient
    let hosts: [ScheduledTaskHost]
    let task: ScheduledTaskRecord?
    let openSession: (String, String) -> Void
    @State private var hostID: String
    @State private var currentTask: ScheduledTaskRecord?
    @State private var draft: ScheduledTaskDraft
    /// The schedule part of the form (Once / Repeat); `draft` keeps the other details.
    @State private var schedule: ScheduleDraft
    /// The host's next runs for `schedule`, refreshed as it changes.
    @State private var preview: SchedulePreview?
    private let startingChat = false
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
    /// The Mac editor's instructions height, measured from the text.
    @State private var instructionsHeight: CGFloat = 60
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    /// Pushed as a page (the Mac's narrow window) instead of presented as a sheet.
    let embedded: Bool
    /// Leaves the page when embedded; a sheet dismisses itself.
    let onClose: (() -> Void)?
    /// After a move: the task's new list id, and a warning when the original could not be stopped.
    let onMoved: ((String, String?) -> Void)?

    init(client: ScheduledTasksClient, hosts: [ScheduledTaskHost] = [], task: ScheduledTaskRecord?, embedded: Bool = false,
         onClose: (() -> Void)? = nil, onMoved: ((String, String?) -> Void)? = nil,
         openSession: @escaping (String, String) -> Void = { _, _ in }) {
        self.origin = client; self.hosts = hosts; self.task = task; self.openSession = openSession
        self.embedded = embedded; self.onClose = onClose; self.onMoved = onMoved
        _hostID = State(initialValue: client.host.id)
        _currentTask = State(initialValue: task)
        _draft = State(initialValue: .init(task: task))
        _schedule = State(initialValue: ScheduleDraft(schedule: task?.schedule, nextRunAt: task?.nextRunAt))
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }

    /// The host picked in the form.
    private var client: ScheduledTasksClient { .init(host: hosts.first(where: { $0.id == hostID }) ?? origin.host) }
    /// An existing task with another host picked: saving creates it there and stops the original.
    private var moving: Bool { task != nil && hostID != origin.host.id }
    private var moveNote: String { "Saving moves this task to \(client.host.name). Its past runs stay on \(origin.host.name), under Closed." }

    var body: some View {
        Group {
            if embedded { content } else { NavigationStack { content } }
        }
        .interactiveDismissDisabled(saving || startingChat)
        #if os(macOS)
        .frame(width: embedded ? nil : 650, height: embedded ? nil : 720)
        #endif
    }

    private var content: some View {
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                if embedded {
                    // Plain title text centred between Cancel and Save, as on the board (not a glass capsule).
                    ToolbarItem(placement: .navigation) { cancelButton }
                    ToolbarSpacer(.flexible)
                    ToolbarItem(placement: .automatic) {
                        Text(task == nil ? "New task" : "Edit task").font(.system(size: 13, weight: .semibold))
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible)
                    ToolbarItem(placement: .automatic) { saveButton }
                } else {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { saveButton }
                }
                #else
                ToolbarItem(placement: .cancellationAction) { cancelButton }
                ToolbarItem(placement: .confirmationAction) { saveButton }
                #endif
            }
            #if os(macOS)
            .navigationBarBackButtonHidden(embedded)
            #endif
            // Folders and models come from the picked host.
            .task(id: hostID) { await loadChoices() }
            .onChange(of: hostID) { preview = nil }
            .sheet(item: $activePicker) { picker in
                switch picker {
                case .directory:
                    TaskDirectoryPicker(entries: directoryChoices, recents: recentDirectoryChoices, selectedPath: draft.cwd) {
                        draft.cwd = $0
                        activePicker = nil
                    }
                case .timezone:
                    TaskTimezonePicker(selection: $schedule.timezone)
                }
            }
            .task(id: [AnyHashable(schedule.schedule), AnyHashable(hostID)]) {
                // Debounce typing, then ask the host what this schedule will do.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if let result = try? await client.preview(schedule.schedule) { preview = result }
            }
            .task(id: task?.id) {
                guard let task else { return }
                await reloadTask(task.id)
            }
    }

    private var cancelButton: some View {
        Button("Cancel") { close() }
            .disabled(saving || startingChat).accessibilityIdentifier("task_editor_cancel")
    }

    private var saveButton: some View {
        Button {
            saving = true
            Task {
                do {
                    let payload = draft.payload(schedule: schedule.schedule)
                    if let task, moving {
                        do {
                            let moved = try await origin.move(task, as: payload, to: client)
                            onMoved?("\(hostID):\(moved.id)", nil)
                        } catch let partial as ScheduledTaskMoveError {
                            onMoved?("\(hostID):\(partial.task.id)", partial.localizedDescription)
                        }
                    } else {
                        try await client.save(payload, id: task?.id)
                    }
                    close()
                }
                catch { self.error = error.localizedDescription }
                saving = false
            }
        } label: {
            // An explicit white label: the prominent style's own label colour read black on the board's blue.
            Text(saving ? "Saving…" : "Save").foregroundStyle(.white)
        }
        .disabled(saving || refreshing || refreshFailed || !draft.hasValidDetails || schedule.problem() != nil
                  || preview?.error != nil || currentTask?.cancelledAt != nil)
        .accessibilityIdentifier("task_save")
        .prominentSaveStyle()
    }

    @ViewBuilder
    private var taskForm: some View {
        #if os(macOS)
        macTaskForm
        #else
        phoneTaskForm
        #endif
    }

    #if os(macOS)
    /// The Mac edit page: cards on a scroll view, sized to the dA2 boards.
    private var macTaskForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("Task name", text: $draft.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold))
                            .accessibilityIdentifier("task_name")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Instructions").font(.system(size: 11)).foregroundStyle(.secondary)
                        // A text field ignores line spacing, so this is an editor sized to its own text.
                        TextEditor(text: $draft.prompt)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .scrollContentBackground(.hidden)
                            .scrollDisabled(true)
                            .padding(.horizontal, -5)
                            .frame(height: max(instructionsHeight + 4, 40))
                            .background(alignment: .topLeading) {
                                Text(draft.prompt.isEmpty ? " " : draft.prompt)
                                    .font(.system(size: 14)).lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .hidden()
                                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { instructionsHeight = $0 }
                                    .accessibilityHidden(true)
                            }
                            .accessibilityIdentifier("task_prompt")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
                }
                .background(TaskPalette.card, in: RoundedRectangle(cornerRadius: 14))
                macSectionHeader("When")
                ScheduleEditorSection(draft: $schedule, preview: preview) { activePicker = .timezone }
                if let problem = schedule.problem() ?? preview?.error {
                    Text(problem).font(.system(size: 12)).foregroundStyle(.red)
                        .padding(.horizontal, 4).padding(.top, 8)
                        .accessibilityIdentifier("task_schedule_problem")
                }
                macSectionHeader("Runs on")
                VStack(spacing: 0) {
                    macRunsOnRow("Host", first: true) { macHostMenu }
                    macRunsOnRow("Folder") {
                        Button { activePicker = .directory } label: {
                            HStack(spacing: 6) {
                                Text(draft.cwd.isEmpty ? "Choose a folder" : TaskDetailHeader.shortPath(draft.cwd))
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1).truncationMode(.middle)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("task_directory")
                    }
                    macRunsOnRow("Agent") {
                        TaskSegmentedPicker(selection: Binding(get: { draft.agent }, set: { agent in
                            guard agent != draft.agent else { return }
                            draft.agent = agent; draft.model = ""
                        }), options: [(AgentKind.claude.rawValue, "Claude Code"), (AgentKind.codex.rawValue, "Codex")],
                            identifier: "task_agent")
                        .fixedSize()
                    }
                    macRunsOnRow("Model") { macModelMenu }
                }
                .background(TaskPalette.card, in: RoundedRectangle(cornerRadius: 14))
                if moving {
                    Text(moveNote).font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.top, 8)
                        .accessibilityIdentifier("task_move_note")
                }
                if let error {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red).accessibilityIdentifier("task_editor_error")
                        if refreshFailed, let task {
                            Button("Try again") { Task { await reloadTask(task.id) } }
                                .accessibilityIdentifier("task_editor_retry")
                        }
                    }
                    .padding(.horizontal, 4).padding(.top, 10)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
        }
        .background(TaskColors.page)
        .disabled(saving || startingChat)
    }

    private func macSectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.top, 19).padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }

    private func macRunsOnRow<Value: View>(_ label: String, first: Bool = false, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary.opacity(0.82))
            Spacer(minLength: 8)
            value()
        }
        .frame(minHeight: 40.5)
        .padding(.horizontal, 14)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
        }
    }

    /// The host's dot is green once it has answered for this form.
    private var macHostMenu: some View {
        let label = HStack(spacing: 6) {
            Circle().fill(preview == nil ? Color.secondary : Color.green).frame(width: 7, height: 7)
            Text(client.host.name).foregroundStyle(.secondary)
        }
        return Group {
            if hosts.count > 1 {
                Menu {
                    Picker("Host", selection: $hostID) { ForEach(hosts) { Text($0.name).tag($0.id) } }
                        .pickerStyle(.inline).labelsHidden()
                } label: {
                    HStack(spacing: 6) {
                        label
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityIdentifier("task_host")
            } else {
                label
            }
        }
    }

    private var macModelMenu: some View {
        let agent = AgentKind(rawValue: draft.agent) ?? .claude
        let models = catalog.models(for: agent)
        return Menu {
            Button("\(agent.displayName) default") { draft.model = "" }
            ForEach(models, id: \.self) { model in Button(model) { draft.model = model } }
            if !draft.model.isEmpty, !models.contains(draft.model) {
                Button("\(draft.model) (saved)") {}
            }
        } label: {
            HStack(spacing: 6) {
                Text(draft.model.isEmpty ? "\(agent.displayName) default" : draft.model)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityIdentifier("task_model")
    }
    #endif

    private var phoneTaskForm: some View {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Text("Name").font(.system(size: 15)).foregroundStyle(.secondary)
                        TextField("Task name", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                            .accessibilityIdentifier("task_name")
                    }
                    NavigationLink {
                        TaskInstructionsEditor(text: $draft.prompt)
                    } label: {
                        HStack(spacing: 10) {
                            Text("Instructions").font(.system(size: 15)).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(draft.prompt.isEmpty ? "What should the agent do?" : draft.prompt)
                                .lineLimit(1).foregroundStyle(.primary.opacity(0.82))
                        }
                    }
                    .accessibilityIdentifier("task_instructions_row")
                }
                ScheduleEditorSection(draft: $schedule, preview: preview) { activePicker = .timezone }
                if let problem = schedule.problem() ?? preview?.error {
                    Section { Text(problem).foregroundStyle(.red).accessibilityIdentifier("task_schedule_problem") }
                }
                Section {
                    if hosts.count > 1 {
                        Picker("Host", selection: $hostID) { ForEach(hosts) { Text($0.name).tag($0.id) } }
                            .pickerStyle(.menu).accessibilityIdentifier("task_host")
                    } else {
                        LabeledContent("Host", value: client.host.name)
                    }
                    Button { activePicker = .directory } label: {
                        LabeledContent("Folder") {
                            HStack(spacing: 6) {
                                Text(draft.cwd.isEmpty ? "Choose a folder" : TaskDetailHeader.shortPath(draft.cwd))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("task_directory")
                    modelPicker
                } header: {
                    Text("Runs on")
                } footer: {
                    if moving { Text(moveNote).accessibilityIdentifier("task_move_note") }
                }
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
            #if os(iOS)
            // The board's first card starts close under the toolbar.
            .contentMargins(.top, 8, for: .scrollContent)
            // Rows size to their content and padding (the time zone row is 33pt on the board).
            .environment(\.defaultMinListRowHeight, 0)
            #endif
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

    private func reloadTask(_ id: String) async {
        refreshing = true; refreshFailed = true; error = nil
        defer { refreshing = false }
        do {
            let saved = try await origin.task(id)
            currentTask = saved; draft = .init(task: saved); schedule = ScheduleDraft(schedule: saved.schedule, nextRunAt: saved.nextRunAt); refreshFailed = false
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct TaskChatStart: Encodable { let prompt: String; let cwd: String; let agent: String; let timezone: String }
private struct TaskChatCreated: Decodable, Sendable { let sessionId: String? }
private struct ScheduledTaskChat: View {
    let hosts: [ScheduledTaskHost]
    let initialHost: ScheduledTaskHost
    var embedded = false
    var onClose: (() -> Void)? = nil
    let openSession: (String, String) -> Void
    @State private var draft = TaskChatDraft()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if embedded { content } else { NavigationStack { content } }
        }
        #if os(macOS)
        .frame(width: embedded ? nil : 650, height: embedded ? nil : 720)
        #endif
    }

    private var content: some View {
        ScheduledTaskChatContent(hosts: hosts, initialHost: initialHost, task: nil,
            draft: $draft, openSession: openSession)
            .navigationTitle("New scheduled task")
            #if os(macOS)
            .navigationBarBackButtonHidden(embedded)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(embedded ? "Cancel" : "Done") {
                    if let onClose { onClose() } else { dismiss() }
                }
                .disabled(draft.starting).accessibilityIdentifier("task_chat_done")
            } }
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
