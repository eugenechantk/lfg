import SwiftUI
import LFGCore

// MARK: - Transcript message

struct TranscriptMessageView: View {
    let message: SessionMessage

    var body: some View {
        switch message.kind {
        case "tool_use", "tool_result":
            ToolLineView(message: message)
        case "thinking":
            ThinkingView(text: message.text)
        default:
            TextBubble(message: message)
        }
    }
}

private struct TextBubble: View {
    let message: SessionMessage
    private var isUser: Bool { message.role == "user" }
    // User bubbles render attachments as cards (incl. inline images, since the
    // bubble text isn't markdown); assistant prose keeps inline markdown images.
    private var media: [MediaRef] { MediaScanner.scan(message.text, includeInlineImages: isUser) }

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
                    }
                    // User attachments show as tappable file cards, not inline previews.
                    if !media.isEmpty { MediaAttachmentsView(refs: media, cardsOnly: true).frame(maxWidth: 280) }
                }
            }
            .padding(.vertical, 10)
        } else {
            // Assistant turns are full-width markdown — no bubble.
            VStack(alignment: .leading, spacing: 6) {
                ProseView(text: message.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !media.isEmpty { MediaAttachmentsView(refs: media) }
                if message.apiError == true {
                    Label("API error", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
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
            Label("Needs your input", systemImage: "questionmark.bubble.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.blue)
            Text(prompt.question).font(.subheadline.weight(.semibold))
            if let detail = prompt.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
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
                            if let d = option.description, !d.isEmpty {
                                Text(d).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
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
                    Task { await store.setModel(id, "opus"); working = false }
                } label: {
                    Text(working ? "Resuming…" : "Resume on Opus")
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

/// Locally-sent messages awaiting pickup, shown as small muted bars just above
/// the composer (not as transcript bubbles). Each appears the instant the user
/// sends and is removed once the agent records the real user turn — at which
/// point it surfaces as a normal user bubble in the transcript.
struct PendingStripView: View {
    let sessionID: String
    let items: [SessionStore.PendingSend]
    @Environment(SessionStore.self) private var store

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        if item.failed {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                        Text(item.displayText)
                            .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if item.failed {
                            Button("Retry") { Task { await store.retryPending(sessionID, item) } }
                                .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.4), in: Capsule())
                }
            }
        }
    }
}

/// A finished-looking user bubble for an optimistic send (no "Sending…"
/// spinner). Used for a session's kickoff message, which is already committed,
/// so it reads as sent immediately and is replaced by the real user turn on
/// reconcile.
struct OptimisticUserBubble: View {
    let sessionID: String
    let pending: SessionStore.PendingSend
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 36)
                Text(pending.displayText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .opacity(pending.failed ? 0.5 : 1)
            }
            // The happy path shows no spinner — the bubble reads as sent the
            // instant the user hits send. Only a genuine send failure surfaces
            // an affordance, since this bubble bypasses the pending bar's Retry.
            if pending.failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text("Not sent").font(.caption2).foregroundStyle(.secondary)
                    Button("Retry") { Task { await store.retryPending(sessionID, pending) } }
                        .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
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
