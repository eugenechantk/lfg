import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

struct ChatJobsView: View {
    let host: ScheduledTaskHost
    let chatId: String
    let taskID: String?
    let openChat: (() -> Void)?
    @State private var jobs: [ChatJobRecord] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editor: JobEditor?
    private var client: ChatJobsClient { .init(host: host) }
    private struct JobEditor: Identifiable { let id = UUID(); var job: ChatJobRecord? }
    init(host: ScheduledTaskHost, chatId: String, taskID: String? = nil, openChat: (() -> Void)? = nil) {
        self.host = host; self.chatId = chatId; self.taskID = taskID; self.openChat = openChat
    }
    var body: some View {
        List {
            Section {
                Text("Tasks run on \(host.name). The host must be awake. Notification delivery uses your registered iOS devices.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let openChat { Section { Button("Open chat", systemImage: "bubble.left.and.bubble.right", action: openChat).accessibilityIdentifier("chat_task_open_chat") } }
            if loading && jobs.isEmpty { ProgressView().accessibilityIdentifier("chat_jobs_loading") }
            if let error { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("chat_jobs_error"); Button("Retry") { Task { await refresh() } }.accessibilityIdentifier("chat_jobs_retry") } }
            if !loading && jobs.isEmpty { ContentUnavailableView("No tasks", systemImage: "clock", description: Text("Ask this chat for a reminder, or add a task here.")).accessibilityIdentifier("chat_jobs_empty") }
            ForEach(jobs) { job in
                Section {
                    Button { editor = JobEditor(job: job) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(job.name).font(.headline); Spacer(); Text(job.statusLabel).font(.caption).foregroundStyle(.secondary) }
                            Text(job.instructions).font(.subheadline).lineLimit(3).foregroundStyle(.primary)
                            Text(job.schedule.description(nextRunAt: job.nextRunAt)).font(.caption).foregroundStyle(.secondary)
                            if let next = job.nextRunAt, job.enabled { Text("Next: \(Date(timeIntervalSince1970: next / 1000).formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                            if let report = job.lastRun?.summary { Text(report).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                            if let failure = job.lastRun?.error { Text(failure).font(.caption).foregroundStyle(.orange) }
                            if let delivery = job.deliveryLabel { Text(delivery).font(.caption).foregroundStyle(.secondary) }
                            if let deliveryError = job.notificationError { Text(deliveryError).font(.caption).foregroundStyle(.orange) }
                        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("chat_job_\(job.id)")
                    if job.cancelledAt == nil {
                        HStack {
                            if job.canPauseOrResume {
                                Button(job.pausedAt == nil ? "Pause" : "Resume") { Task { await mutate { try await client.setEnabled(job, enabled: job.pausedAt != nil) } } }.accessibilityIdentifier("chat_job_toggle_\(job.id)")
                            }
                            Spacer()
                            Button("Cancel task", role: .destructive) { Task { await mutate { try await client.cancel(job.id) } } }.accessibilityIdentifier("chat_job_cancel_\(job.id)")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationTitle(taskID == nil ? "Tasks" : jobs.first?.name ?? "Task").accessibilityIdentifier("chat_jobs_screen")
        .toolbar { if taskID == nil { ToolbarItem(placement: .primaryAction) { Button("Add task", systemImage: "plus") { editor = JobEditor() }.accessibilityIdentifier("chat_jobs_add") } } }
        .sheet(item: $editor) { item in ChatJobEditor(client: client, chatId: chatId, job: item.job) { Task { await refresh() } } }
        .task { await refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { await refresh() } } }
    }
    private func refresh() async { do { let records = try await client.list(chatId: chatId); jobs = records.filter { taskID == nil || $0.id == taskID }; error = nil } catch { self.error = error.localizedDescription }; loading = false }
    private func mutate(_ work: () async throws -> Void) async { do { try await work(); await refresh() } catch { self.error = error.localizedDescription } }
}

private struct ChatJobEditor: View {
    let client: ChatJobsClient
    let chatId: String
    let job: ChatJobRecord?
    let saved: () -> Void
    @State private var draft: ChatJobDraft
    @State private var scheduleChanged = false
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(client: ChatJobsClient, chatId: String, job: ChatJobRecord?, saved: @escaping () -> Void) {
        self.client = client; self.chatId = chatId; self.job = job; self.saved = saved
        _draft = State(initialValue: job.map(ChatJobDraft.init(job:)) ?? ChatJobDraft())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Name", text: $draft.name).accessibilityIdentifier("chat_job_name")
                    if job == nil {
                        Picker("Action", selection: $draft.action) { Text("Send reminder").tag("notify"); Text("Run instructions").tag("run") }.accessibilityIdentifier("chat_job_action")
                    }
                    TextField(draft.action == "notify" ? "Reminder text" : "What should this job do?", text: $draft.instructions, axis: .vertical).lineLimit(4...10).accessibilityIdentifier("chat_job_instructions")
                }
                Section("Schedule") {
                    if job != nil { Toggle("Change schedule", isOn: $scheduleChanged).accessibilityIdentifier("chat_job_change_schedule") }
                    if job == nil || scheduleChanged {
                        DatePicker("First run", selection: $draft.firstRun, in: Date()...).accessibilityIdentifier("chat_job_first_run")
                        Toggle("Repeat", isOn: $draft.repeats).accessibilityIdentifier("chat_job_repeat")
                        if draft.repeats { TextField("Minutes between runs", value: $draft.everyMinutes, format: .number).accessibilityIdentifier("chat_job_interval") }
                        Text(draft.timezone).font(.footnote).foregroundStyle(.secondary)
                    } else if let job { Text(job.schedule.description(nextRunAt: job.nextRunAt)) }
                }
                if draft.action == "run" {
                    Section("Notifications") {
                        Picker("Notify", selection: $draft.notification) { Text("When instructions request it").tag("requested"); Text("After every completed run").tag("always") }.accessibilityIdentifier("chat_job_notification")
                        Toggle("Stop after notifying", isOn: $draft.stopOnNotify).accessibilityIdentifier("chat_job_stop_after_notify")
                        Text("Describe the condition in the instructions. The job reports whether to notify and whether its work is finished.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("chat_job_save_error") }
            }.navigationTitle(job == nil ? "New task" : "Edit task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).disabled(busy).accessibilityIdentifier("chat_job_editor_close") }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "Saving…" : "Save") { Task { await save() } }.disabled(busy || !valid).accessibilityIdentifier("chat_job_save") }
            }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(busy)
        #if os(macOS)
        .frame(width: 440, height: 580)
        #endif
    }
    private var valid: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (job != nil && !scheduleChanged || draft.isValid) && job?.cancelledAt == nil }
    private func save() async {
        busy = true; defer { busy = false }
        do { if let job { try await client.save(job, draft: draft, scheduleChanged: scheduleChanged) } else { try await client.create(chatId: chatId, draft: draft) }; saved(); dismiss() } catch { self.error = error.localizedDescription }
    }
}
