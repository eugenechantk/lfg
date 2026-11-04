import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if canImport(MarkdownUI)
import MarkdownUI
#endif
#if canImport(LFGCore)
import LFGCore
#endif

private struct ChatLocation: Identifiable, Hashable {
    let host: ScheduledTaskHost
    let session: ChatSessionRecord
    var id: String { session.id }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ChatSessionsView: View {
    let hosts: [ScheduledTaskHost]
    var preferredHostID: String? = nil
    var onDetailChange: ((Bool) -> Void)? = nil
    var onRead: ((String) -> Void)? = nil
    var onCreated: (() -> Void)? = nil
    var createTrigger = 0
    var showsCreateInToolbar = true
    var listFooter: AnyView? = nil
    var connectionHeader: ((CGFloat) -> AnyView)? = nil
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>? = nil
    var unreadIDs: Set<String> = []
    @State private var query = ""
    @State private var showingSearch = false
    @State private var showingHidden = false
    @State private var offlineHosts = Set<String>()
    @State private var workspace = ChatWorkspace.shared
    private var chats: [ChatLocation] { workspace.entries(hosts: hosts, includeHidden: showingHidden).map { ChatLocation(host: $0.host, session: $0.session) } }
    @State private var path: [ChatLocation] = []
    @State private var selectedChat: ChatLocation?
    #if os(macOS)
    @State private var availableWidth: CGFloat = 1000
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var listWidth: CGFloat = 360
    @State private var internalSidebarVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var chatWindowSize = CGSize.zero
    private var sidebarBinding: Binding<NavigationSplitViewVisibility> { sidebarVisibility ?? $internalSidebarVisibility }
    #endif
    private var usesSplit: Bool {
        #if os(macOS)
        availableWidth >= 700
        #else
        horizontalSizeClass == .regular
        #endif
    }
    @State private var createError: String?
    @State private var loading = true
    @State private var polling: Task<Void, Never>?
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if usesSplit {
                #if os(iOS)
                tabletLayout
                #else
                desktopLayout
                #endif
            } else {
                NavigationStack(path: $path) {
                    chatList.navigationDestination(for: ChatLocation.self) { item in
                        ChatSessionScreen(host: item.host, sessionID: item.session.id, hosts: hosts, onRead: onRead, onRemoved: { path = [] })
                    }
                }
            }
        }
        .modifier(ChatAppearance())
        #if os(iOS)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { chatWindowSize = $0 }
        .environment(\.filePaneNavigation, FilePaneNavigation(windowSize: chatWindowSize,
            showList: { sidebarBinding.wrappedValue = .doubleColumn }))
        #endif
        #if os(macOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        #endif
        .onChange(of: usesSplit) { _, split in
            if split, let current = path.last { selectedChat = current; path = [] }
            else if !split, let selectedChat, path.isEmpty { path = [selectedChat] }
        }
        .alert("Couldn’t create chat", isPresented: Binding(get: { createError != nil }, set: { if !$0 { createError = nil } })) {
            Button("OK", role: .cancel) { createError = nil }
        } message: {
            Text(createError ?? "")
        }
        .onChange(of: createTrigger) { _, _ in createChat() }
        .onChange(of: path.count) { _, count in onDetailChange?(!usesSplit && count > 0) }
        .onAppear { isVisible = true; onDetailChange?(!usesSplit && !path.isEmpty); startPolling() }
        .onDisappear { isVisible = false; polling?.cancel(); polling = nil }
        .onChange(of: hosts) { _, _ in polling?.cancel(); polling = nil; startPolling() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { polling?.cancel(); polling = nil }
            else if phase == .active { startPolling() }
        }
    }
    private var isTablet: Bool {
        #if os(iOS)
        usesSplit
        #else
        false
        #endif
    }
    private var listCanvas: Color { ChatColors.canvas }
    #if os(macOS)
    private var desktopLayout: some View {
        HStack(spacing: 0) {
            chatList.frame(width: 300)
                .overlay(alignment: .trailing) { Rectangle().fill(ChatColors.separator).frame(width: 1) }
            Group {
                if let selectedChat {
                    ChatSessionScreen(host: selectedChat.host, sessionID: selectedChat.session.id, hosts: hosts, onRead: onRead, onRemoved: { self.selectedChat = nil }).id(selectedChat.id)
                } else {
                    ContentUnavailableView("Choose a chat", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Your conversations keep their own instructions and memory."))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ChatColors.canvas)
        }
    }
    #endif
    #if os(iOS)
    private var tabletLayout: some View {
        NavigationSplitView(columnVisibility: sidebarBinding) {
            chatList
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack {
                Group {
                    if let selectedChat {
                        ChatSessionScreen(host: selectedChat.host, sessionID: selectedChat.session.id, hosts: hosts, onRead: onRead, onRemoved: { self.selectedChat = nil }).id(selectedChat.id)
                    } else {
                        ContentUnavailableView("Choose a chat", systemImage: "bubble.left.and.bubble.right",
                            description: Text("Your conversations keep their own instructions and memory."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(ChatColors.canvas)
                    }
                }
                .toolbar {
                    SidebarToggleToolbar(visibility: sidebarBinding, title: "chats", identifier: "toggleChatSidebar")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif
    private func open(_ item: ChatLocation) {
        if usesSplit { selectedChat = item } else { path.append(item) }
    }
    private func createChat() {
        do {
            let entry = try workspace.createDefault(hosts: hosts, preferredHostID: preferredHostID, knownOffline: offlineHosts)
            open(ChatLocation(host: entry.host, session: entry.session))
            onCreated?()
            Task { await workspace.flush(hosts: hosts, only: entry.session.id) }
        } catch { createError = "Couldn’t save this chat on your device. \(error.localizedDescription)" }
    }
    private var chatList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if showingSearch {
                    TextField("Search chats", text: $query)
                        .textFieldStyle(.plain).padding(12)
                        .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16).padding(.bottom, 12)
                        .accessibilityIdentifier("chat_search_field")
                }
                if loading && chats.isEmpty {
                    ProgressView("Loading chats…").padding(40).accessibilityIdentifier("chat_loading")
                }
                if !loading && chats.isEmpty {
                    emptyList
                }
                ForEach(chats.filter { ChatPresentation.matches($0.session, query: query) }) { item in
                    Button { open(item) } label: { chatRow(item) }
                        .buttonStyle(.plain).accessibilityIdentifier("chat_row_\(item.session.id)")
                }
                if !query.isEmpty && !chats.isEmpty && !chats.contains(where: { ChatPresentation.matches($0.session, query: query) }) {
                    ContentUnavailableView.search(text: query).padding(.top, 80)
                }
            }
        }
        .background(listCanvas)
        #if os(iOS)
        .listScrollChrome(footer: listFooter)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        .toolbar {
            ListHeaderToolbar(searchLabel: "Search chats", searchIdentifier: "chat_search", onSearch: {
                showingSearch.toggle(); if !showingSearch { query = "" }
            }) {
                if let connectionHeader { connectionHeader(listWidth) }
                else { hostStrip }
            } options: {
                chatOptions
            }
            if showsCreateInToolbar {
                ToolbarItem(placement: .primaryAction) {
                    ListCreateButton(title: "New chat", identifier: "chat_create") { createChat() }
                }
            }
        }
        #else
        .safeAreaInset(edge: .top, spacing: 0) { macHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { listFooter }
        #endif
    }
    private var emptyList: some View {
        VStack(spacing: 13) {
            HStack(spacing: -8) {
                ChatAvatar(name: "Mail", size: 54).rotationEffect(.degrees(-8))
                ChatAvatar(name: "Scout", size: 56).zIndex(2)
                ChatAvatar(name: "Patch", size: 54).rotationEffect(.degrees(8))
            }.padding(.bottom, 8)
            Text("No chats yet").font(.system(size: 22, weight: .semibold))
            Text("Start a conversation. It keeps your history, and you can shape it as you chat.")
                .font(.system(size: 16)).lineSpacing(3).foregroundStyle(ChatColors.secondary)
            Button { createChat() } label: {
                Label("New chat", systemImage: "plus").font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 22).frame(height: 50)
                    .background(ChatColors.hex(0x0A6EE0), in: Capsule()).foregroundStyle(.white)
            }.buttonStyle(.plain).padding(.top, 6)
                .accessibilityIdentifier("chat_empty_create")
            Text("Instructions and memory are private to each chat.")
                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(ChatColors.muted)
        }.multilineTextAlignment(.center).padding(.horizontal, 32).frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in max(420, height - 100) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("chat_empty")
    }
    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 8) {
            hostStrip
            Spacer(minLength: 0)
            Menu {
                Text("Most recent activity first")
                Divider()
                Button("New chat") { createChat() }.keyboardShortcut("n")
                Button("Mark all read") { for id in unreadIDs { onRead?(id) } }.disabled(unreadIDs.isEmpty)
                Button("Refresh") { Task { await refresh() } }
                Toggle("Show hidden chats", isOn: $showingHidden)
                    .accessibilityIdentifier("chat_show_hidden")
            } label: {
                HStack(spacing: 4) { Text("Most recent"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
                    .font(.system(size: 11)).foregroundStyle(ChatColors.hex(0xC9CBD3))
                    .padding(.horizontal, 8).frame(height: 22).background(.white.opacity(0.06), in: Capsule())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityIdentifier("chat_options")
        }.padding(.horizontal, 16).frame(height: 30).background(listCanvas)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSearch.toggle(); if !showingSearch { query = "" } } label: { Label("Search chats", systemImage: "magnifyingglass") }
                        .labelStyle(.iconOnly).fixedSize()
                        .accessibilityIdentifier("chat_search")
                }
            }
    }
    #else
    private var chatOptions: some View {
        Menu {
            Toggle("Show hidden chats", isOn: $showingHidden)
                .accessibilityIdentifier("chat_show_hidden")
            Button { createChat() } label: { Label("New chat", systemImage: "plus") }
                .accessibilityIdentifier("chat_create_menu")
            Button("Mark all read") { for id in unreadIDs { onRead?(id) } }
                .disabled(unreadIDs.isEmpty).accessibilityIdentifier("chat_mark_all_read")
            Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .accessibilityIdentifier("chat_refresh")
        } label: {
            ListOptionsLabel(title: "More chat options")
        }
        .tint(Color(.label))
        .accessibilityLabel("More chat options")
        .accessibilityIdentifier("chat_options")
    }
    #endif
    private var hostLabelSize: CGFloat {
        #if os(macOS)
        12
        #else
        16
        #endif
    }
    private var hostStrip: some View {
        HStack(spacing: 12) {
            ForEach(hosts) { host in
                HStack(spacing: 6) {
                    Circle().fill(offlineHosts.contains(host.id) ? ChatColors.amber : ChatColors.green).frame(width: 8, height: 8)
                    Text(host.name).font(.system(size: hostLabelSize, weight: hostLabelSize == 12 ? .regular : .semibold)).lineLimit(1)
                }.accessibilityLabel("\(host.name), \(offlineHosts.contains(host.id) ? "offline" : "connected")")
            }
        }.accessibilityIdentifier("chat_hosts")
    }
    private func chatRow(_ item: ChatLocation) -> some View {
        let chat = item.session, offline = offlineHosts.contains(item.host.id)
        let unread = unreadIDs.contains(chat.id)
        #if os(macOS)
        let avatar: CGFloat = 30, gap: CGFloat = 10, title: CGFloat = 14, time: CGFloat = 11
        let status: CGFloat = 12, purpose: CGFloat = 11, top: CGFloat = 9, bottom: CGFloat = 10
        let firstHeight: CGFloat = 19, secondHeight: CGFloat = 16, thirdHeight: CGFloat = 15
        let avatarTop: CGFloat = 11, leading: CGFloat = 16, trailing: CGFloat = 14, badge: CGFloat = 9, ring: CGFloat = 2
        let inlineStatus = false
        #else
        let avatar: CGFloat = isTablet ? 34 : 38, gap: CGFloat = isTablet ? 11 : 12, title: CGFloat = 17, time: CGFloat = 13
        let status: CGFloat = 15, purpose: CGFloat = 13, top: CGFloat = 11, bottom: CGFloat = 12
        let firstHeight: CGFloat = 22, secondHeight: CGFloat = 20, thirdHeight: CGFloat = 18
        let avatarTop: CGFloat = isTablet ? 12 : 13, leading: CGFloat = isTablet ? 12 : 20, trailing: CGFloat = isTablet ? 8 : 16
        let badge: CGFloat = isTablet ? 10 : 11, ring: CGFloat = 2.5
        let inlineStatus = true
        #endif
        return HStack(alignment: .top, spacing: gap) {
            ChatAvatar(name: chat.name, size: avatar, state: chat.isWorking ? "working" : chat.state, unread: unread, offline: offline, badgeSize: badge, ringWidth: ring, backdrop: listCanvas, halo: inlineStatus)
                .padding(.top, avatarTop)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chat.name).font(.system(size: title, weight: unread || chat.state == "blocked" ? (inlineStatus ? .semibold : .bold) : (inlineStatus ? .regular : .semibold)))
                            .foregroundStyle(ChatColors.ink).lineLimit(1)
                        if workspace.isHidden(chat.id) {
                            Image(systemName: "eye.slash").font(.caption).foregroundStyle(ChatColors.muted)
                                .accessibilityLabel("Hidden on this device")
                        }
                        Spacer(minLength: 8)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(ChatPresentation.activityLabel(chat.lastActivityAt, now: context.date))
                                .font(.system(size: time)).foregroundStyle(ChatColors.muted).lineLimit(1)
                        }
                    }.frame(minHeight: firstHeight)
                    HStack(spacing: 5) {
                        if chat.isWorking && !offline && inlineStatus {
                            Circle().fill(ChatColors.green).frame(width: 7, height: 7)
                                .background(Circle().fill(ChatColors.green.opacity(0.25)).padding(-3))
                        } else if chat.state == "blocked" && !offline && inlineStatus {
                            Image(systemName: "questionmark.bubble").font(.system(size: 13)).foregroundStyle(ChatColors.amber)
                        }
                        Text(ChatPresentation.preview(chat, offline: offline)).font(.system(size: status)).lineLimit(1)
                            .foregroundStyle(chat.isWorking ? (inlineStatus ? ChatColors.green : ChatColors.secondary) : chat.state == "blocked" ? (inlineStatus ? ChatColors.amber : ChatColors.hex(0xFFB340)) : ChatColors.secondary)
                    }.frame(minHeight: secondHeight, alignment: .leading)
                    Text(chat.instructions.isEmpty ? "\(ChatPresentation.modelLabel(chat.model)) · \(item.host.name)" : chat.instructions)
                        .font(.system(size: purpose)).foregroundStyle(ChatColors.muted).lineLimit(1)
                        .frame(minHeight: thirdHeight, alignment: .leading)
                }.padding(.top, top).padding(.bottom, bottom)
                Rectangle().fill(isTablet && selectedChat?.id == item.id ? .clear : ChatColors.separator).frame(height: inlineStatus ? 0.5 : 1)
            }
        }.padding(.leading, leading).padding(.trailing, trailing)
            .background(selectedChat?.id == item.id && usesSplit ? ChatColors.selection : .clear, in: RoundedRectangle(cornerRadius: isTablet ? 12 : 0))
            .padding(.horizontal, isTablet ? 8 : 0)
            .contentShape(Rectangle())
    }
    private func startPolling() {
        guard isVisible, polling == nil else { return }
        polling = Task { @MainActor in
            repeat {
                if usesSplit || path.isEmpty { await refresh() }
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            } while !Task.isCancelled
        }
    }
    private func refresh() async {
        guard !Task.isCancelled else { return }
        offlineHosts.formIntersection(Set(hosts.map(\.id)))
        for await update in ChatHostDiscovery.updates(hosts: hosts) {
            guard !Task.isCancelled else { return }
            if let fresh = update.sessions {
                workspace.accept(fresh, on: update.host, configured: hosts, deletedIDs: update.deletedIDs)
                offlineHosts.remove(update.host.id)
            } else { offlineHosts.insert(update.host.id) }
            loading = false
        }
        if !Task.isCancelled {
            loading = false
            Task { await workspace.flush(hosts: hosts) }
        }
    }

}

// Own network work independently of transient split-view appearance callbacks.
// A navigation transition can report disappear while this screen remains visible.
@MainActor @Observable
private final class ChatSessionModel {
    var record: ChatSessionRecord?
    var messages: [ChatMessageRecord] = []
    var hasMore = false
    var error: String?
    private var polling: Task<Void, Never>?
    private var host: ScheduledTaskHost?
    private var hosts: [ScheduledTaskHost] = []
    private var sessionID = ""
    private var onRead: ((String) -> Void)?

    func start(host: ScheduledTaskHost, hosts: [ScheduledTaskHost], sessionID: String, onRead: ((String) -> Void)?) {
        self.hosts = hosts
        if self.host != host || self.sessionID != sessionID {
            stop(); self.host = host; self.sessionID = sessionID; self.onRead = onRead
        }
        record = ChatWorkspace.shared.record(sessionID, fallback: host)
        messages = ChatWorkspace.shared.messages(sessionID)
        guard polling == nil else { return }
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                guard self != nil else { break }
            }
        }
    }
    func stop() { polling?.cancel(); polling = nil }

    func refresh() async {
        guard let host else { return }
        let workspace = ChatWorkspace.shared
        if workspace.isDeleted(sessionID) { record = nil; messages = []; stop(); return }
        await workspace.flush(hosts: hosts, only: sessionID)
        if workspace.isLocal(sessionID) {
            record = workspace.record(sessionID, fallback: host)
            messages = workspace.messages(sessionID)
            error = workspace.creationFailure(sessionID)
            return
        }
        let owner = workspace.host(for: sessionID, hosts: hosts, fallback: host)
        do {
            let page = try await ChatSessionsClient(host: owner).detail(sessionID)
            guard !Task.isCancelled else { return }
            record = page.session
            let hadOlder = messages.first.map { $0.sequence < (page.messages.first?.sequence ?? 0) } ?? false
            workspace.remember(page, on: owner)
            messages = workspace.messages(sessionID)
            if !hadOlder { hasMore = page.hasMore }
            error = nil
            onRead?(sessionID)
        } catch {
            if (error as? ChatClientError)?.status == 410 {
                try? workspace.forgetDeleted(sessionID); record = nil; messages = []; stop()
            } else if !Task.isCancelled { self.error = "Offline. New messages stay queued on this device." }
        }
    }

}

struct ChatSessionScreen: View {
    let host: ScheduledTaskHost
    let sessionID: String
    var hosts: [ScheduledTaskHost] = []
    var onRead: ((String) -> Void)? = nil
    var onRemoved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var model = ChatSessionModel()
    @State private var workspace = ChatWorkspace.shared
    private var deliveryHosts: [ScheduledTaskHost] { hosts.isEmpty && host.id != ChatWorkspace.localHost.id ? [host] : hosts }
    private var effectiveHost: ScheduledTaskHost { workspace.host(for: sessionID, hosts: deliveryHosts, fallback: host) }
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    private var isTablet: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }
    private var isDesktop: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
    private let paneCanvas = ChatColors.canvas
    private var record: ChatSessionRecord? {
        get { model.record ?? workspace.record(sessionID, fallback: effectiveHost) }
        nonmutating set { model.record = newValue }
    }
    private var messages: [ChatMessageRecord] {
        get { workspace.messages(sessionID).isEmpty ? model.messages : workspace.messages(sessionID) }
        nonmutating set { model.messages = newValue }
    }
    private var hasMore: Bool {
        get { model.hasMore }
        nonmutating set { model.hasMore = newValue }
    }
    @State private var draft = ""
    @State private var sending = false
    @State private var loadingOlder = false
    private var error: String? {
        get { model.error }
        nonmutating set { model.error = newValue }
    }
    @State private var showingSettings = false
    @State private var closeAfterSettings = false
    @State private var followsReply = true
    @State private var modelCatalog = ModelCatalogResponse.fallback
    #if os(iOS)
    @State private var showingFullTitle = false
    @State private var showingSubagents = false
    @State private var subagentsAfterSettings = false
    @State private var toolOutput: ChatToolOutput?
    @State private var filesAfterSettings = false
    @State private var showingAttachments = false
    @State private var viewingChatFile: MediaRef?
    @State private var filePane = FilePaneState()
    @State private var paneResources = TranscriptResources()
    @State private var paneRevision = ""
    @State private var loadingFileHistory = false
    @State private var fileHistoryError: String?
    @State private var fileHistoryTask: Task<Void, Never>?
    @State private var fileHistoryGeneration = UUID()
    @Environment(\.filePaneNavigation) private var paneNavigation
    private struct ChatToolOutput: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }
    private var sessionMessages: [SessionMessage] {
        let cached = workspace.transcript(sessionID)
        return cached.isEmpty ? ChatTranscriptProjection.messages(messages, turns: []) : cached
    }
    private var childAgents: [ChildAgentSession] { workspace.childAgents(sessionID) }
    @State private var composerFocused = false
    @State private var chatScrollProxy: ScrollViewProxy?
    @State private var userScrolling = false
    @State private var keyboardOcclusionHeight: CGFloat = 0
    #else
    @FocusState private var composerFocused: Bool
    #endif
    @Environment(\.scenePhase) private var scenePhase
    private var client: ChatSessionsClient { ChatSessionsClient(host: effectiveHost) }

    var body: some View {
        conversationWithResources
        .background(paneCanvas)
        .modifier(ChatAppearance())
        #if os(macOS)
        .safeAreaInset(edge: .top, spacing: 0) { macThreadHeader }
        #endif
        #if os(iOS)
        .modifier(ConversationNavigationHeader(title: record?.name ?? "Chat", fullTitle: record?.name ?? "Chat",
            status: conversationStatus,
            queued: workspace.queued(for: sessionID).filter { $0.failure == nil }.count,
            hostLabel: effectiveHost.name, project: nil, showingFullTitle: $showingFullTitle,
            optionsTitle: "Chat settings", optionsIdentifier: "chat_settings", optionsEnabled: record != nil,
            titleIdentifier: "chat_details", statusIdentifier: "chat_status",
            disclosureIdentifier: "chat_full_title", titleHint: "Shows the full chat title",
            onOptions: { showingSettings = true }))
        #else
        .navigationTitle(record?.name ?? "Chat")
        #endif
        .sheet(isPresented: $showingSettings, onDismiss: settingsDismissed) {
            if let record { settingsSheet(record) }
        }
        #if os(iOS)
        .environment(\.hostFiles, HostFiles(client: client.filesClient, cwd: record?.workingDirectory))
        .sheet(isPresented: $showingSubagents) {
            ChildAgentSessionsSheet(parentSessionID: sessionID, initialChildID: nil, chatClient: client)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $toolOutput) { output in
            ToolOutputSheet(title: output.title, text: output.text).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAttachments) {
            AttachmentsSheet(messages: sessionMessages, cwd: record?.workingDirectory, contextName: "chat",
                resourceStatus: AnyView(fileHistoryStatus))
                .environment(\.hostFiles, HostFiles(client: client.filesClient, cwd: record?.workingDirectory))
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $viewingChatFile) { ref in
            FileViewerSheet(ref: ref, files: paneResources.files.map(\.ref),
                hostFiles: HostFiles(client: client.filesClient, cwd: record?.workingDirectory))
        }
        .task(id: sessionMessages) {
            let snapshot = sessionMessages
            let resources = await Task.detached(priority: .utility) { TranscriptResourceIndex.collect(from: snapshot) }.value
            guard !Task.isCancelled else { return }
            paneResources = resources
            if !snapshot.isEmpty { filePane.observe(resources) }
        }
        .task(id: "\(filePane.selection?.id ?? "")-\(sessionMessages.hashValue)") {
            let snapshot = sessionMessages, path = filePane.selection?.raw ?? ""
            let revision = await Task.detached(priority: .utility) { FilePaneRevision.token(for: path, messages: snapshot) }.value
            if !Task.isCancelled { paneRevision = revision }
        }
        .onDisappear { fileHistoryTask?.cancel() }
        #endif
        .onAppear { model.start(host: effectiveHost, hosts: deliveryHosts, sessionID: sessionID, onRead: onRead) }
        .task(id: effectiveHost) {
            modelCatalog = .fallback
            if let catalog = try? await client.models(), !Task.isCancelled { modelCatalog = catalog }
        }
        .onChange(of: showingSettings) { _, showing in if showing { dismissComposer() } }
        .onChange(of: effectiveHost) { _, _ in model.start(host: effectiveHost, hosts: deliveryHosts, sessionID: sessionID, onRead: onRead) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
            else if phase == .active { model.start(host: effectiveHost, hosts: deliveryHosts, sessionID: sessionID, onRead: onRead) }
        }
        .onChange(of: deliveryHosts) { _, _ in model.start(host: effectiveHost, hosts: deliveryHosts, sessionID: sessionID, onRead: onRead) }
        .onChange(of: workspace.isDeleted(sessionID)) { _, deleted in
            guard deleted else { return }
            if showingSettings { closeAfterSettings = true; showingSettings = false }
            else { closeConversation() }
        }
    }
    @ViewBuilder private var conversationWithResources: some View {
        #if os(iOS)
        FilePaneContainer(state: $filePane, resources: paneResources, messages: sessionMessages,
            revision: paneRevision, hostFiles: HostFiles(client: client.filesClient, cwd: record?.workingDirectory),
            keyboardVisible: keyboardOcclusionHeight > 0, onReveal: revealFileSource,
            resourceStatus: AnyView(fileHistoryStatus), contextName: "chat", header: { filePaneHeader }, content: { conversationSurface })
            .environment(\.openURL, OpenURLAction { url in
                guard UIDevice.current.userInterfaceIdiom == .pad,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .systemAction }
                filePane.open(MediaRef(raw: url.absoluteString, kind: MediaKind.from(ext: url.pathExtension) ?? .other))
                return .handled
            })
        #else
        conversationSurface
        #endif
    }
    @ViewBuilder private var conversationSurface: some View {
        #if os(iOS)
        GeometryReader { safeArea in
            // Keep the ScrollView inside its real viewport. Expanding its safe
            // area changes bottom alignment even when the composer is separate.
            VStack(spacing: 0) {
                transcriptContent(topInset: 0, width: safeArea.size.width)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("chat_transcript_region")
                    .overlay(alignment: .top) { ConversationHeaderFade(height: max(safeArea.frame(in: .global).minY, 0)) }
                VStack(spacing: 8) {
                    if SubagentPill(agents: childAgents).isVisible {
                        ComposerPillRow(agents: childAgents, onSubagents: { showingSubagents = true })
                    }
                    composer
                }
                    .safeAreaPadding(.bottom, keyboardOcclusionHeight > 0 ? nil : 0)
                    .background { ConversationComposerFade(bottomSafeAreaInset: windowBottomSafeAreaInset) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("chat_composer_region")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardOcclusionHeight = frame.isEmpty ? 0 : max(window.bounds.maxY - window.convert(frame, from: nil).minY, 0)
            }
            followNewest(duration: duration)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            followNewest(duration: 0.2)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            followNewest(duration: 0.2)
        }
        #else
        transcriptContent(topInset: 0).safeAreaInset(edge: .bottom, spacing: 0) { composer }
        #endif
    }

    private var hasTranscriptNotice: Bool {
        error != nil || record?.error != nil || workspace.creationFailure(sessionID) != nil
    }

    private func transcriptContent(topInset: CGFloat, width: CGFloat = 402) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let error = error ?? record?.error {
                    Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                        .accessibilityIdentifier("chat_error")
                }
                if workspace.creationFailure(sessionID) != nil {
                    Button("Retry sync") { workspace.retry(sessionID); Task { await model.refresh() } }
                        .accessibilityIdentifier("chat_retry_sync")
                }
            }
            .padding(.top, hasTranscriptNotice ? topInset : 0)
            transcript(topInset: hasTranscriptNotice ? 0 : topInset, width: width)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { dismissComposer() })
    }

    private func dismissComposer() {
        #if os(iOS)
        dismissKeyboard()
        #else
        composerFocused = false
        #endif
    }

    @ViewBuilder private func settingsSheet(_ record: ChatSessionRecord) -> some View {
        #if os(iOS)
        ChatSettingsSheet(client: client, record: record, onSubagents: childAgents.isEmpty ? nil : {
            subagentsAfterSettings = true
            showingSettings = false
        }, onFiles: {
            filesAfterSettings = true; showingSettings = false
        }, isHidden: workspace.isHidden(sessionID), onHide: { try toggleHidden() },
            onDelete: { try await deleteChat(record) }) { self.record = $0; showingSettings = false }
        #else
        ChatSettingsSheet(client: client, record: record, isHidden: workspace.isHidden(sessionID),
            onHide: { try toggleHidden() }, onDelete: { try await deleteChat(record) }) { self.record = $0; showingSettings = false }
        #endif
    }

    private func settingsDismissed() {
        if closeAfterSettings { closeAfterSettings = false; closeConversation(); return }
        #if os(iOS)
        if subagentsAfterSettings { subagentsAfterSettings = false; showingSubagents = true }
        if filesAfterSettings { filesAfterSettings = false; openFilesIndex() }
        #endif
    }
    private func closeConversation() {
        model.stop()
        if let onRemoved { onRemoved() } else { dismiss() }
    }
    private func toggleHidden() throws {
        let hiding = !workspace.isHidden(sessionID)
        try workspace.setHidden(sessionID, hiding)
        closeAfterSettings = hiding; showingSettings = false
    }
    private func deleteChat(_ record: ChatSessionRecord) async throws {
        if !workspace.canDeleteLocally(sessionID) { try await client.delete(record) }
        try workspace.forgetDeleted(sessionID)
        closeAfterSettings = true; showingSettings = false
    }

    #if os(iOS)
    private var fileHistoryStatus: some View {
        Group {
            if loadingFileHistory {
                HStack(spacing: 8) { ProgressView(); Text("Loading older files and links…") }
                    .accessibilityIdentifier("chat_files_loading")
            } else if let fileHistoryError {
                HStack(spacing: 8) {
                    Text(fileHistoryError).fixedSize(horizontal: false, vertical: true)
                    Button("Retry", action: loadFileHistory).accessibilityIdentifier("chat_files_retry")
                }.accessibilityIdentifier("chat_files_error")
            }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
    }
    private func loadFileHistory() {
        fileHistoryTask?.cancel(); loadingFileHistory = true; fileHistoryError = nil
        let owner = effectiveHost, generation = UUID()
        fileHistoryGeneration = generation
        fileHistoryTask = Task { @MainActor in
            defer { if fileHistoryGeneration == generation { loadingFileHistory = false } }
            do { try await workspace.loadAllHistory(sessionID, on: owner) }
            catch is CancellationError { }
            catch { if !Task.isCancelled { fileHistoryError = "Showing saved files and links. Older history could not be loaded." } }
        }
    }
    private func openFilesIndex() {
        if UIDevice.current.userInterfaceIdiom == .pad { filePane.showFiles() }
        else { showingAttachments = true }
        loadFileHistory()
    }
    private var filePaneHeader: some View {
        ConversationPaneHeader(listTitle: "Show chats", listIdentifier: "chat_file_show_list",
            optionsTitle: "Chat settings", optionsIdentifier: "chat_file_options",
            onShowList: paneNavigation.showList, onOptions: { showingSettings = true }) {
            SessionTitleBarContent(title: record?.name ?? "Chat", status: conversationStatus,
                queued: workspace.queued(for: sessionID).filter { $0.failure == nil }.count,
                hostLabel: effectiveHost.name, project: nil,
                titleIdentifier: "chat_file_title", statusIdentifier: "chat_file_status",
                titleHint: "Shows the full chat title") {
                withAnimation(.easeOut(duration: 0.18)) { showingFullTitle.toggle() }
            }
        }
    }
    private func revealFileSource(_ id: String) {
        followsReply = false; filePane.fullWidth = false
        if !filePane.portraitDocked && paneNavigation.windowSize.height > paneNavigation.windowSize.width { filePane.close() }
        Task { @MainActor in
            await Task.yield()
            chatScrollProxy?.scrollTo(id, anchor: .center)
        }
    }
    private func followNewest(duration: Double = 0.25) {
        guard followsReply, !userScrolling else { return }
        Task { @MainActor in
            await Task.yield()
            guard followsReply, !userScrolling, let chatScrollProxy else { return }
            withAnimation(.easeOut(duration: duration)) {
                chatScrollProxy.scrollTo("chat_end", anchor: .bottom)
            }
        }
    }

    private var windowBottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
    }
    #endif

    #if os(macOS)
    private var macThreadHeader: some View {
        HStack(spacing: 9) {
            Button { showingSettings = true } label: {
                HStack(spacing: 9) {
                    ChatAvatar(name: record?.name ?? "Chat", size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record?.name ?? "Chat").font(.system(size: 14, weight: .semibold)).foregroundStyle(ChatColors.ink)
                        HStack(spacing: 4) {
                            Circle().fill(ChatColors.status(record?.state ?? "idle")).frame(width: 6, height: 6)
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text(record.map { "\($0.statusLabel) · \(ChatPresentation.activityLabel($0.lastActivityAt, now: context.date))" } ?? "Connecting…")
                            }.fontWeight(record?.isWorking == true ? .semibold : .regular)
                                .foregroundStyle(record?.isWorking == true ? ChatColors.green : ChatColors.secondary)
                            if let purpose = record?.instructions.split(separator: "\n").first, !purpose.isEmpty {
                                Text("· \(purpose)").foregroundStyle(ChatColors.secondary).lineLimit(1)
                            }
                        }.font(.system(size: 11)).help("Host: \(effectiveHost.name)")
                    }
                }
            }.buttonStyle(.plain).disabled(record == nil).accessibilityLabel("Chat details").accessibilityIdentifier("chat_details")
            Spacer(minLength: 4)
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13)).foregroundStyle(ChatColors.secondary).frame(width: 26, height: 26).background(.white.opacity(0.07), in: Circle())
            }.buttonStyle(.plain).disabled(record == nil).accessibilityLabel("Chat settings").accessibilityIdentifier("chat_settings")
        }.padding(.horizontal, 14).frame(height: 44).background(ChatColors.canvas)
            .overlay(alignment: .bottom) { Rectangle().fill(ChatColors.separator).frame(height: 1) }
    }
    #endif
    #if os(iOS)
    private var conversationStatus: SessionStatusLine.State {
        if workspace.isLocal(sessionID) { return .activity("On this device") }
        if error?.hasPrefix("Offline.") == true { return .hostOffline(sinceMs: nil) }
        guard let record else { return .activity("Connecting…") }
        if record.isWorking { return .working(sinceMs: nil) }
        switch record.state {
        case "working": return .working(sinceMs: nil)
        case "blocked": return .needsInput(sinceMs: nil)
        default: return .idle
        }
    }
    #endif
    @ViewBuilder private var composer: some View {
        #if os(iOS)
        MessageComposer(text: $draft, placeholder: "Message \(record?.name ?? "chat")…",
            sending: sending, allowsAttachments: false,
            messageIdentifier: "chat_composer", sendIdentifier: "chat_send", stopIdentifier: "chat_stop",
            s2: true, accessory: AnyView(chatModelMenu),
            onStop: record?.isWorking == true ? { Task { await stop() } } : nil,
            bottomPadding: composerFocused ? 8 : -6,
            onFocusChange: { focused in
                composerFocused = focused
                if focused { followNewest() }
            }) { text, _ in
                Task { await send(text) }
            }
            .frame(maxWidth: ReadableColumn.maxWidth)
            .frame(maxWidth: .infinity)
        #else
        macComposer
        #endif
    }

    #if os(iOS)
    private var chatModelMenu: some View {
        Menu {
            Button("Default") { Task { await changeModel("") } }.accessibilityIdentifier("chat_model_default")
            ForEach(modelCatalog.models(for: .claude), id: \.self) { choice in
                Button(ModelChipLabel.model(choice)) { Task { await changeModel(choice) } }
                    .accessibilityIdentifier("chat_model_\(choice)")
            }
            Button("Chat settings…") { showingSettings = true }.accessibilityIdentifier("chat_model_settings")
        } label: {
            ComposerModelLabel(text: record?.model.flatMap { $0.isEmpty ? nil : ModelChipLabel.model($0) } ?? "Claude · Default")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(record == nil || record?.isWorking == true)
        .accessibilityLabel("Chat model").accessibilityIdentifier("chat_model")
    }
    #endif

    #if os(macOS)
    private var macComposer: some View {
        VStack(alignment: .leading, spacing: isDesktop ? 22 : isTablet ? 33 : 18) {
            TextField("Message", text: $draft, prompt: Text("Message \(record?.name ?? "chat")…").foregroundStyle(ChatColors.muted), axis: .vertical).lineLimit(1...6).textFieldStyle(.plain)
                .font(.system(size: isDesktop ? 13 : isTablet ? 16 : 17)).frame(minHeight: isDesktop ? 18 : isTablet ? 20 : 22)
                .focused($composerFocused)
                .accessibilityIdentifier("chat_composer")
            HStack(spacing: 10) {
                Menu {
                    Button("Default") { Task { await changeModel("") } }.accessibilityIdentifier("chat_model_default")
                    ForEach(modelCatalog.models(for: .claude), id: \.self) { choice in
                        Button(choice) { Task { await changeModel(choice) } }.accessibilityIdentifier("chat_model_\(choice)")
                    }
                    Button("Chat settings…") { showingSettings = true }.accessibilityIdentifier("chat_model_settings")
                } label: {
                    HStack(spacing: 6) {
                        Text(ChatPresentation.modelLabel(record?.model))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }.font(.system(size: isDesktop ? 11 : isTablet ? 12 : 13, weight: .medium)).foregroundStyle(ChatColors.secondary)
                        .padding(.horizontal, isDesktop ? 8 : 10).frame(height: isDesktop ? 22 : isTablet ? 26 : 28)
                        .background(ChatColors.field, in: Capsule())
                }
                #if os(macOS)
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                #else
                .menuStyle(.borderlessButton)
                #endif
                .fixedSize()
                    .disabled(record == nil || record?.isWorking == true)
                    .accessibilityLabel("Chat model").accessibilityIdentifier("chat_model")
                Spacer()
                if record?.isWorking == true {
                    Button { Task { await stop() } } label: {
                        RoundedRectangle(cornerRadius: isDesktop ? 2 : 3).fill(ChatColors.canvas).frame(width: isDesktop ? 9 : 11, height: isDesktop ? 9 : 11)
                            .frame(width: isDesktop ? 26 : isTablet ? 32 : 34, height: isDesktop ? 26 : isTablet ? 32 : 34).background(ChatColors.ink, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Stop reply").accessibilityIdentifier("chat_stop")
                }
                Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: isDesktop ? 14 : 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: isDesktop ? 26 : isTablet ? 32 : 34, height: isDesktop ? 26 : isTablet ? 32 : 34).background(ChatColors.blue, in: Circle())
                    }.buttonStyle(.plain)
                        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0.4)
                        .accessibilityLabel("Send message").accessibilityIdentifier("chat_send")
            }
        }
        .padding(.leading, isDesktop ? 12 : 16).padding(.trailing, isDesktop ? 8 : 10).padding(.top, isDesktop ? 9 : 11).padding(.bottom, isDesktop ? 8 : 10).frame(minHeight: isDesktop ? 85 : isTablet ? 106 : 96)
        .background(isDesktop ? ChatColors.hex(0x262629) : ChatColors.raised, in: RoundedRectangle(cornerRadius: isDesktop ? 16 : isTablet ? 22 : 24))
        .overlay(RoundedRectangle(cornerRadius: isDesktop ? 16 : isTablet ? 22 : 24).strokeBorder(isDesktop ? .white.opacity(0.06) : ChatColors.hex(0x38383A), lineWidth: isDesktop ? 1 : 0.5))
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, isDesktop || isTablet ? 8 : composerFocused ? 8 : -6)
        .frame(maxWidth: .infinity).background(paneCanvas.opacity(0.95))
    }
    #endif
    private var emptyChatState: some View {
        ContentUnavailableView("What’s on your mind?", systemImage: "bubble.left.and.bubble.right",
            description: Text("Just start chatting. Ask me to remember something or set a standing instruction whenever you need."))
            .accessibilityIdentifier("chat_empty_state")
    }

    @ViewBuilder private func transcript(topInset: CGFloat, width: CGFloat = 402) -> some View {
        if messages.isEmpty && record?.isWorking != true {
            emptyChatState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: isDesktop ? 11 : 14) {
                        if hasMore {
                            Button(loadingOlder ? "Loading…" : "Earlier messages") { Task { await older() } }
                                .disabled(loadingOlder).accessibilityIdentifier("chat_older")
                                .frame(maxWidth: .infinity)
                        }
                        #if os(iOS)
                        let rendered = sessionMessages
                        ForEach(TranscriptDisplayItem.items(for: rendered)) { item in
                            switch item.item {
                            case .message(let index):
                                let message = rendered[index]
                                VStack(alignment: .trailing, spacing: 4) {
                                    TranscriptMessageView(message: message,
                                        followsUserBubble: rendered[..<index].last(where: { $0.kind != "thinking" })?.rendersAsUserBubble == true,
                                        onFollowup: { draft = FollowupDraft.adding($0, to: draft) },
                                        onOpenFile: { ref, _ in
                                            if UIDevice.current.userInterfaceIdiom == .pad { filePane.open(ref) }
                                            else { viewingChatFile = ref }
                                        })
                                    if message.rendersAsUserBubble, let original = messages.first(where: { $0.id == message.id }), let label = workspace.deliveryLabel(original.requestID) {
                                        HStack(spacing: 8) {
                                            Text(label).font(.caption).foregroundStyle(.secondary)
                                            if label == "Retry" { Button("Retry") { workspace.retry(sessionID); Task { await model.refresh() } } }
                                        }.accessibilityIdentifier("chat_delivery_" + original.requestID)
                                    }
                                }.id(message.stableID)
                            case .steps(let group):
                                ToolStepGroupView(group: group, cwd: record?.workingDirectory, followsStep: item.followsStep) { title, text in
                                    toolOutput = ChatToolOutput(title: title, text: text)
                                }
                            }
                        }
                        #else
                        ForEach(messages) { message in
                            if message.role == "user" {
                                HStack {
                                    Spacer(minLength: 0)
                                    userMessage(message)
                                }.id(message.id)
                            } else {
                                assistantText(message.text).foregroundStyle(ChatColors.ink).lineSpacing(isDesktop ? 2 : 4)
                                    .frame(maxWidth: .infinity, alignment: .leading).id(message.id)
                            }
                        }
                        #endif
                        if record?.isWorking == true && messages.last?.role != "assistant" {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").font(.callout).foregroundStyle(.secondary) }
                                .accessibilityIdentifier("chat_thinking")
                        }
                        Color.clear.frame(height: 1).id("chat_end")
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                    #if os(iOS)
                    .frame(maxWidth: ReadableColumn.maxWidth)
                    .environment(\.transcriptColumnWidth, ReadableColumn.width(in: width))
                    #endif
                    .frame(maxWidth: .infinity)
                }
                #if os(iOS)
                .onAppear {
                    chatScrollProxy = proxy
                    followNewest()
                }
                .onDisappear { chatScrollProxy = nil }
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase == .interacting || phase == .decelerating
                }
                #endif
                .contentMargins(.top, topInset, for: .scrollContent)
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("chat_transcript")
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 80
                } action: { _, nearBottom in
                    #if os(iOS)
                    if userScrolling && !loadingOlder { followsReply = nearBottom }
                    #else
                    if !loadingOlder { followsReply = nearBottom }
                    #endif
                }
                .onChange(of: messages.last?.text) { _, _ in
                    guard followsReply else { return }
                    #if os(iOS)
                    followNewest()
                    #else
                    proxy.scrollTo("chat_end", anchor: .bottom)
                    #endif
                }
                #if os(iOS)
                .onChange(of: sessionMessages) { _, _ in if followsReply { followNewest() } }
                #endif
            }
        }
    }
    @ViewBuilder private func assistantText(_ text: String) -> some View {
        #if canImport(MarkdownUI)
        Markdown(text).textSelection(.enabled).markdownTextStyle { FontSize(isDesktop ? 13 : 17) }
        #else
        Text(.init(text)).font(.system(size: isDesktop ? 13 : 17)).textSelection(.enabled)
        #endif
    }
    private func changeModel(_ model: String) async {
        guard let record else { return }
        do { self.record = try await client.save(record, name: record.name, instructions: record.instructions, memory: record.memory, model: model) }
        catch { self.error = error.localizedDescription }
    }
    private func poll() async {
        await model.refresh()
    }
    private func older() async {
        guard let first = messages.first else { return }
        loadingOlder = true; followsReply = false; defer { loadingOlder = false }
        do { let page = try await client.detail(sessionID, before: first.sequence); workspace.remember(page, on: effectiveHost); messages = workspace.messages(sessionID); hasMore = page.hasMore }
        catch { self.error = error.localizedDescription }
    }
    private func send(_ submittedText: String? = nil) async {
        guard !sending else { return }
        let text = (submittedText ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true; defer { sending = false }
        do {
            try workspace.enqueue(sessionID, text: text, on: effectiveHost)
            if submittedText == nil { draft = "" }
            followsReply = true; error = nil
            Task { await model.refresh() }
        } catch {
            if draft.isEmpty { draft = text }
            self.error = "Couldn’t save this message on your device. \(error.localizedDescription)"
        }
    }
    private func userMessage(_ message: ChatMessageRecord) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.text).font(.system(size: isDesktop ? 13 : 17)).lineSpacing(isDesktop ? 1 : 2)
                .foregroundStyle(ChatColors.hex(0xF2F2F7)).textSelection(.enabled)
                .padding(.horizontal, isDesktop ? 11 : 14).padding(.vertical, isDesktop ? 7 : 10)
                .background(ChatColors.userBubble, in: RoundedRectangle(cornerRadius: isDesktop ? 15 : 20))
            if let label = workspace.deliveryLabel(message.requestID) {
                HStack(spacing: 8) {
                    Text(label).font(.caption).foregroundStyle(ChatColors.secondary)
                    if label == "Retry" {
                        Button("Retry") { workspace.retry(sessionID); Task { await model.refresh() } }
                            .font(.caption).accessibilityIdentifier("chat_retry_" + message.requestID)
                    }
                }.accessibilityIdentifier("chat_delivery_" + message.requestID)
            }
        }.frame(maxWidth: isDesktop ? 278 : 290, alignment: .trailing)
    }
    private func stop() async {
        do { try await client.interrupt(sessionID); await poll() }
        catch { self.error = error.localizedDescription }
    }
}

private enum ChatSettingsPage: String, Hashable {
    case name = "Name", instructions = "Instructions", memory = "Memory", model = "Model", host = "Host"
}
private struct ChatSettingsSheet: View {
    let client: ChatSessionsClient
    let record: ChatSessionRecord
    let saved: (ChatSessionRecord) -> Void
    var onSubagents: (() -> Void)?
    var onFiles: (() -> Void)?
    var isHidden: Bool
    var onHide: (() async throws -> Void)?
    var onDelete: (() async throws -> Void)?
    @State private var name: String
    @State private var instructions: String
    @State private var memory: String
    @State private var model: String
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    init(client: ChatSessionsClient, record: ChatSessionRecord, onSubagents: (() -> Void)? = nil,
         onFiles: (() -> Void)? = nil, isHidden: Bool = false, onHide: (() async throws -> Void)? = nil,
         onDelete: (() async throws -> Void)? = nil, saved: @escaping (ChatSessionRecord) -> Void) {
        self.client = client; self.record = record; self.saved = saved; self.onSubagents = onSubagents
        self.onFiles = onFiles; self.isHidden = isHidden; self.onHide = onHide; self.onDelete = onDelete
        _name = State(initialValue: record.name); _instructions = State(initialValue: record.instructions)
        _memory = State(initialValue: record.memory); _model = State(initialValue: record.model ?? "")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink(value: ChatSettingsPage.name) {
                        HStack(spacing: 12) {
                            ChatAvatar(name: name, size: 42, state: record.state)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.system(size: 20, weight: .semibold)).foregroundStyle(ChatColors.ink)
                                Text(ChatPresentation.modelLabel(model)).font(.system(size: 13)).foregroundStyle(ChatColors.muted)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "pencil").font(.system(size: 15)).foregroundStyle(ChatColors.muted)
                        }.padding(.horizontal, 2).padding(.bottom, 2)
                    }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_identity")
                    HStack(spacing: 8) {
                        shortcut(.instructions, icon: "pencil")
                        shortcut(.memory, icon: "doc.text")
                        shortcut(.model, icon: "cpu")
                        if let onFiles {
                            Button(action: onFiles) {
                                VStack(spacing: 5) {
                                    Image(systemName: "paperclip").font(.system(size: 20))
                                    Text("Files & links").font(.system(size: 12)).multilineTextAlignment(.center)
                                }.foregroundStyle(ChatColors.ink).frame(maxWidth: .infinity).frame(height: 64)
                                    .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_files")
                        }
                    }
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text(busy ? "Saving model…" : "Model")
                                .font(.system(size: 17)).foregroundStyle(ChatColors.ink)
                            Spacer(minLength: 4)
                            ChatModelPicker(selection: Binding(
                                get: { record.model ?? "" },
                                set: { choice in Task { await saveModel(choice) } }
                            ), host: client.host)
                                .frame(maxWidth: 220)
                                .disabled(busy || record.isWorking)
                                .accessibilityIdentifier("chat_options_model")
                        }.padding(.horizontal, 14)
                        Divider().padding(.leading, 14)
                        NavigationLink(value: ChatSettingsPage.host) {
                            HStack(spacing: 12) {
                                Text("Host").foregroundStyle(ChatColors.ink)
                                Spacer(minLength: 4)
                                Text(client.host.name).foregroundStyle(ChatColors.secondary).lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(ChatColors.muted)
                            }.font(.system(size: 17)).padding(.horizontal, 14).frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("chat_options_host")
                    }.background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        ChatSectionHeading(title: "Only this chat")
                        VStack(spacing: 0) {
                            settingsRow(.instructions, title: "Instructions", subtitle: instructions.isEmpty ? "How this chat should respond" : instructions, icon: "pencil")
                            Divider().overlay(ChatColors.hex(0x3A3A3C)).padding(.leading, 41)
                            settingsRow(.memory, title: "What it remembers", subtitle: memory.isEmpty ? "Private facts and preferences" : memory, icon: "doc.text")
                            Divider().overlay(ChatColors.hex(0x3A3A3C)).padding(.leading, 41)
                            NavigationLink { ChatJobsView(host: client.host, chatId: record.id) } label: {
                                HStack(spacing: 12) { Image(systemName: "clock").frame(width: 20); VStack(alignment: .leading, spacing: 3) { Text("Tasks").foregroundStyle(ChatColors.ink); Text("Reminders and instructions for this chat").font(.system(size: 12)).foregroundStyle(ChatColors.muted) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(ChatColors.muted) }.padding(14).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_jobs")
                            if let onSubagents {
                                Divider().overlay(ChatColors.hex(0x3A3A3C)).padding(.leading, 41)
                                Button(action: onSubagents) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.2").frame(width: 20)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Subagents").foregroundStyle(ChatColors.ink)
                                            Text("Live activity and completed work").font(.system(size: 12)).foregroundStyle(ChatColors.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(ChatColors.muted)
                                    }.padding(14).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_subagents")
                            }
                        }.background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Text("Instructions and memory stay with this conversation. Changes apply to your next message.")
                        .font(.system(size: 13)).foregroundStyle(ChatColors.muted).lineSpacing(3).padding(.horizontal, 2)
                    if record.isWorking {
                        Text("Stop the current reply to change these settings.").font(.system(size: 13)).foregroundStyle(ChatColors.amber)
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(ChatColors.amber)
                            .accessibilityIdentifier("chat_settings_error")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        if onHide != nil {
                            Button(isHidden ? "Show in chat list" : "Hide from this device", systemImage: isHidden ? "eye" : "eye.slash") {
                                Task { await removeChat(permanently: false) }
                            }.disabled(busy).accessibilityIdentifier("chat_settings_hide")
                            Text("Hiding only changes this device’s list. The chat and its scheduled tasks continue.")
                                .font(.caption).foregroundStyle(ChatColors.muted)
                        }
                        if onDelete != nil {
                            Button("Delete chat…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                                .disabled(busy || record.isWorking).accessibilityIdentifier("chat_settings_delete")
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }.background(ChatColors.raised).navigationTitle("Chat")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }.disabled(busy).accessibilityIdentifier("chat_settings_cancel")
                    }
                }
                .navigationDestination(for: ChatSettingsPage.self) { page in
                    if page == .host {
                        hostInformation
                    } else {
                        editor(page).onAppear {
                            name = record.name; instructions = record.instructions; memory = record.memory; model = record.model ?? ""
                            error = nil
                        }
                    }
                }
        }.tint(ChatColors.hex(0x409CFF)).modifier(ChatAppearance())
            .confirmationDialog("Delete \(record.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete chat", role: .destructive) { Task { await removeChat(permanently: true) } }
                    .accessibilityIdentifier("chat_delete_confirm")
                Button("Cancel", role: .cancel) { }.accessibilityIdentifier("chat_delete_cancel")
            } message: {
                Text("Deletes this chat’s messages, instructions, memory and files in its chat storage, and cancels its scheduled tasks. Files elsewhere on your hosts remain. This cannot be undone.")
            }
            .interactiveDismissDisabled(busy)
            .presentationBackground(ChatColors.raised)
            .presentationCornerRadius(34).presentationDragIndicator(.visible)
            #if os(macOS)
            .frame(width: 360, height: 600)
            #endif
    }
    private func shortcut(_ page: ChatSettingsPage, icon: String) -> some View {
        NavigationLink(value: page) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20))
                Text(page.rawValue).font(.system(size: 12))
            }.foregroundStyle(ChatColors.ink).frame(maxWidth: .infinity).frame(height: 64)
                .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_\(page.rawValue.lowercased())_open")
    }
    private func settingsRow(_ page: ChatSettingsPage, title: String, subtitle: String, icon: String) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(ChatColors.secondary).frame(width: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16)).foregroundStyle(ChatColors.ink)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(ChatColors.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(ChatColors.hex(0x636366))
            }.padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 72)
        }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_\(page.rawValue.lowercased())_row")
    }
    private var hostInformation: some View {
        Form {
            Section("Current host") {
                LabeledContent("Name", value: client.host.name)
                    .accessibilityIdentifier("chat_host_name")
                LabeledContent("Address", value: client.host.baseURL.absoluteString)
                    .textSelection(.enabled).accessibilityIdentifier("chat_host_address")
            }
            Section {
                Text("This conversation stays on this host. Moving an existing chat to another host is not available yet.")
                    .foregroundStyle(ChatColors.secondary).accessibilityIdentifier("chat_host_transfer_info")
            }
        }.formStyle(.grouped).navigationTitle("Host")
    }
    private func editor(_ page: ChatSettingsPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch page {
                case .name:
                    HStack(spacing: 12) {
                        ChatAvatar(name: name, size: 52)
                        TextField("Name", text: $name).textFieldStyle(.plain).font(.system(size: 20, weight: .semibold))
                            .padding(14).background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("chat_settings_name")
                    }
                case .instructions:
                    ChatPrivateEditor(title: "Instructions", text: $instructions, identifier: "chat_settings_instructions",
                        hint: "How should this chat respond?", helper: "Private to this chat. Changes apply to your next message.", height: 220)
                case .memory:
                    ChatPrivateEditor(title: "Memory", text: $memory, identifier: "chat_settings_memory",
                        hint: "Facts and preferences to remember", helper: "Private facts and preferences. Changes apply to your next message.", height: 220)
                    if !record.summary.isEmpty {
                        ChatSectionHeading(title: "Conversation memory")
                        Text(record.summary).font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("chat_summary")
                        Text("Older messages are summarized automatically. Your full history stays saved.").font(.system(size: 13)).foregroundStyle(ChatColors.muted)
                    }
                case .model:
                    ChatSectionHeading(title: "Claude Code")
                    ChatModelPicker(selection: $model, host: client.host).accessibilityIdentifier("chat_settings_model")
                    Text("This model answers your next message.").font(.system(size: 13)).foregroundStyle(ChatColors.muted)
                case .host:
                    EmptyView()
                }
                if record.isWorking { Text("Stop the current reply to change these settings.").font(.callout).foregroundStyle(ChatColors.amber) }
                if let error { Text(error).font(.callout).foregroundStyle(ChatColors.amber).accessibilityIdentifier("chat_settings_error") }
            }.disabled(busy || record.isWorking).padding(16)
        }.scrollDismissesKeyboard(.interactively).background(ChatColors.raised).navigationTitle(page.rawValue)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(busy || record.isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("chat_settings_save")
                }
            }
    }
    private func saveModel(_ choice: String) async {
        guard !busy, !record.isWorking, choice != (record.model ?? "") else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            saved(try await client.save(record, name: record.name, instructions: record.instructions,
                memory: record.memory, model: choice))
        } catch { self.error = error.localizedDescription }
    }
    private func removeChat(permanently: Bool) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            if permanently { try await onDelete?() }
            else { try await onHide?() }
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        do { saved(try await client.save(record, name: name, instructions: instructions, memory: memory, model: model)) }
        catch { self.error = error.localizedDescription }
    }
}
private struct ChatSectionHeading: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.48)
            .foregroundStyle(ChatColors.muted).padding(.horizontal, 2)
    }
}
private struct ChatPrivateEditor: View {
    let title: String
    @Binding var text: String
    let identifier: String
    let hint: String
    let helper: String
    var height: CGFloat = 110
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatSectionHeading(title: title)
            TextEditor(text: $text).scrollContentBackground(.hidden)
                .font(.system(size: 15)).lineSpacing(4).foregroundStyle(ChatColors.ink)
                .padding(.horizontal, 8).padding(.vertical, 6).frame(minHeight: height)
                .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text(hint).font(.system(size: 15)).foregroundStyle(ChatColors.muted).padding(.horizontal, 13).padding(.top, 14).allowsHitTesting(false) }
                }.accessibilityLabel(title).accessibilityIdentifier(identifier)
            Text(helper).font(.system(size: 13)).foregroundStyle(ChatColors.muted).lineSpacing(3).padding(.horizontal, 2)
        }
    }
}
private struct ChatModelPicker: View {
    @Binding var selection: String
    let host: ScheduledTaskHost?
    var preservesCurrentSelection = true
    @State private var catalog = ModelCatalogResponse.fallback
    var body: some View {
        Menu {
            Picker("Model", selection: $selection) {
                Text("Default").tag("")
                ForEach(catalog.models(for: .claude), id: \.self) { choice in Text(choice).tag(choice) }
                if !selection.isEmpty && !catalog.models(for: .claude).contains(selection) { Text(selection).tag(selection) }
            }.pickerStyle(.inline).labelsHidden()
        } label: {
            HStack {
                Text(selection.isEmpty ? "Default" : selection).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
            }.foregroundStyle(ChatColors.ink).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel("Model")
            .accessibilityValue(selection.isEmpty ? "Default" : selection)
            .task(id: host) {
                catalog = .fallback
                guard let host else { return }
                if let discovered = try? await ChatSessionsClient(host: host).models(), !Task.isCancelled {
                    catalog = discovered
                }
                guard !Task.isCancelled else { return }
                if !preservesCurrentSelection && !selection.isEmpty && !catalog.models(for: .claude).contains(selection) { selection = "" }
            }
    }
}

private struct ChatAvatar: View {
    let name: String
    var size: CGFloat = 38
    var state: String? = nil
    var unread = false
    var offline = false
    var badgeSize: CGFloat = 11
    var ringWidth: CGFloat = 2.5
    var backdrop: Color = ChatColors.canvas
    var halo = true
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(ChatColors.hex(0xF2F2F7))
            .frame(width: size, height: size)
            .background(ChatColors.avatar(name), in: RoundedRectangle(cornerRadius: size * 0.29))
            .overlay(alignment: .bottomTrailing) {
                if let state {
                    Circle().fill(offline ? backdrop : unread && state == "idle" ? ChatColors.purple : ChatColors.status(state))
                        .overlay(Circle().strokeBorder(offline ? ChatColors.amber : .clear, lineWidth: 1.5))
                        .frame(width: badgeSize, height: badgeSize).padding(ringWidth)
                        .background(backdrop, in: Circle())
                        .background(Circle().fill(halo && !offline && state != "idle" ? ChatColors.status(state).opacity(0.267) : .clear).padding(-2))
                        .offset(x: 1, y: 1)
                }
            }.accessibilityHidden(true)
    }
}

/// Native iOS chrome follows the app's appearance. The Mac keeps its design theme.
private struct ChatAppearance: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if os(macOS)
        content.preferredColorScheme(.dark)
        #else
        content
        #endif
    }
}

private enum ChatColors {
    static func hex(_ value: UInt) -> Color { Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255) }
    static var canvas: Color {
        #if os(macOS)
        hex(0x1B1B1E)
        #else
        Color(.systemBackground)
        #endif
    }
    static var raised: Color {
        #if os(macOS)
        hex(0x1C1C1E)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
    static var field: Color {
        #if os(macOS)
        hex(0x2C2C2E)
        #else
        Color(.tertiarySystemBackground)
        #endif
    }
    static var separator: Color {
        #if os(macOS)
        .white.opacity(0.06)
        #else
        Color(.separator)
        #endif
    }
    static var secondary: Color {
        #if os(macOS)
        hex(0xA8A8B0)
        #else
        Color(.secondaryLabel)
        #endif
    }
    static var muted: Color {
        #if os(macOS)
        hex(0x8A8A93)
        #else
        Color(.tertiaryLabel)
        #endif
    }
    static var ink: Color {
        #if os(macOS)
        hex(0xF2F2F7)
        #else
        Color(.label)
        #endif
    }
    static var selection: Color {
        #if os(macOS)
        hex(0x182B3E)
        #else
        S2.listSelection
        #endif
    }
    static let green = hex(0x30D158)
    static let amber = hex(0xFF9F0A)
    static let blue = hex(0x0A84FF)
    static let purple = hex(0xBF5AF0)
    static let userBubble = hex(0x355C8F)
    static func status(_ state: String) -> Color { state == "working" ? green : state == "blocked" ? amber : blue }
    static func avatar(_ name: String) -> Color {
        hex(["mail": 0x3A5A8C, "scout": 0x3F6B52, "patch": 0x5E4A7D, "ledger": 0x7A5A38, "archivist": 0x3F5F6B, "booker": 0x6B4448][name.lowercased()] ?? 0x4A4A52)
    }
}
