import SwiftUI
import LFGCore
import UIKit

struct SessionDetailView: View {
    let session: Session
    /// Called after the session is closed, so the owner (RootView) can clear the
    /// navigation selection and pop back to the list. Without this the split view
    /// keeps `selection` pointed at the now-deleted session and the detail column
    /// gets stuck on `DetailLoading` ("Opening session…").
    var onEnded: () -> Void = {}
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var draft = ""
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmEnd = false
    @State private var forking = false
    @State private var transferring = false
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

    /// Owning host's short label, shown as a pill in the title area in multi-host
    /// setups (a single-host client has nothing to disambiguate).
    private var hostLabel: String? {
        guard settings.hosts.count > 1 else { return nil }
        return store.host(forSession: session.id)?.label
    }

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
                    // This session is LIVE on a host that is currently unreachable.
                    // Its agent only exists on that machine, so a send here could
                    // never land — swap the composer for an explanation rather than
                    // accepting a message that would silently fail. The transcript
                    // above stays readable.
                    if store.isOffline(sid) {
                        OfflineComposerNotice(hostLabel: store.host(forSession: sid)?.label ?? "This host")
                    } else {
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
        .onDisappear {
            store.blur(sid)
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
            Button("End session", role: .destructive) { Task { await store.close(sid); onEnded() } }
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
                HStack(spacing: 5) {
                    if let host = hostLabel {
                        Text(host)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if isBusy {
                        ProgressView().controlSize(.mini)
                        Text("Running")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let path = headerPath {
                        // No status text while idle — surface the working path there
                        // instead so it's clear which directory this session drives.
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)   // keep the meaningful tail visible
                    }
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

                // Fork branches this conversation into a new session (claude
                // --resume --fork-session): the source is untouched, the fork
                // carries the full history and lands at an empty composer. Only
                // Claude-family transcripts (claude/aisdk) can be forked; the
                // codex family isn't --resume-compatible, so hide it there.
                if canFork {
                    Button { Task { await forkSession() } } label: {
                        Label(forking ? "Forking…" : "Fork session",
                              systemImage: "arrow.triangle.branch")
                    }
                    .disabled(forking)
                }

                // Transfer: move a LIVE session to another host. Closes the pane
                // on the current machine and resumes the (synced) transcript on the
                // target — see `store.transfer`. Only for live sessions, and only
                // when there's another host to move to.
                if canTransfer {
                    Menu {
                        ForEach(transferTargets) { target in
                            Button { Task { await transfer(to: target) } } label: {
                                Label(target.label, systemImage: "desktopcomputer")
                            }
                        }
                    } label: {
                        Label(transferring ? "Moving…" : "Move to host",
                              systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(transferring)
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

    /// Only Claude-family sessions (claude CLI + aisdk) keep a claude-shaped
    /// transcript under ~/.claude/projects that `claude --resume --fork-session`
    /// understands. The codex family isn't resume-compatible, so hide Fork there.
    private var canFork: Bool {
        !sid.isEmpty && (session.agent == "claude" || session.agent == "aisdk" || session.agent == nil)
    }

    /// Branch this session and navigate into the fork. The store returns the new
    /// session's id, which we hand to `requestSelection` so the split view opens
    /// the fork directly; history loads from a fork-point snapshot until the
    /// fork's own transcript file appears after its first turn.
    private func forkSession() async {
        guard !forking else { return }
        forking = true
        defer { forking = false }
        let newId = await store.fork(ForkRequest(sessionId: sid))
        if let newId { store.requestSelection(newId) }
    }

    /// Other configured hosts this live session can be moved to.
    private var transferTargets: [Host] {
        let current = store.host(forSession: sid)?.id
        return settings.hosts.filter { $0.id != current }
    }

    /// Transfer is offered for a live (non-closed) session when its owning host is
    /// known and at least one other host exists.
    private var canTransfer: Bool {
        !sid.isEmpty && !session.closed
            && store.host(forSession: sid) != nil
            && !transferTargets.isEmpty
    }

    /// Move this session to another host (close on source → resume on target).
    /// `store.transfer` re-points navigation at the new live id itself.
    private func transfer(to target: Host) async {
        guard !transferring else { return }
        transferring = true
        defer { transferring = false }
        _ = await store.transfer(sid, to: target)
    }

    /// The working path shown under the title when the session is idle (no
    /// "Running" status text). Prefers the real working dir, falling back to the
    /// friendly project name; nil when neither is known.
    private var headerPath: String? {
        if let cwd = session.cwd, !cwd.isEmpty { return cwd }
        if let project = session.project, !project.isEmpty { return project }
        return nil
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

/// Replaces the composer when the open session is live on an unreachable host.
/// The agent's pane exists only on that machine, so there is no host that could
/// accept a message for it — say so instead of taking input that would fail. The
/// session reappears with a working composer as soon as the host answers a poll.
struct OfflineComposerNotice: View {
    let hostLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(hostLabel) is unreachable")
                    .font(.subheadline.weight(.semibold))
                Text("This session is running on \(hostLabel), so it can't take messages until that host is back. Its transcript above is up to date as of the last poll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
