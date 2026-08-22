import SwiftUI
import LFGCore
import UIKit

struct SessionDetailView: View {
    private enum PresentedSheet: Identifiable {
        case attachments
        case childSessions(selectedID: String?)

        var id: String {
            switch self {
            case .attachments: "attachments"
            case .childSessions(let selectedID): "child-sessions-\(selectedID ?? "all")"
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
    /// Holds the transcript against the composer while the keyboard animates.
    @State private var keyboardRepin: Task<Void, Never>?
    /// Holds the transcript at the newest row across an append until arrival.
    @State private var followRepin: Task<Void, Never>?
    /// Releases the identity anchor after an arrival-driven window change.
    @State private var viewportHold: Task<Void, Never>?
    /// Raw "is the scroll view at its end" from geometry, recorded even while
    /// opening — this is what lets the opening pin confirm it actually arrived.
    @State private var scrolledToEnd = false
    /// Stricter twin of `scrolledToEnd`, false while the transcript is still too
    /// short to be meaningfully "at the end".
    @State private var openArrivalConfirmed = false
    @State private var scrollProxy: ScrollViewProxy?
    /// SwiftUI's identity-backed scroll position follows the top-most message
    /// under the user's eyes as rows are inserted above it. Unlike a delayed
    /// `scrollTo`, it keeps updating during drag/deceleration instead of snapping
    /// back to a stale anchor after the user has continued scrolling.
    @State private var scrollPositionID: String?
    // True while the open-at-bottom lifecycle follows history loading. Guards the
    // BOTTOM-anchor debounce from mistaking a still-loading transcript for a
    // deliberate scroll-up and freezing auto-follow before the view settles.
    @State private var pinningToBottom = false
    @State private var settlingInitialBottomPin = false
    @State private var dismissedBrowserFrameID: String?
    @State private var presentedSheet: PresentedSheet?
    /// How many of the newest messages the transcript actually renders. The store
    /// still holds the whole conversation — this bounds only what SwiftUI has to
    /// place. See `TranscriptWindow` for the profile that motivates it.
    @State private var window = TranscriptWindow.pageSize
    /// True from the moment a page is added until the reader's position has been
    /// restored — see `extendWindow` for why this gate is load-bearing.
    @State private var extending = false

    private var sid: String { session.sessionId ?? "" }
    private var messages: [SessionMessage] { store.transcripts[sid] ?? [] }
    private var messageStableIDs: [String] { messages.map(\.stableID) }

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
            bottomDebounce?.cancel()
            keyboardRepin?.cancel()
            followRepin?.cancel()
            viewportHold?.cancel()
            isAtBottom = true
            pinningToBottom = true
            settlingInitialBottomPin = false
            scrollPositionID = nil
            // A session opens on its newest page; whatever history the previous
            // session had paged in must not carry over.
            window = TranscriptWindow.pageSize
            store.focus(sid)
            store.loadHistory(sid)   // store-owned: not cancelled by view churn

            // Cached/live messages can already provide the newest tail before
            // the network history walk begins. Settle immediately in that case;
            // otherwise the messages onChange below does this when the first
            // renderable batch lands. Do not wait for every older page: those
            // pages load above the bounded tail and must not lock user scrolling.
            if TranscriptWindow.shouldSettleInitialPin(
                isOpening: pinningToBottom,
                hasRenderedTail: !messages.isEmpty
            ) {
                await settleInitialBottomPin(for: sid)
            }
            await store.loadBrowserFrame(sid)
            if TranscriptWindow.shouldSettleInitialPin(
                isOpening: pinningToBottom,
                hasRenderedTail: !messages.isEmpty
            ) {
                await settleInitialBottomPin(for: sid)
            }
        }
        .onDisappear {
            bottomDebounce?.cancel()
            keyboardRepin?.cancel()
            followRepin?.cancel()
            viewportHold?.cancel()
            pinningToBottom = false
            settlingInitialBottomPin = false
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .attachments:
                AttachmentsSheet(messages: messages)
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: 1).id("TOP")   // jump-to-top anchor
                    if session.isBlocked { PausedBannerView(session: session) }

                    if messages.isEmpty && !isBusy {
                        Text("Connecting to live transcript…")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        // Everything older than the window sits behind this row;
                        // scrolling it into view walks one page further back.
                        if historyTopRow != .hidden { olderHistoryLoader }
                        ForEach(Array(zip(windowedMessages.indices, windowedMessages)), id: \.1.stableID) { idx, msg in
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
                .scrollTargetLayout()
            }
            .scrollPosition(id: historyRevealAnchor)
            // Authoritative "is the reader at the newest end", from geometry.
            // The 1pt BOTTOM anchor below still drives this on iOS 17, but its
            // `onAppear` reports row *creation*, not visibility — see
            // `TranscriptWindow.isScrolledToEnd`.
            .modifier(BottomProximityTracker { atEnd, confirmsOpen in
                // Recorded unconditionally, including while opening: the opening
                // pin needs these to know whether its scroll actually ARRIVED.
                scrolledToEnd = atEnd
                openArrivalConfirmed = confirmsOpen
                guard !pinningToBottom else { return }
                bottomDebounce?.cancel()
                isAtBottom = atEnd
            })
            // The keyboard resizes the transcript out from under the reader.
            // See `repinForKeyboardChange` for what that costs if nobody reacts.
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )) { note in
                repinForKeyboardChange(note, using: proxy)
            }
            .onChange(of: messageStableIDs) { old, new in
                let shouldFollowLatest = TranscriptWindow.shouldFollowLatest(
                    isAtBottom: isAtBottom,
                    isOpening: pinningToBottom
                )
                // Reading history while the agent streams: the window is a count
                // taken from the newest end, so an arriving turn would silently
                // push a row off the TOP and shift the text under the user's
                // eyes. Grow only for rows that actually arrived AFTER the old
                // tail. Older network pages are prepended; expanding for their
                // raw count is the jump that used to lay hundreds of rows above
                // the viewport.
                if !shouldFollowLatest {
                    let previousWindow = window
                    let grown = TranscriptWindow.reconciled(
                        window: window,
                        previousIDs: old,
                        currentIDs: new
                    )
                    // `reconciled` keeps the row COUNT honest, but the window is
                    // measured from the newest end, so `startIndex` still moves
                    // whenever the total changes — and that lays older rows above
                    // whatever the reader is looking at. Measured on a real
                    // session: startIndex walked 0 → 282 → 640 → 1035 → 1221 as
                    // pages landed, shoving the visible text each time. Re-anchor
                    // to the row that was on top, in the SAME transaction that
                    // changes the window — exactly what `extendWindow` does for a
                    // user-driven reveal, applied to an arrival-driven one.
                    let anchor = TranscriptWindow.anchorAfterMutation(
                        previousIDs: old,
                        currentIDs: new,
                        previousWindow: previousWindow,
                        currentWindow: grown
                    )
                    if let anchor {
                        holdViewportAcrossMutation(anchoredTo: anchor) { window = grown }
                    } else {
                        window = grown
                    }
                }
                if shouldFollowLatest {
                    if pinningToBottom {
                        scrollToLatest(using: proxy, animated: false)
                    } else {
                        followLatestUntilArrived(using: proxy)
                    }
                }
                if TranscriptWindow.shouldSettleInitialPin(
                    isOpening: pinningToBottom,
                    hasRenderedTail: !new.isEmpty
                ), !settlingInitialBottomPin {
                    Task { @MainActor in
                        await settleInitialBottomPin(for: sid)
                    }
                }
            }
            .onChange(of: prompt) { _, _ in
                if TranscriptWindow.shouldFollowLatest(
                    isAtBottom: isAtBottom,
                    isOpening: pinningToBottom
                ) {
                    if pinningToBottom {
                        scrollToLatest(using: proxy, animated: false)
                    } else {
                        followLatestUntilArrived(using: proxy)
                    }
                }
            }
            // Optimistic sent bubbles and the pending strip live outside `messages`,
            // so a fresh send changes neither `messages.count` nor `prompt`. Track
            // the pending count too, or submitting a message wouldn't scroll down.
            //
            // Routed through the same verified pin as the transcript path. When a
            // send resolves, `pending.count` and `messages` change in quick
            // succession; two independently ANIMATED `scrollTo`s over an
            // insert-plus-remove is what made a follow-up visibly scroll up and
            // then settle back. One non-animated pin per change, and they
            // coalesce instead of competing.
            .onChange(of: pending.count) { _, _ in
                if TranscriptWindow.shouldFollowLatest(
                    isAtBottom: isAtBottom,
                    isOpening: pinningToBottom
                ) {
                    if pinningToBottom {
                        scrollToLatest(using: proxy, animated: false)
                    } else {
                        followLatestUntilArrived(using: proxy)
                    }
                }
            }
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

    /// The anchor `.scrollPosition(id:)` is allowed to enforce, which is ONLY
    /// while `extendWindow` is revealing a page.
    ///
    /// `.scrollPosition(id:)` is a *continuous* contract, not a one-shot scroll:
    /// SwiftUI keeps re-deriving the content offset to hold the bound row at the
    /// anchor for as long as the modifier is bound to a non-nil id — including
    /// across layout changes that have nothing to do with history. Raising the
    /// keyboard is exactly such a change, and re-anchoring against it threw the
    /// reader's rows 407pt off the top of the screen (measured on the shipped
    /// 1.3.0 build; `.claude/evidence/20260822-keyboard-scroll`). The same fires
    /// for any `safeAreaInset` height change — the pending strip, the child
    /// sessions bar, the offline notice.
    ///
    /// The history reveal only ever needed the anchor for the one transaction
    /// that inserts the page, so report it for exactly that long and report nil
    /// the rest of the time, leaving the scroll view's own offset management
    /// alone. The setter still writes through, so `scrollPositionID` keeps
    /// tracking the top-most row for whenever the next reveal needs it.
    private var historyRevealAnchor: Binding<String?> {
        Binding(
            get: {
                KeyboardViewportPolicy.enforcesHistoryAnchor(isRevealingPage: extending)
                    ? scrollPositionID
                    : nil
            },
            set: { scrollPositionID = $0 }
        )
    }

    /// Keep a bottom-pinned reader pinned across a keyboard transition.
    ///
    /// The composer hangs off `safeAreaInset(edge: .bottom)`, so the keyboard
    /// shrinks the transcript's viewport by ~300pt. Nothing moved the content to
    /// match: measured on 1.3.0, the newest message sat at y=428…655 while the
    /// keyboard claimed everything below y=373 — i.e. tapping the composer hid
    /// the very message you were replying to, and left older content on screen.
    ///
    /// Re-pinning once on `willChangeFrame` is not enough: the notification
    /// arrives *before* the safe-area inset lands, so a single scroll targets the
    /// pre-keyboard layout. Re-pin across the animation instead, then once more
    /// at the end. Fires for hide as well as show, which is what keeps the
    /// viewport stable on the way back down.
    private func repinForKeyboardChange(_ note: Notification, using proxy: ScrollViewProxy) {
        guard KeyboardViewportPolicy.shouldRepinToLatest(
            isAtBottom: isAtBottom,
            isOpening: pinningToBottom
        ) else { return }
        // The BOTTOM anchor leaves the viewport while the inset animates. Left
        // alone, that trips the `onDisappear` debounce into reading a keyboard
        // transition as a deliberate scroll-up and freezing auto-follow.
        bottomDebounce?.cancel()
        let frames = KeyboardViewportPolicy.repinFrameCount(
            animationDuration: note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
                as? Double
        )
        keyboardRepin?.cancel()
        keyboardRepin = Task { @MainActor in
            for _ in 0..<frames {
                if Task.isCancelled { return }
                scrollToLatest(using: proxy, animated: false)
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            scrollToLatest(using: proxy, animated: false)
            isAtBottom = true
        }
    }

    /// The row above the oldest rendered message. Coming into view IS the
    /// request for more history — it only reaches the viewport if the user
    /// scrolled to the top of the window.
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

    /// Apply a render-window change while holding the given row where it is.
    ///
    /// Same shape as `extendWindow`'s transaction — the identity anchor is set
    /// and the window changed together, so SwiftUI resolves the new layout
    /// against a row the reader can see rather than re-deriving an offset from
    /// a slice whose top just moved. `extending` is what exposes the anchor to
    /// `.scrollPosition(id:)` (see `historyRevealAnchor`), and it is released on
    /// the same 300 ms settle the reveal path uses.
    private func holdViewportAcrossMutation(
        anchoredTo anchorID: String,
        _ apply: () -> Void
    ) {
        extending = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.scrollTargetAnchor = .top
        if #available(iOS 18.0, *) {
            transaction.scrollPositionUpdatePreservesVelocity = true
            transaction.scrollContentOffsetAdjustmentBehavior = .automatic
        }
        withTransaction(transaction) {
            scrollPositionID = anchorID
            apply()
        }
        viewportHold?.cancel()
        viewportHold = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            extending = false
        }
    }

    /// Walk the window one page further back, keeping the reader in place.
    private func extendWindow() {
        // Two guards, both learned the hard way:
        //
        // `pinningToBottom` — the open-at-bottom pin is still force-scrolling,
        // and the loader flashes through the viewport on the way down. Reading
        // that as intent would page in the whole history on every open.
        //
        // `extending` — this one is load-bearing, not belt-and-braces. Restoring
        // the reader's position is asynchronous, and until it lands the loader is
        // still on screen, where its `onAppear` fires again. Measured without it:
        // a SINGLE swipe walked the window 1000 → 1400, paging in a thousand
        // messages nobody scrolled past and rebuilding the exact list this whole
        // change exists to avoid.
        guard !pinningToBottom, hasOlderHistory, !extending else { return }
        extending = true
        let anchorID = messages[windowStart].stableID
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.scrollTargetAnchor = .top
        if #available(iOS 18.0, *) {
            // A page can land while a flick is still decelerating. Preserve that
            // velocity so revealing history never feels like the app grabbed the
            // scroll view away from the user's gesture.
            transaction.scrollPositionUpdatePreservesVelocity = true
            transaction.scrollContentOffsetAdjustmentBehavior = .automatic
        }
        // Target the first retained message in the SAME transaction that inserts
        // the page. This excludes the fixed TOP/loader targets from SwiftUI's
        // choice of semantic anchor without scheduling a stale future scroll.
        withTransaction(transaction) {
            scrollPositionID = anchorID
            window = TranscriptWindow.extended(window: window, total: messages.count)
        }
        Task { @MainActor in
            // Hold the gate while SwiftUI places the new targets and moves the
            // loader out of the viewport. A continued drag remains entirely
            // user-driven because this task never writes a scroll destination.
            try? await Task.sleep(for: .milliseconds(300))
            extending = false
        }
    }

    private func jumpToTop() {
        guard let scrollProxy else { return }
        isAtBottom = false
        // "Jump to the beginning" has to mean the beginning, so this is the one
        // place that renders the whole transcript. The cost is now something the
        // user asks for explicitly instead of what every session open pays; the
        // window is restored the next time the session is opened.
        window = max(window, messages.count)
        withAnimation { scrollProxy.scrollTo("TOP", anchor: .top) }
    }

    private func jumpToBottom() {
        guard let scrollProxy else { return }
        isAtBottom = true
        withAnimation { scrollProxy.scrollTo("BOTTOM", anchor: .bottom) }
    }

    private func scrollToLatest(animated: Bool) {
        guard let scrollProxy else { return }
        scrollToLatest(using: scrollProxy, animated: animated)
    }

    /// Scroll to the newest row and keep asserting it until geometry confirms we
    /// arrived.
    ///
    /// A single `scrollTo("BOTTOM")` undershoots in this `LazyVStack` — the rows
    /// are tall and variable and many are not measured yet — so the view can end
    /// up a few hundred points short of the end. That used to be invisible
    /// because `isAtBottom` was latched true by the BOTTOM anchor's `onAppear`,
    /// which re-followed on the next message. Now that follow is honest geometry,
    /// an undershoot turns auto-follow OFF and every later message drifts the
    /// reader further from the newest content — measured at ~640 pt over 28 s on
    /// a streaming session. Verify, don't assume.
    private func followLatestUntilArrived(using proxy: ScrollViewProxy) {
        followRepin?.cancel()
        followRepin = Task { @MainActor in
            for _ in 0..<Self.followRepinFrames {
                if Task.isCancelled { return }
                scrollToLatest(using: proxy, animated: false)
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(16))
                if Self.canVerifyScrollGeometry, scrolledToEnd { break }
            }
            guard !Task.isCancelled else { return }
            if Self.canVerifyScrollGeometry, scrolledToEnd { isAtBottom = true }
        }
    }

    /// Short — this rides an append, not an open. Long enough to absorb a couple
    /// of layout passes, short enough that it cannot feel like the view is
    /// fighting a deliberate scroll.
    private static let followRepinFrames = 12

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
        }
    }

    private func settleInitialBottomPin(for openingSessionID: String) async {
        guard sid == openingSessionID,
              pinningToBottom,
              !settlingInitialBottomPin else { return }
        settlingInitialBottomPin = true

        // Pin until the scroll view CONFIRMS it reached the end.
        //
        // This used to pin twice — once after a yield, once 120 ms later — and
        // then release regardless. It never checked that the scroll arrived. A
        // `LazyVStack` that is still measuring rows lands `scrollTo`
        // approximately, so on a cold open of a long transcript the pin could be
        // released part-way up; and because `isAtBottom` is now honest geometry
        // rather than a latched anchor callback, auto-follow correctly stayed
        // off and the reader was simply parked mid-transcript. Measured before
        // this: newest rows ~800 pt below the fold, and they stayed there.
        //
        // Re-asserting costs nothing once we have arrived — the loop exits on
        // the first confirmation — and the budget is bounded so a transcript
        // that can never satisfy the check still hands control back.
        let budget = TranscriptWindow.openPinFrameBudget(
            canVerifyGeometry: Self.canVerifyScrollGeometry
        )
        for _ in 0..<budget {
            guard sid == openingSessionID, pinningToBottom else {
                settlingInitialBottomPin = false
                return
            }
            scrollToLatest(animated: false)
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
            if Self.canVerifyScrollGeometry, openArrivalConfirmed { break }
        }
        guard sid == openingSessionID, pinningToBottom else {
            settlingInitialBottomPin = false
            return
        }
        scrollToLatest(animated: false)
        pinningToBottom = false
        settlingInitialBottomPin = false
        isAtBottom = true
    }

    /// Whether `BottomProximityTracker` can actually report arrival on this OS.
    /// On iOS 17 `scrolledToEnd` never updates, so the opening pin must not wait
    /// on it.
    private static var canVerifyScrollGeometry: Bool {
        if #available(iOS 18.0, *) { true } else { false }
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
                dismissedBrowserFrameID: dismissedBrowserFrameID,
                onShowAttachments: { presentedSheet = .attachments },
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
    let dismissedBrowserFrameID: String?
    let onShowAttachments: () -> Void
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

        primary.append(action("Files & Links", systemImage: "paperclip", handler: onShowAttachments))

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

/// Reports whether the transcript is scrolled to its newest end, from the scroll
/// view's real geometry.
///
/// This exists because the 1 pt `BOTTOM` anchor cannot answer the question
/// honestly. In a `LazyVStack`, `onAppear` fires when SwiftUI *creates* a row,
/// not when it becomes visible, so a large transcript mutation re-creates the
/// anchor while the reader is hundreds of points up and latches `isAtBottom`
/// true. From then on every arriving message scrolls toward the newest end and
/// the transcript walks out from under the reader — measured at −146 pt per
/// arrival on a live session, which is what "the transcript disappears while I'm
/// typing" actually is.
///
/// iOS 18+ only; on iOS 17 the anchor keeps its previous behavior, unchanged.
private struct BottomProximityTracker: ViewModifier {
    /// `(atEnd, confirmsOpenArrival)`. They differ for a transcript shorter than
    /// the viewport: that is "at the end" for auto-follow, but must NOT confirm
    /// an open — see `TranscriptWindow.confirmsOpenArrival`.
    let onChange: (Bool, Bool) -> Void

    private struct Proximity: Equatable {
        var atEnd: Bool
        var confirmsOpen: Bool
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Proximity.self) { geo in
                Proximity(
                    atEnd: TranscriptWindow.isScrolledToEnd(
                        contentHeight: geo.contentSize.height,
                        containerHeight: geo.containerSize.height,
                        offsetY: geo.contentOffset.y,
                        bottomInset: geo.contentInsets.bottom
                    ),
                    confirmsOpen: TranscriptWindow.confirmsOpenArrival(
                        contentHeight: geo.contentSize.height,
                        containerHeight: geo.containerSize.height,
                        offsetY: geo.contentOffset.y,
                        bottomInset: geo.contentInsets.bottom
                    )
                )
            } action: { _, p in
                onChange(p.atEnd, p.confirmsOpen)
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
