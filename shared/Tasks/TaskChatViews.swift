import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

#if os(iOS)
/// "Change task": a chat over the task view. The agent saves changes directly; each time the saved
/// task changes, a "Saved · N changes" card lands in the thread (diffed from the task before).
/// The Mac does not show this sheet: its Change with chat button opens the chat in iTerm.
struct TaskChatSheet: View {
    let client: ScheduledTasksClient
    /// The task as the list last loaded it; refreshed by `refresh`.
    let task: () -> ScheduledTaskRecord?
    let refresh: () async -> Void
    /// Sent once on open (Ask to fix), or nil to wait for the user.
    let firstMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var sessionID: String?
    @State private var messages: [SessionMessage] = []
    @State private var pending: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    /// The task as it was before the latest change card.
    @State private var baseline: ScheduledTaskRecord?
    @State private var cards: [ChangeCard] = []
    @State private var sentFirst = false

    struct ChangeCard: Identifiable {
        let id = UUID()
        let at: Date
        let changes: [TaskChange]
        let nextRun: String?
        /// Shown after this many transcript messages.
        let afterMessages: Int
    }

    /// Save cards outlive the sheet, so reopening a task's chat still shows what changed.
    @MainActor private static var cardCache: [String: [ChangeCard]] = [:]

    var body: some View {
        let current = task()
        VStack(spacing: 0) {
            header(current)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("The agent saves changes as soon as it makes them.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        ForEach(Array(thread.enumerated()), id: \.offset) { _, item in
                            Group {
                                switch item {
                                case .message(let m): TaskChatMessageView(role: m.role, text: m.text).id(m.stableID)
                                case .pending(let text): TaskChatMessageView(role: "user", text: text).opacity(0.7)
                                case .card(let card): TaskChangeCardView(card: card)
                                }
                            }
                            .padding(.top, 14)
                        }
                        if working { TaskChatTypingDots().padding(.top, 14).accessibilityIdentifier("task_chat_working") }
                        if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red).padding(.top, 12).accessibilityIdentifier("task_chat_error") }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
                }
                .onChange(of: thread.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
        .background(TaskChatColors.sheet)
        .presentationBackground(TaskChatColors.sheet)
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task_chat_sheet")
        .onChange(of: cards.count) { if let id = task()?.id { Self.cardCache[id] = cards } }
        .task {
            if let id = current?.id, cards.isEmpty { cards = Self.cardCache[id] ?? [] }
            if baseline == nil { baseline = current }
            if sessionID == nil { sessionID = current?.editSessionId }
            if let firstMessage, !sentFirst { sentFirst = true; send(firstMessage) }
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private enum ThreadItem { case message(SessionMessage), pending(String), card(ChangeCard) }

    /// Messages with change cards placed under the reply that announced them. An agent saves
    /// before it writes its reply, so a card follows the agent messages after its save point.
    private var thread: [ThreadItem] {
        let shown = messages.filter { ($0.role == "user" || $0.role == "assistant") && $0.kind == "text" }
        func slot(_ card: ChangeCard) -> Int {
            var i = card.afterMessages
            while i < shown.count, shown[i].role == "assistant" { i += 1 }
            return i
        }
        var items: [ThreadItem] = []
        for (i, m) in shown.enumerated() {
            var copy = m
            if m.role == "user" { copy.text = ScheduledTaskChatContext.displayedMessage(m.text) }
            items.append(.message(copy))
            for card in cards where slot(card) == i + 1 { items.append(.card(card)) }
        }
        for card in cards where slot(card) > shown.count || (slot(card) == 0 && shown.isEmpty) { items.append(.card(card)) }
        if let pending { items.append(.pending(pending)) }
        return items
    }

    /// The agent has the last word pending: a request is out and no reply has landed after it.
    private var working: Bool {
        if pending != nil || sending { return true }
        let shown = messages.filter { ($0.role == "user" || $0.role == "assistant") && $0.kind == "text" }
        return shown.last?.role == "user"
    }

    private func header(_ current: ScheduledTaskRecord?) -> some View {
        HStack(spacing: 10) {
            // The board's outline four-point star; SF Symbols only has it filled.
            // 20pt box: the star spans 13 of the 24 grid units, so it draws 11pt across, as on the board.
            TaskSparkleGlyph(size: 20, lineWidth: 1.8, small: false)
                .foregroundStyle(TaskColors.accent)
                .frame(width: 34, height: 34)
                .background(TaskChatColors.raised, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("Change task").font(.system(size: 17, weight: .semibold))
                if let current {
                    Text("\(current.name) · \(TaskScheduleSummary.changeLine(current.schedule))")
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(TaskTone.soft.color)
                    .frame(width: 44, height: 44)
                    .background(TaskChatColors.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("task_chat_close")
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
    }

    /// A raised field on the sheet with a hairline border, as on the board, over a fade of the thread.
    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft, prompt: Text("Ask for a change…").foregroundStyle(Color(.systemGray)), axis: .vertical)
                .font(.system(size: 17))
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(submit)
                .accessibilityLabel("Ask for a change")
                .accessibilityIdentifier("task_chat_field")
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? TaskColors.accentFill : TaskChatColors.control, in: Circle())
            }
            .buttonStyle(.plain)
            // Not `.disabled`: the board keeps a white arrow on an empty field; `submit` ignores empty text.
            .accessibilityLabel("Send")
            .accessibilityIdentifier("task_chat_send")
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
        .background(TaskChatColors.raised, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
        .background(alignment: .bottom) {
            LinearGradient(stops: [.init(color: TaskChatColors.sheet.opacity(0), location: 0), .init(color: TaskChatColors.sheet, location: 0.5)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110).ignoresSafeArea().allowsHitTesting(false)
        }
    }

    private var canSend: Bool { !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        draft = ""
        send(text)
    }

    private func send(_ text: String) {
        guard let id = task()?.id else { return }
        sending = true; error = nil; pending = text
        Task {
            defer { sending = false }
            do { sessionID = try await client.startChat(id, prompt: text); await poll() }
            catch { self.error = error.localizedDescription; pending = nil }
        }
    }

    /// Loads the chat's messages and adds a change card when the saved task moved on.
    private func poll() async {
        if let sid = sessionID,
           let page: MessagesResponse = try? await client.call("/api/sessions/\(sid)/messages?limit=80") {
            messages = page.messages
            if let p = pending, messages.contains(where: { $0.role == "user" && ScheduledTaskChatContext.displayedMessage($0.text).contains(p) }) {
                pending = nil
            }
        }
        await refresh()
        guard let before = baseline, let after = task(), after.updatedAt != before.updatedAt else { return }
        let changes = TaskChangeDiff.changes(before: before, after: after)
        baseline = after
        guard !changes.isEmpty else { return }
        let shown = messages.filter { ($0.role == "user" || $0.role == "assistant") && $0.kind == "text" }.count
        // An absolute date on the card ("Fri, Oct 16 at 8:00 AM"): it stays true when read later.
        let next = after.nextScheduledRun.map { ms -> String in
            let d = Date(timeIntervalSince1970: ms / 1000)
            return "Next run: \(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(d.formatted(date: .omitted, time: .shortened))"
        }
        cards.append(.init(at: Date(), changes: changes, nextRun: next, afterMessages: shown))
    }
}

/// "Saved · 3 changes": each field, old (struck through) → new, and the next run.
struct TaskChangeCardView: View {
    let card: TaskChatSheet.ChangeCard
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.green)
                Text("Saved · \(card.changes.count) change\(card.changes.count == 1 ? "" : "s")").font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Text(card.at, format: .dateTime.hour().minute()).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            ForEach(card.changes) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.field).font(.system(size: 12)).foregroundStyle(.secondary)
                    // Old value and arrow stay together; the new value moves to its own line when it does not fit.
                    TaskFlowLayout(spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(change.from).strikethrough().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        }
                        Text(change.to).fontWeight(.semibold)
                    }
                    .font(.system(size: 15))
                }
            }
            if let next = card.nextRun {
                Divider()
                Label(next, systemImage: "clock")
                    .font(.system(size: 13)).foregroundStyle(.primary.opacity(0.82))
                    .labelStyle(TaskIconLabelStyle(spacing: 6))
            }
        }
        .padding(14)
        .background(TaskChatColors.raised, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task_change_card")
    }
}

/// The chat board's surfaces: the sheet (#1C1C1E), raised parts (#2C2C2E) and controls (#3A3A3C).
enum TaskChatColors {
    static let sheet = TaskColors.adaptive(light: Color(.secondarySystemBackground), dark: Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255))
    static let raised = TaskColors.adaptive(light: Color(.tertiarySystemBackground), dark: Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255))
    static let control = TaskColors.adaptive(light: Color(.systemGray4), dark: Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255))
}

/// One chat message: the user's in a blue bubble on the right, the agent's as plain text.
struct TaskChatMessageView: View {
    let role: String
    let text: String

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    var body: some View {
        if role == "user" {
            HStack {
                Spacer(minLength: 52)
                Text(rendered)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(TaskColors.accentFill, in: RoundedRectangle(cornerRadius: 20))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You: \(text)")
        } else {
            Text(rendered)
                .font(.system(size: 17))
                .lineSpacing(3.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityLabel("Agent: \(text)")
        }
    }
}

struct TaskChatTypingDots: View {
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7).opacity(phase == i ? 1 : 0.35)
            }
        }
        .padding(.vertical, 6)
        .task { while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(350)); phase = (phase + 1) % 3 } }
        .accessibilityLabel("The agent is working")
    }
}
#endif
