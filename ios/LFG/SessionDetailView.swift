import SwiftUI
import LFGCore
import UIKit

struct SessionDetailView: View {
    private static let bottomTranscriptClearance: CGFloat = 16

    private enum PresentedSheet: Identifiable {
        case attachments
        case phoneSignIn(requestID: String?)
        case requestedSignIn(requestID: String)
        case childSessions(selectedID: String?)
        case inversionSpike

        var id: String {
            switch self {
            case .phoneSignIn(let requestID): "phone-sign-in-\(requestID ?? "all")"
            case .requestedSignIn(let requestID): "sign-in-\(requestID)"
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
    #if DEBUG
    /// Deterministic wrapped draft for the network-free send-follow UI fixture.
    var debugInitialDraft = ""
    #endif
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
    @State private var composerFocused = false
    @State private var followupFocusRequest = 0
    /// Keyboard height captured from UIKit notifications. The transcript keeps
    /// its full-screen viewport for performance, while one animated content
    /// clearance moves its visual bottom with the floating composer.
    @State private var keyboardOcclusionHeight: CGFloat = 0
    @State private var keyboardBottomClearance: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    // True while the open-at-bottom lifecycle follows history loading. Guards the
    // BOTTOM-anchor debounce from mistaking a still-loading transcript for a
    // deliberate scroll-up and freezing auto-follow before the view settles.
    @State private var dismissedBrowserFrameID: String?
    @State private var presentedSheet: PresentedSheet?
    /// The shell on this session's host (`TerminalScreen`), from the ••• menu.
    @State private var showTerminal = false
    @State private var showingSessionOptions = false
    /// How many of the newest messages the transcript actually renders. The store
    /// still holds the whole conversation — this bounds only what SwiftUI has to
    /// place. See `TranscriptWindow` for the profile that motivates it.
    @State private var window = TranscriptWindow.pageSize
    /// True from the moment a page is added until the reader's position has been
    /// restored — see `extendWindow` for why this gate is load-bearing.
    @State private var extending = false
    /// Snapshot only when transcript identity changes. Dragging the edge index
    /// writes state every time it crosses an anchor, so deriving this in `body`
    /// would turn each gesture update into an O(transcript) filter.
    @State private var userMessageAnchors: [UserMessageAnchor] = []
    @State private var selectedUserMessageAnchorIndex: Int?
    /// Cancels stale next-runloop scrolls when a fast drag crosses several
    /// anchors before SwiftUI finishes revealing an older render window.
    @State private var pendingUserMessageTargetID: String?
    /// Includes the full dynamic bottom stack and its home-indicator clearance:
    /// pending/offline notices, child-agent and sign-in controls, plus composer.
    /// On iOS 26 this becomes a scroll-content margin at the inverted list's
    /// visual bottom, keeping the newest row above every floating control while
    /// older rows can pass behind the stack.
    @State private var bottomChromeHeight: CGFloat = 0
    @State private var frozenTranscriptBottomContentMargin: CGFloat?

    /// Structural top is the visual bottom because the transcript is inverted.
    /// A scroll-content margin keeps this boundary outside the transcript's
    /// scrollable rows while placing the newest row above the floating chrome.
    private var calculatedTranscriptBottomContentMargin: CGFloat {
        CGFloat(TranscriptWindow.bottomContentMargin(
            keyboardOcclusionHeight: Double(keyboardBottomClearance),
            bottomChromeHeight: Double(bottomChromeHeight),
            bottomSafeAreaInset: Double(windowBottomSafeAreaInset),
            bottomTranscriptClearance: Double(Self.bottomTranscriptClearance)
        ))
    }
    private var transcriptBottomContentMargin: CGFloat {
        CGFloat(TranscriptWindow.effectiveBottomContentMargin(
            calculated: Double(calculatedTranscriptBottomContentMargin),
            frozen: frozenTranscriptBottomContentMargin.map(Double.init)
        ))
    }
    private var historyKeyboardViewportOffset: CGFloat {
        CGFloat(TranscriptWindow.historyKeyboardViewportOffset(
            isAtBottom: isAtBottom,
            keyboardOcclusionHeight: Double(keyboardOcclusionHeight),
            bottomSafeAreaInset: Double(windowBottomSafeAreaInset)
        ))
    }
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
    private var isBusy: Bool {
        ChildAgentActivity.parentIsRunning(
            parentBusy: store.busy[sid] == true,
            agents: childAgents,
            reportedRunningCount: session.runningChildAgentCount
        )
    }
    private var isMovingHost: Bool { store.isMovingHost(sid) }
    private var childAgents: [ChildAgentSession] { store.childAgentsBySession[sid] ?? [] }

    /// Owning host's short label, shown as a pill in the title area in multi-host
    /// setups (a single-host client has nothing to disambiguate).
    private var hostLabel: String? {
        guard settings.hosts.count > 1 else { return nil }
        return (store.movingHostSource(sid) ?? store.host(forSession: sid))?.label
    }

    /// Optimistic "sent" bubbles whose real user turn hasn't landed in the
    /// transcript yet. Computed from `messages`, so the instant the real turn
    /// appears the matching placeholder drops out of the same render pass — no
    /// visible duplicate. Mirrors the store's reconcile matching.
    private var unmatchedSentBubbles: [SessionStore.PendingSend] {
        pending.filter { $0.showSent && !hasLanded($0) }
    }

    private var unmatchedSentBubbleIDs: [String] {
        unmatchedSentBubbles.map(\.id)
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
        sessionSurface
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
                if let event = store.errorEvent(for: sid) {
                    SessionErrorBanner(message: event.message) {
                        store.dismissErrorEvent()
                    }
                    .id(event.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: event.id) {
                        try? await Task.sleep(for: .milliseconds(Int(event.remainingLifetimeMs())))
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Resolve relative file refs in this session's transcript (e.g.
        // `improvement-log/foo.md`) against its working directory.
        .transformEnvironment(\.hostFiles) { hf in
            if let cwd = session.cwd, !cwd.isEmpty { hf?.cwd = cwd }
        }
        // Keep this system-owned: on iOS 26 the native navigation toolbar
        // supplies adaptive Liquid Glass and coordinates its scroll edge with
        // the transcript behind it. A custom background here would make it
        // more opaque and break that integration.
        .toolbar { toolbarMenu }
        .modifier(SessionNavigationBarBackdropVisibility())
        .overlay {
            SessionOptionsAccessibilityProxy {
                showingSessionOptions = true
            }
            .frame(width: 1, height: 1)
        }
        .task(id: sid) {
            // Opening is now just state: the inverted list rests at the newest
            // message because that is `contentOffset == 0`. There is nothing to
            // pin, settle or confirm.
            isAtBottom = true
            // A session opens on its newest page; whatever history the previous
            // session had paged in must not carry over.
            window = TranscriptWindow.pageSize
            lastMessageIDs = messages.map(\.stableID)
            userMessageAnchors = UserMessageScrubber.anchors(in: messages)
            // Baseline both, or the first history load after opening reads as a
            // landing and a send from a *previous* session's view stays armed.
            newestUserTurnID = messages.last(where: \.rendersAsUserBubble)?.stableID
            followSendUntilLanded = false
            keyboardBottomClearance = 0
            frozenTranscriptBottomContentMargin = nil
            #if DEBUG
            if draft.isEmpty { draft = debugInitialDraft }
            #endif
            vp("open")
            store.focus(sid)
            store.loadHistory(sid)   // store-owned: not cancelled by view churn
            await store.loadBrowserFrame(sid)
        }
        .task(id: "model-catalog-\(sid)") {
            await store.loadModelCatalog(forSession: sid)
        }
        .onDisappear {
            store.blur(sid)
        }
        .onChange(of: unmatchedSentBubbleIDs) { _, ids in
            guard followSendUntilLanded, let newestPendingID = ids.last else { return }
            scheduleJumpToMessage(Self.pendingMessageAnchor(newestPendingID))
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification
        )) { notification in
            updateKeyboardOcclusion(from: notification)
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
            case .requestedSignIn(let requestID):
                PhoneSignInView(sessionID: sid, agentRequestID: requestID)
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

    /// The transcript is the full-screen content layer. On iOS 26 the custom
    /// composer floats independently above it, so rows continue behind both
    /// pieces of glass instead of terminating at opaque safe-area boundaries.
    @ViewBuilder
    private var sessionSurface: some View {
        if #available(iOS 26.0, *) {
            GeometryReader { safeAreaProxy in
                // This reader stays in the navigation-safe content region. Its
                // global top is therefore the exact status + navigation chrome
                // height, even though the transcript inside expands behind it.
                let topChromeHeight = max(safeAreaProxy.frame(in: .global).minY, 0)

                // Keep keyboard avoidance local to the composer. When both
                // layers were one overlay chain, every keyboard animation step
                // changed the transcript's proposed height and made the lazy
                // stack re-place its visible Markdown/TextKit rows. Separate
                // siblings let the transcript keep one stable viewport while
                // the composer alone follows the keyboard-safe-area boundary.
                ZStack(alignment: .bottom) {
                    transcript
                        .offset(y: historyKeyboardViewportOffset)
                        .ignoresSafeArea(.container, edges: [.top, .bottom])
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        // The 180-degree transcript transform confuses SwiftUI's
                        // automatic edge detector, expanding its blur through the
                        // viewport instead of confining it to a bar boundary.
                        .scrollEdgeEffectHidden(true, for: [.top, .bottom])
                        .overlay(alignment: .top) {
                            TopChromeFade(chromeHeight: topChromeHeight)
                                .offset(y: -topChromeHeight)
                        }

                    // This sibling intentionally still respects `.keyboard`.
                    // Its safe-area padding lifts the glass composer above the
                    // software keyboard without resizing the transcript behind it.
                    measuredBottomChrome
                }
            }
        } else {
            transcript
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomChrome
                }
        }
    }

    private var bottomChrome: some View {
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

            // Keep the draft editable while its owning host is unreachable;
            // the store queues sends durably until the host comes back.
            if store.isOffline(sid) {
                OfflineComposerNotice(hostLabel: store.host(forSession: sid)?.label ?? "This host")
            }

            if store.showsChildSessionsBar(sid) {
                ChildSessionsComposerBar(agents: childAgents) {
                    presentedSheet = .childSessions(selectedID: nil)
                }
            }

            // A waiting request the prompt panel is already showing (the server
            // surfaces it as the session's prompt) gets one entry point, not two.
            ForEach(signInRequests.filter { $0.isWaiting && $0.id != prompt?.signIn?.requestId }) { request in
                Button { presentedSheet = .requestedSignIn(requestID: request.id) } label: {
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

            MessageComposer(
                text: $draft,
                sending: isMovingHost,
                focusRequest: followupFocusRequest,
                onFocusChange: { isFocused in
                    composerFocused = isFocused
                    applyKeyboardTransition(
                        occlusionHeight: keyboardOcclusionHeight,
                        animation: .easeOut(duration: 0.25)
                    )
                }
            ) { text, atts in
                let wasAtBottom = isAtBottom
                let shouldJump = TranscriptWindow.shouldJumpAfterSend(
                    isAtBottom: wasAtBottom,
                    composerFocused: composerFocused
                )
                // Capture reader intent before dispatch mutates the transcript.
                // A reader at newest may need an explicit keyboard-aware follow;
                // a reader in history must remain there through both optimistic
                // insertion and reconciliation.
                followSendUntilLanded = shouldJump
                store.dispatchSend(sid, text: text, attachments: atts)
            }
        }
    }

    private var measuredBottomChrome: some View {
        // Measure outside the stack—not around MessageComposer—so every
        // conditional row automatically enlarges transcript clearance when it
        // appears and gives that space back when it disappears. Keep the probe
        // *inside* safeAreaPadding, though: otherwise the software keyboard's
        // animated safe-area height is published as chrome height on every
        // frame, rewriting LazyVStack padding throughout the transition.
        bottomChrome
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SessionBottomChromeHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .safeAreaPadding(.bottom)
            .onPreferenceChange(SessionBottomChromeHeightKey.self) {
                // UIWindow's inset is the stable device/container inset; it
                // does not grow with SwiftUI's keyboard safe-area region.
                let measuredHeight = $0 + windowBottomSafeAreaInset
                guard abs(bottomChromeHeight - measuredHeight) > 0.5 else { return }
                let shouldFollowNewest = isAtBottom
                bottomChromeHeight = measuredHeight
                // A growing multiline draft raises the top of the composer
                // without changing keyboard height. If the reader was already
                // at the newest edge, follow that discrete boundary change once.
                if shouldFollowNewest {
                    scheduleJumpToNewest()
                }
            }
    }

    private var windowBottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }

    // MARK: Transcript

    private var transcript: some View {
      // Lazy rows can render after a host move remaps and removes the old
      // transcript key. Capture rows and indices from the SAME value instead
      // of subscripting the store again with an index from an earlier render.
      let renderedMessages = messages
      let renderedStart = TranscriptWindow.startIndex(total: renderedMessages.count, window: window)
      let renderedWindow = renderedMessages[renderedStart...]
      return GeometryReader { geo in
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
                        PromptPanelView(sessionID: sid, prompt: prompt, onSignIn: { signIn in
                            // Straight to the browser: the login sheet fetches the
                            // request by id itself, so it never needs the polled list
                            // (which lags the prompt by up to 3s) or the history sheet.
                            presentedSheet = .requestedSignIn(requestID: signIn.requestId)
                        }).flippedRow()
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
                        OptimisticUserBubble(sessionID: sid, pending: $0)
                            .id(Self.pendingMessageAnchor($0.id))
                            .flippedRow()
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
                        ForEach(Array(renderedWindow.indices.reversed()), id: \.self) { idx in
                            TranscriptMessageView(
                                message: renderedMessages[idx],
                                followsUserBubble: idx > 0 && renderedMessages[idx - 1].rendersAsUserBubble,
                                onFollowup: { prompt in
                                    draft = FollowupDraft.adding(prompt, to: draft)
                                    followupFocusRequest += 1
                                }
                            )
                            .id(renderedMessages[idx].stableID)
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
                // Preserve ordinary side and visual-top breathing room. Do not
                // add structural-top padding here: after inversion that becomes
                // a second visual-bottom spacer reachable only by manual drag.
                .padding(.horizontal)
                .padding(.bottom)
            }
            // Structural top is the visual bottom. Reserve the floating chrome
            // outside the transcript so it cannot become a blank tail the user
            // can scroll into.
            .contentMargins(.top, transcriptBottomContentMargin, for: .scrollContent)
            .flippedRow()
            // The flip would draw the indicator down the wrong edge and run it
            // backwards; there is no correct-looking version of it here.
            .scrollIndicators(.hidden)
            .overlay(alignment: .trailing) {
                ZStack(alignment: .trailing) {
                    NativeUserMessageScrubber(
                        messageCount: userMessageAnchors.count,
                        selectedIndex: selectedUserMessageAnchorIndex,
                        onSelect: selectUserMessage(at:)
                    )
                    .frame(width: 44)
                    .accessibilityHidden(true)

                    UserMessageScrubberAccessibilityProxy(
                        value: userMessageScrubberAccessibilityValue,
                        isHidden: userMessageAnchors.isEmpty,
                        onIncrement: { adjustUserMessageSelection(.increment) },
                        onDecrement: { adjustUserMessageSelection(.decrement) }
                    )
                    .frame(width: 44)
                }
            }
            .sensoryFeedback(.selection, trigger: selectedUserMessageAnchorIndex)
            // Offset-only "am I at the newest end". Deliberately does not read
            // content height — see `TranscriptWindow.isAtNewestEnd`.
            .modifier(NewestEndTracker { atNewest in
                guard isAtBottom != atNewest else { return }
                vp("tracker.atNewest", "-> \(atNewest)")
                if !atNewest {
                    frozenTranscriptBottomContentMargin = transcriptBottomContentMargin
                }
                isAtBottom = atNewest
                guard atNewest else { return }
                // Keyboard clearance is frozen while reading history. Sync it
                // only after the reader deliberately returns to newest.
                Task { @MainActor in
                    await Task.yield()
                    guard isAtBottom else { return }
                    frozenTranscriptBottomContentMargin = nil
                    applyKeyboardTransition(
                        occlusionHeight: keyboardOcclusionHeight,
                        animation: .easeOut(duration: 0.25)
                    )
                    scheduleJumpToNewest()
                }
            })
            .onChange(of: store.transcriptVersion[sid] ?? 0) { _, _ in
                let old = lastMessageIDs
                let new = messages.map(\.stableID)
                guard old != new else { return }
                lastMessageIDs = new
                userMessageAnchors = UserMessageScrubber.anchors(in: messages)
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
                        if let newestUserTurn {
                            scheduleJumpToMessage(newestUserTurn)
                        }
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
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    guard event.location.y < geo.size.height - bottomChromeHeight else { return }
                    dismissKeyboard()
                }
            )
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
                    guard event.location.y < geo.size.height - bottomChromeHeight else { return }
                    guard event.location.y > geo.size.height * 0.70 else { return }
                    jumpToNewest()
                }
            )
        }
      }
    }

    private var userMessageScrubberAccessibilityValue: String {
        guard !userMessageAnchors.isEmpty else { return "No user messages" }
        guard let selectedUserMessageAnchorIndex else {
            return "\(userMessageAnchors.count) messages"
        }
        return "Message \(selectedUserMessageAnchorIndex + 1) of \(userMessageAnchors.count)"
    }

    private func adjustUserMessageSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !userMessageAnchors.isEmpty else { return }
        let current = selectedUserMessageAnchorIndex ?? (userMessageAnchors.count - 1)
        switch direction {
        case .increment:
            selectUserMessage(at: min(current + 1, userMessageAnchors.count - 1))
        case .decrement:
            selectUserMessage(at: max(current - 1, 0))
        @unknown default:
            break
        }
    }

    /// Reveal an older suffix before scrolling. A next-main-actor-turn scroll is
    /// required because the destination does not exist in the lazy stack until
    /// the larger `window` has gone through layout.
    private func selectUserMessage(at index: Int) {
        guard userMessageAnchors.indices.contains(index), let scrollProxy else { return }
        let anchor = userMessageAnchors[index]
        guard selectedUserMessageAnchorIndex != index || pendingUserMessageTargetID != anchor.id
        else { return }

        selectedUserMessageAnchorIndex = index
        pendingUserMessageTargetID = anchor.id
        let requiredWindow = UserMessageScrubber.requiredWindow(
            totalMessages: messages.count,
            targetMessageIndex: anchor.messageIndex,
            currentWindow: window
        )
        if requiredWindow != window {
            vp("userScrubber.grow", "win \(window)->\(requiredWindow)")
            window = requiredWindow
        }

        Task { @MainActor in
            await Task.yield()
            guard pendingUserMessageTargetID == anchor.id else { return }
            vp("userScrubber.jump", "index=\(index) id=\(anchor.id)")
            scrollProxy.scrollTo(anchor.id, anchor: .center)
        }
    }

    /// Sentinel at the array start, i.e. the visual bottom.
    private static let newestAnchor = "NEWEST"

    private static func pendingMessageAnchor(_ id: String) -> String {
        "pending-user-\(id)"
    }

    /// An explicit jump to the newest edge, used by the lower-band gesture and
    /// by layout transitions only when the reader was already following newest.
    private func jumpToNewest() {
        guard let scrollProxy else { return }
        vp("jumpToNewest")
        withAnimation {
            scrollProxy.scrollTo(Self.newestAnchor, anchor: .top)
        }
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

    /// Follow the real newest boundary after SwiftUI inserts or reconciles the
    /// outgoing row. The content margin owns composer and keyboard clearance, so
    /// an interior row anchor would only create a second, blank resting offset.
    private func scheduleJumpToMessage(_ id: String) {
        Task { @MainActor in
            await Task.yield()
            guard let scrollProxy else { return }
            vp("jumpToSentMessage", "id=\(id)")
            withAnimation(.easeOut(duration: 0.25)) {
                scrollProxy.scrollTo(Self.newestAnchor, anchor: .top)
            }
        }
    }

    private func updateKeyboardOcclusion(from notification: Notification) {
        guard let screenFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
        else { return }

        let frame = window.convert(screenFrame, from: nil)
        let occlusionHeight = max(window.bounds.maxY - frame.minY, 0)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? Double ?? 0.25
        let animation = Animation.easeOut(duration: duration)
        withAnimation(animation) {
            keyboardOcclusionHeight = occlusionHeight
        }
        applyKeyboardTransition(
            occlusionHeight: occlusionHeight,
            animation: animation
        )
    }

    private func applyKeyboardTransition(
        occlusionHeight: CGFloat,
        animation: Animation
    ) {
        let transition = TranscriptWindow.keyboardTransition(
            occlusionHeight: Double(occlusionHeight),
            composerFocused: composerFocused,
            previousBottomClearance: Double(keyboardBottomClearance),
            readerAtNewest: isAtBottom
        )
        let clearance = CGFloat(transition.bottomClearance)
        guard abs(keyboardBottomClearance - clearance) > 0.5
                || transition.shouldFollowNewest
        else { return }

        withAnimation(animation) {
            keyboardBottomClearance = clearance
        }
        guard transition.shouldFollowNewest else { return }
        isAtBottom = true
        Task { @MainActor in
            await Task.yield()
            guard let scrollProxy else { return }
            vp("keyboard.jumpToNewest", "clearance=\(clearance)")
            withAnimation(animation) {
                scrollProxy.scrollTo(Self.newestAnchor, anchor: .top)
            }
        }
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
                            .accessibilityIdentifier("sessionHostPill")
                    }
                    if isMovingHost || isBusy {
                        ProgressView().controlSize(.mini)
                        Text(isMovingHost ? "Moving host…" : "Running")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("sessionActivityStatus")
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
            .animation(.easeInOut(duration: 0.2), value: isMovingHost)
        }

        ToolbarItem(placement: .topBarTrailing) {
            // Keep the trigger itself outside UIKit's context-menu source
            // lifecycle. The app-owned popover remains stable while transcript
            // deltas stream and leaves this toolbar glyph mounted on dismissal.
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
                onMarkedUnread: onMarkedUnread,
                showingOptions: $showingSessionOptions
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

/// The custom full-width glass fade owns the navigation backdrop on iOS 26.
/// Earlier systems keep their existing system navigation-bar appearance.
private struct SessionNavigationBarBackdropVisibility: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}

/// The navigation bar's visual SwiftUI button is omitted from iOS 26's runtime
/// accessibility tree when the transcript renders behind transparent chrome.
/// This zero-sized proxy advertises the visible button's real navigation-bar
/// frame and forwards VoiceOver activation to the same popover state.
private struct SessionOptionsAccessibilityProxy: UIViewRepresentable {
    let onActivate: () -> Void

    func makeUIView(context: Context) -> AccessibilityView {
        let view = AccessibilityView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityLabel = "More"
        view.accessibilityIdentifier = "sessionOptionsMenu"
        view.accessibilityTraits = .button
        return view
    }

    func updateUIView(_ view: AccessibilityView, context: Context) {
        view.onActivate = onActivate
        view.setNeedsLayout()
    }

    final class AccessibilityView: UIView {
        var onActivate: (() -> Void)?

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            false
        }

        override func accessibilityActivate() -> Bool {
            onActivate?()
            return true
        }

        override var accessibilityFrame: CGRect {
            get {
                guard let window,
                      let navigationBar = Self.navigationBar(in: window) else {
                    return super.accessibilityFrame
                }
                let bar = navigationBar.convert(navigationBar.bounds, to: nil)
                return CGRect(
                    x: bar.maxX - 64,
                    y: bar.midY - 22,
                    width: 44,
                    height: 44
                )
            }
            set { super.accessibilityFrame = newValue }
        }

        private static func navigationBar(in view: UIView) -> UINavigationBar? {
            if let navigationBar = view as? UINavigationBar,
               !navigationBar.isHidden,
               navigationBar.alpha > 0 {
                return navigationBar
            }
            return view.subviews.lazy.compactMap(navigationBar(in:)).first
        }
    }
}

/// A transparent 44-point activation zone backed by a real `UIScrollView`.
/// Its own content never renders; only UIKit's native vertical scroll indicator
/// appears, flashes while the long-press moves, and fades on the system's timing.
private struct SessionBottomChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NativeUserMessageScrubber: UIViewRepresentable {
    let messageCount: Int
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(messageCount: messageCount, onSelect: onSelect)
    }

    func makeUIView(context: Context) -> NativeIndicatorScrollView {
        let scrollView = NativeIndicatorScrollView()
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.indicatorStyle = .default
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: 3, left: 0, bottom: 3, right: 3
        )
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        // The custom long press supplies one-finger anchor semantics. Keep the
        // native pan recognizer enabled (UIKit uses it when managing indicator
        // presentation), but move it to two fingers so this invisible auxiliary
        // view never steals an ordinary one-finger transcript edge swipe.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2

        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePress(_:))
        )
        press.minimumPressDuration = 0.28
        press.allowableMovement = 18
        scrollView.addGestureRecognizer(press)
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: NativeIndicatorScrollView, context: Context) {
        context.coordinator.messageCount = messageCount
        context.coordinator.onSelect = onSelect
        scrollView.messageCount = messageCount
        scrollView.selectedIndex = selectedIndex
        scrollView.isUserInteractionEnabled = messageCount > 0
        scrollView.setNeedsLayout()
    }

    final class Coordinator: NSObject {
        var messageCount: Int
        var onSelect: (Int) -> Void
        weak var scrollView: NativeIndicatorScrollView?
        private var indicatorRefreshTimer: Timer?

        init(messageCount: Int, onSelect: @escaping (Int) -> Void) {
            self.messageCount = messageCount
            self.onSelect = onSelect
        }

        @objc func handlePress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else {
                stopIndicatorRefresh()
                return
            }
            if recognizer.state == .began {
                startIndicatorRefresh()
            }
            guard let scrollView,
                  let index = UserMessageScrubber.anchorIndex(
                    at: Double(recognizer.location(in: scrollView).y),
                    height: Double(scrollView.bounds.height),
                    count: messageCount
                  ) else { return }

            if #available(iOS 17.4, *) {
                scrollView.withScrollIndicatorsShown(forContentOffsetChanges: {
                    scrollView.selectedIndex = index
                    scrollView.updateIndicatorPosition(animated: false)
                })
            } else {
                scrollView.selectedIndex = index
                scrollView.updateIndicatorPosition(animated: false)
            }
            scrollView.flashScrollIndicators()
            onSelect(index)
        }

        private func startIndicatorRefresh() {
            indicatorRefreshTimer?.invalidate()
            refreshIndicator()
            indicatorRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) {
                [weak self] _ in self?.refreshIndicator()
            }
        }

        private func stopIndicatorRefresh() {
            indicatorRefreshTimer?.invalidate()
            indicatorRefreshTimer = nil
        }

        @objc private func refreshIndicator() {
            scrollView?.flashScrollIndicators()
        }

        deinit {
            indicatorRefreshTimer?.invalidate()
        }
    }

    final class NativeIndicatorScrollView: UIScrollView {
        var messageCount = 0
        var selectedIndex: Int?

        override func layoutSubviews() {
            super.layoutSubviews()
            updateIndicatorPosition(animated: false)
        }

        func updateIndicatorPosition(animated: Bool) {
            guard bounds.height > 0 else { return }
            // One viewport per user turn gives UIKit enough scroll range to
            // size and place its indicator while keeping the mapping linear.
            contentSize = CGSize(
                width: max(bounds.width, 1),
                height: max(bounds.height * CGFloat(max(messageCount, 1)), bounds.height + 1)
            )
            guard let selectedIndex else { return }
            let progress = messageCount > 1
                ? CGFloat(selectedIndex) / CGFloat(messageCount - 1)
                : 0.5
            let maximumOffset = max(contentSize.height - bounds.height, 0)
            let target = CGPoint(x: 0, y: maximumOffset * progress)
            if abs(contentOffset.y - target.y) > 0.5 {
                setContentOffset(target, animated: animated)
            }
        }
    }
}

/// Exposes the scrubber below the navigation bar without changing its visual or
/// gesture footprint. The visual scrubber intentionally spans the full trailing
/// edge, but advertising that full-height rectangle to accessibility overlaps
/// and suppresses the navigation bar's More control in the runtime AX tree.
private struct UserMessageScrubberAccessibilityProxy: UIViewRepresentable {
    let value: String
    let isHidden: Bool
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    func makeUIView(context: Context) -> AccessibilityView {
        let view = AccessibilityView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityLabel = "User message index"
        view.accessibilityHint = "Swipe up or down to jump between your messages."
        view.accessibilityIdentifier = "userMessageScrubber"
        view.accessibilityTraits = .adjustable
        return view
    }

    func updateUIView(_ view: AccessibilityView, context: Context) {
        view.isAccessibilityElement = !isHidden
        view.accessibilityValue = value
        view.onIncrement = onIncrement
        view.onDecrement = onDecrement
        view.setNeedsLayout()
    }

    final class AccessibilityView: UIView {
        var onIncrement: (() -> Void)?
        var onDecrement: (() -> Void)?

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            false
        }

        override func accessibilityIncrement() {
            onIncrement?()
        }

        override func accessibilityDecrement() {
            onDecrement?()
        }

        override var accessibilityFrame: CGRect {
            get {
                var frame = super.accessibilityFrame
                guard let window,
                      let navigationBarBottom = Self.navigationBarBottom(in: window),
                      navigationBarBottom > frame.minY else { return frame }
                let clippedTop = min(navigationBarBottom, frame.maxY)
                frame.size.height = max(frame.maxY - clippedTop, 0)
                frame.origin.y = clippedTop
                return frame
            }
            set { super.accessibilityFrame = newValue }
        }

        private static func navigationBarBottom(in view: UIView) -> CGFloat? {
            let ownBottom: CGFloat? = if let navigationBar = view as? UINavigationBar,
                                         !navigationBar.isHidden,
                                         navigationBar.alpha > 0 {
                navigationBar.convert(navigationBar.bounds, to: nil).maxY
            } else {
                nil
            }
            return view.subviews.reduce(ownBottom) { result, subview in
                max(result ?? 0, navigationBarBottom(in: subview) ?? 0)
            }
        }
    }
}

/// An app-owned options popover whose toolbar trigger never participates in a
/// context-menu source-preview animation.
///
/// UIKit hides a context menu's source view while dismissing it on iOS 26. A
/// native `UIMenu` therefore cannot keep the toolbar ellipsis continuously
/// visible, even when the visible glyph and menu interaction use sibling views.
/// This popover owns its scrolling and subpage navigation while leaving the
/// SwiftUI toolbar button mounted and accessibility-visible throughout.
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
    @Binding var showingOptions: Bool

    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var forking = false
    @State private var transferring = false
    @State private var page: OptionsPage = .root
    @State private var deferredAction: DeferredAction?
    /// A move the target's pre-flight said would resume from an older copy.
    /// Held until the user confirms or cancels — never moved silently.
    @State private var staleMove: StaleMove?

    struct StaleMove: Identifiable {
        let target: Host
        let behindSeconds: TimeInterval
        var id: String { target.id }
    }

    private enum OptionsPage {
        case root
        case childSessions
        case models
        case assignees
        case transferTargets

        var title: String {
            switch self {
            case .root: "More"
            case .childSessions: "Child sessions"
            case .models: "Switch model"
            case .assignees: "Assign to"
            case .transferTargets: "Move to host"
            }
        }
    }

    private enum DeferredAction: Sendable {
        case showPhoneSignIn(String?)
        case showAttachments
        case openTerminal
        case showInversionSpike
        case showChildSession(String?)
        case rename
        case restoreBrowserPreview
        case confirmEnd
    }

    var body: some View {
        Button {
            page = .root
            showingOptions = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
            .accessibilityHidden(true)
            .accessibilityLabel("More")
            .accessibilityIdentifier("sessionOptionsMenu")
            .frame(width: 44, height: 44)
            .popover(isPresented: $showingOptions, arrowEdge: .top) {
                optionsPopover
                    .presentationCompactAdaptation(.popover)
            }
            .onChange(of: showingOptions) { _, isShowing in
                guard !isShowing else { return }
                page = .root
                guard let action = deferredAction else { return }
                deferredAction = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    perform(action)
                }
            }
            .confirmationDialog(
                "Move anyway?",
                isPresented: Binding(get: { staleMove != nil }, set: { if !$0 { staleMove = nil } }),
                titleVisibility: .visible,
                presenting: staleMove
            ) { move in
                Button("Move to \(move.target.label)") {
                    Task {
                        transferring = true
                        defer { transferring = false }
                        _ = await store.transfer(sid, to: move.target, preflight: .ready)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { move in
                let source = store.host(forSession: sid)?.label ?? "the current host"
                Text("\(move.target.label)'s copy of this conversation is \(SessionTransfer.behindLabel(move.behindSeconds)) behind \(source). Moving now continues from that older copy; the newer turns stay only on \(source).")
            }
    }

    private var optionsPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if page != .root {
                    Button {
                        page = .root
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Back")
                }

                Text(page.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showingOptions = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 10)
            .frame(height: 48)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    optionsPage
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.visible)
        }
        .buttonStyle(.plain)
        .frame(width: 320, height: 520)
    }

    @ViewBuilder
    private var optionsPage: some View {
        switch page {
        case .root:
            rootOptions
        case .childSessions:
            childSessionOptions
        case .models:
            modelOptions
        case .assignees:
            assigneeOptions
        case .transferTargets:
            transferOptions
        }
    }

    @ViewBuilder
    private var rootOptions: some View {
        if isBusy {
            optionButton("Stop", systemImage: "stop.circle", destructive: true) {
                dismissOptions()
                Task { await store.interrupt(sid) }
            }
            optionDivider
        }

        if !childAgents.isEmpty {
            optionButton(
                "Child sessions (\(childAgents.count))",
                systemImage: "person.2",
                showsChevron: true
            ) { page = .childSessions }
            optionDivider
        }

        optionButton(
            signInRequests.isEmpty ? "Sign in on iPhone" : "Sign in on iPhone (\(signInRequests.count))",
            systemImage: "key"
        ) { dismissThen(.showPhoneSignIn(nil)) }
        optionDivider
        optionButton("Files & Links", systemImage: "paperclip") {
            dismissThen(.showAttachments)
        }
        optionDivider
        optionButton("Open Terminal", systemImage: "apple.terminal") {
            dismissThen(.openTerminal)
        }
        optionDivider
        // PHASE-2 SPIKE entry — remove with the spike.
        optionButton("Spike: inverted transcript", systemImage: "arrow.up.arrow.down") {
            dismissThen(.showInversionSpike)
        }
        optionDivider

        optionButton(
            switchingModels ? "Switching model…" : "Switch model",
            systemImage: "cpu",
            showsChevron: true,
            disabled: switchingModels
        ) { page = .models }
        optionDivider
        optionButton("Assign to", systemImage: "person", showsChevron: true) {
            page = .assignees
        }
        optionDivider
        optionButton("Rename", systemImage: "pencil", identifier: "renameSessionButton") {
            dismissThen(.rename)
        }

        if let frame = store.browserFrames[sid],
           frame.frameId == dismissedBrowserFrameID {
            optionDivider
            optionButton("Show Browser Preview", systemImage: "safari") {
                dismissThen(.restoreBrowserPreview)
            }
        }

        if canFork {
            optionDivider
            optionButton(
                forking ? "Forking…" : "Fork session",
                systemImage: "arrow.triangle.branch",
                disabled: forking
            ) {
                dismissOptions()
                Task { await forkSession() }
            }
        }

        if canTransfer {
            optionDivider
            optionButton(
                transferring ? "Moving…" : "Move to host",
                systemImage: "arrow.left.arrow.right",
                showsChevron: true,
                disabled: transferring
            ) { page = .transferTargets }
        }

        if ManualUnread.canMarkUnread(sid) {
            optionDivider
            if store.isManuallyUnread(sid) {
                optionButton("Mark as read", systemImage: "envelope.open") {
                    dismissOptions()
                    store.markRead(sid)
                }
            } else {
                optionButton("Mark as unread", systemImage: "envelope.badge") {
                    dismissOptions()
                    markUnreadAndExit()
                }
            }
        }

        if (tmuxIdentifier?.isEmpty == false) || !sid.isEmpty {
            sectionDivider("Debug — tap to copy")
        }
        if let tmuxIdentifier, !tmuxIdentifier.isEmpty {
            optionButton("tmux · \(tmuxIdentifier)", systemImage: "terminal") {
                dismissOptions()
                copyToClipboard(tmuxIdentifier)
            }
        }
        if !sid.isEmpty {
            if tmuxIdentifier?.isEmpty == false { optionDivider }
            optionButton("\(agentIdLabel) · \(sid)", systemImage: "number") {
                dismissOptions()
                copyToClipboard(sid)
            }
        }

        sectionDivider()
        optionButton("End session", systemImage: "xmark.circle", destructive: true) {
            dismissThen(.confirmEnd)
        }
    }

    @ViewBuilder
    private var childSessionOptions: some View {
        optionButton("View all", systemImage: "list.bullet") {
            dismissThen(.showChildSession(nil))
        }
        ForEach(childAgents) { child in
            optionDivider
            optionButton(child.description, systemImage: child.status.menuSystemImage) {
                dismissThen(.showChildSession(child.id))
            }
        }
    }

    @ViewBuilder
    private var modelOptions: some View {
        ForEach(Array(modelSections.enumerated()), id: \.offset) { sectionIndex, section in
            if sectionIndex > 0 { sectionDivider() }
            Text(section.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

            ForEach(Array(section.models.enumerated()), id: \.offset) { modelIndex, model in
                if modelIndex > 0 { optionDivider }
                optionButton(
                    model,
                    isSelected: agent == section.agent.rawValue && store.session(sid)?.model == model,
                    disabled: switchingModels || sid.hasPrefix("local-")
                ) {
                    dismissOptions()
                    Task {
                        let selection = AgentModelSelection(agent: section.agent, model: model)
                        if let id = await store.switchModel(sid, to: selection) {
                            store.requestSelection(id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var assigneeOptions: some View {
        optionButton("Unassigned") {
            dismissOptions()
            Task { await store.assign(sid, nil) }
        }
        ForEach(store.users, id: \.self) { user in
            optionDivider
            optionButton(user) {
                dismissOptions()
                Task { await store.assign(sid, user) }
            }
        }
    }

    @ViewBuilder
    private var transferOptions: some View {
        ForEach(Array(transferTargets.enumerated()), id: \.element.id) { index, target in
            if index > 0 { optionDivider }
            optionButton(
                target.label,
                systemImage: "desktopcomputer",
                disabled: transferring
            ) {
                dismissOptions()
                Task { await transfer(to: target) }
            }
        }
    }

    private var optionDivider: some View {
        Divider().padding(.leading, 50)
    }

    private func sectionDivider(_ title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.top, 7)
    }

    private func optionButton(
        _ title: String,
        systemImage: String? = nil,
        identifier: String? = nil,
        showsChevron: Bool = false,
        isSelected: Bool = false,
        disabled: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 24)
                } else {
                    Color.clear.frame(width: 24, height: 1)
                }

                Text(title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(disabled)
        .accessibilityIdentifier(identifier ?? "")
    }

    private var switchingModels: Bool {
        store.switchingModelSessionIds.contains(sid)
    }

    private var modelSections: [SessionHandoff.ModelSection] {
        SessionHandoff.modelSections(
            current: AgentKind(rawValue: agent) ?? .claude,
            closed: closed,
            catalog: store.modelCatalog(forSession: sid)
        )
    }

    private func dismissOptions() {
        showingOptions = false
        page = .root
    }

    private func dismissThen(_ action: DeferredAction) {
        deferredAction = action
        dismissOptions()
    }

    private func perform(_ action: DeferredAction) {
        switch action {
        case .showPhoneSignIn(let id): onShowPhoneSignIn(id)
        case .showAttachments: onShowAttachments()
        case .openTerminal: onOpenTerminal()
        case .showInversionSpike: onShowInversionSpike()
        case .showChildSession(let id): onShowChildSessions(id)
        case .rename: onRename()
        case .restoreBrowserPreview: onRestoreBrowserPreview()
        case .confirmEnd: onConfirmEnd()
        }
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
        // Ask the target first; the source is untouched until this says go.
        let check = await store.transferPreflight(sid, to: target)
        if case .behind(let seconds) = check {
            staleMove = StaleMove(target: target, behindSeconds: seconds)
            return
        }
        _ = await store.transfer(sid, to: target, preflight: check)
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

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geo in
                TranscriptWindow.newestEndTrackingValue(
                    offsetY: Double(geo.contentOffset.y)
                )
            } action: { _, atNewest in
                onChange(atNewest)
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
                    .accessibilityIdentifier("childSessionsSheet")
                } else {
                    List(agents) { child in
                        NavigationLink(value: child.id) {
                            ChildAgentSessionRow(child: child)
                        }
                        .accessibilityIdentifier("childSessionRow_\(child.id)")
                    }
                    .listStyle(.insetGrouped)
                    .accessibilityIdentifier("childSessionsSheet")
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
                    .accessibilityIdentifier("childSessionTranscript")
            } else if let errorMessage, messages.isEmpty {
                ContentUnavailableView(
                    "Transcript unavailable",
                    systemImage: "exclamationmark.bubble",
                    description: Text(errorMessage)
                )
                .accessibilityIdentifier("childSessionTranscript")
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "No transcript yet",
                    systemImage: "text.bubble",
                    description: Text("This child session has not produced visible output.")
                )
                .accessibilityIdentifier("childSessionTranscript")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages, id: \.stableID) { message in
                            TranscriptMessageView(message: message)
                        }
                    }
                    .padding()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("childSessionTranscript")
                    .accessibilityLabel("Child session transcript")
                }
            }
        }
        .navigationTitle(child.description)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: child.id) { await loadTranscriptUntilTerminal() }
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
