import SwiftUI
import LFGCore
import UIKit

struct SessionDetailView: View {
    /// The 1pt newest-edge anchor and the stack's 14pt spacing already give
    /// more than the boards' gap; `calculatedTranscriptBottomContentMargin`
    /// trims the rest.
    private static let bottomTranscriptClearance: CGFloat = 0

    private enum PresentedSheet: Identifiable {
        case attachments
        case filePreview(selected: MediaRef, rowFiles: [MediaRef])
        case phoneSignIn(requestID: String?)
        case requestedSignIn(requestID: String)
        case childSessions(selectedID: String?)
        case iPhonePreview
        /// The full result behind a tool card's "Show all N lines".
        case toolOutput(title: String, text: String)
        /// The whole plan behind the panel's "Read the full plan ›".
        case planText(String)
        /// The S2 session sheet (board `s2-menu`), from the top-right button.
        case session

        var id: String {
            switch self {
            case .phoneSignIn(let requestID): "phone-sign-in-\(requestID ?? "all")"
            case .requestedSignIn(let requestID): "sign-in-\(requestID)"
            case .attachments: "attachments"
            case .filePreview(let selected, _): "file-preview-\(selected.id)"
            case .childSessions(let selectedID): "child-sessions-\(selectedID ?? "all")"
            case .iPhonePreview: "iphone-preview"
            case .toolOutput(let title, let text): "tool-output-\(title.hashValue)-\(text.count)"
            case .planText(let text): "plan-\(text.count)"
            case .session: "session"
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
    @Environment(\.hostFiles) private var hostFiles

    @Environment(\.scenePhase) private var scenePhase
    @State private var signInRequests: [PhoneSignInAgentRequest] = []
    @State private var draft = ""
    @State private var renaming = false
    /// Tapping the (truncated) nav-bar title reveals the full one in a card below it.
    @State private var showFullTitle = false
    /// The queued-strip row whose menu is open (S2: drawn at the row).
    @State private var openStripMenuID: String?
    @State private var newTitle = ""
    @State private var confirmEnd = false
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
    /// What the session sheet asked for; runs once the sheet has dismissed.
    @State private var afterSheet: SessionSheetAction?
    @State private var continuingInLFG = false
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
    @State private var bottomContainerInset: CGFloat = 0
    @State private var frozenTranscriptBottomContentMargin: CGFloat?
    /// File-only session order used by inline attachment previews. Rebuilt only
    /// when the transcript version changes so ordinary scrolling never repeats
    /// the whole-transcript media scan.
    @State private var transcriptPreviewFiles: [MediaRef]?

    /// Structural top is the visual bottom because the transcript is inverted.
    /// A scroll-content margin keeps this boundary outside the transcript's
    /// scrollable rows while placing the newest row above the floating chrome.
    private var calculatedTranscriptBottomContentMargin: CGFloat {
        CGFloat(TranscriptWindow.bottomContentMargin(
            keyboardOcclusionHeight: Double(keyboardBottomClearance),
            bottomChromeHeight: Double(bottomChromeHeight),
            bottomSafeAreaInset: Double(windowBottomSafeAreaInset),
            bottomTranscriptClearance: Double(Self.bottomTranscriptClearance),
            bottomContainerInset: Double(bottomContainerInset)
        )) - bottomMarginTrim
    }

    /// What the anchor row + stack spacing overshoot the boards' gap by, per
    /// chrome: above the pills, above a needs-input panel, and above the strip
    /// or composer when no pill applies (measured, boards `s2-view`,
    /// `s2-question`, `s2-queued-failed`).
    private var bottomMarginTrim: CGFloat {
        if prompt != nil && !session.isExternallyOwned { return 3 }
        return hasPills ? 1.7 : 1.3
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
    private var crossProviderSwitchStatus: String? {
        guard let source = AgentKind(rawValue: session.agent),
              let target = store.switchingModelTargetsBySession[sid] else { return nil }
        return SessionHandoff.crossProviderSwitchStatus(from: source, to: target)
    }

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
            .environment(\.transcriptPreviewFiles, transcriptPreviewFiles)
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
            transcriptPreviewFiles = nil
            #if DEBUG
            if draft.isEmpty { draft = debugInitialDraft }
            #endif
            vp("open")
            store.focus(sid)
            store.loadHistory(sid)   // store-owned: not cancelled by view churn
            await store.loadBrowserFrame(sid)
        }
        .task(id: "inline-file-index-\(sid)-\(store.transcriptVersion[sid] ?? 0)") {
            let snapshot = messages
            let files = await Task.detached(priority: .utility) {
                TranscriptResourceIndex.collect(from: snapshot).files.map(\.ref)
            }.value
            guard !Task.isCancelled else { return }
            transcriptPreviewFiles = files
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
        #if DEBUG
        .task(id: sid) {
            // `LFG_S2_VIEW_FIXTURE=menu|subagents` (boards `s2-menu`,
            // `s2-subagents`): open that sheet.
            guard sid.hasPrefix("s2fx-") else { return }
            switch SessionStore.s2ViewFixtureMode {
            case "menu":
                try? await Task.sleep(for: .seconds(1))
                presentedSheet = .session
            case "subagents":
                try? await Task.sleep(for: .seconds(1))
                presentedSheet = .childSessions(selectedID: nil)
            case "files":
                try? await Task.sleep(for: .seconds(1))
                presentedSheet = .attachments
            default: break
            }
        }
        #endif
        .fullScreenCover(isPresented: $showTerminal) {
            TerminalScreen(initialHostURL: store.host(forSession: sid)?.url)
        }
        .sheet(item: $presentedSheet, onDismiss: runAfterSheet) { sheet in
            switch sheet {
            case .session:
                SessionSheet(
                    session: session,
                    sid: sid,
                    isBusy: isBusy,
                    subagentCount: childAgents.count,
                    waitingSignIns: signInRequests.filter(\.isWaiting).count,
                    messages: messages
                ) { action in
                    afterSheet = action
                    presentedSheet = nil
                }
            case .requestedSignIn(let requestID):
                PhoneSignInView(sessionID: sid, agentRequestID: requestID)
                    .presentationDetents([.large])
            case .phoneSignIn(let requestID):
                PhoneSignInRequestsSheet(sessionID: sid, initialRequestID: requestID)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .attachments:
                AttachmentsSheet(messages: messages, cwd: session.cwd)
                    // Board `s2-files`: the sheet's top sits 644pt above the bottom.
                    .presentationDetents([.height(644), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(S2.surface)
                    .presentationCornerRadius(38)
            case .filePreview(let selected, let rowFiles):
                FileViewerSheet(
                    sequence: FilePreviewSequence.forInlinePreview(
                        sessionFiles: transcriptPreviewFiles,
                        rowFiles: rowFiles,
                        selected: selected
                    ),
                    hostFiles: resolvedHostFiles
                )
            case .iPhonePreview:
                IPhonePreviewSheet(sessionID: sid)
                    .presentationDetents([.large])
            case .toolOutput(let title, let text):
                ToolOutputSheet(title: title, text: text)
                    .presentationDetents([.medium, .large])
            case .planText(let text):
                PlanTextSheet(text: text)
                    .presentationDetents([.large])
            case .childSessions(let selectedID):
                ChildAgentSessionsSheet(parentSessionID: sid, initialChildID: selectedID)
                    // Board `s2-subagents`: the sheet's top sits 644pt above the bottom.
                    .presentationDetents([.height(644), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(S2.surface)
                    .presentationCornerRadius(38)
            }
        }
        .alert("Rename session", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await store.rename(sid, newTitle) } }
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
                        // viewport instead of confining it to a bar boundary
                        // (re-checked on iOS 26.3). `ChromeFade` draws the same
                        // edge the lists use instead.
                        .scrollEdgeEffectHidden(true, for: [.top, .bottom])
                        .overlay(alignment: .top) {
                            ChromeFade(barHeight: topChromeHeight, solid: true)
                                .offset(y: -topChromeHeight)
                        }

                    // An open strip menu closes on a tap anywhere outside it.
                    if openStripMenuID != nil {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.15)) { openStripMenuID = nil }
                            }
                            .accessibilityHidden(true)
                    }

                    // This sibling intentionally still respects `.keyboard`.
                    // Its safe-area padding lifts the glass composer above the
                    // software keyboard without resizing the transcript behind it.
                    measuredBottomChrome
                        // The bottom edge effect, pinned to the composer's top so
                        // it lines up with the composer and rides up with the
                        // keyboard.
                        .background(alignment: .top) {
                            GeometryReader { proxy in
                                ChromeFade(edge: .bottom,
                                           barHeight: proxy.size.height + windowBottomSafeAreaInset,
                                           solid: true)
                                    .offset(y: -ChromeFade.tail(.bottom))
                            }
                        }
                }
                .background {
                    // The transcript extends behind the tab bar, while the
                    // composer stays above it. Measure that container inset
                    // independently of the keyboard's animated safe area.
                    GeometryReader { containerProxy in
                        Color.clear
                            .onChange(of: containerProxy.safeAreaInsets.bottom, initial: true) {
                                bottomContainerInset = containerProxy.safeAreaInsets.bottom
                            }
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
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
        VStack(spacing: 0) {
            // S2: Subagents, Files and Terminal sit above the composer as pills.
            // An unreachable host is said once, in the status line under the
            // title; the draft stays editable and the store queues the send.
            if (prompt == nil || session.isExternallyOwned) && hasPills {
            ComposerPillRow(
                agents: childAgents,
                fileCount: pillFileCount,
                // A shell needs the host; an offline one cannot connect.
                showsTerminal: !session.isExternallyOwned && !store.isOffline(sid),
                onSubagents: { presentedSheet = .childSessions(selectedID: nil) },
                onFiles: { presentedSheet = .attachments },
                onTerminal: { showTerminal = true }
            )
            .padding(.bottom, 10)
            }

            // A send the backend hasn't taken yet (queued behind a running
            // turn, offline, or failed) waits here as a one-line bar — not
            // as a transcript bubble. It becomes a blue bubble only when
            // the real user turn comes back from the host, so "queued" and
            // "received" never look the same.
            PendingStripView(sessionID: sid, items: pendingBars, agent: session.agent,
                             openMenuID: $openStripMenuID) { editable in
                draft = editable
            }
            .padding(.horizontal, 12)
            .padding(.bottom, pendingBars.isEmpty ? 0 : 6)

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
                .padding(.bottom, 8)
                .accessibilityIdentifier("phone_sign_in_request_button")
            }

            if let prompt, !session.isExternallyOwned {
                NeedsInputPanel(
                    sessionID: sid, prompt: prompt, agent: session.agent, cwd: session.cwd,
                    hostLabel: store.host(forSession: sid)?.label,
                    onSignIn: { signIn in
                        // Straight to the browser: the login sheet fetches the
                        // request by id itself, so it never needs the polled list
                        // (which lags the prompt by up to 3s) or the history sheet.
                        presentedSheet = .requestedSignIn(requestID: signIn.requestId)
                    },
                    onReadPlan: { text in presentedSheet = .planText(text) }
                )
            } else if session.isExternallyOwned {
                ExternalSessionComposerNotice(
                    ownerName: session.externalOwnerName ?? "another desktop client",
                    continuing: continuingInLFG,
                    action: continueInLFG
                )
            } else {
                MessageComposer(
                    text: $draft,
                    placeholder: composerPlaceholder,
                    sending: isMovingHost,
                    focusRequest: followupFocusRequest,
                    s2: true,
                    accessory: AnyView(ComposerModelChip(
                        sid: sid,
                        agent: session.agent,
                        closed: session.closed,
                        // The host refuses a model or effort change mid-turn.
                        locked: isBusy || prompt != nil || !pendingBars.isEmpty
                    )),
                    onStop: isBusy ? { Task { await store.interrupt(sid) } } : nil,
                    // The board's bar sits 28pt off the bottom edge, inside the
                    // home-indicator inset; above the keyboard it keeps a gap.
                    bottomPadding: composerFocused ? 8 : -6,
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
    }

    private func continueInLFG() {
        guard !continuingInLFG, !sid.isEmpty else { return }
        continuingInLFG = true
        Task {
            let newID = await store.fork(ForkRequest(sessionId: sid))
            continuingInLFG = false
            if let newID { store.requestSelection(newID) }
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
            // A length-less `safeAreaPadding` adds the system's default 16pt on
            // top of the safe area the view already respects. The S2 boards
            // measure the composer from the screen edge, so that margin only
            // applies above the keyboard. Same modifier either way (a value,
            // not a branch), so the focused field keeps its identity.
            .safeAreaPadding(.bottom, keyboardOcclusionHeight > 0 ? nil : 0)
            .onPreferenceChange(SessionBottomChromeHeightKey.self) {
                // UIWindow's inset is the stable device inset; it
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
                // 14pt between items, the boards' gap (`s2-view`).
                LazyVStack(alignment: .leading, spacing: 14) {
                    // ---- visual BOTTOM (newest) ----
                    Color.clear.frame(height: 1).id(Self.newestAnchor).flippedRow()

                    // What the model said just before asking. Held out of the
                    // transcript by Claude Code until answered, so it arrives
                    // scraped from the pane and renders as an ordinary assistant
                    // bubble immediately above the panel.
                    if let preamble = PromptPreamble.message(
                        for: prompt, sessionID: sid, transcriptTail: messages
                    ) {
                        TranscriptMessageView(
                            message: preamble,
                            onOpenFile: openInlineFile
                        )
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
                        // Newest first. Consecutive tool rows fold into one S2
                        // step (`TranscriptStepGrouper`); every other row keeps
                        // its index into `messages`, so the back-to-back
                        // user-turn rule reads the message ABOVE it as before.
                        ForEach(Self.transcriptItems(renderedMessages, from: renderedStart).reversed(), id: \.id) { item in
                            switch item.item {
                            case .message(let idx):
                                TranscriptMessageView(
                                    message: renderedMessages[idx],
                                    followsUserBubble: idx > 0 && renderedMessages[idx - 1].rendersAsUserBubble,
                                    onFollowup: { prompt in
                                        draft = FollowupDraft.adding(prompt, to: draft)
                                        followupFocusRequest += 1
                                    },
                                    onOpenFile: openInlineFile
                                )
                                .id(renderedMessages[idx].stableID)
                                .flippedRow()
                            case .steps(let group):
                                ToolStepGroupView(group: group, cwd: session.cwd, followsStep: item.followsStep) { title, text in
                                    presentedSheet = .toolOutput(title: title, text: text)
                                }
                                .id(group.id)
                                .flippedRow()
                            }
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

    /// The rendered window as S2 transcript items, with indices into the FULL
    /// message array (the grouper sees only the window, so its indices are
    /// shifted back by `start`).
    private struct IdentifiedItem: Identifiable {
        let id: String
        let item: TranscriptItem
        /// A step directly under another step (board `s2-queued`: the pair
        /// keeps the full 14pt gap between rows).
        var followsStep = false
    }

    private static func transcriptItems(_ messages: [SessionMessage], from start: Int) -> [IdentifiedItem] {
        let window = Array(messages[start...])
        var previousWasStep = false
        return TranscriptStepGrouper.items(for: window).map { item in
            switch item {
            case .message(let i):
                previousWasStep = false
                return IdentifiedItem(id: messages[start + i].stableID, item: .message(start + i))
            case .steps(let group):
                defer { previousWasStep = true }
                return IdentifiedItem(id: "steps-\(group.id)", item: .steps(group), followsStep: previousWasStep)
            }
        }
    }

    /// Inline rows live inside a lazy transcript and can be recreated while the
    /// session-wide file index refreshes. Keep sheet ownership on this stable
    /// session view so a row update cannot discard an in-flight presentation.
    /// Runs what the session sheet asked for, after it has dismissed: the
    /// terminal, an alert or another sheet cannot present over it.
    private func runAfterSheet() {
        guard let action = afterSheet else { return }
        afterSheet = nil
        switch action {
        case .rename:
            newTitle = session.title
            renaming = true
        case .terminal: showTerminal = true
        case .files: presentedSheet = .attachments
        case .subagents: presentedSheet = .childSessions(selectedID: nil)
        case .signIn: presentedSheet = .phoneSignIn(requestID: nil)
        case .browserPreview: dismissedBrowserFrameID = nil
        case .iPhonePreview: presentedSheet = .iPhonePreview
        case .confirmEnd: confirmEnd = true
        case .markedUnread: onMarkedUnread()
        }
    }

    private func openInlineFile(_ selected: MediaRef, rowFiles: [MediaRef]) {
        presentedSheet = .filePreview(selected: selected, rowFiles: rowFiles)
    }

    private var resolvedHostFiles: HostFiles? {
        var files = hostFiles
        if let cwd = session.cwd, !cwd.isEmpty { files?.cwd = cwd }
        return files
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
            SessionTitleBarContent(
                title: displayTitle,
                status: statusLineState,
                // An unsent message is "Not sent", not queued.
                queued: pendingBars.filter { !$0.failed }.count,
                hostLabel: hostLabel,
                project: SessionRowMeta.projectLabel(cwd: session.cwd, project: session.project)
            ) {
                withAnimation(.easeOut(duration: 0.18)) { showFullTitle.toggle() }
            }
        }

        sessionOptionsToolbarItem
    }

    @ToolbarContentBuilder
    private var sessionOptionsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // The system toolbar owns the button's material, placement, menu
            // transition and accessibility. Keep one visible native source;
            // layering app-owned glass above it caused sheet/menu lifecycle
            // glitches and an opaque double background.
            SessionOptionsButton { presentedSheet = .session }
                // Keep the same native 44-point toolbar footprint as Back while
                // letting the system provide the actual material and shape.
                .frame(width: 44, height: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Session")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("sessionOptionsMenu")
        }
    }

    /// Whether any pill applies: subagents, files, or a reachable shell.
    private var hasPills: Bool {
        !childAgents.isEmpty || pillFileCount > 0 || (!session.isExternallyOwned && !store.isOffline(sid))
    }

    private var pillFileCount: Int {
        #if DEBUG
        if let n = store.s2FixtureFiles(sid) { return n }
        #endif
        return transcriptPreviewFiles?.count ?? 0
    }

    /// S2 boards: "Add to this turn…" while working (`s2-view`), and "Message ·
    /// sends when Air is back" while the host is unreachable (`s2-queued-failed`).
    private var composerPlaceholder: String {
        if store.isOffline(sid) {
            return "Message · sends when \(store.host(forSession: sid)?.label ?? "the host") is back"
        }
        return isBusy ? "Add to this turn…" : "Message"
    }

    /// What the line under the title says (S2): a transient action wins, then
    /// an unreachable host, a waiting question or sign-in, an API pause, the
    /// running turn, else idle.
    private var statusLineState: SessionStatusLine.State {
        if let activity = SessionTitleActivity.resolve(
            modelSwitchStatus: crossProviderSwitchStatus,
            forking: store.isForking(sid),
            movingHost: isMovingHost,
            busy: false
        ) {
            return .activity(activity.label)
        }
        if store.isOffline(sid) {
            return .hostOffline(sinceMs: store.offlineSinceMs(sid))
        }
        if let prompt {
            return prompt.signIn != nil ? .needsSignIn(sinceMs: prompt.askedAt) : .needsInput(sinceMs: prompt.askedAt)
        }
        if session.isBlocked { return .paused(reason: session.statusReason) }
        if isBusy {
            // Same anchor as the list row (`SessionStore.turnStartedAt`).
            return .working(sinceMs: store.turnStartedAt(session))
        }
        return .idle
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

}

/// The navigation bar's principal content (S2, canvas board `s2-view`): the
/// title, and under it the session's state — "● Working · 3m 12s · Pro · lfg",
/// "● Needs input · 2m", "● Air offline · 2m" — so status lives in the top bar
/// instead of as banners in the transcript.
struct SessionTitleBarContent: View {
    let title: String
    let status: SessionStatusLine.State
    let queued: Int
    let hostLabel: String?
    let project: String?
    let onTitleTapped: () -> Void

    private static let live = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        : UIColor(red: 0x24 / 255, green: 0x8A / 255, blue: 0x3D / 255, alpha: 1) })
    private static let attention = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
        : UIColor(red: 0xC9 / 255, green: 0x34 / 255, blue: 0, alpha: 1) })
    private static let grey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA6 / 255, alpha: 1)
        : UIColor(red: 0x6C / 255, green: 0x6C / 255, blue: 0x70 / 255, alpha: 1) })

    var body: some View {
        VStack(spacing: 3) {
            // Titles are whole sentences, so keep the bar to one line and let
            // SessionDetailView reveal the full title when this is tapped.
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(S2.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTitleTapped)
                .accessibilityIdentifier("sessionTitle")
                .accessibilityHint("Shows the full session title")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let line = SessionStatusLine.resolve(status, queued: queued, host: hostLabel, project: project,
                                                     nowMs: context.date.timeIntervalSince1970 * 1_000)
                statusRow(line)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    private func statusRow(_ line: SessionStatusLine) -> some View {
        HStack(spacing: 6) {
            if line.tone != .none {
                let tint = line.tone == .live ? Self.live : Self.attention
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .background(Circle().fill(tint.opacity(0.25)).frame(width: 13, height: 13)
                                    .opacity(line.tone == .live ? 1 : 0))
                if let label = line.label {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityIdentifier("sessionStatusLabel")
                }
            }
            if !line.detail.isEmpty {
                Text(line.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Self.grey)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sessionStatusLine")
    }
}

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

/// The top bar's session button (board `s2-view`: the tools glyph). It opens
/// the S2 session sheet; the old pull-down menu's actions all live there now.
private struct SessionOptionsButton: UIViewRepresentable {
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    /// The board's tools glyph (`s2-view`): two sliders, drawn from its SVG
    /// (24-unit box, 1.9 stroke) at 20pt as a template image.
    static let toolsGlyph: UIImage = {
        let size: CGFloat = 20, k = size / 24
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let path = UIBezierPath()
            for (x0, x1, y) in [(4.0, 13.0, 7.0), (17.0, 20.0, 7.0), (4.0, 7.0, 17.0), (11.0, 20.0, 17.0)] {
                path.move(to: CGPoint(x: x0 * k, y: y * k))
                path.addLine(to: CGPoint(x: x1 * k, y: y * k))
            }
            for (cx, cy) in [(15.0, 7.0), (9.0, 17.0)] {
                path.append(UIBezierPath(arcCenter: CGPoint(x: cx * k, y: cy * k), radius: 2.2 * k,
                                         startAngle: 0, endAngle: .pi * 2, clockwise: true))
            }
            path.lineWidth = 1.9 * k
            path.lineCapStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Self.toolsGlyph, for: .normal)
        button.tintColor = .label
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.isAccessibilityElement = true
        button.accessibilityLabel = "Session"
        button.accessibilityIdentifier = "sessionOptionsMenu"
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            Task { @MainActor in coordinator?.onTap() }
        }, for: .primaryActionTriggered)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onTap = onTap
    }

    @MainActor
    final class Coordinator {
        var onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }
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
/// A live transcript whose writer belongs to another desktop frontend. Reading
/// remains live; continuing creates a lineage-preserving LFG branch instead of
/// racing the owner's writer lock or interrupting the desktop app.
struct ExternalSessionComposerNotice: View {
    let ownerName: String
    let continuing: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("Open in \(ownerName). You can read it here; continuing creates an LFG branch from the latest saved turn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: action) {
                HStack(spacing: 7) {
                    if continuing { ProgressView().controlSize(.small) }
                    Text(continuing ? "Continuing…" : "Continue in LFG")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(continuing)
            .accessibilityIdentifier("continue_external_session")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

/// The pills above the composer (S2, board `s2-view`): Subagents with a ring,
/// Files with a count, Terminal. Scrolls sideways when they do not fit.
private struct ComposerPillRow: View {
    let agents: [ChildAgentSession]
    let fileCount: Int
    let showsTerminal: Bool
    let onSubagents: () -> Void
    let onFiles: () -> Void
    let onTerminal: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                let pill = SubagentPill(agents: agents)
                if !pill.isEmpty {
                    Button(action: onSubagents) {
                        HStack(spacing: 8) {
                            SubagentRing(done: pill.doneFraction, failed: pill.failedFraction)
                            Text("Subagents")
                            if let running = pill.running {
                                Text(running).foregroundStyle(S2.live)
                            }
                            Text(pill.progress).foregroundStyle(S2.metaInk)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 12)
                        .modifier(ComposerPillChrome())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(pill.accessibilityLabel)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("composerPill.subagents")
                }
                if fileCount > 0 {
                    Button(action: onFiles) {
                        HStack(spacing: 6) {
                            StepGlyph(kind: .doc, lineWidth: 1.9).frame(width: 15, height: 15)
                            Text("Files")
                            Text("\(fileCount)").foregroundStyle(S2.metaInk)
                        }
                        .padding(.horizontal, 12)
                        .modifier(ComposerPillChrome())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("composerPill.files")
                }
                if showsTerminal {
                    Button(action: onTerminal) {
                        HStack(spacing: 6) {
                            StepGlyph(kind: .terminal, lineWidth: 1.9).frame(width: 15, height: 15)
                            Text("Terminal")
                        }
                        .padding(.horizontal, 12)
                        .modifier(ComposerPillChrome())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("composerPill.terminal")
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        // Board `s2-view`: the row clips 12pt from each side, in line with the
        // composer, not at the screen edge.
        .padding(.horizontal, 12)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

private struct ComposerPillChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(S2.ink)
            .frame(height: 36)
            .background(S2.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(S2.surfaceBorder, lineWidth: 0.5))
            .contentShape(Capsule())
    }
}

/// Done work in green, failed in red, the rest (still running) as the track.
private struct SubagentRing: View {
    let done: Double
    let failed: Double

    var body: some View {
        // A small gap keeps the red arc visibly separate from the green one.
        let gap = done > 0 && failed > 0 ? 0.07 : 0
        ZStack {
            Circle().stroke(S2.ringTrack, lineWidth: 3)
            if done > 0 {
                Circle().trim(from: 0, to: done)
                    .stroke(S2.live, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if failed > 0 {
                Circle().trim(from: done + gap, to: min(1, done + failed))
                    .stroke(S2.failed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 16, height: 16)
        .frame(width: 22, height: 22)
    }
}

/// The composer's model chip, "Opus 5.5 · High" (S2, board `s2-view`). It opens
/// the model and effort pickers. While the agent works or asks, the host refuses
/// a change, so the menu says so and its items are disabled.
private struct ComposerModelChip: View {
    let sid: String
    let agent: String
    let closed: Bool
    let locked: Bool
    @Environment(SessionStore.self) private var store

    var body: some View {
        let session = store.session(sid)
        let switching = store.switchingModelSessionIds.contains(sid)
        let changing = store.changingEffortSessionIds.contains(sid)
        let kind = AgentKind(rawValue: agent) ?? .claude
        let unavailable = locked || switching || sid.hasPrefix("local-")
        let sections = SessionHandoff.modelSections(current: kind, closed: closed,
                                                    catalog: store.modelCatalog(forSession: sid))
        let efforts = closed ? [] : store.modelCatalog(forSession: sid).efforts(for: kind, model: session?.model)
        Menu {
            if locked {
                Text("Change the model when this turn ends")
            }
            ForEach(sections.indices, id: \.self) { i in
                let section = sections[i]
                Section(section.title) {
                    ForEach(section.models, id: \.self) { model in
                        let isCurrent = agent == section.agent.rawValue && session?.model == model
                        Button {
                            Task {
                                if let id = await store.switchModel(sid, to: AgentModelSelection(agent: section.agent, model: model)) {
                                    store.requestSelection(id)
                                }
                            }
                        } label: {
                            if isCurrent {
                                Label(ModelChipLabel.model(model), systemImage: "checkmark")
                            } else {
                                Text(ModelChipLabel.model(model))
                            }
                        }
                        .disabled(unavailable)
                    }
                }
            }
            if !efforts.isEmpty {
                Section(changing ? "Changing effort…" : "Effort") {
                    ForEach(efforts, id: \.self) { level in
                        Button {
                            Task { await store.setEffort(sid, to: level) }
                        } label: {
                            if session?.effort == level {
                                Label(SessionEffort.displayName(level), systemImage: "checkmark")
                            } else {
                                Text(SessionEffort.displayName(level))
                            }
                        }
                        .disabled(unavailable || changing)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(switching ? "Switching…" : ModelChipLabel.text(model: session?.model, effort: session?.effort))
                    .lineLimit(1)
                BoardGlyph(kind: .chevronDown, lineWidth: 3).frame(width: 9, height: 9)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(S2.chipInk)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(S2.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityIdentifier("composer.modelChip")
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
            // Board `s2-subagents`: a title with the tally, then one row per
            // subagent; a row opens its transcript.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.leading, 20)
                        .padding(.trailing, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 22)
                    if agents.isEmpty {
                        Text("This session has not started a subagent.")
                            .font(.system(size: 15))
                            .foregroundStyle(S2.secondaryInk)
                            .padding(.horizontal, 20)
                    } else {
                        let now = Date().timeIntervalSince1970 * 1_000
                        ForEach(agents) { child in
                            NavigationLink(value: child.id) {
                                SubagentRowView(row: SubagentRow(child, nowMs: now))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("childSessionRow_\(child.id)")
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // A NavigationStack paints its own background over the sheet's.
            .background(S2.surface.ignoresSafeArea())
            .accessibilityIdentifier("childSessionsSheet")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { childID in
                if let child = agents.first(where: { $0.id == childID }) {
                    ChildAgentTranscriptView(parentSessionID: parentSessionID, child: child)
                } else {
                    ContentUnavailableView("Child session unavailable", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        }
        .task { await store.refreshChildAgents(parentSessionID) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Subagents")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(S2.white)
                    .cssLineBox(size: 22, lineHeight: 28)
                let summary = SubagentPill(agents: agents).sheetSummary
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(S2.secondaryInk)
                        .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
                SheetGlyph(kind: .close)
                    .stroke(SessionSheet.chromeInk, style: StrokeStyle(lineWidth: 2.8 * 14 / 24, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(S2.chip))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("childSessionsDoneButton")
        }
    }
}

/// One subagent (board `s2-subagents`): status mark, task, "Running" or the
/// result, then "general-purpose · 1m 12s", and a chevron to its transcript.
private struct SubagentRowView: View {
    let row: SubagentRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            mark
                .frame(width: 22, alignment: .center)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 17))
                        .foregroundStyle(S2.white)
                        .lineLimit(1)
                        .cssLineBox(size: 17, lineHeight: 22)
                    Text(row.line)
                        .font(.system(size: 15))
                        .foregroundStyle(lineColor)
                        .lineLimit(1)
                        .cssLineBox(size: 15, lineHeight: 20)
                    Text(row.meta)
                        .font(.system(size: 13))
                        .foregroundStyle(S2.secondaryInk)
                        .lineLimit(1)
                        .cssLineBox(size: 13, lineHeight: 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BoardGlyph(kind: .chevronRight, lineWidth: 2.8)
                    .foregroundStyle(SessionSheet.chevronInk)
                    .frame(width: 12, height: 12)
            }
            .padding(.top, 11)
            .padding(.bottom, 12)
            .padding(.trailing, 16)
            .overlay(alignment: .bottom) {
                // Board: `border-bottom: 0.5px solid #38383A`.
                Rectangle().fill(S2.surfaceBorder).frame(height: 0.5)
            }
        }
        .padding(.leading, 20)
        .frame(height: 88, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var lineColor: Color {
        switch row.tone {
        case .live: return S2.live
        case .result: return S2.chipInk
        case .failed: return S2.failed
        case .secondary: return S2.secondaryInk
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch row.mark {
        case .running:
            Circle()
                .fill(S2.live)
                .frame(width: 9, height: 9)
                .background(Circle().fill(S2.live.opacity(0.25)).frame(width: 15, height: 15))
                .padding(.top, 17)
        case .done:
            SubagentMarkGlyph(failed: false)
                .stroke(S2.live, style: StrokeStyle(lineWidth: 2.4 * 17 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 17, height: 17)
                .padding(.top, 14)
        case .failed:
            SubagentMarkGlyph(failed: true)
                .stroke(S2.failed, style: StrokeStyle(lineWidth: 2.4 * 17 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 17, height: 17)
                .padding(.top, 14)
        case .stopped:
            Circle()
                .stroke(S2.secondaryInk, lineWidth: 2.4 * 17 / 24)
                .frame(width: 15, height: 15)
                .padding(.top, 15)
        }
    }
}

/// A done check or a failed cross in a circle (board SVGs, 24-unit box).
private struct SubagentMarkGlyph: Shape {
    let failed: Bool

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path(ellipseIn: CGRect(x: rect.minX + 3 * k, y: rect.minY + 3 * k, width: 18 * k, height: 18 * k))
        if failed {
            path.move(to: p(9, 9)); path.addLine(to: p(15, 15))
            path.move(to: p(15, 9)); path.addLine(to: p(9, 15))
        } else {
            path.move(to: p(8, 12.5)); path.addLine(to: p(10.8, 15.3)); path.addLine(to: p(16.5, 9.5))
        }
        return path
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
