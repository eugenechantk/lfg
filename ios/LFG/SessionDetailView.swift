import SwiftUI
import LFGCore
import UIKit

struct SessionDetailView: View {
    let session: Session
    @Environment(SessionStore.self) private var store

    @State private var draft = ""
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmEnd = false
    /// The queued message the user tapped (drives the remove / edit / send-now sheet).
    @State private var queueAction: SessionStore.PendingSend?
    @State private var isAtBottom = true
    @State private var bottomDebounce: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?
    // True while the open-at-bottom pin loop is force-scrolling. Guards the
    // BOTTOM-anchor debounce from mistaking a still-loading transcript for a
    // deliberate scroll-up and freezing auto-follow before the view settles.
    @State private var pinningToBottom = false

    private var sid: String { session.sessionId ?? "" }
    private var messages: [SessionMessage] { store.transcripts[sid] ?? [] }
    private var prompt: AgentPrompt? { store.prompts[sid] }
    private var pending: [SessionStore.PendingSend] { store.pendingSends[sid] ?? [] }
    private var isBusy: Bool { store.busy[sid] == true }

    /// Optimistic "sent" bubbles whose real user turn hasn't landed in the
    /// transcript yet. Computed from `messages`, so the instant the real turn
    /// appears the matching placeholder drops out of the same render pass — no
    /// visible duplicate. Mirrors the store's reconcile matching.
    private var unmatchedSentBubbles: [SessionStore.PendingSend] {
        let userTurns = messages
            .filter { $0.role == "user" && $0.kind == "text" }
            .map { Self.normForMatch($0.text) }
        return pending.filter { p in
            guard p.showSent else { return false }
            let needle = Self.normForMatch(p.matchText)
            guard needle.count >= 3 else { return true }
            let key = String(needle.prefix(80))
            return !userTurns.contains { $0.contains(key) }
        }
    }

    private static func normForMatch(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    var body: some View {
        transcript
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    PendingStripView(sessionID: sid, items: pending.filter { !$0.showSent }) { tapped in
                        queueAction = tapped
                    }
                    .padding(.horizontal, 16)
                    MessageComposer(text: $draft, sending: false) { text, atts in
                        // Hand the send to the store, which owns it for the app's
                        // lifetime (under a background-task assertion). Leaving
                        // this view or backgrounding the app no longer drops the
                        // message — the optimistic bubble + pending strip already
                        // give immediate feedback, so no view-owned spinner.
                        store.dispatchSend(sid, text: text, attachments: atts)
                        // Sending is an explicit "follow me to the latest" intent:
                        // re-arm auto-follow even if the user had scrolled up. The
                        // onChange(of: pending.count) below does the actual scroll
                        // once the optimistic bubble has laid out.
                        isAtBottom = true
                        scrollProxy?.scrollTo("BOTTOM", anchor: .bottom)
                    }
                }
            }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Resolve relative file refs in this session's transcript (e.g.
        // `improvement-log/foo.md`) against its working directory.
        .transformEnvironment(\.hostFiles) { hf in
            if let cwd = session.cwd, !cwd.isEmpty { hf?.cwd = cwd }
        }
        .toolbar { toolbarMenu }
        .task(id: sid) {
            isAtBottom = true
            store.focus(sid)
            store.loadHistory(sid)   // store-owned: not cancelled by view churn
            // Open at the latest message. The transcript loads asynchronously and
            // incrementally (stream backfill, then the full history), and a big
            // batch shoves the bottom anchor far off-screen — so a single scroll,
            // or one gated on `isAtBottom`, lands mid-transcript. Force-pin to the
            // bottom across the load window instead; afterwards the isAtBottom-gated
            // follow below takes over (and respects a manual scroll-up).
            pinningToBottom = true
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(110))
                scrollProxy?.scrollTo("BOTTOM", anchor: .bottom)
            }
            pinningToBottom = false
            isAtBottom = true
        }
        .alert("Rename session", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await store.rename(sid, newTitle) } }
        }
        .confirmationDialog(
            "Queued message",
            isPresented: Binding(get: { queueAction != nil }, set: { if !$0 { queueAction = nil } }),
            titleVisibility: .visible,
            presenting: queueAction
        ) { item in
            Button("Send now (interrupt)") { Task { await store.sendQueuedNow(sid, item) } }
            Button("Edit") { Task { draft = await store.editQueued(sid, item) } }
            Button("Remove", role: .destructive) { Task { await store.removeQueued(sid, item) } }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.displayText)
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End session", role: .destructive) { Task { await store.close(sid) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The agent's tmux session will be closed.")
        }
    }

    // MARK: Transcript

    private var transcript: some View {
      GeometryReader { geo in
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: 1).id("TOP")   // jump-to-top anchor
                    if session.isBlocked { PausedBannerView(session: session) }

                    if messages.isEmpty && !isBusy {
                        Text("Connecting to live transcript…")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(messages) { TranscriptMessageView(message: $0).id($0.stableID) }
                    }

                    // Kickoff sends show as a finished user bubble right away
                    // (no pending bar), until the real user turn reconciles them.
                    // Filtered against the live transcript so the placeholder
                    // disappears in the SAME render pass that the real user turn
                    // appears — otherwise the two overlap for a beat (the
                    // "momentary duplicate") until the store's reconcile mutates
                    // pendingSends a tick later.
                    ForEach(unmatchedSentBubbles) { OptimisticUserBubble(sessionID: sid, pending: $0) }

                    // "Running" now lives in the nav-bar header (below the title),
                    // not inline in the transcript.
                    if let prompt { PromptPanelView(sessionID: sid, prompt: prompt) }
                    // Bottom anchor: track its visibility so we only auto-scroll
                    // when the user is already at the bottom — otherwise a running
                    // session would yank them back down whenever a new turn streams
                    // in, making it impossible to scroll up through history.
                    Color.clear.frame(height: 1).id("BOTTOM")
                        .onAppear {
                            bottomDebounce?.cancel()
                            isAtBottom = true
                        }
                        .onDisappear {
                            // The anchor leaves the viewport for two very different
                            // reasons: the user scrolled up, OR new content was just
                            // appended (a transient — the onChange handler below is
                            // about to scroll us back to the bottom). Debounce so an
                            // append transient isn't mistaken for a deliberate
                            // scroll-up: that mistake freezes auto-follow, so live
                            // messages (especially a bulk reconnect backfill) appear
                            // to "stop coming in" until the user leaves and reopens
                            // the session. A real scroll-up has no follow-up scroll,
                            // so the anchor stays gone and isAtBottom flips after the
                            // delay; a transient is cancelled by the anchor returning.
                            bottomDebounce?.cancel()
                            bottomDebounce = Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                if !Task.isCancelled && !pinningToBottom { isAtBottom = false }
                            }
                        }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in if isAtBottom { withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) } } }
            .onChange(of: prompt) { _, _ in if isAtBottom { withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) } } }
            // Optimistic sent bubbles and the pending strip live outside `messages`,
            // so a fresh send changes neither `messages.count` nor `prompt`. Track
            // the pending count too, or submitting a message wouldn't scroll down.
            .onChange(of: pending.count) { _, _ in if isAtBottom { withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) } } }
            .onAppear {
                scrollProxy = proxy                      // shared with .task's open-at-bottom pin
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
            // Double-tap the top of the transcript to jump to the beginning, the
            // bottom to jump to the latest. Simultaneous so normal scrolling and
            // single-taps on content still work; the neutral middle band avoids
            // hijacking double-taps while reading.
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { event in
                    let h = geo.size.height
                    if event.location.y < h * 0.30 { jumpToTop() }
                    else if event.location.y > h * 0.70 { jumpToBottom() }
                }
            )
        }
      }
    }

    private func jumpToTop() {
        guard let scrollProxy else { return }
        isAtBottom = false
        withAnimation { scrollProxy.scrollTo("TOP", anchor: .top) }
    }

    private func jumpToBottom() {
        guard let scrollProxy else { return }
        isAtBottom = true
        withAnimation { scrollProxy.scrollTo("BOTTOM", anchor: .bottom) }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(session.title.isEmpty ? "Session" : session.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isBusy {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Running")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isBusy)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if isBusy {
                    Button(role: .destructive) { Task { await store.interrupt(sid) } } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                }
                Menu {
                    ForEach(modelOptions, id: \.self) { m in
                        Button(m) { Task { await store.setModel(sid, m) } }
                    }
                } label: { Label("Switch model", systemImage: "cpu") }

                Menu {
                    Button("Unassigned") { Task { await store.assign(sid, nil) } }
                    ForEach(store.users, id: \.self) { u in
                        Button(u) { Task { await store.assign(sid, u) } }
                    }
                } label: { Label("Assign to", systemImage: "person") }

                Button { newTitle = session.title; renaming = true } label: {
                    Label("Rename", systemImage: "pencil")
                }

                // Debug: surface the underlying ids; tapping copies to clipboard.
                Section("Debug — tap to copy") {
                    if let tmux = session.tmuxName ?? session.tmuxTarget, !tmux.isEmpty {
                        Button { copyToClipboard(tmux) } label: {
                            Label("tmux · \(tmux)", systemImage: "terminal")
                        }
                    }
                    if !sid.isEmpty {
                        Button { copyToClipboard(sid) } label: {
                            Label("\(agentIdLabel) · \(sid)", systemImage: "number")
                        }
                    }
                }

                Divider()
                Button(role: .destructive) { confirmEnd = true } label: {
                    Label("End session", systemImage: "xmark.circle")
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private var modelOptions: [String] {
        AgentKind(rawValue: session.agent)?.models ?? AgentKind.aisdk.models
    }

    /// Human label for the agent's own session id (used in the Debug menu).
    private var agentIdLabel: String {
        switch session.agent {
        case "claude", "aisdk": return "Claude id"
        case "codex", "codex-aisdk": return "Codex id"
        default: return "Session id"
        }
    }

    private func copyToClipboard(_ value: String) {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

