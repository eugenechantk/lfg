import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

@MainActor @Observable final class ScheduledTasksModel {
    var tasks: [HostedScheduledTask] = []
    var hosts: [ScheduledTaskHost] = []
    var loading = false
    var error: String?
    var changing = false

    func refresh() async {
        let snapshot = hosts
        loading = tasks.isEmpty
        defer { loading = false }
        var updated: [HostedScheduledTask] = []
        var failures: [String] = []
        await withTaskGroup(of: (String, [ScheduledTaskRecord]?, String?).self) { group in
            for host in snapshot {
                group.addTask {
                    do { return (host.id, try await ScheduledTasksClient(host: host).list(), nil) }
                    catch { return (host.id, nil, "\(host.name): \(error.localizedDescription)") }
                }
            }
            for await (id, records, failure) in group {
                guard let host = snapshot.first(where: { $0.id == id }) else { continue }
                if let records { updated += records.map { HostedScheduledTask(task: $0, host: host) } }
                else {
                    updated += tasks.filter { $0.host.id == id }
                    if let failure { failures.append(failure) }
                }
            }
        }
        guard !Task.isCancelled, hosts.map(\.id) == snapshot.map(\.id) else { return }
        tasks = updated
        error = failures.isEmpty ? nil : failures.sorted().joined(separator: "\n")
    }
    func act(_ item: HostedScheduledTask, _ action: String, enabled: Bool? = nil) async {
        guard !changing else { return }
        changing = true; defer { changing = false }
        do {
            try await ScheduledTasksClient(host: item.host).action(item.task.id, action, enabled: enabled)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}

struct ScheduledTasksView: View {
    let hosts: [ScheduledTaskHost]
    var openSession: (String, String) -> Void
    @State private var model = ScheduledTasksModel()
    @State private var hostFilter = "all"
    @State private var selection: String?
    @State private var filter = "all"
    @State private var search = ""
    @State private var sheet: TaskSheet?
    private enum TaskSheet: Identifiable {
        case manual(ScheduledTaskHost), edit(HostedScheduledTask), chat, run(HostedScheduledTask, ScheduledTaskRun)
        var id: String {
            switch self {
            case .manual(let h): "manual-\(h.id)"
            case .edit(let t): "edit-\(t.id)"
            case .chat: "chat"
            case .run(let t, let r): "run-\(t.id)-\(r.id)"
            }
        }
    }
    private var filtered: [HostedScheduledTask] {
        model.tasks.filter { item in
            let task = item.task
            return (hostFilter == "all" || item.host.id == hostFilter)
                && (filter == "all" || (task.cancelledAt == nil && task.canResume))
                && (search.isEmpty || task.name.localizedCaseInsensitiveContains(search)
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
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if hosts.count > 1 {
                        Picker("Host", selection: $hostFilter) {
                            Text("All hosts").tag("all")
                            ForEach(hosts) { Text($0.name).tag($0.id) }
                        }.accessibilityIdentifier("tasks_host_picker")
                    }
                    Picker("Show tasks", selection: $filter) { Text("All tasks").tag("all"); Text("Upcoming").tag("active") }
                        .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("tasks_filter")
                }.padding()
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                        Button("Try again") { Task { await model.refresh() } }.accessibilityIdentifier("tasks_retry")
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.10))
                }
                if model.loading {
                    ProgressView("Loading tasks…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(search.isEmpty ? "Your next task starts here" : "No matching tasks", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("Tell Claude Code what you want done and when. Work out the details together.")
                    } actions: {
                        Button("Create with Claude Code", systemImage: "plus") { sheet = .chat }
                            .buttonStyle(.borderedProminent).disabled(hosts.isEmpty).accessibilityIdentifier("tasks_empty_chat")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(filtered) { item in taskRow(item).tag(item.id) }
                    }.listStyle(.sidebar)
                }
                Text("Tasks run while their host is awake and LFG is running.")
                    .font(.caption).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(macOS)
            .frame(minWidth: 360, idealWidth: 410)
            #endif
            .navigationTitle("Scheduled Tasks")
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 500)
            .searchable(text: $search, prompt: "Search tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(hosts) { host in
                            Button("Set up manually on \(host.name)") { sheet = .manual(host) }
                                .accessibilityIdentifier("tasks_create_manual_\(host.id)")
                        }
                    } label: { Label("More task options", systemImage: "ellipsis") }
                    .disabled(hosts.isEmpty).accessibilityIdentifier("tasks_more")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { sheet = .chat } label: { Label("New scheduled task", systemImage: "plus") }
                        .disabled(hosts.isEmpty).accessibilityIdentifier("tasks_add")
                }
            }
        } detail: {
            NavigationStack {
                if let item = model.tasks.first(where: { $0.id == selection }) {
                    ScheduledTaskDetail(task: item.task, client: .init(host: item.host), changing: model.changing,
                        edit: { sheet = .edit(item) },
                        action: { action, enabled in Task { await model.act(item, action, enabled: enabled) } },
                        openSession: { openSession(item.host.id, $0) })
                } else {
                    ContentUnavailableView("Your work, on a schedule", systemImage: "calendar", description: Text("Select a task to see its instructions, next run, and previous results."))
                }
            }.id(selection)
        }
        .task(id: hosts.map(\.id)) {
            model.hosts = hosts
            if hostFilter != "all", !hosts.contains(where: { $0.id == hostFilter }) { hostFilter = "all" }
            while !Task.isCancelled { await model.refresh(); try? await Task.sleep(for: .seconds(5)) }
        }
        .onChange(of: hostFilter) { _, _ in selection = nil }
        .sheet(item: $sheet, onDismiss: { Task { await model.refresh() } }) { destination in
            switch destination {
            case .manual(let host): ScheduledTaskEditor(client: .init(host: host), task: nil)
            case .edit(let item): ScheduledTaskEditor(client: .init(host: item.host), task: item.task)
            case .chat:
                if let host = hosts.first(where: { $0.id == hostFilter }) ?? hosts.first {
                    ScheduledTaskChat(hosts: hosts, initialHost: host) { hostID, sessionID in
                        sheet = nil; openSession(hostID, sessionID)
                    }
                }
            case .run(let item, let run):
                NavigationStack {
                    ScheduledRunDetail(run: run, client: .init(host: item.host)) { sessionID in
                        sheet = nil; openSession(item.host.id, sessionID)
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { sheet = nil }.accessibilityIdentifier("task_run_done")
                    } }
                }
                #if os(macOS)
                .frame(width: 650, height: 650)
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 620)
        #endif
    }

    private func taskRow(_ item: HostedScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            Button { selection = item.id } label: { TaskListSummary(item: item).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityIdentifier("task_row_\(item.task.id)")
            #else
            NavigationLink(value: item.id) { TaskListSummary(item: item) }
                .accessibilityIdentifier("task_row_\(item.task.id)")
            #endif
            VStack(alignment: .leading, spacing: 8) {
                Text("Previous sessions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if item.task.recentRuns.isEmpty {
                    Text("No previous sessions").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(item.task.recentRuns) { run in
                    Button { sheet = .run(item, run) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: run.sessionId == nil ? "exclamationmark.circle" : "bubble.left")
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(run.statusLabel)
                                    if let at = run.startedAt {
                                        Text(Date(timeIntervalSince1970: at / 1000), format: .dateTime.month(.abbreviated).day().hour().minute())
                                    }
                                }
                                if let sid = run.sessionId { Text("Session \(sid.prefix(8))").foregroundStyle(.secondary) }
                                else { Text("No session started").foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.borderless).accessibilityIdentifier("task_recent_run_\(run.id)")
                }
                if item.task.runCount > 3 {
                    #if os(macOS)
                    Button("View all \(item.task.runCount) runs") { selection = item.id }
                        .buttonStyle(.borderless).accessibilityIdentifier("task_all_runs_\(item.task.id)")
                    #else
                    NavigationLink("View all \(item.task.runCount) runs", value: item.id)
                        .accessibilityIdentifier("task_all_runs_\(item.task.id)")
                    #endif
                }
            }
        }.padding(.vertical, 10)
    }
}

private struct TaskListSummary: View {
    let item: HostedScheduledTask
    private var task: ScheduledTaskRecord { item.task }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.name).font(.headline).lineLimit(2)
                Spacer(minLength: 0)
                Text(task.statusLabel).font(.caption).foregroundStyle(.secondary)
            }
            Text(task.prompt).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            Label(item.host.name, systemImage: "desktopcomputer").font(.caption)
            Label(task.modelLabel, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(task.schedule.label, systemImage: "calendar.badge.clock").lineLimit(1)
                if task.enabled, let next = task.nextRunAt {
                    Spacer(minLength: 4)
                    Text(Date(timeIntervalSince1970: next / 1000), format: .dateTime.month(.abbreviated).day().hour().minute())
                        .environment(\.timeZone, TimeZone(identifier: task.schedule.timezone) ?? .current)
                }
            }.font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
    var body: some View {
        List {
            Section {
                Label(task.statusLabel, systemImage: task.enabled ? "clock" : "pause.circle").foregroundStyle(.secondary)
                LabeledContent("Schedule", value: task.schedule.label)
                LabeledContent("Timezone", value: task.schedule.timezone)
                if let next = task.nextRunAt, task.enabled {
                    LabeledContent("Next run") { Text(Date(timeIntervalSince1970: next / 1000), format: .dateTime.month().day().hour().minute().timeZone()) }
                        .environment(\.timeZone, TimeZone(identifier: task.schedule.timezone) ?? .current)
                }
                LabeledContent("Host", value: client.host.name)
                LabeledContent("Agent", value: task.agent == "codex" ? "Codex" : "Claude")
                if let model = task.model { LabeledContent("Model", value: model) }
                LabeledContent("Directory") { Text(task.cwd).textSelection(.enabled).lineLimit(3) }
            }
            Section("Instructions") { Text(task.prompt).textSelection(.enabled).accessibilityIdentifier("task_instructions") }
            if task.cancelledAt == nil {
                Section {
                    Button("Run now", systemImage: "play.fill") { action("run", nil) }
                        .disabled(changing || task.currentRun != nil).accessibilityIdentifier("task_run_now")
                    if task.canResume {
                        Button(task.enabled ? "Pause schedule" : "Resume schedule", systemImage: task.enabled ? "pause" : "play") { action("", !task.enabled) }
                            .disabled(changing).accessibilityIdentifier("task_pause_resume")
                    }
                    Button("Cancel future runs", systemImage: "xmark.circle", role: .destructive) { confirmCancel = true }
                        .disabled(changing).accessibilityIdentifier("task_cancel")
                }
            }
            Section("Run history") {
                if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("task_history_error") }
                if !historyLoaded, error == nil { ProgressView("Loading run history…").accessibilityIdentifier("task_history_loading") }
                else if runs.isEmpty, error == nil { Text("No runs yet. The first result will appear here.").foregroundStyle(.secondary).accessibilityIdentifier("task_history_empty") }
                ForEach(runs) { run in
                    NavigationLink {
                        ScheduledRunDetail(run: run, client: client, openSession: openSession)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(run.statusLabel).font(.headline); Spacer(); Text(run.trigger == "manual" ? "Manual" : "Scheduled").font(.caption).foregroundStyle(.secondary) }
                            if let at = run.startedAt { Text(Date(timeIntervalSince1970: at / 1000), format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline).foregroundStyle(.secondary) }
                            if let summary = run.error ?? run.summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("task_run_\(run.id)")
                }
                if runs.count < total { Button("Load older runs") { Task { await load(more: true) } }.accessibilityIdentifier("task_runs_more") }
            }
        }
        .navigationTitle(task.name)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit", action: edit).disabled(task.cancelledAt != nil).accessibilityIdentifier("task_edit") } }
        .confirmationDialog("Cancel future runs?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel future runs", role: .destructive) { action("cancel", nil) }
        } message: { Text("Previous runs stay in history. Any running session will continue.") }
        .task(id: task.id) { runs = []; historyLoaded = false; while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(5)) } }
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
                    NavigationLink("Read conversation") { TaskConversationView(client: client, sessionID: sid, openSession: openSession) }.accessibilityIdentifier("task_run_conversation")
                    Button("Open in Sessions") { openSession(sid) }.accessibilityIdentifier("task_run_open_session")
                }
            }
            if let error = run.error { Section("What happened") { Text(error).textSelection(.enabled) } }
            if let summary = run.summary { Section("Result") { Text(summary).textSelection(.enabled).accessibilityIdentifier("task_run_result") } }
        }.navigationTitle("Run details")
    }
}

private struct TaskRepo: Decodable, Identifiable, Sendable { var cwd: String; var name: String?; var id: String { cwd } }
private struct TaskRepos: Decodable, Sendable { var repos: [TaskRepo] }

private struct ScheduledTaskEditor: View {
    let client: ScheduledTasksClient
    let task: ScheduledTaskRecord?
    @State private var draft: ScheduledTaskDraft
    @State private var repos: [TaskRepo] = []
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(client: ScheduledTasksClient, task: ScheduledTaskRecord?) { self.client = client; self.task = task; _draft = State(initialValue: .init(task: task)) }
    var body: some View {
        NavigationStack {
            Form {
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
                        TextField("Cron expression", text: $draft.expression).font(.system(.body, design: .monospaced)).accessibilityIdentifier("task_cron")
                        Text("Minute · hour · day · month · weekday\nExample: 0 9 * * 1-5 runs every weekday at 9 AM.").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Timezone", text: $draft.timezone).accessibilityIdentifier("task_timezone")
                    if task == nil || task?.canResume == true { Toggle("Enabled", isOn: $draft.enabled).accessibilityIdentifier("task_enabled") }
                }
                Section("Where and how") {
                    LabeledContent("Host", value: client.host.name)
                    Picker("Agent", selection: $draft.agent) { Text("Claude").tag("claude"); Text("Codex").tag("codex") }.accessibilityIdentifier("task_agent")
                    TextField("Model (optional)", text: $draft.model).accessibilityIdentifier("task_model")
                    if !repos.isEmpty {
                        Menu("Choose a directory") { ForEach(repos) { repo in Button(repo.name ?? repo.cwd) { draft.cwd = repo.cwd } } }.accessibilityIdentifier("task_directory_picker")
                    }
                    TextField("Absolute directory on host", text: $draft.cwd).accessibilityIdentifier("task_directory")
                }
                Section { Text("Each run starts a new conversation. If the host is offline, the task runs when it returns. Missed repeating runs are combined into one.").font(.footnote).foregroundStyle(.secondary) }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("task_editor_error") } }
            }.formStyle(.grouped)
            .navigationTitle(task == nil ? "New task" : "Edit task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("task_editor_cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task { do { try await client.save(draft, id: task?.id); dismiss() } catch { self.error = error.localizedDescription }; saving = false }
                    }.disabled(saving || !draft.isValid).accessibilityIdentifier("task_save")
                }
            }
            .task { repos = (try? await client.call("/api/repos", as: TaskRepos.self))?.repos ?? [] }
        }
        #if os(macOS)
        .frame(width: 580, height: 680)
        #endif
    }
}

private struct TaskChatStart: Encodable { let prompt: String; let cwd: String; let agent: String; let timezone: String }
private struct TaskChatCreated: Decodable, Sendable { let sessionId: String? }
private struct TaskChatMessage: Decodable, Identifiable, Sendable {
    let id: String; let role: String?; let kind: String?; let text: String?
    var displayed: String {
        guard let text else { return "" }
        if text.hasPrefix("Help the user create an LFG scheduled task"), let range = text.range(of: "The user's request follows:\n") { return String(text[range.upperBound...]) }
        return text
    }
}
private struct TaskChatMessages: Decodable, Sendable { let messages: [TaskChatMessage] }
private struct TaskChatSessions: Decodable, Sendable { let sessions: [TaskChatSession] }
private struct TaskChatSession: Decodable, Sendable { let sessionId: String?; let busy: Bool?; let prompt: TaskChatQuestion? }
private struct TaskChatQuestion: Decodable, Sendable { let question: String?; let context: String?; let options: [TaskChatOption]? }
private struct TaskChatOption: Decodable, Identifiable, Sendable { let index: Int; let label: String; var id: Int { index } }
private struct TaskChatSend: Encodable { let text: String; let clientId: String }
private struct TaskChatAnswer: Encodable { let index: Int }
private struct TaskChatSent: Decodable, Sendable { let ok: Bool?; let sessionId: String? }

private struct ScheduledTaskChat: View {
    let hosts: [ScheduledTaskHost]
    let initialHost: ScheduledTaskHost
    let openSession: (String, String) -> Void
    @State private var hostID: String
    private var client: ScheduledTasksClient { .init(host: hosts.first(where: { $0.id == hostID }) ?? initialHost) }
    @State private var prompt = ""
    @State private var cwd = ""
    @State private var sessionID: String?
    @State private var repos: [TaskRepo] = []
    @State private var starting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var savedChatKey: String { "lfg.taskAuthoring.\(client.host.id)" }
    init(hosts: [ScheduledTaskHost], initialHost: ScheduledTaskHost, openSession: @escaping (String, String) -> Void) {
        self.hosts = hosts; self.initialHost = initialHost; self.openSession = openSession
        _hostID = State(initialValue: initialHost.id)
    }
    var body: some View {
        NavigationStack {
            Group {
                if let sessionID { TaskConversationView(client: client, sessionID: sessionID) { openSession(client.host.id, $0) } }
                else {
                    Form {
                        Section {
                            Label("Describe it. Work out the details together.", systemImage: "bubble.left.and.bubble.right").font(.headline)
                            Text("Claude Code will help choose the timing, model, and instructions, then save your task.").foregroundStyle(.secondary)
                            TextField("Tomorrow morning, review changes in…", text: $prompt, axis: .vertical).lineLimit(4...8).accessibilityIdentifier("task_chat_request")
                        }
                        Section("On this host") {
                            Picker("Host", selection: $hostID) { ForEach(hosts) { Text($0.name).tag($0.id) } }
                                .disabled(starting).accessibilityIdentifier("task_chat_host")
                            LabeledContent("Setup agent", value: "Claude Code")
                            if !repos.isEmpty { Menu("Choose a directory") { ForEach(repos) { repo in Button(repo.name ?? repo.cwd) { cwd = repo.cwd } } }.accessibilityIdentifier("task_chat_directory_picker") }
                            TextField("Directory (optional)", text: $cwd).accessibilityIdentifier("task_chat_directory")
                        }
                        Section {
                            Button(starting ? "Starting conversation…" : "Start conversation", systemImage: "arrow.up.message") { start() }
                                .disabled(starting || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("task_chat_start")
                            if let saved = UserDefaults.standard.string(forKey: savedChatKey) {
                                Button("Continue previous setup") { sessionID = saved }.accessibilityIdentifier("task_chat_continue")
                            }
                        }
                        if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("task_chat_error") } }
                    }.formStyle(.grouped)
                }
            }
            .navigationTitle("New scheduled task")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("task_chat_done") } }
            .task(id: client.host.id) { cwd = ""; repos = (try? await client.call("/api/repos", as: TaskRepos.self))?.repos ?? [] }
        }
        #if os(macOS)
        .frame(width: 650, height: 720)
        #endif
    }
    private func start() {
        starting = true; error = nil
        Task {
            do {
                let result: TaskChatCreated = try await client.call("/api/scheduled-tasks/chat", body: JSONEncoder().encode(TaskChatStart(prompt: prompt, cwd: cwd, agent: "claude", timezone: TimeZone.current.identifier)))
                guard let id = result.sessionId else { throw ScheduledTaskClientError(message: "The conversation started without an ID. Check Sessions before starting again.") }
                UserDefaults.standard.set(id, forKey: savedChatKey); sessionID = id
            } catch { self.error = error.localizedDescription }
            starting = false
        }
    }
}

private struct TaskConversationView: View {
    let client: ScheduledTasksClient
    let sessionID: String
    let openSession: (String) -> Void
    @State private var messages: [TaskChatMessage] = []
    @State private var message = ""
    @State private var busy = false
    @State private var sending = false
    @State private var question: TaskChatQuestion?
    @State private var error: String?
    @State private var activeSessionID = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if messages.isEmpty { ProgressView("Waiting for the conversation…").padding() }
                        ForEach(messages) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.role == "user" ? "You" : "Agent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(.init(item.displayed)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(14).background(item.role == "user" ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14)).id(item.id)
                        }
                        if busy { HStack { ProgressView().controlSize(.small); Text("Working…").font(.callout).foregroundStyle(.secondary) } }
                        if let question {
                            VStack(alignment: .leading, spacing: 10) {
                                if let context = question.context { Text(context).font(.callout) }
                                Text(question.question ?? "The agent needs your input.").font(.headline)
                                ForEach(question.options ?? []) { option in
                                    Button(option.label) { answer(option.index) }.buttonStyle(.bordered).disabled(sending).accessibilityIdentifier("task_chat_option_\(option.index)")
                                }
                            }.padding().background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding()
                }.onChange(of: messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal).accessibilityIdentifier("task_conversation_error") }
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Reply…", text: $message, axis: .vertical).lineLimit(1...6).textFieldStyle(.plain).padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("task_chat_reply")
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .buttonStyle(.plain).disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send reply").accessibilityIdentifier("task_chat_send")
            }.padding()
        }
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Button { openSession(activeSessionID.isEmpty ? sessionID : activeSessionID) } label: {
                Label("Open in Sessions", systemImage: "arrow.up.forward.app")
                    #if os(iOS)
                    .labelStyle(.iconOnly)
                    #endif
            }.accessibilityIdentifier("task_chat_open_session")
        } }
        .task(id: sessionID) { activeSessionID = sessionID; while !Task.isCancelled { await refresh(); try? await Task.sleep(for: .seconds(3)) } }
    }
    private func refresh() async {
        do {
            let response: TaskChatMessages = try await client.call("/api/sessions/\(activeSessionID)/messages?limit=150")
            messages = response.messages.filter { ($0.role == "user" || $0.role == "assistant") && $0.kind == "text" && !($0.text ?? "").isEmpty }
            let live: TaskChatSessions = try await client.call("/api/sessions")
            let state = live.sessions.first { $0.sessionId == activeSessionID }; busy = state?.busy ?? false; question = state?.prompt; error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func send() {
        let text = message; sending = true
        Task {
            do {
                let result: TaskChatSent = try await client.call("/api/sessions/\(activeSessionID)/send", body: JSONEncoder().encode(TaskChatSend(text: text, clientId: UUID().uuidString)))
                if let id = result.sessionId { activeSessionID = id }
                message = ""; error = nil; await refresh()
            } catch { self.error = error.localizedDescription }
            sending = false
        }
    }
    private func answer(_ index: Int) {
        sending = true
        Task { do { let _: TaskChatSent = try await client.call("/api/sessions/\(activeSessionID)/answer", body: JSONEncoder().encode(TaskChatAnswer(index: index))); await refresh() } catch { self.error = error.localizedDescription }; sending = false }
    }
}
