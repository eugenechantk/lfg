import SwiftUI
import LFGCore

private struct TranscriptPreviewFilesKey: EnvironmentKey {
    static let defaultValue: [MediaRef]? = nil
}

extension EnvironmentValues {
    /// Session-wide, file-only order shared by every inline transcript card.
    /// `nil` means the index is not available in this rendering context, so the
    /// card falls back to the attachments in its own message.
    var transcriptPreviewFiles: [MediaRef]? {
        get { self[TranscriptPreviewFilesKey.self] }
        set { self[TranscriptPreviewFilesKey.self] = newValue }
    }
}

// MARK: - Transcript message

struct TranscriptMessageView: View {
    let message: SessionMessage
    /// True when the entry directly above also rendered as a user bubble — the
    /// bubble then drops its top padding so stacked user turns read as one run
    /// instead of being separated by a double gap.
    var followsUserBubble: Bool = false
    var onFollowup: ((String) -> Void)? = nil
    var onOpenFile: ((MediaRef, [MediaRef]) -> Void)? = nil

    var body: some View {
        switch message.kind {
        case "tool_use", "tool_result":
            ToolLineView(message: message)
        case "thinking":
            EmptyView()
        case "system_notice":
            SystemNoticeView(text: message.text)
        case "memory_citation":
            MemoryCitationView(text: message.text)
        default:
            TextBubble(
                message: message,
                followsUserBubble: followsUserBubble,
                onFollowup: onFollowup,
                onOpenFile: onOpenFile
            )
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
        let derived = TranscriptRowText.derive(
            from: message.text,
            extractFollowups: message.role != "user"
        )
        if entries.count >= capacity { entries.removeAll(keepingCapacity: true) }
        entries[key] = derived
        return derived
    }
}

/// Offers its content at most `maxWidth` and takes the content's own size, so
/// short content hugs (unlike `.frame(maxWidth:)`, which expands to the cap).
struct CappedWidth: Layout {
    let maxWidth: CGFloat
    init(_ maxWidth: CGFloat) { self.maxWidth = maxWidth }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct TextBubble: View {
    let message: SessionMessage
    var followsUserBubble: Bool = false
    var onFollowup: ((String) -> Void)? = nil
    var onOpenFile: ((MediaRef, [MediaRef]) -> Void)? = nil
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
                        // S2 bubble (board `s2-view`): #0A6EE0, 20pt corners,
                        // at most 290pt of text. A cap on the offered width, not
                        // a `maxWidth` frame, which would stretch short bubbles.
                        CappedWidth(290) {
                            SelectableProseView(plain: displayText, palette: .onAccent, hugsContent: true) {
                                withAnimation(.easeInOut(duration: 0.15)) { showTimestamp.toggle() }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        // 9pt + the board's 22pt line + 9pt = 40; the text view's
                        // line is ~21pt, so the extra point goes above and below.
                        .padding(.horizontal, 14).padding(.vertical, 9.5)
                        .background(S2.send, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    // Narrower than assistant attachments so the cards read as
                    // part of the trailing bubble run.
                    if !media.isEmpty {
                        MediaAttachmentsView(refs: media, onOpen: onOpenFile)
                            .frame(maxWidth: 280)
                    }
                    // Sent-time caption — only while toggled on.
                    if showTimestamp, let sentAt = timestampText {
                        Text(sentAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            // Measured on boards `s2-view`, `s2-queued-failed`, `s2-signin-prompt`:
            // the next item's text starts 1.67pt lower under a bubble there.
            .padding(.bottom, 1.67)
        } else {
            // Assistant turns are full-width markdown — no bubble.
            VStack(alignment: .leading, spacing: 6) {
                // One native text view owns the whole assistant turn, so a
                // long-press selection can cross paragraphs and list items.
                if !prose.isEmpty {
                    ProseView(text: prose)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !media.isEmpty { MediaAttachmentsView(refs: media, onOpen: onOpenFile) }
                if let onFollowup, !rowText.followups.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rowText.followups.enumerated()), id: \.offset) { index, followup in
                            Button {
                                onFollowup(followup.prompt)
                            } label: {
                                Text(followup.title)
                                    .font(.body)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("followup_\(index)")
                        }
                    }
                }
                if message.apiError == true {
                    Label("API error", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            // Attachment-only turns use the compact tool-row spacing. Empty
            // prose and follow-up containers must not create extra gaps.
            .padding(.top, prose.isEmpty && !media.isEmpty ? -4 : 0)
            .padding(.bottom, prose.isEmpty && !media.isEmpty ? 2 : 0)
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

/// Provider-owned transcript activity such as a local slash command or model
/// switch. Its quiet, full-width style distinguishes it from a user message.
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
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                Image(systemName: isUse ? "wrench.and.screwdriver" : "arrow.turn.down.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text(content)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // A collapsed tool row must not be able to grow unbounded.
                    // `lineLimit` alone does not cap it: one measured row was
                    // 2,858pt tall, which `LazyVStack` must place on every
                    // scroll update. Expanding is still one tap away.
                    .frame(maxHeight: Self.collapsedMaxHeight,
                           alignment: .top)
                    .clipped()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("legacyToolDisclosure-\(message.stableID)")
            if expanded {
                ScrollableCodeBlock(text: content, fontSize: 12, foregroundColor: .secondaryLabel,
                                    accessibilityID: "legacyToolCode-\(message.stableID)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Interactive prompt panel

/// The panel docked at the bottom while the agent waits on you (S2, boards
/// `s2-question` — question, permission, plan — and `s2-signin-prompt`). It
/// takes the composer's place; the model's preamble stays in the transcript.
struct NeedsInputPanel: View {
    let sessionID: String
    let prompt: AgentPrompt
    let agent: String
    let cwd: String?
    let hostLabel: String?
    /// Opens the phone sign-in sheet for a request id (sign-in prompts only).
    var onSignIn: (PromptSignIn) -> Void = { _ in }
    /// Opens the whole plan.
    var onReadPlan: (String) -> Void = { _ in }
    @Environment(SessionStore.self) private var store
    @State private var answering: Int?
    @State private var typed = ""
    @State private var sendingTyped = false
    @FocusState private var typedFocused: Bool

    private static let tag = S2.color(dark: 0xFFB340, light: 0xC93400)
    private static let field = S2.color(dark: 0x2C2C2E, light: 0xF2F2F7)
    private static let fieldInk = S2.color(dark: 0xD1D1D6, light: 0x3A3A3C)
    private static let rule = S2.color(dark: 0x48484A, light: 0xC7C7CC)
    private static let link = S2.color(dark: 0x409CFF, light: 0x007AFF)

    private var model: NeedsInputPanelModel {
        NeedsInputPanelModel(prompt: prompt, agent: agent, cwd: cwd, host: hostLabel)
    }

    var body: some View {
        let model = model
        VStack(alignment: .leading, spacing: isSignIn(model) ? 14 : 12) {
            header(model)
            switch model.layout {
            case let .question(choices, allowsTypedAnswer):
                titleBlock(model, gap: 5)
                VStack(spacing: 8) {
                    ForEach(choices, id: \.index) { choice in optionRow(choice) }
                }
                .padding(.top, 2)
                if allowsTypedAnswer { typedAnswerField }
            case let .permission(command, place, allow, deny, always):
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(S2.white)
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollableCodeBlock(text: command, fontSize: 13, lineHeight: 18,
                                        foregroundColor: UIColor(S2.ink), maxHeight: 120,
                                        accessibilityID: "permissionCommandCodeBlock")
                        .background(S2.color(dark: 0x000000, light: 0xF2F2F7), in: RoundedRectangle(cornerRadius: 12))
                    if let place {
                        Text(place).font(.system(size: 13)).foregroundStyle(S2.secondaryInk)
                    }
                }
                pairButtons(primary: ("Allow once", allow), secondary: ("Deny", deny))
                if let always {
                    Button { answer(always.index) } label: {
                        Text(always.label)
                            .font(.system(size: 15))
                            .foregroundStyle(Self.link)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(answering != nil)
                    .accessibilityIdentifier("needsInput.always")
                }
            case let .plan(summary, fullText, approve, keepPlanning):
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(S2.white)
                    if !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(summary, id: \.self) {
                                Text($0).frame(minHeight: 21, alignment: .leading)
                            }
                        }
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(S2.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Self.field, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if !fullText.isEmpty {
                        Button { onReadPlan(fullText) } label: {
                            Text("Read the full plan ›").font(.system(size: 14)).foregroundStyle(Self.link)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("needsInput.readPlan")
                    }
                }
                pairButtons(primary: ("Approve", approve), secondary: ("Keep planning", keepPlanning))
            case let .signIn(website, target, initial):
                titleBlock(model, gap: 5, titleMinHeight: 25)
                HStack(spacing: 12) {
                    Text(initial)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(S2.ink)
                        .frame(width: 32, height: 32)
                        .background(S2.color(dark: 0x3A3A3C, light: 0xE5E5EA), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(website).font(.system(size: 16, weight: .medium)).foregroundStyle(S2.white)
                        if let target {
                            Text(target).font(.system(size: 13)).foregroundStyle(S2.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 11.8)
                .background(Self.field, in: RoundedRectangle(cornerRadius: 14))
                if let signIn = prompt.signIn {
                    Button { onSignIn(signIn) } label: {
                        HStack(spacing: 8) {
                            BoardGlyph(kind: .key).frame(width: 17, height: 17)
                            Text("Sign in on iPhone").font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(S2.send, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("prompt_sign_in_\(signIn.requestId)")
                }
                Text("There is no Dismiss here. The agent stays paused on this step until the sign-in arrives.")
                    .font(.system(size: 13))
                    .lineSpacing(2.5)
                    .foregroundStyle(S2.metaInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 1.7)
                    .padding(.bottom, 2.7)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 26, trailing: 16))
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(S2.surface)
                .shadow(color: .black.opacity(0.4), radius: 15, y: -2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(S2.color(dark: 0x38383A, light: 0xD1D1D6), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
        // The board docks the panel 8pt off the screen's bottom edge, inside
        // the home-indicator inset; above the keyboard it keeps a gap instead.
        .padding(.bottom, typedFocused ? 8 : -26)
        .accessibilityIdentifier("needsInputPanel")
    }

    private func isSignIn(_ model: NeedsInputPanelModel) -> Bool {
        if case .signIn = model.layout { return true } else { return false }
    }

    private func header(_ model: NeedsInputPanelModel) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(S2.attention)
                .frame(width: 8, height: 8)
                .background(Circle().fill(S2.attention.opacity(0.28)).frame(width: 14, height: 14))
            Text(model.label.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Self.tag)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.canDismiss {
                Button { Task { await store.dismissPrompt(sessionID) } } label: {
                    Text("Dismiss")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Self.fieldInk)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Self.field, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("needsInput.dismiss")
            }
        }
    }

    private func titleBlock(_ model: NeedsInputPanelModel, gap: CGFloat = 4,
                            titleMinHeight: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            Text(model.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(S2.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: titleMinHeight, alignment: .leading)
            if let body = model.body {
                Text(body)
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(Self.fieldInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func optionRow(_ choice: NeedsInputPanelModel.Choice) -> some View {
        Button { answer(choice.index) } label: {
            HStack(spacing: 12) {
                Text("\(choice.index)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.fieldInk)
                    .frame(width: 24, height: 24)
                    .background(Self.field, in: Circle())
                Text(choice.label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(S2.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if answering == choice.index { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Self.field, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(answering != nil)
        .accessibilityIdentifier("needsInput.option.\(choice.index)")
    }

    private var typedAnswerField: some View {
        let canSend = !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sendingTyped
        return HStack(spacing: 8) {
            TextField(text: $typed, prompt: Text("Type something else…").foregroundStyle(S2.metaInk)) {
                Text("Type something else…")
            }
            .font(.system(size: 16))
            .foregroundStyle(S2.ink)
            .submitLabel(.send)
            .focused($typedFocused)
            .onSubmit(sendTyped)
            .accessibilityIdentifier("needsInput.typedAnswer")
            Button(action: sendTyped) {
                Group {
                    if sendingTyped {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        SendArrowGlyph().frame(width: 14, height: 14).foregroundStyle(.white)
                    }
                }
                .frame(width: 32, height: 32)
                .background(canSend ? S2.send : Self.rule, in: Circle())
            }
            .buttonStyle(.plain)
            // Not `.disabled`: that dims the board's grey to half strength.
            .allowsHitTesting(canSend)
            .accessibilityLabel("Send answer")
            .accessibilityIdentifier("needsInput.sendTyped")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 46)
        .overlay(Capsule().strokeBorder(Self.rule, lineWidth: 0.5))
    }

    private func pairButtons(primary: (String, Int?), secondary: (String, Int?)) -> some View {
        HStack(spacing: 8) {
            Button { if let i = primary.1 { answer(i) } } label: {
                Text(primary.0)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(S2.send, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(primary.1 == nil || answering != nil)
            .accessibilityIdentifier("needsInput.primary")
            Button { if let i = secondary.1 { answer(i) } } label: {
                Text(secondary.0)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(S2.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Self.field, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(secondary.1 == nil || answering != nil)
            .accessibilityIdentifier("needsInput.secondary")
        }
    }

    private func answer(_ index: Int) {
        answering = index
        Task { await store.answer(sessionID, index); answering = nil }
    }

    private func sendTyped() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sendingTyped else { return }
        sendingTyped = true
        Task {
            await store.answer(sessionID, text: text)
            sendingTyped = false
            typed = ""
        }
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
                    Task { await store.setModel(id, AgentKind.claude.defaultModel); working = false }
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
    /// Names who holds a message once it is in the agent's own queue.
    var agent: String = "claude"
    /// The row whose menu is open. Owned by the session view, which also
    /// closes it on a tap anywhere else.
    var openMenuID: Binding<String?> = .constant(nil)
    /// Returns an edited queued message to the owning composer.
    var onEdit: (String) -> Void = { _ in }
    @Environment(SessionStore.self) private var store

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items) { item in
                    let row = presentation(for: item)
                    let isOpen = openMenuID.wrappedValue == item.id
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            openMenuID.wrappedValue = isOpen ? nil : item.id
                        }
                    } label: {
                        pendingRow(item, row, highlighted: isOpen)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityValue(item.displayText)
                    .accessibilityHint("Shows actions for this message")
                    .accessibilityIdentifier(rowAccessibilityIdentifier(for: item))
                    // Each row owns its menu, drawn 8pt above the row and flush
                    // with its right edge (boards `s2-queued`, `s2-queued-failed`),
                    // so the message stays visible. The system menu centred over
                    // the row and covered it.
                    .overlay(alignment: .bottomTrailing) {
                        if isOpen {
                            // The row is 32pt: lift the card's bottom 8pt clear of its top.
                            queuedMessageActions(for: item)
                                .fixedSize()
                                .offset(y: -(32 + 8))
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                        }
                    }
                    .zIndex(isOpen ? 1 : 0)
                }
            }
        }
    }

    private func presentation(for item: SessionStore.PendingSend) -> QueuedStripRow {
        let serverStatus = item.serverQueueID.flatMap { qid in
            store.queues[sessionID]?.first { $0.id == qid }?.status
        }
        return QueuedStripRow(failed: item.failed, queuedOffline: item.queuedOffline,
                              queuedForResume: item.queuedForResume,
                              serverStatus: serverStatus, agent: agent)
    }

    private func pendingRow(_ item: SessionStore.PendingSend, _ row: QueuedStripRow, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            switch row.icon {
            case .spinner: QueuedSpinner().frame(width: 13, height: 13)
            case .clock: QueuedClock().frame(width: 14, height: 14)
            case .failed: NotSentMark().frame(width: 15, height: 15)
            }
            Text(item.displayText)
                .font(.system(size: 13))
                .foregroundStyle(S2.secondaryInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = row.tag {
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(row.tagIsError ? S2.color(dark: 0xFF6961, light: 0xD70015) : S2.metaInk)
                    .fixedSize()
            }
            RowMenuMark().frame(width: 16, height: 16)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 32)
        .background(highlighted ? S2.ink.opacity(0.08) : .clear, in: Capsule())
        .modifier(GlassPanel(cornerRadius: 16))
        .contentShape(Capsule())
    }

    private func queuedMessageActions(for item: SessionStore.PendingSend) -> some View {
        let row = presentation(for: item)
        return StripMenuCard(row: row) { action in
            withAnimation(.easeOut(duration: 0.15)) { openMenuID.wrappedValue = nil }
            perform(action, item)
        }
    }

    private func perform(_ action: QueuedStripRow.Action, _ item: SessionStore.PendingSend) {
        Task {
            switch action {
            case .sendNow, .trySendingNow: await store.sendQueuedNow(sessionID, item)
            case .retry: await store.retryPending(sessionID, item)
            case .edit:
                if let editable = await store.editQueued(sessionID, item) { onEdit(editable) }
            case .remove, .delete: await store.removeQueued(sessionID, item)
            }
        }
    }

    private func rowAccessibilityIdentifier(for item: SessionStore.PendingSend) -> String {
        item.queuedForResume ? "pendingStripRowResuming" : "pendingStripRow"
    }
}

/// The strip row's menu as the boards draw it: a dark rounded card, one row
/// per action with its icon on the right, Send now's subtitle, destructive in red.
private struct StripMenuCard: View {
    let row: QueuedStripRow
    let onPick: (QueuedStripRow.Action) -> Void

    private static let card = S2.color(dark: 0x2C2C2E, light: 0xFFFFFF)
    private static let rule = S2.color(dark: 0x48484A, light: 0xC6C6C8)

    var body: some View {
        VStack(spacing: 0) {
            if let note = row.menuNote {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(S2.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Rectangle().fill(Self.rule).frame(height: 0.5)
            }
            ForEach(Array(row.actions.enumerated()), id: \.offset) { index, action in
                Button { onPick(action) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(action.title).font(.system(size: 17))
                            if let subtitle = action.subtitle {
                                Text(subtitle).font(.system(size: 13)).foregroundStyle(S2.secondaryInk)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        StripMenuGlyph(action: action)
                            .frame(width: action == .sendNow || action == .trySendingNow ? 18 : 17,
                                   height: action == .sendNow || action == .trySendingNow ? 18 : 17)
                    }
                    .foregroundStyle(action.isDestructive ? S2.failed : S2.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, action.subtitle == nil ? 11 : 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(StripMenuCard.identifier(for: action))
                if index < row.actions.count - 1 {
                    Rectangle().fill(Self.rule).frame(height: 0.5)
                }
            }
        }
        .frame(width: row.actions.contains(.sendNow) ? 250 : 230)
        // No clip on the card: it would cut off the shadow (board: 0 12 40 at
        // 60% black, which darkens the strip under the menu). Rows are clear,
        // so the rounded background alone gives the shape.
        .background {
            // The board's shadow (0 12 40, 60% black): measured on the strip
            // under the menu it darkens 16 levels at the top, as on the board.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Self.card.opacity(0.97))
                .shadow(color: .black.opacity(0.6), radius: 20, y: 12)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queuedMessageMenu")
    }

    static func identifier(for action: QueuedStripRow.Action) -> String {
        switch action {
        case .sendNow, .trySendingNow: "queuedMessageSendNowButton"
        case .retry: "queuedMessageRetryButton"
        case .edit: "queuedMessageEditButton"
        case .remove, .delete: "queuedMessageRemoveButton"
        }
    }
}

/// The menu's icons, from the boards' SVGs (24-unit box).
private struct StripMenuGlyph: View {
    let action: QueuedStripRow.Action

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * k, y: y * k) }
            Path { p in
                switch action {
                case .sendNow, .trySendingNow:
                    // "M12 19V5M5 12l7-7 7 7"
                    p.move(to: pt(12, 19)); p.addLine(to: pt(12, 5))
                    p.move(to: pt(5, 12)); p.addLine(to: pt(12, 5)); p.addLine(to: pt(19, 12))
                case .retry:
                    // "M20 12a8 8 0 1 1-2.3-5.6 M20 4v5h-5"
                    p.move(to: pt(20, 12))
                    p.addArc(center: pt(12, 12), radius: 8 * k, startAngle: .degrees(0),
                             endAngle: .degrees(315.5), clockwise: false)
                    p.move(to: pt(20, 4)); p.addLine(to: pt(20, 9)); p.addLine(to: pt(15, 9))
                case .edit:
                    // "M4 20h4L19 9l-4-4L4 16z"
                    p.move(to: pt(4, 20)); p.addLine(to: pt(8, 20)); p.addLine(to: pt(19, 9))
                    p.addLine(to: pt(15, 5)); p.addLine(to: pt(4, 16)); p.closeSubpath()
                case .remove, .delete:
                    // "M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13"
                    p.move(to: pt(5, 7)); p.addLine(to: pt(19, 7))
                    p.move(to: pt(10, 7)); p.addLine(to: pt(10, 4)); p.addLine(to: pt(14, 4)); p.addLine(to: pt(14, 7))
                    p.move(to: pt(7, 7)); p.addLine(to: pt(8, 20)); p.addLine(to: pt(16, 20)); p.addLine(to: pt(17, 7))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: (action == .retry ? 2.2 : 2) * k, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A quarter arc turning on a grey ring (board `s2-queued`, 13pt).
private struct QueuedSpinner: View {
    // Driven by the clock, not `withAnimation(.repeatForever)` in `onAppear`:
    // a repeat-forever transaction can capture the layout changes made in the
    // same update (the strip row appearing, the bottom chrome growing) and
    // replay them forever over the whole transcript.
    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            GeometryReader { geo in
                let w = geo.size.width * 3 / 24
                ZStack {
                    Circle().inset(by: geo.size.width * 3 / 24)
                        .stroke(S2.color(dark: 0x48484A, light: 0xD1D1D6), lineWidth: w)
                    Circle().inset(by: geo.size.width * 3 / 24)
                        .trim(from: 0, to: 0.25)
                        .stroke(S2.secondaryInk, style: StrokeStyle(lineWidth: w, lineCap: .round))
                        .rotationEffect(.degrees(-90 + turn * 360))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Queued" while the host is offline (board `s2-queued-failed`, 14pt).
private struct QueuedClock: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            Path { p in
                p.addEllipse(in: CGRect(x: 3.5 * k, y: 3.5 * k, width: 17 * k, height: 17 * k))
                p.move(to: CGPoint(x: 12 * k, y: 7.5 * k))
                p.addLine(to: CGPoint(x: 12 * k, y: 12 * k))
                p.addLine(to: CGPoint(x: 15 * k, y: 14 * k))
            }
            .stroke(S2.secondaryInk, style: StrokeStyle(lineWidth: 2.2 * k, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A red disc with a white "!" (board `s2-queued-failed`, 15pt).
private struct NotSentMark: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            ZStack {
                Circle().fill(S2.failed).frame(width: 20 * k, height: 20 * k)
                Path { p in
                    p.move(to: CGPoint(x: 12 * k, y: 7 * k))
                    p.addLine(to: CGPoint(x: 12 * k, y: 13 * k))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2.6 * k, lineCap: .round))
                Circle().fill(.white).frame(width: 2.8 * k, height: 2.8 * k)
                    .position(x: 12 * k, y: 16.8 * k)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// The row's "more" mark: three dots in a ring (16pt).
private struct RowMenuMark: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            ZStack {
                Circle().inset(by: 3 * k).stroke(S2.metaInk, lineWidth: 1.8 * k)
                // r0.9 dots that also take the icon's 1.8 stroke: 3.6 units wide.
                ForEach([8.0, 12.0, 16.0], id: \.self) { x in
                    Circle().fill(S2.metaInk).frame(width: 3.6 * k, height: 3.6 * k)
                        .position(x: x * k, y: 12 * k)
                }
            }
        }
        .accessibilityHidden(true)
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

// MARK: - S2 tool steps (canvas boards `s2-view`, `s2-tools-group`, `s2-tools-single`)

/// S2 ink for tool steps: the board's exact dark hexes, matching system shades
/// in light mode.
private enum StepInk {
    static func hex(_ dark: UInt32, _ light: UInt32) -> Color {
        func ui(_ v: UInt32) -> UIColor {
            UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let header = hex(0xA1A1A6, 0x6C6C70)
    static let chevron = hex(0x636366, 0xAEAEB2)
    static let meta = hex(0x8E8E93, 0x8E8E93)
    static let rowVerb = hex(0xD1D1D6, 0x3A3A3C)
    static let rule = hex(0x38383A, 0xD1D1D6)
    static let card = hex(0x1C1C1E, 0xF2F2F7)
    static let cardStroke = hex(0x38383A, 0xD1D1D6)
    static let inputInk = hex(0xF2F2F7, 0x1C1C1E)
    static let outputBox = hex(0x000000, 0xFFFFFF)
    static let outputInk = hex(0xD1D1D6, 0x3A3A3C)
    static let link = hex(0x409CFF, 0x007AFF)
    static let error = hex(0xFF6961, 0xD70015)
}

extension ToolKind {
    /// The step header's icon (board: magnifier for reading, pencil for edits,
    /// terminal for commands).
    var stepSymbol: String {
        switch self {
        case .read, .explore, .search: return "magnifyingglass"
        case .edit: return "pencil"
        case .command: return "terminal"
        case .web: return "globe"
        case .agent: return "person.2"
        case .ask: return "questionmark.circle"
        case .other: return "wrench.and.screwdriver"
        }
    }

    /// A call row's icon inside an expanded step.
    var callSymbol: String {
        switch self {
        case .read: return "doc"
        case .explore, .search: return "magnifyingglass"
        case .edit: return "pencil"
        case .command: return "terminal"
        case .web: return "globe"
        case .agent: return "person.2"
        case .ask: return "questionmark.circle"
        case .other: return "wrench.and.screwdriver"
        }
    }

    /// The card's input label.
    var inputLabel: String {
        switch self {
        case .command: return "Command"
        case .read, .edit: return "File"
        case .search: return "Pattern"
        case .web: return "Address"
        case .agent: return "Task"
        case .ask: return "Question"
        case .explore, .other: return "Input"
        }
    }
}

enum StepFormat {
    /// "0.4s", "1.8s", "9s", "1m 5s".
    static func duration(_ ms: Double) -> String {
        let s = ms / 1000
        if s < 10 { return String(format: "%.1fs", s) }
        if s < 60 { return "\(Int(s.rounded()))s" }
        let m = Int(s) / 60
        return "\(m)m \(Int(s) % 60)s"
    }

    /// Paths inside the session's folder read relative to it, as on the board.
    static func display(_ target: String, cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return target }
        let base = cwd.hasSuffix("/") ? cwd : cwd + "/"
        return target.hasPrefix(base) ? String(target.dropFirst(base.count)) : target
    }

    /// "/Users/eugene/dev/lfg" -> "~/dev/lfg".
    static func abbreviatingHome(_ path: String) -> String {
        if let range = path.range(of: #"^/Users/[^/]+"#, options: .regularExpression) {
            return "~" + path[range.upperBound...]
        }
        return path
    }
}

/// Step and call icons drawn from the boards' SVGs (24-unit box).
struct StepGlyph: View {
    enum Kind: Equatable {
        case magnifier, pencil, terminal, lines, doc
        case symbol(String)

        static func call(_ kind: ToolKind) -> Kind {
            switch kind {
            case .read: return .doc
            case .explore, .search: return .magnifier
            case .edit: return .pencil
            case .command: return .terminal
            case .web: return .symbol("globe")
            case .agent: return .symbol("person.2")
            case .ask: return .symbol("questionmark.circle")
            case .other: return .symbol("wrench.and.screwdriver")
            }
        }
    }
    let kind: Kind
    var lineWidth: CGFloat = 1.9

    var body: some View {
        if case let .symbol(name) = kind {
            Image(systemName: name).resizable().scaledToFit().padding(1)
        } else {
            GeometryReader { geo in
                let k = geo.size.width / 24
                let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * k, y: y * k) }
                Path { p in
                    switch kind {
                    case .magnifier:
                        p.addEllipse(in: CGRect(x: 4.5 * k, y: 4.5 * k, width: 13 * k, height: 13 * k))
                        p.move(to: pt(16, 16)); p.addLine(to: pt(20.5, 20.5))
                    case .pencil:
                        // "M4 20h4L19 9l-4-4L4 16z M13.5 6.5l4 4"
                        p.move(to: pt(4, 20)); p.addLine(to: pt(8, 20)); p.addLine(to: pt(19, 9))
                        p.addLine(to: pt(15, 5)); p.addLine(to: pt(4, 16)); p.closeSubpath()
                        p.move(to: pt(13.5, 6.5)); p.addLine(to: pt(17.5, 10.5))
                    case .terminal:
                        // "M4 5h16v14H4z M8 10l3 2-3 2 M13 15h3"
                        p.addRect(CGRect(x: 4 * k, y: 5 * k, width: 16 * k, height: 14 * k))
                        p.move(to: pt(8, 10)); p.addLine(to: pt(11, 12)); p.addLine(to: pt(8, 14))
                        p.move(to: pt(13, 15)); p.addLine(to: pt(16, 15))
                    case .lines:
                        // "M4 6h10M4 12h16M4 18h12"
                        p.move(to: pt(4, 6)); p.addLine(to: pt(14, 6))
                        p.move(to: pt(4, 12)); p.addLine(to: pt(20, 12))
                        p.move(to: pt(4, 18)); p.addLine(to: pt(16, 18))
                    case .doc:
                        // "M6 2.5h8l4.5 4.5v14.5H6z M14 2.5V7h4.5"
                        p.move(to: pt(6, 2.5)); p.addLine(to: pt(14, 2.5)); p.addLine(to: pt(18.5, 7))
                        p.addLine(to: pt(18.5, 21.5)); p.addLine(to: pt(6, 21.5)); p.closeSubpath()
                        p.move(to: pt(14, 2.5)); p.addLine(to: pt(14, 7)); p.addLine(to: pt(18.5, 7))
                    case .symbol:
                        break
                    }
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth * k, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// One folded run of tool rows. Collapsed it reads "Read 6 files, ran 3
/// commands"; tapped, it lists every call, and a call opens a card with its
/// input and result. A run of one call opens straight to its card.
struct ToolStepGroupView: View {
    let group: ToolStepGroup
    let cwd: String?
    /// Directly under another step: no prose above to compensate for.
    var followsStep = false
    var onShowAll: (_ title: String, _ text: String) -> Void = { _, _ in }

    @State private var expanded = false
    @State private var openCallID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if expanded {
                if group.isSingleCall {
                    ToolCallCard(call: group.calls[0], cwd: cwd, showsCwd: true, onShowAll: onShowAll)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(group.calls) { call in
                            callRow(call)
                            if openCallID == call.id {
                                ToolCallCard(call: call, cwd: cwd, showsCwd: false, onShowAll: onShowAll)
                                    .padding(.top, 2)
                                    .padding(.bottom, 6)
                            }
                        }
                    }
                    .padding(.leading, 15.5)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(StepInk.rule).frame(width: 1.5)
                    }
                    .padding(.leading, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                StepGlyph(kind: headerGlyph, lineWidth: 1.9)
                    .frame(width: 17, height: 17)
                if group.isSingleCall {
                    singleCallLabel(group.calls[0])
                } else {
                    Text(group.summary)
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if expanded {
                        Text(stepMeta)
                            .font(.system(size: 12))
                            .foregroundStyle(StepInk.meta)
                    }
                }
                BoardGlyph(kind: expanded ? .chevronDown : .chevronRight, lineWidth: 2.8)
                    .foregroundStyle(expanded ? StepInk.meta : StepInk.chevron)
                    .frame(width: 12, height: 12)
            }
            .foregroundStyle(StepInk.header)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Measured against the boards: SwiftUI's 15pt line box sits ~4pt lower
        // than the board's after prose, and ~2pt tighter before the next row.
        // Under another step only the 2pt below that step needs taking back.
        .padding(.top, followsStep ? -2 : -4)
        .padding(.bottom, expanded ? 0 : 2)
        .accessibilityLabel(group.summary)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("toolStep-\(group.id)")
    }

    /// Boards: magnifier for reading, pencil for edits, a terminal for one
    /// command, three lines for a run of commands.
    private var headerGlyph: StepGlyph.Kind {
        if group.isSingleCall { return StepGlyph.Kind.call(group.calls[0].kind) }
        switch group.dominantKind {
        case .read, .explore, .search: return .magnifier
        case .edit: return .pencil
        case .command: return .lines
        default: return StepGlyph.Kind.call(group.dominantKind)
        }
    }

    private var stepMeta: String {
        let steps = "\(group.calls.count) steps"
        guard let ms = group.durationMs else { return steps }
        return "\(steps) · \(StepFormat.duration(ms))"
    }

    private func singleCallLabel(_ call: ToolCall) -> some View {
        HStack(spacing: 8) {
            Text(call.verb.replacingOccurrences(of: " ·", with: ""))
                .font(.system(size: 15))
                .fixedSize()
            Text(StepFormat.display(call.target, cwd: cwd))
                // A question is prose; commands, paths and patterns are code.
                .font(call.kind == .ask ? .system(size: 15) : .system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let ms = call.durationMs {
                Text(StepFormat.duration(ms))
                    .font(.system(size: 12))
                    .foregroundStyle(StepInk.meta)
                    .fixedSize()
            }
        }
    }

    private func callRow(_ call: ToolCall) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                openCallID = openCallID == call.id ? nil : call.id
            }
        } label: {
            HStack(spacing: 8) {
                StepGlyph(kind: .call(call.kind), lineWidth: 2)
                    .foregroundStyle(call.isError ? StepInk.error : StepInk.header)
                    .frame(width: 14, height: 14)
                Text(call.verb.replacingOccurrences(of: " ·", with: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(StepInk.rowVerb)
                    .fixedSize()
                Text(StepFormat.display(call.target, cwd: cwd))
                    .font(call.kind == .ask ? .system(size: 14) : .system(size: 12.5, design: .monospaced))
                    .foregroundStyle(StepInk.header)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let ms = call.durationMs {
                    Text(StepFormat.duration(ms))
                        .font(.system(size: 12))
                        .foregroundStyle(StepInk.meta)
                        .fixedSize()
                }
                BoardGlyph(kind: openCallID == call.id ? .chevronDown : .chevronRight, lineWidth: 3)
                    .foregroundStyle(StepInk.chevron)
                    .frame(width: 10, height: 10)
            }
            .padding(.vertical, 4.83)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolCall-\(call.id)")
    }
}

/// A call's input and result (board: Command / Output, File / Result).
struct ToolCallCard: View {
    let call: ToolCall
    let cwd: String?
    let showsCwd: Bool
    var onShowAll: (_ title: String, _ text: String) -> Void

    private static let previewLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(call.kind.inputLabel)
            ScrollableCodeBlock(text: inputText, fontSize: 12.5, lineHeight: 17,
                                foregroundColor: UIColor(StepInk.inputInk), maxHeight: 122,
                                accessibilityID: "toolCallInput-\(call.id)")
            if showsCwd, call.kind == .command, let cwd, !cwd.isEmpty {
                Text("In \(StepFormat.abbreviatingHome(cwd))")
                    .font(.system(size: 12))
                    .foregroundStyle(StepInk.meta)
            }
            if let result = call.result {
                // Commands show their last 8 lines, everything else its first 6.
                let preview = ToolCallPreview.lines(of: result, kind: call.kind,
                                                    limit: call.kind == .command ? Self.previewLimit : 6)
                sectionLabel(resultLabel(preview), tint: call.isError ? StepInk.error : StepInk.meta)
                    .padding(.top, 4)
                ScrollableCodeBlock(text: result, fontSize: 11.5, lineHeight: 16,
                                    foregroundColor: UIColor(StepInk.outputInk), maxHeight: 148,
                                    startsAtBottom: call.kind == .command, highlightsPassLines: true,
                                    accessibilityID: "toolCallOutput-\(call.id)")
                .background(StepInk.outputBox)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if preview.total > preview.lines.count {
                    Button("Show all \(preview.total) lines") {
                        onShowAll(call.label, result)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(StepInk.link)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toolCallShowAll-\(call.id)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepInk.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(StepInk.cardStroke, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toolCallCard-\(call.id)")
    }

    private var inputText: String {
        if !call.target.isEmpty {
            let target = StepFormat.display(call.target, cwd: cwd)
            return call.inputDetail.map { "\(target) · \($0)" } ?? target
        }
        return call.input
    }

    private func resultLabel(_ p: ToolCallPreview.Lines) -> String {
        let noun = call.kind == .command ? "Output" : "Result"
        let head = call.isError ? "Error" : noun
        let count = "\(p.total) line\(p.total == 1 ? "" : "s")"
        return "\(head) · \(count)"
    }

    private func sectionLabel(_ text: String, tint: Color = StepInk.meta) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(tint)
    }
}

/// The full result behind "Show all N lines".
struct ToolOutputSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollableCodeBlock(text: text, fontSize: 12, maxHeight: .infinity,
                                accessibilityID: "toolOutputCodeBlock")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("toolOutputDone")
                }
            }
        }
    }
}
