import SwiftUI
import LFGCore
import UIKit

struct SessionDetailView: View {
    private enum PresentedSheet: Identifiable {
        case attachments
        case phoneSignIn(requestID: String?)
        case requestedSignIn(PhoneSignInAgentRequest)
        case childSessions(selectedID: String?)
        case inversionSpike

        var id: String {
            switch self {
            case .phoneSignIn(let requestID): "phone-sign-in-\(requestID ?? "all")"
            case .requestedSignIn(let request): "sign-in-\(request.id)"
            case .attachments: "attachments"
            case .childSessions(let selectedID): "child-sessions-\(selectedID ?? "all")"
            case .inversionSpike: "inversion-spike"
            }
        }
    }

    let session: Session
    /// Called after the session is closed, so the owner (RootView) can clear the
    /// navigation selection and pop back to the list. Without this the split view
    /// keeps `selection` pointed at the now-deleted session and the detail column
    /// gets stuck on `DetailLoading` ("Opening session…").
    var onEnded: () -> Void = {}
    var onMarkedUnread: () -> Void = {}
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @Environment(\.scenePhase) private var scenePhase
    @State private var signInRequests: [PhoneSignInAgentRequest] = []
    @State private var draft = ""
    @State private var renaming = false
    /// Tapping the (truncated) nav-bar title reveals the full one in a card below it.
    @State private var showFullTitle = false
    @State private var newTitle = ""
    @State private var confirmEnd = false
    /// The queued message the user tapped (drives the remove / edit / send-now sheet).
    @State private var queueAction: SessionStore.PendingSend?
    @State private var isAtBottom = true
    @State private var scrollProxy: ScrollViewProxy?
    // True while the open-at-bottom lifecycle follows history loading. Guards the
    // BOTTOM-anchor debounce from mistaking a still-loading transcript for a
    // deliberate scroll-up and freezing auto-follow before the view settles.
    @State private var dismissedBrowserFrameID: String?
    @State private var presentedSheet: PresentedSheet?
    /// The shell on this session's host (`TerminalScreen`), from the ••• menu.
    @State private var showTerminal = false
    /// How many of the newest messages the transcript actually renders. The store
    /// still holds the whole conversation — this bounds only what SwiftUI has to
    /// place. See `TranscriptWindow` for the profile that motivates it.
    @State private var window = TranscriptWindow.pageSize
    /// True from the moment a page is added until the reader's position has been
    /// restored — see `extendWindow` for why this gate is load-bearing.
    @State private var extending = false

    /// PHASE-1 INSTRUMENTATION — remove before shipping. Every code path that
    /// can move the viewport logs through here, tagged LFGVP for `log stream`.
    private func vp(_ trigger: String, _ detail: String = "") {
        #if DEBUG
        NSLog("LFGVP \(trigger) atNewest=\(isAtBottom) ext=\(extending) win=\(window) start=\(windowStart) total=\(messages.count) \(detail)")
        #endif
    }

    private var sid: String { session.sessionId ?? "" }
    private var messages: [SessionMessage] { store.transcripts[sid] ?? [] }
    /// Identity snapshot of the transcript as of the last observed mutation.
    ///
    /// Deliberately NOT a computed property any more. It used to be
    /// `messages.map(\.stableID)` feeding `.onChange`, which rebuilt a
    /// ~1,150-element array on every body evaluation — and with
    /// `.scrollPosition(id:)` writing `@State` once per scroll tick, that meant
    /// once per frame, making scrolling O(transcript) (Phase-1 finding 1). The
    /// store's `transcriptVersion` is the trigger now; this array is rebuilt
    /// only when it actually changed.
    @State private var lastMessageIDs: [String] = []

    /// Armed by sending, disarmed when that send's real user turn appears in the
    /// transcript.
    ///
    /// The optimistic bubble and the server's user turn are two different rows.
    /// `reconcilePending` swaps one for the other whenever the turn lands, which
    /// on a busy session is well after the tap — so a scroll at send time alone
    /// leaves the user looking at a row that is shortly replaced by one they
    /// never get taken to.
    @State private var followSendUntilLanded = false

    /// Identity of the newest real user turn, so a landing can be told from any
    /// other transcript mutation. Compared rather than counted because a user
    /// turn and the reply to it can arrive in the same batch.
    @State private var newestUserTurnID: String?

    /// Index of the oldest rendered message, and the slice from it. `indices` on
    /// the slice are indices into `messages`, so `followsUserBubble` can still
    /// look at the message *above* the window.
    private var windowStart: Int {
        TranscriptWindow.startIndex(total: messages.count, window: window)
    }
    private var windowedMessages: ArraySlice<SessionMessage> { messages[windowStart...] }
    private var hasOlderHistory: Bool {
        TranscriptWindow.hasOlder(total: messages.count, window: window)
    }
    private var historyTopRow: TranscriptHistoryTopRow {
        TranscriptHistoryTopRow.resolve(
            isNetworkLoading: store.isHistoryLoading(sid),
            hasBufferedEarlierMessages: hasOlderHistory
        )
    }
    private var prompt: AgentPrompt? { store.prompts[sid] }
    private var pending: [SessionStore.PendingSend] { store.pendingSends[sid] ?? [] }
    private var isBusy: Bool { store.busy[sid] == true }
    private var childAgents: [ChildAgentSession] { store.childAgentsBySession[sid] ?? [] }

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
            // Failures used to be entirely silent: `store.lastError` was written
            // by every failing send / stop / close / fork / transfer and read by
            // nothing, so "Stop didn't take — the agent isn't responding" looked
            // exactly like a stop that worked. Surfaced here as a transient
            // banner rather than an alert: these are reports, not decisions, and
            // an alert would interrupt a conversation to say something the user
            // can only acknowledge.
            .overlay(alignment: .top) {
                if let event = store.errorEvent {
                    SessionErrorBanner(message: event.message) {
                        store.dismissErrorEvent()
                    }
                    .id(event.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: event.id) {
                        try? await Task.sleep(for: .seconds(6))
                        guard !Task.isCancelled else { return }
                        store.dismissErrorEvent()
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: store.errorEvent?.id)
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
                    // Store-driven, not `!childAgents.isEmpty`: the bar has to
                    // stay dismissed across navigation, and "is this work still
                    // worth interrupting the composer for" is a question about
                    // send history, which the view does not own.
                    if store.showsChildSessionsBar(sid) {
                        ChildSessionsComposerBar(agents: childAgents) {
                            presentedSheet = .childSessions(selectedID: nil)
                        }
                    }
                    ForEach(signInRequests.filter(\.isWaiting)) { request in
                        Button { presentedSheet = .requestedSignIn(request) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "key.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Sign in to \(request.website)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(request.target.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Color(.separator).opacity(0.55), lineWidth: 0.5)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("phone_sign_in_request_button")
                    }
                    MessageComposer(text: $draft, sending: false) { text, atts in
                        // Hand the send to the store, which owns it for the app's
                        // lifetime (under a background-task assertion). Leaving
                        // this view or backgrounding the app no longer drops the
                        // message — the optimistic bubble + pending strip already
                        // give immediate feedback, so no view-owned spinner.
                        store.dispatchSend(sid, text: text, attachments: atts)
                        // Sending is an explicit "follow me to the latest" intent,
                        // even if the user had scrolled up to read history.
                        isAtBottom = true
                        // Two scrolls, because the thing the user wants to look at
                        // does not exist yet. This one lands on the optimistic
                        // bubble; `followSendUntilLanded` does it again when the
                        // real accent bubble replaces it, which on a busy session
                        // is seconds later.
                        //
                        // This used to be `scrollTo("BOTTOM")` — a sentinel the
                        // inversion rewrite deleted — so it had been a silent
                        // no-op: sending scrolled nowhere at all.
                        followSendUntilLanded = true
                        scheduleJumpToNewest()
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
            // Opening is now just state: the inverted list rests at the newest
            // message because that is `contentOffset == 0`. There is nothing to
            // pin, settle or confirm.
            isAtBottom = true
            // A session opens on its newest page; whatever history the previous
            // session had paged in must not carry over.
            window = TranscriptWindow.pageSize
            lastMessageIDs = messages.map(\.stableID)
            // Baseline both, or the first history load after opening reads as a
            // landing and a send from a *previous* session's view stays armed.
            newestUserTurnID = messages.last(where: \.rendersAsUserBubble)?.stableID
            followSendUntilLanded = false
            vp("open")
            store.focus(sid)
            store.loadHistory(sid)   // store-owned: not cancelled by view churn
            await store.loadBrowserFrame(sid)
        }
        .onDisappear {
            store.blur(sid)
        }
        .task(id: "child-agents-\(sid)") {
            while !Task.isCancelled {
                await store.refreshChildAgents(sid)
                try? await Task.sleep(for: .seconds(
                    childAgents.contains(where: { $0.status.isActive }) || isBusy ? 2 : 8
                ))
            }
        }
        .task(id: "phone-sign-in-\(sid)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                if let host = store.host(forSession: sid), let client = settings.client(for: host) {
                    signInRequests = (try? await client.phoneSignInRequests(sessionID: sid)) ?? []
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
        .fullScreenCover(isPresented: $showTerminal) {
            TerminalScreen(initialHostURL: store.host(forSession: sid)?.url)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .requestedSignIn(let request):
                PhoneSignInView(sessionID: sid, agentRequest: request)
                    .presentationDetents([.large])
            case .phoneSignIn(let requestID):
                PhoneSignInRequestsSheet(sessionID: sid, initialRequestID: requestID)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .attachments:
                AttachmentsSheet(messages: messages)
            case .inversionSpike:
                InvertedTranscriptSpike(sessionID: sid)
            case .childSessions(let selectedID):
                ChildAgentSessionsSheet(parentSessionID: sid, initialChildID: selectedID)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
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
            // INVERTED LIST. The stack and every row are flipped 180°, so the
            // array's FIRST element renders at the visual BOTTOM.
            //
            // Both product constraints become structural instead of maintained:
            //   * "open shows the latest" is `contentOffset == 0`, the scroll
            //     view's resting state — no pin, no settle, no arrival check;
            //   * "older pages attach at the top" is an append to the array END,
            //     which grows content at offsets the reader is not looking at,
            //     so it cannot displace them.
            //
            // That is why there is no `.scrollPosition(id:)` binding, no follow
            // loop and no keyboard re-pin below: the machinery existed only to
            // re-assert a position the layout now holds by itself.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // ---- visual BOTTOM (newest) ----
                    Color.clear.frame(height: 1).id(Self.newestAnchor).flippedRow()

                    if let prompt {
                        PromptPanelView(sessionID: sid, prompt: prompt).flippedRow()
                    }
                    // What the model said just before asking. Held out of the
                    // transcript by Claude Code until answered, so it arrives
                    // scraped from the pane and renders as an ordinary assistant
                    // bubble immediately above the panel.
                    if let preamble = PromptPreamble.message(
                        for: prompt, sessionID: sid, transcriptTail: messages
                    ) {
                        TranscriptMessageView(message: preamble)
                            .id(preamble.stableID)
                            .flippedRow()
                    }
                    // Reversed so that, once the stack is flipped back, they read
                    // in send order.
                    ForEach(unmatchedSentBubbles.reversed()) {
                        OptimisticUserBubble(sessionID: sid, pending: $0).flippedRow()
                    }

                    if messages.isEmpty && !isBusy {
                        Text("Connecting to live transcript…")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                            .flippedRow()
                    } else {
                        // Newest first. `idx` still indexes `messages`, so the
                        // back-to-back user-turn rule reads the message ABOVE
                        // this one exactly as before.
                        ForEach(Array(windowedMessages.indices.reversed()), id: \.self) { idx in
                            TranscriptMessageView(
                                message: messages[idx],
                                followsUserBubble: idx > 0 && messages[idx - 1].rendersAsUserBubble
                            )
                            .id(messages[idx].stableID)
                            .flippedRow()
                        }
                        // Visually the TOP of the transcript; structurally the
                        // END of the array. Appending here is what makes a
                        // history reveal free.
                        if historyTopRow != .hidden {
                            olderHistoryLoader.flippedRow()
                        }
                    }

                    if session.isBlocked {
                        PausedBannerView(session: session).flippedRow()
                    }
                    // ---- visual TOP (oldest) ----
                }
                .padding()
            }
            .flippedRow()
            // The flip would draw the indicator down the wrong edge and run it
            // backwards; there is no correct-looking version of it here.
            .scrollIndicators(.hidden)
            // Offset-only "am I at the newest end". Deliberately does not read
            // content height — see `TranscriptWindow.isAtNewestEnd`.
            .modifier(NewestEndTracker { atNewest in
                if isAtBottom != atNewest { vp("tracker.atNewest", "-> \(atNewest)") }
                isAtBottom = atNewest
            })
            .onChange(of: store.transcriptVersion[sid] ?? 0) { _, _ in
                let old = lastMessageIDs
                let new = messages.map(\.stableID)
                guard old != new else { return }
                lastMessageIDs = new
                // Did a real user turn just land? If it was ours, follow it —
                // this is the scroll the user is actually asking for when they
                // send: take me to my message once it is really in the
                // conversation, not to the placeholder standing in for it.
                //
                // Checked before the follow/window logic below, which returns
                // early in the at-the-newest-end case.
                let newestUserTurn = messages.last(where: \.rendersAsUserBubble)?.stableID
                if newestUserTurn != newestUserTurnID {
                    newestUserTurnID = newestUserTurn
                    if followSendUntilLanded {
                        followSendUntilLanded = false
                        vp("sendLanded.jump")
                        scheduleJumpToNewest()
                    }
                }
                // The ONLY thing a transcript mutation still does. Nothing
                // scrolls: a reader at the newest end is already at offset 0 and
                // stays there, and a reader in history is untouched because the
                // new rows land at the far end of the array.
                //
                // The window is still a count of the newest N, so an arriving
                // turn would push the oldest rendered row out of the prefix.
                // Grow by exactly the appended rows to keep it rendered.
                guard !TranscriptWindow.shouldFollowLatest(
                    isAtBottom: isAtBottom, isOpening: false
                ) else { return }
                let grown = TranscriptWindow.reconciled(
                    window: window, previousIDs: old, currentIDs: new)
                if grown != window { vp("idsChanged.grow", "win \(window)->\(grown)") }
                window = grown
            }
            .onAppear { scrollProxy = proxy }
            // Tapping the transcript puts the keyboard away — the composer's
            // focus is its own private @FocusState, so this goes through the
            // responder chain. Simultaneous, so a tap that lands on a link,
            // attachment card or button still activates it.
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            .scrollDismissesKeyboard(.interactively)
            // Double-tap the LOWER band to jump to the latest message.
            //
            // The old top band ran `jumpToTop`, which set `window =
            // messages.count` — rendering the entire transcript — and animated to
            // the oldest row. That is the only code path that ever went to the
            // first few responses, and it is the prime suspect for the reported
            // teleport (Phase-1 finding 5). It is gone: there is no
            // jump-to-oldest, and nothing silently expands the window.
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { event in
                    guard event.location.y > geo.size.height * 0.70 else { return }
                    jumpToNewest()
                }
            )
        }
      }
    }

    /// Sentinel at the array start, i.e. the visual bottom.
    private static let newestAnchor = "NEWEST"

    /// The one remaining programmatic scroll, and only on an explicit user
    /// action (double-tap the lower band, or sending a message).
    private func jumpToNewest() {
        guard let scrollProxy else { return }
        vp("jumpToNewest")
        withAnimation { scrollProxy.scrollTo(Self.newestAnchor, anchor: .top) }
    }

    /// `jumpToNewest`, but off the current view update.
    ///
    /// Scrolling synchronously from inside a view update spins the main thread at
    /// 100%: the animated scroll drives `onScrollGeometryChange`, which writes
    /// `isAtBottom`, which invalidates the body, which rebuilds `NewestEndTracker`
    /// — and because the write happens *within* the same update, the graph never
    /// gets a runloop turn to settle. Verified as a hard hang (main-thread sample
    /// pegged in `NewestEndTracker.body`) when the send handler called
    /// `jumpToNewest` directly.
    ///
    /// The double-tap path never hit this because a gesture callback already runs
    /// between updates. Sending does not: it mutates store state, inserts the
    /// pending strip (changing `safeAreaInset` height) and scrolls, all in one
    /// synchronous hand-off from the composer.
    private func scheduleJumpToNewest() {
        Task { @MainActor in jumpToNewest() }
    }

    /// The row above the oldest rendered message — visually the top of the
    /// transcript, structurally the END of the array. Coming into view IS the
    /// request for more history.
    private var olderHistoryLoader: some View {
        HStack(spacing: 8) {
            if historyTopRow == .loadingNetwork || extending {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(historyTopRow == .loadingNetwork || extending
                 ? "Loading earlier messages…"
                 : "Earlier messages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityIdentifier(
            historyTopRow == .loadingNetwork
                ? "transcriptHistoryLoadingIndicator"
                : "transcriptOlderLoader"
        )
        .onAppear { extendWindow() }
    }

    /// Reveal one more page of older messages.
    ///
    /// Under inversion this is the whole operation: the page appends to the END
    /// of the array, which is the visual TOP, at offsets the reader is not
    /// looking at. There is no anchor to capture, no transaction to coordinate
    /// and no position to restore — Phase-1 finding 4 showed the old anchored
    /// reveal was already compensating correctly, and this removes the need for
    /// it entirely.
    ///
    /// `extending` remains as a one-shot re-entrancy guard: restoring layout is
    /// asynchronous and the loader stays on screen meanwhile, where its
    /// `onAppear` would otherwise fire again and walk the window several pages
    /// in a single flick.
    private func extendWindow() {
        guard hasOlderHistory, !extending else { return }
        extending = true
        let grown = TranscriptWindow.extended(window: window, total: messages.count)
        vp("extendWindow", "win \(window)->\(grown)")
        window = grown
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            extending = false
        }
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
            // Keep the native UIKit menu object stable for the lifetime of this
            // toolbar button. Its deferred contents refresh each time it opens,
            // while transcript deltas cannot rebuild an already-presented menu
            // and reset UIKit's native scroll position.
            SessionOptionsMenu(
                sid: sid,
                agent: session.agent,
                closed: session.closed,
                tmuxIdentifier: session.tmuxName ?? session.tmuxTarget,
                isBusy: isBusy,
                childAgents: childAgents,
                signInRequests: signInRequests,
                dismissedBrowserFrameID: dismissedBrowserFrameID,
                onShowAttachments: { presentedSheet = .attachments },
                onOpenTerminal: { showTerminal = true },
                onShowPhoneSignIn: { requestID in presentedSheet = .phoneSignIn(requestID: requestID) },
                onShowInversionSpike: { presentedSheet = .inversionSpike },
                onShowChildSessions: { selectedID in
                    presentedSheet = .childSessions(selectedID: selectedID)
                },
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

/// Apple's native pull-down menu, backed by a stable UIKit menu object.
///
/// A SwiftUI `Menu` directly inside this transcript-observing toolbar is rebuilt
/// for every streaming delta, which makes UIKit recreate the presented menu at
/// offset zero. `NativeSessionOptionsButton` assigns its root `UIMenu` only once;
/// the deferred child reads the latest actions when a presentation begins.
private struct SessionOptionsMenu: View {
    let sid: String
    let agent: String
    let closed: Bool
    let tmuxIdentifier: String?
    let isBusy: Bool
    let childAgents: [ChildAgentSession]
    let signInRequests: [PhoneSignInAgentRequest]
    let dismissedBrowserFrameID: String?
    let onShowAttachments: () -> Void
    let onOpenTerminal: () -> Void
    let onShowPhoneSignIn: (String?) -> Void
    let onShowInversionSpike: () -> Void
    let onShowChildSessions: (String?) -> Void
    let onRename: () -> Void
    let onRestoreBrowserPreview: () -> Void
    let onConfirmEnd: () -> Void
    let onMarkedUnread: () -> Void

    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var forking = false
    @State private var transferring = false

    var body: some View {
        NativeSessionOptionsButton { menuElements }
            // A UIViewRepresentable otherwise accepts the toolbar's spare width,
            // turning the system glass circle into a capsule for short titles.
            // Match the fixed 44pt footprint of the native back control.
            .frame(width: 44, height: 44)
    }

    private var menuElements: [UIMenuElement] {
        var primary: [UIMenuElement] = []

        if isBusy {
            primary.append(action("Stop", systemImage: "stop.circle", attributes: .destructive) {
                Task { await store.interrupt(sid) }
            })
        }

        if !childAgents.isEmpty {
            let childActions: [UIMenuElement] = [
                action("View all", systemImage: "list.bullet") {
                    onShowChildSessions(nil)
                },
            ] + childAgents.map { child in
                action(
                    child.description,
                    systemImage: child.status.menuSystemImage
                ) {
                    onShowChildSessions(child.id)
                }
            }
            primary.append(UIMenu(
                title: "Child sessions (\(childAgents.count))",
                image: UIImage(systemName: "person.2"),
                children: childActions
            ))
        }

        primary.append(action(
            signInRequests.isEmpty ? "Sign in on iPhone" : "Sign in on iPhone (\(signInRequests.count))",
            systemImage: "key"
        ) { onShowPhoneSignIn(nil) })
        primary.append(action("Files & Links", systemImage: "paperclip", handler: onShowAttachments))
        primary.append(action("Open Terminal", systemImage: "apple.terminal", handler: onOpenTerminal))
        // PHASE-2 SPIKE entry — remove with the spike.
        primary.append(action("Spike: inverted transcript", systemImage: "arrow.up.arrow.down",
                              handler: onShowInversionSpike))

        let models = modelOptions.map { model in
            action(model) { Task { await store.setModel(sid, model) } }
        }
        primary.append(UIMenu(
            title: "Switch model",
            image: UIImage(systemName: "cpu"),
            children: models
        ))

        var assignees: [UIMenuElement] = [
            action("Unassigned") { Task { await store.assign(sid, nil) } }
        ]
        assignees.append(contentsOf: store.users.map { user in
            action(user) { Task { await store.assign(sid, user) } }
        })
        primary.append(UIMenu(
            title: "Assign to",
            image: UIImage(systemName: "person"),
            children: assignees
        ))

        primary.append(action("Rename", systemImage: "pencil", handler: onRename))

        if let frame = store.browserFrames[sid],
           frame.frameId == dismissedBrowserFrameID {
            primary.append(action(
                "Show Browser Preview",
                systemImage: "safari",
                handler: onRestoreBrowserPreview
            ))
        }

        if canFork {
            primary.append(action(
                forking ? "Forking…" : "Fork session",
                systemImage: "arrow.triangle.branch",
                attributes: forking ? .disabled : []
            ) {
                Task { await forkSession() }
            })
        }

        if canTransfer {
            let targets = transferTargets.map { target in
                action(
                    target.label,
                    systemImage: "desktopcomputer",
                    attributes: transferring ? .disabled : []
                ) {
                    Task { await transfer(to: target) }
                }
            }
            primary.append(UIMenu(
                title: transferring ? "Moving…" : "Move to host",
                image: UIImage(systemName: "arrow.left.arrow.right"),
                children: targets
            ))
        }

        if ManualUnread.canMarkUnread(sid) {
            if store.isManuallyUnread(sid) {
                primary.append(action("Mark as read", systemImage: "envelope.open") {
                    store.markRead(sid)
                })
            } else {
                primary.append(action("Mark as unread", systemImage: "envelope.badge") {
                    markUnreadAndExit()
                })
            }
        }

        var debug: [UIMenuElement] = []
        if let tmuxIdentifier, !tmuxIdentifier.isEmpty {
            debug.append(action("tmux · \(tmuxIdentifier)", systemImage: "terminal") {
                copyToClipboard(tmuxIdentifier)
            })
        }
        if !sid.isEmpty {
            debug.append(action("\(agentIdLabel) · \(sid)", systemImage: "number") {
                copyToClipboard(sid)
            })
        }

        return [
            UIMenu(options: .displayInline, children: primary),
            UIMenu(title: "Debug — tap to copy", options: .displayInline, children: debug),
            UIMenu(options: .displayInline, children: [
                action("End session", systemImage: "xmark.circle", attributes: .destructive,
                       handler: onConfirmEnd)
            ])
        ]
    }

    private func action(
        _ title: String,
        systemImage: String? = nil,
        attributes: UIMenuElement.Attributes = [],
        handler: @escaping @MainActor () -> Void
    ) -> UIAction {
        UIAction(
            title: title,
            image: systemImage.flatMap(UIImage.init(systemName:)),
            attributes: attributes
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    private var modelOptions: [String] {
        AgentKind(rawValue: agent)?.models ?? AgentKind.claude.models
    }

    private var canFork: Bool {
        !sid.isEmpty && (agent == "claude" || agent == "codex")
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
        case "claude": return "Claude id"
        case "codex": return "Codex id"
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

}

/// A UIKit pull-down button whose root menu identity never changes after mount.
/// `updateUIView` only replaces the deferred builder, so a live SwiftUI update can
/// affect the next presentation without disturbing the one the user is scrolling.
private struct NativeSessionOptionsButton: UIViewRepresentable {
    let makeElements: @MainActor () -> [UIMenuElement]

    func makeCoordinator() -> Coordinator {
        Coordinator(makeElements: makeElements)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        // This is a neutral toolbar action, not a primary action. Dynamic label
        // color matches the system back chevron in both light and dark appearance.
        button.tintColor = .label
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.accessibilityLabel = "More"
        button.accessibilityIdentifier = "sessionOptionsMenu"
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
                guard let coordinator else {
                    completion([])
                    return
                }
                completion(MainActor.assumeIsolated { coordinator.makeElements() })
            }
        ])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.makeElements = makeElements
    }

    @MainActor
    final class Coordinator {
        var makeElements: @MainActor () -> [UIMenuElement]

        init(makeElements: @escaping @MainActor () -> [UIMenuElement]) {
            self.makeElements = makeElements
        }
    }
}

/// The 180° flip that makes the transcript an inverted list.
///
/// Applied to the `ScrollView` AND to every row, so rows read the right way up
/// inside an upside-down stack. `scaleEffect` rather than `rotationEffect`
/// because it is a pure mirror — no rounding drift on repeated application.
private extension View {
    func flippedRow() -> some View {
        rotationEffect(.degrees(180))
    }
}

/// Reports whether an inverted transcript is at its newest end.
///
/// Reads the offset ONLY. The predecessor read content height too, and Phase-1
/// finding 2 measured that height swinging 15,600 → 8,100 → 14,700 pt between
/// adjacent samples while `LazyVStack` re-estimated unmeasured rows — which made
/// `atEnd` flap and fire 12-frame follow bursts against the user's finger. An
/// offset cannot do that.
///
/// iOS 18+. On iOS 17 the value stays at its initial `true`, which under
/// inversion is the safe default: the only thing it gates is whether an arriving
/// message grows the render window.
private struct NewestEndTracker: ViewModifier {
    let onChange: (Bool) -> Void

    private struct AtNewest: Equatable {
        var value: Bool
        /// PHASE-1 INSTRUMENTATION — coarse buckets so the geometry trace fires
        /// on real movement without per-frame spam.
        var yBucket: Int
        var contentBucket: Int
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: AtNewest.self) { geo in
                AtNewest(
                    value: TranscriptWindow.isAtNewestEnd(offsetY: geo.contentOffset.y),
                    yBucket: Int(geo.contentOffset.y / 40),
                    contentBucket: Int(geo.contentSize.height / 100)
                )
            } action: { _, p in
                #if DEBUG
                NSLog("LFGVP geo y=\(p.yBucket * 40) contentH=\(p.contentBucket * 100) atNewest=\(p.value)")
                #endif
                onChange(p.value)
            }
        } else {
            content
        }
    }
}

/// Transient failure report, shown under the nav bar.
///
/// Deliberately quiet: these are things that already happened and cannot be
/// retried from here (the pending strip owns retryable sends), so the banner
/// states the host's own sentence and gets out of the way on its own. Tapping
/// dismisses it early.
struct SessionErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "xmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onDismiss)
        .accessibilityIdentifier("sessionErrorBanner")
        .accessibilityLabel(message)
        .accessibilityHint("Dismisses this error")
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

private struct ChildSessionsComposerBar: View {
    let agents: [ChildAgentSession]
    let action: () -> Void

    private var presentation: ChildAgentCollectionPresentation {
        ChildAgentCollectionPresentation(agents: agents)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    if presentation.runningCount > 0 {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            .offset(x: 11, y: -9)
                    }
                }
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(presentation.compactStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if presentation.runningCount > 0 {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color(.separator).opacity(0.55), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("childSessionsComposerBar")
        .accessibilityLabel("\(presentation.title), \(presentation.compactStatus)")
        .accessibilityHint("Shows child sessions")
    }
}

private struct ChildAgentSessionsSheet: View {
    let parentSessionID: String
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String]

    init(parentSessionID: String, initialChildID: String?) {
        self.parentSessionID = parentSessionID
        _path = State(initialValue: initialChildID.map { [$0] } ?? [])
    }

    private var agents: [ChildAgentSession] {
        store.childAgentsBySession[parentSessionID] ?? []
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if agents.isEmpty {
                    ContentUnavailableView(
                        "No child sessions",
                        systemImage: "person.2",
                        description: Text("This session has not spawned a child agent.")
                    )
                } else {
                    List(agents) { child in
                        NavigationLink(value: child.id) {
                            ChildAgentSessionRow(child: child)
                        }
                        .accessibilityIdentifier("childSessionRow_\(child.id)")
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Child sessions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { childID in
                if let child = agents.first(where: { $0.id == childID }) {
                    ChildAgentTranscriptView(parentSessionID: parentSessionID, child: child)
                } else {
                    ContentUnavailableView("Child session unavailable", systemImage: "person.crop.circle.badge.xmark")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("childSessionsDoneButton")
                }
            }
        }
        .task { await store.refreshChildAgents(parentSessionID) }
        .accessibilityIdentifier("childSessionsSheet")
    }
}

private struct ChildAgentSessionRow: View {
    let child: ChildAgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            child.status.statusView
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(child.description)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Text(child.agentType)
                    Text("·")
                    Text(child.status.label)
                        .foregroundStyle(child.status.tint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(child.description), \(child.agentType), \(child.status.label)")
    }
}

private struct ChildAgentTranscriptView: View {
    let parentSessionID: String
    let child: ChildAgentSession
    @Environment(SessionStore.self) private var store
    @State private var messages: [SessionMessage] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading && messages.isEmpty {
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, messages.isEmpty {
                ContentUnavailableView(
                    "Transcript unavailable",
                    systemImage: "exclamationmark.bubble",
                    description: Text(errorMessage)
                )
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "No transcript yet",
                    systemImage: "text.bubble",
                    description: Text("This child session has not produced visible output.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages, id: \.stableID) { message in
                            TranscriptMessageView(message: message)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(child.description)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: child.id) { await loadTranscriptUntilTerminal() }
        .accessibilityIdentifier("childSessionTranscript")
    }

    private func loadTranscriptUntilTerminal() async {
        while !Task.isCancelled {
            do {
                messages = try await store.childAgentMessages(
                    parentID: parentSessionID,
                    childID: child.id
                )
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = (error as? LFGError)?.userMessage ?? error.localizedDescription
            }
            loading = false
            await store.refreshChildAgents(parentSessionID)
            let isActive = store.childAgentsBySession[parentSessionID]?
                .first(where: { $0.id == child.id })?.status.isActive == true
            guard isActive else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

private extension ChildAgentStatus {
    var menuSystemImage: String {
        switch self {
        case .running: "clock.arrow.circlepath"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .stopped: "stop.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .running: .blue
        case .completed: .green
        case .failed: .orange
        case .stopped, .unknown: .secondary
        }
    }

    @ViewBuilder var statusView: some View {
        if self == .running {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: menuSystemImage)
                .foregroundStyle(tint)
        }
    }
}
