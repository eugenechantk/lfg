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
    var onMarkedUnread: () -> Void = {}
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var draft = ""
    @State private var renaming = false
    /// Tapping the (truncated) nav-bar title reveals the full one in a card below it.
    @State private var showFullTitle = false
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
    @State private var dismissedBrowserFrameID: String?

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
        pending.filter { $0.showSent && !hasLanded($0) }
    }

    /// Sends still waiting on the host: the one-line bars above the composer.
    /// Filtered against the transcript for the same reason the bubbles are — the
    /// bar must clear in the SAME render pass the real user turn appears, so the
    /// message visibly *moves* into the conversation instead of briefly existing
    /// twice.
    private var pendingBars: [SessionStore.PendingSend] {
        pending.filter { !$0.showSent && !hasLanded($0) }
    }

    private func hasLanded(_ p: SessionStore.PendingSend) -> Bool {
        OptimisticSendReconciliation.containsMatchingUserTurn(matchText: p.matchText, in: messages)
    }

    var body: some View {
        transcript
            // Full title, revealed by tapping the (truncated) nav-bar title. An overlay
            // card rather than an expanded bar, because these titles are whole
            // sentences and can need several lines (see `fullTitle` for where the
            // untruncated text comes from).
            .overlay(alignment: .top) {
                if showFullTitle { fullTitleCard }
            }
            .overlay {
                if let frame = store.browserFrames[sid],
                   frame.frameId != dismissedBrowserFrameID,
                   let url = store.browserFrameURL(for: sid) {
                    BrowserPreviewOverlay(frame: frame, url: url) {
                        dismissedBrowserFrameID = frame.frameId
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: store.browserFrames[sid]?.frameId)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    // A send the backend hasn't taken yet (queued behind a running
                    // turn, offline, or failed) waits here as a one-line bar — not
                    // as a transcript bubble. It becomes a blue bubble only when
                    // the real user turn comes back from the host, so "queued" and
                    // "received" never look the same.
                    PendingStripView(sessionID: sid, items: pendingBars) { tapped in
                        queueAction = tapped
                    }
                    .padding(.horizontal, 16)
                    // This session is LIVE on a host that is currently unreachable.
                    // Keep the draft editable; the store queues sends durably until
                    // the owning host comes back.
                    if store.isOffline(sid) {
                        OfflineComposerNotice(hostLabel: store.host(forSession: sid)?.label ?? "This host")
                    }
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
            await store.loadBrowserFrame(sid)
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
            // Gated on the result: `close` returns false and sets `lastError` when
            // the server could not reap the agent. Dismissing regardless made a
            // failed close indistinguishable from a successful one — the view
            // closed, the row stayed, and the session was still running.
            Button("End session", role: .destructive) {
                Task { if await store.close(sid) { onEnded() } }
            }
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
                        ForEach(Array(messages.enumerated()), id: \.element.stableID) { idx, msg in
                            TranscriptMessageView(
                                message: msg,
                                // Back-to-back user turns collapse their leading gap.
                                followsUserBubble: idx > 0 && messages[idx - 1].rendersAsUserBubble
                            )
                            .id(msg.stableID)
                        }
                    }

                    // Sends the agent takes immediately (kickoff, or a follow-up
                    // to an idle session) show as a finished user bubble right
                    // away — everything still waiting sits in the pending bar
                    // above the composer instead. Filtered against the live
                    // transcript so the placeholder disappears in the SAME render
                    // pass that the real user turn appears — otherwise the two
                    // overlap for a beat (the "momentary duplicate") until the
                    // store's reconcile mutates pendingSends a tick later.
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
                // Titles are whole sentences (the session's first prompt), so the
                // one-line nav-bar title almost always truncates. Tapping it opens
                // a popover with the full text rather than expanding the bar, which
                // would reflow the status/path line under it on every session.
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { showFullTitle.toggle() }
                    }
                    .accessibilityIdentifier("sessionTitle")
                    .accessibilityHint("Shows the full session title")
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

                if let frame = store.browserFrames[sid],
                   frame.frameId == dismissedBrowserFrameID {
                    Button {
                        dismissedBrowserFrameID = nil
                    } label: {
                        Label("Show Browser Preview", systemImage: "safari")
                    }
                    .accessibilityIdentifier("showBrowserPreviewButton")
                }

                // Fork branches this conversation into a new session: the source
                // is untouched, the fork carries the full history and lands at an
                // empty composer. Claude-family sessions use claude resume/fork;
                // codex CLI sessions use codex's native fork lane.
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

                if ManualUnread.canMarkUnread(sid) {
                    if store.isManuallyUnread(sid) {
                        Button { store.markRead(sid) } label: {
                            Label("Mark as read", systemImage: "envelope.open")
                        }
                        .accessibilityIdentifier("markReadButton")
                    } else {
                        Button { markUnreadAndExit() } label: {
                            Label("Mark as unread", systemImage: "envelope.badge")
                        }
                        .accessibilityIdentifier("markUnreadButton")
                    }
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

    /// Nav-bar title text, shared by the truncated bar label and the full-title card.
    private var displayTitle: String {
        session.title.isEmpty ? "Session" : session.title
    }

    /// The session's full title. `Session.title` from the API is the first user prompt
    /// already truncated to 72 chars with a trailing "…" (`TITLE_MAX` in
    /// `src/sessions.ts`), so the untruncated text can only come from the transcript —
    /// the same first user turn the server derives the title from. Falls back to the
    /// truncated title until the transcript has loaded.
    private var fullTitle: String {
        let firstPrompt = messages.first { m in
            guard m.role == "user" else { return false }
            let t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !t.hasPrefix("<")   // skip harness/meta turns, as the server does
        }
        guard let text = firstPrompt?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return displayTitle }
        return text
    }

    /// The untruncated title, shown under the nav bar until tapped away (tapping the
    /// bar title again also closes it). Selectable so a long title can be copied.
    ///
    /// Sized by its text — deliberately no `frame(maxHeight:)` or ScrollView here:
    /// a flexible frame claims the whole proposed height, which left a short title
    /// floating in the middle of a 240pt card. `lineLimit` is the cap instead, so a
    /// runaway first prompt can't swallow the transcript.
    private var fullTitleCard: some View {
        fullTitleText
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) { showFullTitle = false }
        }
        .accessibilityIdentifier("fullTitleCard")
    }

    private var fullTitleText: some View {
        Text(fullTitle)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.leading)
            .lineLimit(12)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelOptions: [String] {
        AgentKind(rawValue: session.agent)?.models ?? AgentKind.aisdk.models
    }

    /// Fork is available for transcript families whose server lane can branch
    /// natively: Claude-family sessions use `claude --resume --fork-session`,
    /// while codex CLI sessions use `codex fork`. `codex-aisdk` and opencode stay
    /// hidden until the server grows explicit fork support for those agents.
    private var canFork: Bool {
        !sid.isEmpty
            && (session.agent == "claude"
                || session.agent == "aisdk"
                || session.agent == "codex"
                || session.agent == nil)
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

    private func markUnreadAndExit() {
        store.markUnread(sid)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onMarkedUnread()
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

/// Compact banner shown above the composer when the open session is live on an
/// unreachable host.
struct OfflineComposerNotice: View {
    let hostLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text("\(hostLabel) is unreachable — messages will send when it's back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }
}
