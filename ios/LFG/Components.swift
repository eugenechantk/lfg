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
    private var media: [MediaRef] { MediaScanner.scan(message.text, includeInlineImages: true) }

    var body: some View {
        if isUser {
            // User turns stay as a trailing bubble, with extra breathing room
            // above and below to separate them from surrounding assistant content.
            HStack {
                Spacer(minLength: 36)
                VStack(alignment: .trailing, spacing: 6) {
                    if !displayText.isEmpty {
                        Text(displayText)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                            // Tap the bubble to reveal the sent time; tap again to hide.
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) { showTimestamp.toggle() }
                            }
                    }
                    // User attachments show as tappable file cards, not inline previews.
                    if !media.isEmpty { MediaAttachmentsView(refs: media, cardsOnly: true).frame(maxWidth: 280) }
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
    private var prose: String {
        var t = message.text
        for ref in media where ref.kind == .image {
            let escaped = NSRegularExpression.escapedPattern(for: ref.raw)
            if let re = try? NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\(\\s*" + escaped + "\\s*\\)") {
                t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For user bubbles, hide attachment references (shown as cards below):
    /// strips the surrounding markdown link/image, then any bare leftover path.
    private var displayText: String {
        var t = message.text
        for ref in media {
            let escaped = NSRegularExpression.escapedPattern(for: ref.raw)
            if let re = try? NSRegularExpression(pattern: "!?\\[[^\\]]*\\]\\(\\s*" + escaped + "\\s*\\)") {
                t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
            }
            t = t.replacingOccurrences(of: ref.raw, with: "")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Collapsible reasoning block, collapsed by default.
struct ThinkingView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                    Text("Thinking")
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolLineView: View {
    let message: SessionMessage
    @State private var expanded = false

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
    @Environment(SessionStore.self) private var store
    @State private var answering: Int?

    var body: some View {
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
            // The model's explanation, written right before it asked. It isn't in
            // the transcript yet while the question is live (Claude flushes that
            // turn only after it's answered), so the panel is the only place the
            // user can read the context needed to choose.
            if let context = prompt.context, !context.isEmpty {
                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    private var detail: String {
        if session.statusReason == "out_of_credits" {
            return "This session's agent ran out of AI credits. Top up to resume."
        }
        return (session.statusDetail ?? "The selected model isn't available.")
             + " Switch to a working model to continue."
    }
}

// MARK: - Optimistic outbound message

/// A finished-looking user bubble for an optimistic send (no "Sending…"
/// spinner). Every send gets one — kickoff, follow-up, or a message queued
/// behind a running turn — so what you typed joins the conversation the moment
/// you send it, and is replaced by the real user turn on reconcile. The states
/// that aren't "delivered" are captions under the bubble, not a different
/// widget somewhere else on screen.
struct OptimisticUserBubble: View {
    let sessionID: String
    let pending: SessionStore.PendingSend
    /// Opens the remove / edit / send-now sheet for a message still waiting on
    /// the current turn. Nil where that isn't offered.
    var onManage: (() -> Void)? = nil
    @Environment(SessionStore.self) private var store

    // Awaiting the backend: a wake-up send to a reaped session that's still
    // resuming server-side. Render muted/gray until it's confirmed (then blue).
    private var awaitingResume: Bool { !pending.confirmed && !pending.failed && !pending.queuedOffline }
    private var mutedBubble: Bool { awaitingResume || pending.queuedOffline }

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
            // instant the user hits send. A wake-up send shows a quiet "Waking…"
            // note while the session resumes; a genuine failure surfaces Retry
            // (this bubble bypasses the pending bar's own Retry).
            if pending.queuedOffline {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    Text("Will send when reachable").font(.caption2).foregroundStyle(.secondary)
                }
            } else if awaitingResume {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Waking session…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if pending.failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text("Not sent").font(.caption2).foregroundStyle(.secondary)
                    Button("Retry") { Task { await store.retryPending(sessionID, pending) } }
                        .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
                }
            } else if pending.queuedBehindTurn {
                // Sent, accepted, waiting on the turn in progress. The caption
                // carries what the old pending bar said, and the same tap —
                // remove / edit / send-now — without moving the message out of
                // the conversation to say it.
                HStack(spacing: 5) {
                    Text("Queued").font(.caption2).foregroundStyle(.secondary)
                    if onManage != nil {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onManage?() }
                .accessibilityIdentifier("queuedBubbleManage")
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
