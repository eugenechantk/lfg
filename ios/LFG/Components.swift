import SwiftUI
import LFGCore

// MARK: - Transcript message

struct TranscriptMessageView: View {
    let message: SessionMessage
    /// True when the entry directly above also rendered as a user bubble — the
    /// bubble then drops its top padding so stacked user turns read as one run
    /// instead of being separated by a double gap.
    var followsUserBubble: Bool = false

    var body: some View {
        switch message.kind {
        case "tool_use", "tool_result":
            ToolLineView(message: message)
        case "thinking":
            ThinkingView(text: message.text)
        case "system_notice":
            SystemNoticeView(text: message.text)
        case "memory_citation":
            MemoryCitationView(text: message.text)
        default:
            TextBubble(message: message, followsUserBubble: followsUserBubble)
        }
    }
}

extension SessionMessage {
    /// Whether this message renders as a trailing user bubble (`TextBubble`'s
    /// user branch) — tool lines and thinking blocks carry role "user" too.
    public var rendersAsUserBubble: Bool {
        role == "user" && kind != "tool_use" && kind != "tool_result" && kind != "thinking"
    }
}

/// Memoises `TranscriptRowText.derive` by stable id.
///
/// The derivation is pure but not cheap (a media scan plus an `NSRegularExpression`
/// compiled per ref), and it used to run inside `TextBubble.body` — i.e. for
/// every visible row on every SwiftUI update, which Phase-1 finding 1 showed is
/// once per scroll frame. Rows are immutable once delivered (the client never
/// rewrites a message's text), so a plain id-keyed memo is safe.
@MainActor
private enum TranscriptRowTextCache {
    private static var entries: [String: TranscriptRowText] = [:]
    /// Bounded so a 5,000-message transcript cannot pin unbounded strings; the
    /// working set is the render window, far below this.
    private static let capacity = 1_200

    static func text(for message: SessionMessage) -> TranscriptRowText {
        let key = message.stableID
        if let hit = entries[key] { return hit }
        let derived = TranscriptRowText.derive(from: message.text)
        if entries.count >= capacity { entries.removeAll(keepingCapacity: true) }
        entries[key] = derived
        return derived
    }
}

private struct TextBubble: View {
    let message: SessionMessage
    var followsUserBubble: Bool = false
    /// Sent time is hidden by default and toggled by tapping the bubble.
    @State private var showTimestamp = false
    private var isUser: Bool { message.role == "user" }
    // Always surface inline images as refs so they render as compact, tappable
    // file cards (below) rather than full-width inline previews — for both user
    // bubbles and assistant prose. Keeps long, screenshot-heavy transcripts
    // scannable instead of a wall of images.
    private var rowText: TranscriptRowText { TranscriptRowTextCache.text(for: message) }
    private var media: [MediaRef] { rowText.media }

    var body: some View {
        if isUser {
            // User turns stay as a trailing bubble, with extra breathing room
            // above and below to separate them from surrounding assistant content.
            HStack {
                Spacer(minLength: 36)
                VStack(alignment: .trailing, spacing: 6) {
                    if !displayText.isEmpty {
                        // Native text view: long-press for the cursor, drag to
                        // highlight, system Copy — in place. The tap that
                        // reveals the sent time comes back through `onTap`
                        // because the text view sees touches first.
                        SelectableProseView(plain: displayText, palette: .onAccent, hugsContent: true) {
                            withAnimation(.easeInOut(duration: 0.15)) { showTimestamp.toggle() }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    // Narrower than assistant attachments so the cards read as
                    // part of the trailing bubble run.
                    if !media.isEmpty { MediaAttachmentsView(refs: media).frame(maxWidth: 280) }
                    // Sent-time caption — only while toggled on.
                    if showTimestamp, let sentAt = timestampText {
                        Text(sentAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.top, followsUserBubble ? 0 : 10)
            .padding(.bottom, 10)
        } else {
            // Assistant turns are full-width markdown — no bubble.
            VStack(alignment: .leading, spacing: 6) {
                // MarkdownUI layout; each paragraph / table cell / code block
                // is a native text view (see `Theme.lfgFlat`), so a long-press
                // selects in place, scoped to that block.
                ProseView(text: prose)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !media.isEmpty { MediaAttachmentsView(refs: media) }
                if message.apiError == true {
                    Label("API error", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    /// Human-readable send time for the user bubble caption. `ts` is epoch
    /// milliseconds; show the time of day, prefixed with the date when it isn't today.
    private var timestampText: String? {
        guard let ts = message.ts, ts > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ts / 1000)
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Assistant prose with inline image markdown removed — each image now shows
    /// as a compact file card below, so leaving `![alt](path)` in the markdown
    /// would double-render it full-width. Links and all other text are untouched
    /// (links stay tappable inline AND get a card, as before).
    private var prose: String { rowText.prose }

    /// For user bubbles, hide attachment references (shown as cards below):
    /// strips the surrounding markdown link/image, then any bare leftover path.
    private var displayText: String { rowText.displayText }
}

/// Collapsible reasoning block, collapsed by default.
struct ThinkingView: View {
    let text: String
    @State private var expanded = false
    private var presentation: TranscriptThinkingPresentation {
        .resolve(text: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if presentation.isDisclosure {
                Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                    header(showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("thinkingDisclosure")
            } else {
                header(showsDisclosure: false)
                    .accessibilityIdentifier("compactingConversationIndicator")
            }

            if expanded, let detail = presentation.detail {
                Text(detail)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(showsDisclosure: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "brain")
            Text(presentation.title)
            if showsDisclosure {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

/// Provider-owned transcript activity such as a local slash command or model
/// switch. It shares the quiet, full-width visual language of `ThinkingView`
/// so it reads as session state rather than something the human sent.
private struct SystemNoticeView: View {
    let text: String
    private var presentation: TranscriptSystemNoticePresentation {
        .resolve(text: text)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal")
            Text(presentation.text)
                .lineLimit(nil)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("systemTranscriptNotice")
    }
}

private struct MemoryCitationView: View {
    let text: String
    @State private var expanded = false
    private var presentation: TranscriptMemoryCitationPresentation {
        .resolve(text: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "books.vertical")
                    Text(presentation.title)
                    Text("· \(presentation.summary)")
                        .foregroundStyle(.tertiary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("memoryCitationDisclosure")

            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(presentation.citations.enumerated()), id: \.offset) { _, citation in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(citation.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !citation.location.isEmpty {
                                Text(citation.location)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if presentation.priorSessionCount > 0 {
                        Text("\(presentation.priorSessionCount) prior sessions")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier("memoryCitationDetails")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("memoryCitationNotice")
    }
}

private struct ToolLineView: View {
    let message: SessionMessage
    @State private var expanded = false
    /// Roughly three lines of caption-monospaced text plus slack.
    private static let collapsedMaxHeight: CGFloat = 64

    private var content: String { message.text.isEmpty ? message.kind : message.text }
    private var isUse: Bool { message.kind == "tool_use" }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isUse ? "wrench.and.screwdriver" : "arrow.turn.down.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text(content)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // A collapsed tool row must not be able to grow unbounded.
                    // `lineLimit` alone does not cap it: one measured row was
                    // 2,858pt tall, which `LazyVStack` must place on every
                    // scroll update. Expanding is still one tap away.
                    .frame(maxHeight: expanded ? nil : Self.collapsedMaxHeight,
                           alignment: .top)
                    .clipped()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Interactive prompt panel

struct PromptPanelView: View {
    let sessionID: String
    let prompt: AgentPrompt
    /// Opens the phone sign-in sheet for a request id. Only used when
    /// `prompt.signIn` is set; the detail view owns the sheet.
    var onSignIn: ((PromptSignIn) -> Void)? = nil
    @Environment(SessionStore.self) private var store
    @State private var answering: Int?

    var body: some View {
        if let signIn = prompt.signIn {
            signInPanel(signIn)
        } else {
            questionPanel
        }
    }

    /// An agent-requested phone sign-in. Same chrome as a question so the
    /// session reads "needs input" the same way, but the one action is opening
    /// the sign-in sheet — there are no numbered answers to type into the pane,
    /// and no Dismiss: Escape would interrupt the agent's waiting command.
    /// Cancelling lives in the sheet, which cancels the request server-side.
    private func signInPanel(_ signIn: PromptSignIn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label("Needs your input", systemImage: "key.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                Text((prompt.header ?? "Sign in").uppercased())
                    .font(.caption2.weight(.bold)).foregroundStyle(.blue)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.blue.opacity(0.15), in: Capsule())
            }
            Text(prompt.question)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let target = signIn.targetName, !target.isEmpty {
                Text("The login is sent to \(target) on your Mac. The agent is waiting.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                onSignIn?(signIn)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "iphone")
                        .font(.subheadline)
                        .frame(width: 22, height: 22)
                        .background(.blue.opacity(0.15), in: Circle())
                    Text("Sign in to \(signIn.website)")
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prompt_sign_in_\(signIn.requestId)")
        }
        .padding(14)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.blue.opacity(0.25)))
    }

    private var questionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label("Needs your input", systemImage: "questionmark.bubble.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                if let header = prompt.header, !header.isEmpty {
                    Text(header.uppercased())
                        .font(.caption2.weight(.bold)).foregroundStyle(.blue)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
            }
            // NOTE: `prompt.context` — the model's explanation, written right
            // before it asked — is deliberately NOT rendered here. It is the
            // model answering, so it renders as a normal assistant bubble
            // immediately above this panel (see `PromptPreamble`), where it gets
            // markdown, real typography, and reads as part of the conversation
            // instead of as a caption on a form. Re-adding it here would show it
            // twice.
            Text(prompt.question)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = prompt.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if prompt.multiSelect == true {
                Text("Multiple answers allowed — tap the one to send back")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            ForEach(prompt.options) { option in
                Button {
                    answering = option.index
                    Task { await store.answer(sessionID, option.index); answering = nil }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(option.index)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(.blue.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            if let d = option.description, !d.isEmpty {
                                Text(d).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if option.selected == true {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.blue)
                        }
                        if answering == option.index { ProgressView().controlSize(.small) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(answering != nil)
            }
            Button("Dismiss") { Task { await store.dismissPrompt(sessionID) } }
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.blue.opacity(0.25)))
    }
}

// MARK: - Paused banner

struct PausedBannerView: View {
    let session: Session
    @Environment(SessionStore.self) private var store
    @State private var working = false

    private var canSwitchToOpus: Bool {
        session.statusReason == "model_unavailable" && session.isClaude && session.hasPane
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "pause.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if canSwitchToOpus, let id = session.sessionId {
                Button {
                    working = true
                    Task { await store.setModel(id, "claude-opus-5"); working = false }
                } label: {
                    Text(working ? "Resuming…" : "Resume on Opus 5")
                }
                .buttonStyle(.borderedProminent).controlSize(.small).tint(.orange)
                .disabled(working)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var title: String {
        session.statusReason == "out_of_credits" ? "Build paused — out of credits" : "Build paused"
    }
    /// The server's `statusDetail` is the agent's own sentence and wins when
    /// present: for a codex usage limit it carries the reset time ("try again
    /// at 9:00 PM"), which a generic "top up" line would hide. The model-switch
    /// hint is only true advice for `model_unavailable`.
    private var detail: String {
        let hint = session.statusReason == "model_unavailable"
            ? " Switch to a working model to continue." : ""
        if let text = session.statusDetail, !text.isEmpty { return text + hint }
        if session.statusReason == "out_of_credits" {
            return "This session's agent ran out of AI credits. Top up to resume."
        }
        return "The selected model isn't available." + hint
    }
}

// MARK: - Optimistic outbound message

/// Locally-sent messages awaiting pickup, shown as small muted bars just above
/// the composer (not as transcript bubbles). Each appears the instant the user
/// sends and is removed once the agent records the real user turn — at which
/// point it surfaces as a normal user bubble in the transcript.
///
/// This is deliberately NOT a bubble: a message the backend hasn't taken yet
/// hasn't joined the conversation, and showing it in the accent color next to
/// delivered messages makes "queued behind a running turn" and "the agent has
/// it" look identical. The bar is the waiting room; the blue bubble means
/// received.
struct PendingStripView: View {
    let sessionID: String
    let items: [SessionStore.PendingSend]
    /// Tapping an in-flight (not-failed) message surfaces remove / edit / send-now.
    var onTap: (SessionStore.PendingSend) -> Void = { _ in }
    @Environment(SessionStore.self) private var store

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        if item.queuedOffline {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                        } else if item.failed {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                        Text(item.displayText)
                            .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if item.queuedOffline {
                            // An offline-queued message is waiting on the phone,
                            // not on the host — but the user still needs to be
                            // able to force it through or take it back, same as
                            // any server-tracked send. Carry the same
                            // ellipsis affordance so the row reads as tappable.
                            Text("Queued")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: "ellipsis.circle").font(.caption).foregroundStyle(.tertiary)
                        } else if item.failed {
                            Button("Retry") { Task { await store.retryPending(sessionID, item) } }
                                .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
                        } else if item.queuedForResume {
                            // Waking a closed session. Labelled the same as any
                            // other queued message on purpose — from here it is
                            // one: the host has it, nothing has run it yet. It
                            // stays this way until the reopened session's
                            // transcript carries the turn, at which point it
                            // becomes a real accent bubble.
                            Text("Queued")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: "ellipsis.circle").font(.caption).foregroundStyle(.tertiary)
                        } else {
                            // Affordance hint that the queued message is tappable.
                            Image(systemName: "ellipsis.circle").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.4), in: Capsule())
                    .contentShape(Capsule())
                    .accessibilityIdentifier(
                        item.queuedForResume ? "pendingStripRowResuming" : "pendingStripRow")
                    // Failed rows carry their own inline Retry button, so a tap
                    // there would compete with it; everything else opens the menu.
                    .onTapGesture { if !item.failed { onTap(item) } }
                }
            }
        }
    }
}

/// A finished-looking user bubble for an optimistic send (no "Sending…"
/// spinner). Used for sends the agent takes immediately — a session's kickoff
/// message and a follow-up typed while the session is idle — so they read as
/// sent right away and are replaced by the real user turn on reconcile. A send
/// that is waiting on a running turn is NOT one of these; it lives in
/// `PendingStripView` until the backend has actually taken it.
struct OptimisticUserBubble: View {
    let sessionID: String
    let pending: SessionStore.PendingSend
    @Environment(SessionStore.self) private var store

    // Defensive: a bubble the backend hasn't confirmed renders muted rather than
    // accent, so the invariant ("accent means the conversation has it") holds
    // even if a future path routes an unconfirmed send here. The states that
    // actually wait — behind a running turn, waking a closed session, offline —
    // are all `showSent == false` and live in `PendingStripView` instead.
    private var awaitingBackend: Bool { !pending.confirmed && !pending.failed && !pending.queuedOffline }
    private var mutedBubble: Bool { awaitingBackend || pending.queuedOffline }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 36)
                Text(pending.displayText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mutedBubble ? Color(.secondarySystemFill) : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(mutedBubble ? Color.primary : Color.white)
                    .opacity(pending.failed ? 0.5 : 1)
            }
            .animation(.easeInOut(duration: 0.25), value: pending.confirmed)
            // The happy path shows no spinner — the bubble reads as sent the
            // instant the user hits send. A genuine failure surfaces Retry
            // (this bubble bypasses the pending bar's own Retry).
            if pending.queuedOffline {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    Text("Will send when reachable").font(.caption2).foregroundStyle(.secondary)
                }
            } else if awaitingBackend {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Sending…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if pending.failed {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                        Text("Not sent").font(.caption2).foregroundStyle(.secondary)
                        Button("Retry") { Task { await store.retryPending(sessionID, pending) } }
                            .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
                    }
                    // "Not sent" alone leaves the user guessing. The host's own
                    // sentence ("directory not found: /Uzers/…") is usually the
                    // whole diagnosis.
                    if let reason = pending.failureReason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Outbound queue

struct QueueStripView: View {
    let sessionID: String
    let items: [QueueItem]
    @Environment(SessionStore.self) private var store

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        statusIcon(item)
                        Text(item.text).font(.caption).lineLimit(1)
                        Spacer(minLength: 0)
                        if item.isFailed {
                            Button("Retry") { Task { await store.retry(sessionID, item.id) } }
                                .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.4), in: Capsule())
                }
            }
        }
    }

    private func statusIcon(_ item: QueueItem) -> some View {
        Group {
            switch item.status {
            case "delivered": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case "failed": Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            default: ProgressView().controlSize(.mini)
            }
        }
        .font(.caption2)
    }
}

// MARK: - Usage

struct UsageView: View {
    let usage: Usage?
    var body: some View {
        if let usage, let five = usage.fiveHour?.pct {
            HStack(spacing: 10) {
                gauge("5h", five)
                if let seven = usage.sevenDay?.pct { gauge("7d", seven) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func gauge(_ label: String, _ pct: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.tertiary)
            Text("\(Int(pct))%")
        }
    }
}
