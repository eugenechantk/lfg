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
    @State private var showingAttachments = false

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
        OptimisticSendReconciliation.containsMatchingUserTurn(
            matchText: p.matchText,
            sentAt: p.ts,
            in: messages)
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
        .sheet(isPresented: $showingAttachments) {
            AttachmentsSheet(messages: messages)
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
            // A message waking a closed session is the resumed process's kickoff
            // argument, not a queue entry — there is nothing to interrupt and
            // nothing to pull back and edit. Offering either would be a no-op
            // dressed as an action. Remove is still honest: it stops showing the
            // row here (the reopened session will surface the real turn anyway),
            // which is the escape hatch if a resume never lands.
            if item.queuedForResume && !item.queuedOffline {
                Button("Remove", role: .destructive) { Task { await store.removeQueued(sid, item) } }
                Button("Cancel", role: .cancel) {}
            } else {
                // An offline-queued message never reached the host, so there is no
                // running turn to interrupt — "send now" just means try the host
                // again instead of waiting for the reconnect drain.
                Button(item.queuedOffline ? "Try sending now" : "Send now (interrupt)") {
                    Task { await store.sendQueuedNow(sid, item) }
                }
                .accessibilityIdentifier("queuedMessageSendNowButton")
                Button("Edit") {
                    Task {
                        if let editable = await store.editQueued(sid, item) { draft = editable }
                    }
                }
                .accessibilityIdentifier("queuedMessageEditButton")
                Button("Remove", role: .destructive) { Task { await store.removeQueued(sid, item) } }
                    .accessibilityIdentifier("queuedMessageRemoveButton")
                Button("Cancel", role: .cancel) {}
            }
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

                    // What the model said just before asking. While the question
                    // is live this is NOT in the transcript — Claude Code holds
                    // that turn back until it's answered — so it arrives scraped
                    // from the pane on `prompt.context`. It is still the model
                    // answering, so it renders as an ordinary assistant bubble
                    // here rather than as a caption inside the panel below: same
                    // markdown and typography as every other turn, and the thread
                    // reads continuously into the question. Drops out of the same
                    // render pass in which the real turn lands (see
                    // `PromptPreamble.shouldSynthesize`), so there is no doubled
                    // beat when the question is answered.
                    if let preamble = PromptPreamble.message(
                        for: prompt, sessionID: sid, transcriptTail: messages
                    ) {
                        TranscriptMessageView(message: preamble).id(preamble.stableID)
                    }

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
            // Tapping the transcript puts the keyboard away — the composer's
            // focus is its own private @FocusState, so this goes through the
            // responder chain (see `dismissKeyboard`). Simultaneous, so a tap
            // that lands on a link, attachment card or button still activates
            // it; the keyboard just goes down at the same time.
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            // Dragging the transcript dismisses it too, tracking the finger.
            .scrollDismissesKeyboard(.interactively)
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
            // Transcript deltas can arrive several times per second. A native
            // Menu rebuilds its presented UIMenu for those updates and loses its
            // scroll offset, so the root options surface is a scroll-owning
            // popover instead. Short model/owner/host choices remain submenus.
            SessionOptionsMenu(
                sid: sid,
                agent: session.agent,
                closed: session.closed,
                tmuxIdentifier: session.tmuxName ?? session.tmuxTarget,
                isBusy: isBusy,
                dismissedBrowserFrameID: dismissedBrowserFrameID,
                onShowAttachments: { showingAttachments = true },
                onRename: { newTitle = session.title; renaming = true },
                onRestoreBrowserPreview: { dismissedBrowserFrameID = nil },
                onConfirmEnd: { confirmEnd = true },
                onMarkedUnread: onMarkedUnread
            )
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

    /// The working path shown under the title when the session is idle (no
    /// "Running" status text). Prefers the real working dir, falling back to the
    /// friendly project name; nil when neither is known.
    private var headerPath: String? {
        if let cwd = session.cwd, !cwd.isEmpty { return cwd }
        if let project = session.project, !project.isEmpty { return project }
        return nil
    }

}

/// A transient, toolbar-anchored options surface with its own scroll state.
/// SwiftUI can update the rows in place without recreating the presentation, so
/// live transcript rendering cannot send the user back to the first option.
private struct SessionOptionsMenu: View {
    let sid: String
    let agent: String
    let closed: Bool
    let tmuxIdentifier: String?
    let isBusy: Bool
    let dismissedBrowserFrameID: String?
    let onShowAttachments: () -> Void
    let onRename: () -> Void
    let onRestoreBrowserPreview: () -> Void
    let onConfirmEnd: () -> Void
    let onMarkedUnread: () -> Void

    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var forking = false
    @State private var transferring = false
    @State private var showingOptions = false

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("sessionOptionsMenu")
        .popover(isPresented: $showingOptions, arrowEdge: .top) {
            optionsList
                .frame(width: 320, height: 520)
                // Keep the transient, toolbar-anchored idiom on iPhone too. The
                // custom scroll view owns its offset while live data changes.
                .presentationCompactAdaptation(.popover)
        }
    }

    private var optionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isBusy {
                    Button(role: .destructive) {
                        showingOptions = false
                        Task { await store.interrupt(sid) }
                    } label: {
                        optionLabel("Stop", systemImage: "stop.circle", tint: .red)
                    }
                    rowDivider
                }

                // Every file and link this session produced, without scrolling
                // back through the transcript to find them.
                Button { dismissThen(onShowAttachments) } label: {
                    optionLabel("Files & Links", systemImage: "paperclip")
                }
                .accessibilityIdentifier("filesAndLinksButton")
                rowDivider

                Menu {
                    ForEach(modelOptions, id: \.self) { model in
                        Button(model) {
                            showingOptions = false
                            Task { await store.setModel(sid, model) }
                        }
                    }
                } label: {
                    optionLabel("Switch model", systemImage: "cpu", showsSubmenu: true)
                }
                rowDivider

                Menu {
                    Button("Unassigned") {
                        showingOptions = false
                        Task { await store.assign(sid, nil) }
                    }
                    ForEach(store.users, id: \.self) { user in
                        Button(user) {
                            showingOptions = false
                            Task { await store.assign(sid, user) }
                        }
                    }
                } label: {
                    optionLabel("Assign to", systemImage: "person", showsSubmenu: true)
                }
                rowDivider

                Button { dismissThen(onRename) } label: {
                    optionLabel("Rename", systemImage: "pencil")
                }
                rowDivider

                if let frame = store.browserFrames[sid],
                   frame.frameId == dismissedBrowserFrameID {
                    Button {
                        showingOptions = false
                        onRestoreBrowserPreview()
                    } label: {
                        optionLabel("Show Browser Preview", systemImage: "safari")
                    }
                    .accessibilityIdentifier("showBrowserPreviewButton")
                    rowDivider
                }

                // Fork branches this conversation into a new session: the source
                // is untouched and the fork carries the full history.
                if canFork {
                    Button {
                        showingOptions = false
                        Task { await forkSession() }
                    } label: {
                        optionLabel(forking ? "Forking…" : "Fork session",
                                    systemImage: "arrow.triangle.branch")
                    }
                    .disabled(forking)
                    rowDivider
                }

                // Transfer is offered only for a live session with another host.
                if canTransfer {
                    Menu {
                        ForEach(transferTargets) { target in
                            Button {
                                showingOptions = false
                                Task { await transfer(to: target) }
                            } label: {
                                Label(target.label, systemImage: "desktopcomputer")
                            }
                        }
                    } label: {
                        optionLabel(transferring ? "Moving…" : "Move to host",
                                    systemImage: "arrow.left.arrow.right",
                                    showsSubmenu: true)
                    }
                    .disabled(transferring)
                    rowDivider
                }

                if ManualUnread.canMarkUnread(sid) {
                    if store.isManuallyUnread(sid) {
                        Button {
                            showingOptions = false
                            store.markRead(sid)
                        } label: {
                            optionLabel("Mark as read", systemImage: "envelope.open")
                        }
                        .accessibilityIdentifier("markReadButton")
                    } else {
                        Button {
                            showingOptions = false
                            markUnreadAndExit()
                        } label: {
                            optionLabel("Mark as unread", systemImage: "envelope.badge")
                        }
                        .accessibilityIdentifier("markUnreadButton")
                    }
                    rowDivider
                }

                // Debug: surface the underlying ids; tapping copies to clipboard.
                Text("Debug — tap to copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 5)

                if let tmuxIdentifier, !tmuxIdentifier.isEmpty {
                    Button {
                        showingOptions = false
                        copyToClipboard(tmuxIdentifier)
                    } label: {
                        optionLabel("tmux · \(tmuxIdentifier)", systemImage: "terminal")
                    }
                    rowDivider
                }

                if !sid.isEmpty {
                    Button {
                        showingOptions = false
                        copyToClipboard(sid)
                    } label: {
                        optionLabel("\(agentIdLabel) · \(sid)", systemImage: "number")
                    }
                }

                Divider().padding(.vertical, 7)
                Button(role: .destructive) {
                    dismissThen(onConfirmEnd)
                } label: {
                    optionLabel("End session", systemImage: "xmark.circle", tint: .red)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.visible)
    }

    private func optionLabel(
        _ title: String,
        systemImage: String,
        tint: Color = .primary,
        showsSubmenu: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 20)
            Text(title)
                .multilineTextAlignment(.leading)
            Spacer()
            if showsSubmenu {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 48)
    }

    private var modelOptions: [String] {
        AgentKind(rawValue: agent)?.models ?? AgentKind.aisdk.models
    }

    /// Fork is available for transcript families whose server lane can branch
    /// natively. codex-aisdk and opencode remain hidden until supported.
    private var canFork: Bool {
        !sid.isEmpty
            && (agent == "claude"
                || agent == "aisdk"
                || agent == "codex")
    }

    private var transferTargets: [Host] {
        let current = store.host(forSession: sid)?.id
        return settings.hosts.filter { $0.id != current }
    }

    private var canTransfer: Bool {
        !sid.isEmpty && !closed
            && store.host(forSession: sid) != nil
            && !transferTargets.isEmpty
    }

    private var agentIdLabel: String {
        switch agent {
        case "claude", "aisdk": return "Claude id"
        case "codex", "codex-aisdk": return "Codex id"
        default: return "Session id"
        }
    }

    private func forkSession() async {
        guard !forking else { return }
        forking = true
        defer { forking = false }
        let newID = await store.fork(ForkRequest(sessionId: sid))
        if let newID { store.requestSelection(newID) }
    }

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

    private func copyToClipboard(_ value: String) {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Secondary sheets and dialogs need the popover to finish dismissing before
    /// they present from SessionDetailView. Deferring by one short animation
    /// interval avoids overlapping presentation-controller transitions.
    private func dismissThen(_ action: @escaping @MainActor () -> Void) {
        showingOptions = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !showingOptions else { return }
            action()
        }
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
