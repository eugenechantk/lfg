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
    var id: String { host.id + session.id }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ChatSessionsView: View {
    let hosts: [ScheduledTaskHost]
    var onDetailChange: ((Bool) -> Void)? = nil
    var onRead: ((String) -> Void)? = nil
    var onCreated: (() -> Void)? = nil
    var createTrigger = 0
    var showsCreateInToolbar = true
    var listFooter: AnyView? = nil
    var unreadIDs: Set<String> = []
    @State private var query = ""
    @State private var showingSearch = false
    @State private var offlineHosts = Set<String>()
    @State private var chats: [ChatLocation] = []
    @State private var path: [ChatLocation] = []
    @State private var selectedChat: ChatLocation?
    #if os(macOS)
    @State private var availableWidth: CGFloat = 1000
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    private var usesSplit: Bool {
        #if os(macOS)
        availableWidth >= 700
        #else
        horizontalSizeClass == .regular
        #endif
    }
    @State private var showCreate = false
    @State private var loading = true
    @State private var errors: [String] = []
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
                        ChatSessionScreen(host: item.host, sessionID: item.session.id, onRead: onRead)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        #if os(macOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .onChange(of: usesSplit) { _, split in
            if split, let current = path.last { selectedChat = current; path = [] }
            else if !split, let selectedChat, path.isEmpty { path = [selectedChat] }
        }
        #endif
        .sheet(isPresented: $showCreate) {
            ChatCreateSheet(hosts: hosts) { host, record in
                let item = ChatLocation(host: host, session: record)
                chats.insert(item, at: 0); showCreate = false; open(item); onCreated?()
            }
        }
        .onChange(of: createTrigger) { _, _ in showCreate = true }
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
    private var listCanvas: Color { isTablet ? ChatColors.raised : ChatColors.canvas }
    #if os(macOS)
    private var desktopLayout: some View {
        HStack(spacing: 0) {
            chatList.frame(width: 300)
                .overlay(alignment: .trailing) { Rectangle().fill(ChatColors.separator).frame(width: 1) }
            Group {
                if let selectedChat {
                    ChatSessionScreen(host: selectedChat.host, sessionID: selectedChat.session.id, onRead: onRead).id(selectedChat.id)
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
        HStack(spacing: 18) {
            chatList.frame(width: 320)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .padding(.top, 18).padding(.bottom, 10)
            NavigationStack {
                Group {
                    if let selectedChat {
                        ChatSessionScreen(host: selectedChat.host, sessionID: selectedChat.session.id, onRead: onRead).id(selectedChat.id)
                    } else {
                        ContentUnavailableView("Choose a chat", systemImage: "bubble.left.and.bubble.right",
                            description: Text("Your conversations keep their own instructions and memory."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(ChatColors.canvas)
                    }
                }
            }
        }.padding(.horizontal, 10).background(ChatColors.canvas)
    }
    #endif
    private func open(_ item: ChatLocation) {
        if usesSplit { selectedChat = item } else { path.append(item) }
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
                    if errors.isEmpty { emptyList } else { listFailure }
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
        .safeAreaInset(edge: .top, spacing: 0) { listHeader }
        .modifier(ChatListDock(footer: listFooter))
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
    private var listFailure: some View {
        VStack(spacing: 13) {
            Image(systemName: "wifi.slash").font(.system(size: 32)).foregroundStyle(ChatColors.muted)
            Text("Chats are unavailable").font(.system(size: 22, weight: .semibold))
            ForEach(errors, id: \.self) { Text($0).font(.system(size: 15)).foregroundStyle(ChatColors.secondary) }
            Button("Try again") { Task { await refresh() } }.buttonStyle(.bordered)
                .accessibilityIdentifier("chat_list_retry")
        }.multilineTextAlignment(.center).padding(32).frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in max(420, height - 100) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("chat_list_error")
    }
    private var emptyList: some View {
        VStack(spacing: 13) {
            HStack(spacing: -8) {
                ChatAvatar(name: "Mail", size: 54).rotationEffect(.degrees(-8))
                ChatAvatar(name: "Scout", size: 56).zIndex(2)
                ChatAvatar(name: "Patch", size: 54).rotationEffect(.degrees(8))
            }.padding(.bottom, 8)
            Text("No chats yet").font(.system(size: 22, weight: .semibold))
            Text("Give a chat a name and standing instructions. It keeps one lasting conversation and what it learns from then on.")
                .font(.system(size: 16)).lineSpacing(3).foregroundStyle(ChatColors.hex(0xD1D1D6))
            Button { showCreate = true } label: {
                Label("New chat", systemImage: "plus").font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 22).frame(height: 50)
                    .background(ChatColors.hex(0x0A6EE0), in: Capsule()).foregroundStyle(.white)
            }.buttonStyle(.plain).padding(.top, 6).disabled(hosts.isEmpty)
                .accessibilityIdentifier("chat_empty_create")
            Text(hosts.isEmpty ? "Connect a host to start a conversation." : "Instructions and memory are private to each chat.")
                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(ChatColors.muted)
        }.multilineTextAlignment(.center).padding(.horizontal, 32).frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in max(420, height - 100) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("chat_empty")
    }
    @ViewBuilder private var listHeader: some View {
        #if os(macOS)
        macHeader
        #else
        if isTablet { tabletHeader } else { phoneHeader }
        #endif
    }
    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 8) {
            hostStrip
            Spacer(minLength: 0)
            Menu {
                Text("Most recent activity first")
                Divider()
                Button("New chat") { showCreate = true }.disabled(hosts.isEmpty).keyboardShortcut("n")
                Button("Mark all read") { for id in unreadIDs { onRead?(id) } }.disabled(unreadIDs.isEmpty)
                Button("Refresh") { Task { await refresh() } }
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
    private var tabletHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(offlineHosts.isEmpty ? ChatColors.green : ChatColors.amber).frame(width: 8, height: 8)
                Text("\(hosts.count) \(hosts.count == 1 ? "host" : "hosts")").font(.system(size: 16, weight: .semibold))
            }.accessibilityIdentifier("chat_hosts")
            Spacer(minLength: 0)
            Button { showingSearch.toggle(); if !showingSearch { query = "" } } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 21)).frame(width: 44, height: 44)
            }.accessibilityLabel("Search chats").accessibilityIdentifier("chat_search")
            Menu {
                Button("New chat") { showCreate = true }.disabled(hosts.isEmpty)
                Button("Mark all read") { for id in unreadIDs { onRead?(id) } }.disabled(unreadIDs.isEmpty)
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "plus").font(.system(size: 21)).frame(width: 44, height: 44)
            }.accessibilityLabel("Chat options").accessibilityIdentifier("chat_options")
        }.buttonStyle(.plain).foregroundStyle(.white)
            .padding(.leading, 16).padding(.trailing, 4).frame(height: 56).padding(.bottom, 10).background(listCanvas)
    }
    #endif
    private var phoneHeader: some View {
        HStack(spacing: 12) {
            hostStrip
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                Button { showingSearch.toggle(); if !showingSearch { query = "" } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 21)).frame(width: 44, height: 44)
                }.accessibilityLabel("Search chats").accessibilityIdentifier("chat_search")
                Menu {
                    Button { showCreate = true } label: { Label("New chat", systemImage: "plus") }
                        .disabled(hosts.isEmpty).accessibilityIdentifier("chat_create_menu")
                    Button("Mark all read") { for id in unreadIDs { onRead?(id) } }
                        .disabled(unreadIDs.isEmpty).accessibilityIdentifier("chat_mark_all_read")
                    Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .accessibilityIdentifier("chat_refresh")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Chat options").accessibilityIdentifier("chat_options")
            }.padding(2).modifier(ChatChrome())
            if showsCreateInToolbar {
                Button { showCreate = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .modifier(ChatChrome()).disabled(hosts.isEmpty).accessibilityLabel("New chat").accessibilityIdentifier("chat_create")
            }
        }.buttonStyle(.plain).foregroundStyle(.white)
            .frame(height: 56).padding(.horizontal, 16).padding(.bottom, 14)
            .background(ChatColors.canvas)
    }
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
            ChatAvatar(name: chat.name, size: avatar, state: chat.state, unread: unread, offline: offline, badgeSize: badge, ringWidth: ring, backdrop: listCanvas, halo: inlineStatus)
                .padding(.top, avatarTop)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chat.name).font(.system(size: title, weight: unread || chat.state == "blocked" ? (inlineStatus ? .semibold : .bold) : (inlineStatus ? .regular : .semibold)))
                            .foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 8)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(ChatPresentation.activityLabel(chat.lastActivityAt, now: context.date))
                                .font(.system(size: time)).foregroundStyle(ChatColors.muted).lineLimit(1)
                        }
                    }.frame(minHeight: firstHeight)
                    HStack(spacing: 5) {
                        if chat.state == "working" && !offline && inlineStatus {
                            Circle().fill(ChatColors.green).frame(width: 7, height: 7)
                                .background(Circle().fill(ChatColors.green.opacity(0.25)).padding(-3))
                        } else if chat.state == "blocked" && !offline && inlineStatus {
                            Image(systemName: "questionmark.bubble").font(.system(size: 13)).foregroundStyle(ChatColors.amber)
                        }
                        Text(ChatPresentation.preview(chat, offline: offline)).font(.system(size: status)).lineLimit(1)
                            .foregroundStyle(chat.state == "working" ? (inlineStatus ? ChatColors.green : ChatColors.secondary) : chat.state == "blocked" ? (inlineStatus ? ChatColors.amber : ChatColors.hex(0xFFB340)) : ChatColors.secondary)
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
            .opacity(offline ? 0.5 : 1).contentShape(Rectangle())
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
        var result = chats.filter { item in hosts.contains(where: { $0.id == item.host.id }) }
        var failures: [String] = []
        var seen = Set<String>()
        var failed = Set<String>()
        for host in hosts where seen.insert(host.id).inserted {
            do {
                let fresh = try await ChatSessionsClient(host: host).list()
                result.removeAll { $0.host.id == host.id }
                result += fresh.map { ChatLocation(host: host, session: $0) }
            }
            catch { failures.append("\(host.name): \(error.localizedDescription)"); failed.insert(host.id) }
        }
        guard !Task.isCancelled else { return }
        chats = result.sorted {
            $0.session.lastActivityAt == $1.session.lastActivityAt ? $0.id < $1.id : $0.session.lastActivityAt > $1.session.lastActivityAt
        }
        errors = failures; offlineHosts = failed; loading = false
    }
}

private struct ChatListDock: ViewModifier {
    let footer: AnyView?
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) { footer }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        #else
        content.safeAreaInset(edge: .bottom, spacing: 0) { footer }
        #endif
    }
}

private struct ChatCreateSheet: View {
    let hosts: [ScheduledTaskHost]
    let created: (ScheduledTaskHost, ChatSessionRecord) -> Void
    @State private var hostID = ""
    private var host: ScheduledTaskHost? { hosts.first { $0.id == hostID } ?? hosts.first }
    @State private var name = ""
    @State private var instructions = ""
    @State private var memory = ""
    @State private var model = ""
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ChatAvatar(name: name.isEmpty ? "Chat" : name, size: 52)
                        TextField("Name your chat", text: $name).textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .semibold)).padding(.horizontal, 14).frame(height: 48)
                            .background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("Chat name").accessibilityIdentifier("chat_name")
                    }.padding(.horizontal, 2)
                    ChatPrivateEditor(title: "Instructions", text: $instructions, identifier: "chat_instructions",
                        hint: "How should this chat respond?", helper: "This is the chat’s personality. It stays with this thread and is not shared with your other chats.")
                    VStack(alignment: .leading, spacing: 8) {
                        ChatSectionHeading(title: "Model")
                        ChatModelPicker(selection: $model, host: host, preservesCurrentSelection: false)
                            .accessibilityIdentifier("chat_create_model")
                        Text("Claude Code replies on \(host?.name ?? "your host").")
                            .font(.system(size: 13)).foregroundStyle(ChatColors.muted).padding(.horizontal, 2)
                    }
                    ChatPrivateEditor(title: "Memory", text: $memory, identifier: "chat_memory",
                        hint: "Facts and preferences to remember", helper: "Private to this chat. You can read and change it at any time.", height: 94)
                    if hosts.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            ChatSectionHeading(title: "Host")
                            Picker("Replies run on", selection: $hostID) {
                                ForEach(hosts) { Text($0.name).tag($0.id) }
                            }.padding(12).background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityIdentifier("chat_host_picker")
                        }
                    }
                    if hosts.isEmpty { Text("Connect a host to create a chat.").font(.callout).foregroundStyle(ChatColors.amber) }
                    if let error { Text(error).font(.callout).foregroundStyle(ChatColors.amber).accessibilityIdentifier("chat_create_error") }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16).disabled(busy)
            }.scrollDismissesKeyboard(.interactively)
                .background(ChatColors.raised)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button { Task { await create() } } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "Creating chat…" : "Create chat").font(.system(size: 17, weight: .semibold))
                        }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50)
                            .background(ChatColors.hex(0x0A6EE0), in: Capsule())
                    }.buttonStyle(.plain)
                        .disabled(busy || host == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(!busy && host != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0.45)
                        .accessibilityIdentifier("chat_create_save")
                        .padding(.horizontal, 16).padding(.vertical, 12).background(ChatColors.raised)
                }
                .navigationTitle("New chat")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly).disabled(busy).accessibilityIdentifier("chat_create_cancel")
                    }
                }
        }
        .tint(ChatColors.hex(0x409CFF)).preferredColorScheme(.dark)
        .interactiveDismissDisabled(busy)
        .presentationBackground(ChatColors.raised)
        .presentationCornerRadius(34).presentationDragIndicator(.visible)
        .onAppear { if hostID.isEmpty { hostID = hosts.first?.id ?? "" } }
        #if os(macOS)
        .frame(width: 360, height: 680)
        #endif
    }
    private func create() async {
        guard let host else { return }
        busy = true; error = nil; defer { busy = false }
        do { created(host, try await ChatSessionsClient(host: host).create(name: name, instructions: instructions, memory: memory, model: model)) }
        catch { self.error = error.localizedDescription }
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
    private var sessionID = ""
    private var onRead: ((String) -> Void)?

    func start(host: ScheduledTaskHost, sessionID: String, onRead: ((String) -> Void)?) {
        if self.host != host || self.sessionID != sessionID {
            stop(); self.host = host; self.sessionID = sessionID; self.onRead = onRead
        }
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
        do {
            let page = try await ChatSessionsClient(host: host).detail(sessionID)
            guard !Task.isCancelled else { return }
            record = page.session
            let hadOlder = messages.first.map { $0.sequence < (page.messages.first?.sequence ?? 0) } ?? false
            messages = ChatHistoryMerge.merge(messages, page.messages)
            if !hadOlder { hasMore = page.hasMore }
            error = nil
            onRead?(sessionID)
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ChatSessionScreen: View {
    let host: ScheduledTaskHost
    let sessionID: String
    var onRead: ((String) -> Void)? = nil
    @State private var model = ChatSessionModel()
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
        get { model.record }
        nonmutating set { model.record = newValue }
    }
    private var messages: [ChatMessageRecord] {
        get { model.messages }
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
    @State private var followsReply = true
    @State private var pendingSend: (id: String, text: String)?
    @State private var modelCatalog = ModelCatalogResponse.fallback
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var client: ChatSessionsClient { ChatSessionsClient(host: host) }

    var body: some View {
        VStack(spacing: 0) {
            if let error = error ?? record?.error {
                Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                    .accessibilityIdentifier("chat_error")
            }
            transcript
        }
        .background(paneCanvas)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        #if os(macOS)
        .safeAreaInset(edge: .top, spacing: 0) { macThreadHeader }
        #else
        .safeAreaInset(edge: .top, spacing: 0) { if isTablet { tabletThreadHeader } }
        #endif
        .navigationTitle(record?.name ?? "Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isTablet ? .hidden : .visible, for: .navigationBar)
        #endif
        #if os(iOS)
        .toolbar {
            if !isTablet {
                ToolbarItem(placement: .principal) { threadHeading }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(uiImage: SessionOptionsGlyph.image).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.frame(width: 44, height: 44).accessibilityLabel("Chat settings")
                        .disabled(record == nil).accessibilityIdentifier("chat_settings")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingSettings) {
            if let record { ChatSettingsSheet(client: client, record: record) { self.record = $0; showingSettings = false } }
        }
        .onAppear { model.start(host: host, sessionID: sessionID, onRead: onRead) }
        .task(id: host) {
            modelCatalog = .fallback
            if let catalog = try? await client.models(), !Task.isCancelled { modelCatalog = catalog }
        }
        .onChange(of: showingSettings) { _, showing in if showing { composerFocused = false } }
        .onChange(of: host) { _, _ in model.start(host: host, sessionID: sessionID, onRead: onRead) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
            else if phase == .active { model.start(host: host, sessionID: sessionID, onRead: onRead) }
        }
        .onChange(of: messages) { _, _ in reconcilePendingSend() }
    }
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
                            }.fontWeight(record?.state == "working" ? .semibold : .regular)
                                .foregroundStyle(record?.state == "working" ? ChatColors.green : ChatColors.secondary)
                            if let purpose = record?.instructions.split(separator: "\n").first, !purpose.isEmpty {
                                Text("· \(purpose)").foregroundStyle(ChatColors.secondary).lineLimit(1)
                            }
                        }.font(.system(size: 11)).help("Host: \(host.name)")
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
    private var tabletThreadHeader: some View {
        HStack(spacing: 11) {
            threadHeading
            Spacer(minLength: 8)
            Button { showingSettings = true } label: {
                Image(uiImage: SessionOptionsGlyph.image).frame(width: 44, height: 44)
            }.buttonStyle(.plain).foregroundStyle(.white).disabled(record == nil)
                .accessibilityLabel("Chat settings").accessibilityIdentifier("chat_settings")
        }.padding(.leading, 14).padding(.trailing, 6).frame(height: 62)
            .background(ChatColors.canvas)
    }
    #endif
    private var threadHeading: some View {
        Button { showingSettings = true } label: {
            HStack(spacing: 11) {
                if isTablet { ChatAvatar(name: record?.name ?? "Chat", size: 36, state: record?.state) }
                VStack(alignment: isTablet ? .leading : .center, spacing: 3) {
                    Text(record?.name ?? "Chat").font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(ChatColors.status(record?.state ?? "idle")).frame(width: 7, height: 7)
                            .background(Circle().fill(record?.state == "working" ? ChatColors.green.opacity(0.25) : .clear).padding(-3))
                        Text(record?.statusLabel ?? "Connecting…")
                            .foregroundStyle(record?.state == "working" ? ChatColors.green : record?.state == "blocked" ? ChatColors.amber : ChatColors.secondary)
                        Text("· \(host.name)").foregroundStyle(ChatColors.secondary)
                    }.font(.system(size: 12)).accessibilityIdentifier("chat_status")
                }
            }
        }.buttonStyle(.plain).foregroundStyle(.white).disabled(record == nil)
            .accessibilityLabel("Chat details").accessibilityIdentifier("chat_details")
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: isDesktop ? 22 : isTablet ? 33 : 18) {
            TextField("Message", text: $draft, prompt: Text("Message \(record?.name ?? "chat")…").foregroundStyle(ChatColors.muted), axis: .vertical).lineLimit(1...6).textFieldStyle(.plain)
                .font(.system(size: isDesktop ? 13 : isTablet ? 16 : 17)).frame(minHeight: isDesktop ? 18 : isTablet ? 20 : 22).disabled(pendingSend != nil)
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
                    }.font(.system(size: isDesktop ? 11 : isTablet ? 12 : 13, weight: .medium)).foregroundStyle(ChatColors.hex(0xD1D1D6))
                        .padding(.horizontal, isDesktop ? 8 : 10).frame(height: isDesktop ? 22 : isTablet ? 26 : 28)
                        .background(ChatColors.field, in: Capsule())
                }
                #if os(macOS)
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                #else
                .menuStyle(.borderlessButton)
                #endif
                .fixedSize()
                    .disabled(record == nil || record?.state == "working")
                    .accessibilityLabel("Chat model").accessibilityIdentifier("chat_model")
                Spacer()
                if record?.state == "working" {
                    Button { Task { await stop() } } label: {
                        RoundedRectangle(cornerRadius: isDesktop ? 2 : 3).fill(ChatColors.canvas).frame(width: isDesktop ? 9 : 11, height: isDesktop ? 9 : 11)
                            .frame(width: isDesktop ? 26 : isTablet ? 32 : 34, height: isDesktop ? 26 : isTablet ? 32 : 34).background(ChatColors.ink, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Stop reply").accessibilityIdentifier("chat_stop")
                } else {
                    Button { Task { await send() } } label: {
                        Image(systemName: pendingSend == nil ? "arrow.up" : "arrow.clockwise")
                            .font(.system(size: isDesktop ? 14 : 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: isDesktop ? 26 : isTablet ? 32 : 34, height: isDesktop ? 26 : isTablet ? 32 : 34).background(ChatColors.blue, in: Circle())
                    }.buttonStyle(.plain)
                        .disabled(sending || record == nil || (pendingSend == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .opacity(record != nil && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingSend != nil) ? 1 : 0.4)
                        .accessibilityLabel(pendingSend == nil ? "Send message" : "Retry send").accessibilityIdentifier("chat_send")
                }
            }
        }
        .padding(.leading, isDesktop ? 12 : 16).padding(.trailing, isDesktop ? 8 : 10).padding(.top, isDesktop ? 9 : 11).padding(.bottom, isDesktop ? 8 : 10).frame(minHeight: isDesktop ? 85 : isTablet ? 106 : 96)
        .background(isDesktop ? ChatColors.hex(0x262629) : ChatColors.raised, in: RoundedRectangle(cornerRadius: isDesktop ? 16 : isTablet ? 22 : 24))
        .overlay(RoundedRectangle(cornerRadius: isDesktop ? 16 : isTablet ? 22 : 24).strokeBorder(isDesktop ? .white.opacity(0.06) : ChatColors.hex(0x38383A), lineWidth: isDesktop ? 1 : 0.5))
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, isDesktop || isTablet ? 8 : composerFocused ? 8 : -6)
        .frame(maxWidth: .infinity).background(paneCanvas.opacity(0.95))
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: isDesktop ? 11 : 14) {
                    if hasMore {
                        Button(loadingOlder ? "Loading…" : "Earlier messages") { Task { await older() } }
                            .disabled(loadingOlder).accessibilityIdentifier("chat_older")
                            .frame(maxWidth: .infinity)
                    }
                    if messages.isEmpty {
                        ContentUnavailableView("What’s on your mind?", systemImage: "bubble.left.and.bubble.right",
                            description: Text("Your instructions and memory stay with this chat."))
                    }
                    ForEach(messages) { message in
                        if message.role == "user" {
                            HStack {
                                Spacer(minLength: 0)
                                Text(message.text).font(.system(size: isDesktop ? 13 : 17)).lineSpacing(isDesktop ? 1 : 2).foregroundStyle(Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255))
                                    .textSelection(.enabled).padding(.horizontal, isDesktop ? 11 : 14).padding(.vertical, isDesktop ? 7 : 10)
                                    .background(ChatColors.userBubble, in: RoundedRectangle(cornerRadius: isDesktop ? 15 : 20))
                                    .frame(maxWidth: isDesktop ? 278 : 290, alignment: .trailing)
                            }.id(message.id)
                        } else {
                            assistantText(message.text).foregroundStyle(ChatColors.ink).lineSpacing(isDesktop ? 2 : 4).frame(maxWidth: .infinity, alignment: .leading).id(message.id)
                        }
                    }
                    if record?.state == "working" && messages.last?.role != "assistant" {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").font(.callout).foregroundStyle(.secondary) }
                            .accessibilityIdentifier("chat_thinking")
                    }
                    Color.clear.frame(height: 1).id("chat_end")
                }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat_transcript")
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 80
            } action: { _, nearBottom in if !loadingOlder { followsReply = nearBottom } }
            .onChange(of: messages.last?.text) { _, _ in if followsReply { proxy.scrollTo("chat_end", anchor: .bottom) } }
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
        reconcilePendingSend()
    }
    private func reconcilePendingSend() {
        if let pendingSend, messages.contains(where: { $0.requestID == pendingSend.id && $0.role == "user" }) {
            self.pendingSend = nil; if draft == pendingSend.text { draft = "" }
        }
    }
    private func older() async {
        guard let first = messages.first else { return }
        loadingOlder = true; followsReply = false; defer { loadingOlder = false }
        do { let page = try await client.detail(sessionID, before: first.sequence); messages = ChatHistoryMerge.merge(messages, page.messages); hasMore = page.hasMore }
        catch { self.error = error.localizedDescription }
    }
    private func send() async {
        guard !sending else { return }
        let message = pendingSend ?? (id: UUID().uuidString, text: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !message.text.isEmpty else { return }
        sending = true; pendingSend = message; error = nil; followsReply = true; defer { sending = false }
        do {
            try await client.send(sessionID, text: message.text, requestID: message.id)
            pendingSend = nil; if draft.trimmingCharacters(in: .whitespacesAndNewlines) == message.text { draft = "" }
        } catch {
            self.error = error.localizedDescription
            if let failure = error as? ChatClientError, let status = failure.status, (400..<500).contains(status) { pendingSend = nil }
        }
        await poll()
    }
    private func stop() async {
        do { try await client.interrupt(sessionID); await poll() }
        catch { self.error = error.localizedDescription }
    }
}

private enum ChatSettingsPage: String, Hashable {
    case name = "Name", instructions = "Instructions", memory = "Memory", model = "Model"
}
private struct ChatSettingsSheet: View {
    let client: ChatSessionsClient
    let record: ChatSessionRecord
    let saved: (ChatSessionRecord) -> Void
    @State private var name: String
    @State private var instructions: String
    @State private var memory: String
    @State private var model: String
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(client: ChatSessionsClient, record: ChatSessionRecord, saved: @escaping (ChatSessionRecord) -> Void) {
        self.client = client; self.record = record; self.saved = saved
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
                                Text(name).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
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
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ChatSectionHeading(title: "Only this chat")
                        VStack(spacing: 0) {
                            settingsRow(.instructions, title: "Instructions", subtitle: instructions.isEmpty ? "How this chat should respond" : instructions, icon: "pencil")
                            Divider().overlay(ChatColors.hex(0x3A3A3C)).padding(.leading, 41)
                            settingsRow(.memory, title: "What it remembers", subtitle: memory.isEmpty ? "Private facts and preferences" : memory, icon: "doc.text")
                            Divider().overlay(ChatColors.hex(0x3A3A3C)).padding(.leading, 41)
                            NavigationLink { ChatJobsView(host: client.host, chatId: record.id) } label: {
                                HStack(spacing: 12) { Image(systemName: "clock").frame(width: 20); VStack(alignment: .leading, spacing: 3) { Text("Tasks").foregroundStyle(.white); Text("Reminders and instructions for this chat").font(.system(size: 12)).foregroundStyle(ChatColors.muted) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(ChatColors.muted) }.padding(14).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_jobs")
                        }.background(ChatColors.field, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Text("Instructions and memory stay with this conversation. Changes apply to your next message.")
                        .font(.system(size: 13)).foregroundStyle(ChatColors.muted).lineSpacing(3).padding(.horizontal, 2)
                    if record.state == "working" {
                        Text("Stop the current reply to change these settings.").font(.system(size: 13)).foregroundStyle(ChatColors.amber)
                    }
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
                    editor(page).onAppear {
                        name = record.name; instructions = record.instructions; memory = record.memory; model = record.model ?? ""
                        error = nil
                    }
                }
        }.tint(ChatColors.hex(0x409CFF)).preferredColorScheme(.dark)
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
                    Text(title).font(.system(size: 16)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(ChatColors.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(ChatColors.hex(0x636366))
            }.padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 72)
        }.buttonStyle(.plain).accessibilityIdentifier("chat_settings_\(page.rawValue.lowercased())_row")
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
                }
                if record.state == "working" { Text("Stop the current reply to change these settings.").font(.callout).foregroundStyle(ChatColors.amber) }
                if let error { Text(error).font(.callout).foregroundStyle(ChatColors.amber).accessibilityIdentifier("chat_settings_error") }
            }.disabled(busy || record.state == "working").padding(16)
        }.scrollDismissesKeyboard(.interactively).background(ChatColors.raised).navigationTitle(page.rawValue)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(busy || record.state == "working" || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("chat_settings_save")
                }
            }
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
            .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(ChatColors.ink)
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
private struct ChatChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content.glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            content.background(ChatColors.field.opacity(0.94), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        }
    }
}
private enum ChatColors {
    static func hex(_ value: UInt) -> Color { Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255) }
    static var canvas: Color {
        #if os(macOS)
        hex(0x1B1B1E)
        #else
        .black
        #endif
    }
    static let raised = hex(0x1C1C1E)
    static let field = hex(0x2C2C2E)
    static var separator: Color {
        #if os(macOS)
        .white.opacity(0.06)
        #else
        hex(0x2C2C2E)
        #endif
    }
    static var secondary: Color {
        #if os(macOS)
        hex(0xA8A8B0)
        #else
        hex(0xA1A1A6)
        #endif
    }
    static var muted: Color {
        #if os(macOS)
        hex(0x8A8A93)
        #else
        hex(0x8E8E93)
        #endif
    }
    static let ink = hex(0xF2F2F7)
    static let selection = hex(0x182B3E)
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
