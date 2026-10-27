import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MessageSpacesView: View {
    let hosts: [ScheduledTaskHost]
    var onDetailChange: ((Bool) -> Void)? = nil
    @State private var hostID = ""
    @State private var spaces: [MessageSpace] = []
    @State private var selected: MessageSpace?
    @State private var loading = false
    @State private var creating = false
    @State private var showCreate = false
    @State private var name = ""
    @State private var agent = "claude-code"
    @State private var error: String?
    private var host: ScheduledTaskHost? { hosts.first { $0.id == hostID } ?? hosts.first }

    var body: some View {
        NavigationStack {
            List {
                if hosts.count > 1 {
                    Picker("Computer", selection: $hostID) {
                        ForEach(hosts) { Text($0.name).tag($0.id) }
                    }
                    .accessibilityIdentifier("message_host_picker")
                }
                Section {
                    if loading && spaces.isEmpty { ProgressView("Loading Spaces…") }
                    if let error {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                            .accessibilityIdentifier("message_error")
                        Button("Try loading again") { Task { await refresh() } }
                            .accessibilityIdentifier("message_retry")
                    }
                    if spaces.isEmpty && !loading && error == nil {
                        ContentUnavailableView("Your agent’s computer", systemImage: "desktopcomputer",
                            description: Text("Create a Space, then message an agent or use its browser."))
                            .accessibilityIdentifier("message_empty")
                    }
                    ForEach(spaces) { space in
                        Button { selected = space } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(space.name).font(.headline).foregroundStyle(.primary)
                                    Text("\(space.agent == "claude-code" ? "Claude Code" : "Codex") · \(space.powerState)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .accessibilityIdentifier("message_space_\(space.id)")
                    }
                } header: { Text("Spaces on \(host?.name ?? "this computer")") }
                Section {
                    Text("Spaces use this computer’s resources. Turn a Space off when you finish. Configure email and other accounts inside its browser.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Message")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Label("New Space", systemImage: "plus") }
                        .disabled(host == nil || creating)
                        .accessibilityIdentifier("message_new_space")
                }
                ToolbarItem(placement: .automatic) {
                    Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(loading || creating)
                        .accessibilityIdentifier("message_refresh")
                }
            }
            .navigationDestination(item: $selected) { space in
                if let host { MessageSpaceDetail(host: host, initialSpace: space).id(host.id + space.id) }
            }
            .sheet(isPresented: $showCreate) { createSheet }
            .task(id: host?.id) { spaces = []; selected = nil; await refresh() }
        }
        .onChange(of: selected?.id) { _, id in onDetailChange?(id != nil) }
        .onAppear { onDetailChange?(selected != nil) }
    }
    private var createSheet: some View {
        NavigationStack {
            Form {
                TextField("Name your Space", text: $name).accessibilityIdentifier("message_space_name")
                Picker("Agent", selection: $agent) {
                    Text("Claude Code").tag("claude-code")
                    Text("Codex").tag("openai-codex")
                }.accessibilityIdentifier("message_agent_picker")
                Text("Creates a Linux desktop on \(host?.name ?? "this computer"). The first download can take several minutes.")
                    .font(.footnote).foregroundStyle(.secondary)
                if creating { ProgressView("Creating your Space…") }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            .navigationTitle("New Space")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreate = false }.disabled(creating).accessibilityIdentifier("message_create_cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(creating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("message_create_confirm")
                }
            }
        }
        .interactiveDismissDisabled(creating)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
    private func refresh() async {
        guard let host, !loading else { return }
        let expected = host.id
        loading = true; defer { loading = false }
        do {
            let result = try await MessageSpacesClient(host: host).list()
            guard self.host?.id == expected, !Task.isCancelled else { return }
            spaces = result; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func create() async {
        guard let host, !creating else { return }
        creating = true; error = nil; defer { creating = false }
        do {
            let space = try await MessageSpacesClient(host: host).create(name: name, agent: agent)
            spaces.append(space); showCreate = false; selected = space; name = ""
        } catch { self.error = error.localizedDescription; showCreate = false; await refresh() }
    }
}

private struct MessageSpaceDetail: View {
    let host: ScheduledTaskHost
    let initialSpace: MessageSpace
    @State private var space: MessageSpace
    @State private var events: [SpaceAgentEvent] = []
    @State private var cursor = 0
    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?
    @State private var status = ""
    @State private var mode = 0
    @Environment(\.scenePhase) private var scenePhase
    private var client: MessageSpacesClient { MessageSpacesClient(host: host) }
    init(host: ScheduledTaskHost, initialSpace: MessageSpace) {
        self.host = host; self.initialSpace = initialSpace; _space = State(initialValue: initialSpace)
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) { Text("Chat").tag(0); Text("Live Space").tag(1) }
                .pickerStyle(.segmented).padding().accessibilityIdentifier("message_detail_mode")
            HStack {
                Label(status.isEmpty ? space.powerState : status, systemImage: "circle.fill").font(.caption)
                Spacer()
                Text(host.name).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal).padding(.bottom, 8)
            if let error = error ?? space.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .padding().accessibilityIdentifier("message_detail_error")
            }
            if mode == 0 { chat } else { SpaceLiveView(client: client, space: space) }
        }
        .navigationTitle(space.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Pause agent", systemImage: "pause") { Task { await act { try await client.interrupt(space.id) } } }
                        .disabled(space.runID == nil).accessibilityIdentifier("message_pause_agent")
                    Button("Turn Space on", systemImage: "power") { Task { await act { space = try await client.power(space.id, action: "start") } } }
                        .accessibilityIdentifier("message_power_on")
                    Button("Turn Space off", systemImage: "moon") { Task { await act { space = try await client.power(space.id, action: "stop") } } }
                        .accessibilityIdentifier("message_power_off")
                } label: { Label("Space controls", systemImage: "ellipsis.circle") }
                .disabled(busy).accessibilityIdentifier("message_space_controls")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await poll()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }
    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if space.messages.isEmpty {
                            ContentUnavailableView("What should we work on?", systemImage: "bubble.left.and.bubble.right",
                                description: Text("Ask your agent to browse, research, or work with files. Provider authentication must be configured on this host."))
                        }
                        ForEach(chatRows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.user ? "You" : row.activity ? "Activity" : "Agent").font(.caption).foregroundStyle(.secondary)
                                Text(row.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12).background(row.user ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .id(row.id)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.padding()
                }
                .accessibilityIdentifier("message_transcript")
                .onChange(of: chatRows.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField("Message your agent", text: $draft, axis: .vertical).lineLimit(1...5)
                    .textFieldStyle(.plain).accessibilityIdentifier("message_composer")
                Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(busy || !space.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message").accessibilityIdentifier("message_send")
            }.padding()
            if busy { ProgressView().padding(.bottom, 8) }
        }
    }
    private var chatRows: [SpaceTranscriptRow] {
        MessageSpaceTranscript.rows(messages: space.messages, events: events)
    }
    private func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        await act {
            space = try await client.send(space.id, text: prompt, requestID: UUID().uuidString)
            draft = ""
        }
        await poll()
    }
    private func act(_ work: () async throws -> Void) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { try await work() } catch { self.error = error.localizedDescription }
    }
    private func poll() async {
        do {
            let result = try await client.detail(space.id, cursor: cursor)
            guard !Task.isCancelled else { return }
            space = result.space; status = result.status ?? status
            let existing = Set(events.map(\.seq))
            events.append(contentsOf: (result.events ?? []).filter { !existing.contains($0.seq) })
            cursor = result.cursor ?? cursor
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
