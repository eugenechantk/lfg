import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

/// Surfaces for the task view. Phone values follow the A2 dark board; the Mac uses the 400pt board.
enum TaskPalette {
    #if os(iOS)
    static let card = Color(.secondarySystemBackground)
    static let control = Color(.tertiarySystemBackground)
    #else
    /// The dA2 boards' opaque card (#26262B) on their #1B1B1E page.
    static let card = TaskColors.adaptive(light: Color.primary.opacity(0.07), dark: Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x2B / 255))
    static let control = Color.primary.opacity(0.10)
    #endif
    /// Header chips: the card fill on the phone; on the Mac the board's 7% white over the page (#2E2E32).
    #if os(iOS)
    static let chip = card
    #else
    static let chip = TaskColors.adaptive(light: Color.primary.opacity(0.07), dark: Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x32 / 255))
    #endif
    /// Typed fields on a form card: darker than the card (#1C1C1E on the phone, #1E1E22 on the Mac).
    #if os(iOS)
    static let field = TaskColors.adaptive(light: Color(.systemBackground), dark: Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255))
    #else
    static let field = TaskColors.adaptive(light: Color.primary.opacity(0.05), dark: Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x22 / 255))
    #endif
}

enum TaskDetailMetrics {
    #if os(macOS)
    static let title: CGFloat = 22, schedule: CGFloat = 14, chip: CGFloat = 12, chipHeight: CGFloat = 24
    static let cardLabel: CGFloat = 11, cardMain: CGFloat = 19, cardSub: CGFloat = 13, button: CGFloat = 13, buttonHeight: CGFloat = 34
    static let cardRadius: CGFloat = 16, cardPadding: CGFloat = 14, section: CGFloat = 12, body: CGFloat = 14
    static let runHead: CGFloat = 13, runTail: CGFloat = 12, runBody: CGFloat = 13, runLine: CGFloat = 17.5
    /// The rail column, its node, the line above the node, and the row's text padding.
    static let runRail: CGFloat = 14, runNode: CGFloat = 11, runTopLine: CGFloat = 9, runPadTop: CGFloat = 4, runPadBottom: CGFloat = 11
    #else
    static let title: CGFloat = 28, schedule: CGFloat = 17, chip: CGFloat = 13, chipHeight: CGFloat = 26
    static let cardLabel: CGFloat = 12, cardMain: CGFloat = 22, cardSub: CGFloat = 15, button: CGFloat = 16, buttonHeight: CGFloat = 44
    static let cardRadius: CGFloat = 22, cardPadding: CGFloat = 16, section: CGFloat = 15, body: CGFloat = 16
    static let runHead: CGFloat = 15, runTail: CGFloat = 13, runBody: CGFloat = 15, runLine: CGFloat = 20
    static let runRail: CGFloat = 16, runNode: CGFloat = 12, runTopLine: CGFloat = 10, runPadTop: CGFloat = 5, runPadBottom: CGFloat = 12
    #endif
}

// MARK: - Header

struct TaskDetailHeader: View {
    let task: ScheduledTaskRecord
    let hostName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.name)
                .font(.system(size: TaskDetailMetrics.title, weight: .bold))
                .foregroundStyle(TaskColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("task_title")
            Label {
                Text(TaskScheduleSummary.detailLine(task.schedule))
            } icon: {
                Image(systemName: task.schedule.kind == "once" ? "clock" : "repeat")
            }
            .font(.system(size: TaskDetailMetrics.schedule))
            .foregroundStyle(TaskColors.soft)
            .labelStyle(TaskIconLabelStyle(spacing: 7))
            .accessibilityIdentifier("task_schedule")
            HStack(spacing: 6) {
                TaskChip(systemImage: "display", text: hostName)
                // The phone boards name the model ("Opus 5.5"); the Mac boards show the raw id.
                #if os(iOS)
                TaskChip(agent: task.agent, text: ModelName.display(task.modelLabel))
                #else
                TaskChip(agent: task.agent, text: task.modelLabel)
                #endif
                TaskChip(systemImage: "folder", text: TaskDetailHeader.shortPath(task.cwd))
            }
            .padding(.top, 2)
        }
    }

    /// "~/dev/personal/lfg" for paths under a home directory.
    static func shortPath(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Users" || parts[0] == "home" else { return path }
        let rest = parts.dropFirst(2).joined(separator: "/")
        return rest.isEmpty ? "~" : "~/" + rest
    }
}

struct TaskIconLabelStyle: LabelStyle {
    var spacing: CGFloat = 6
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) { configuration.icon; configuration.title }
    }
}

struct TaskChip: View {
    var systemImage: String? = nil
    var agent: String? = nil
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            if let agent { TaskAgentMark(agent: agent) }
            else if let systemImage { Image(systemName: systemImage).font(.system(size: TaskDetailMetrics.chip)) }
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: TaskDetailMetrics.chip))
        .foregroundStyle(TaskColors.soft)
        .padding(.leading, agent == nil ? 9 : TaskAgentMark.leadingPadding).padding(.trailing, 9)
        .frame(height: TaskDetailMetrics.chipHeight)
        .background(TaskPalette.chip, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The agent's logo: Claude Code's clay starburst, Codex's app icon.
struct TaskAgentMark: View {
    let agent: String
    #if os(macOS)
    static let leadingPadding: CGFloat = 6
    private static let claudeSize: CGFloat = 13, codexSize: CGFloat = 14
    @MainActor private static let claude = logo("agent-claude")
    @MainActor private static let codex = logo("agent-codex")
    /// build.sh copies the app's SVG logos into the bundle; AppKit draws SVG natively.
    private static func logo(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 24, height: 24)
        return image
    }
    #else
    static let leadingPadding: CGFloat = 7
    private static let claudeSize: CGFloat = 14, codexSize: CGFloat = 15
    #endif

    var body: some View {
        let codex = agent.contains("codex")
        let size = codex ? Self.codexSize : Self.claudeSize
        logo(codex: codex)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func logo(codex: Bool) -> Image {
        #if os(macOS)
        if let image = codex ? Self.codex : Self.claude { return Image(nsImage: image) }
        return Image(systemName: codex ? "terminal" : "sparkle")
        #else
        Image(codex ? "agent-codex" : "agent-claude")
        #endif
    }
}

// MARK: - Status card

/// What a card button or link asks the task view to do.
enum TaskCardIntent {
    case action(TaskStatusCardModel.Action)
    case openSession(String)
    case answer(sessionID: String, option: ScheduledTaskPrompt.Option)
    case reply(sessionID: String, text: String)
}

struct TaskStatusCard: View {
    let model: TaskStatusCardModel
    let prompt: ScheduledTaskPrompt?
    let busy: Bool
    /// The option the user picked, shown until the host reports the run running again.
    let answered: String?
    /// The task's host, named where the Mac points at its tmux session.
    var hostName = ""
    let perform: (TaskCardIntent) -> Void
    @State private var reply = ""

    #if os(macOS)
    // The 400pt board: a faint tint with a hairline border, and a smaller title for attention states.
    private static let tintOpacity = 0.08, borderOpacity = 0.28
    #else
    private static let tintOpacity = 0.17, borderOpacity = 0.0
    #endif

    private var mainSize: CGFloat {
        #if os(macOS)
        model.kind == .failed ? TaskDetailMetrics.cardMain - 2 : TaskDetailMetrics.cardMain
        #else
        TaskDetailMetrics.cardMain
        #endif
    }

    private var tint: Color? {
        if answered != nil { return TaskColors.success }
        switch model.kind {
        case .failed: return TaskColors.danger
        case .waiting: return TaskColors.warning
        case .running: return TaskColors.success
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let answered { answeredContent(answered) }
            else if model.kind == .waiting { waitingContent }
            else { standardContent }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TaskDetailMetrics.cardPadding)
        .background(tint.map { $0.opacity(Self.tintOpacity) } ?? TaskPalette.card, in: RoundedRectangle(cornerRadius: TaskDetailMetrics.cardRadius))
        .overlay {
            if let tint, Self.borderOpacity > 0 {
                RoundedRectangle(cornerRadius: TaskDetailMetrics.cardRadius).strokeBorder(tint.opacity(Self.borderOpacity), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task_status_card")
    }

    private func label(_ text: String, color: Color, dot: Bool = false, dotColor: Color? = nil, icon: String? = nil) -> some View {
        let dotColor = dotColor ?? color
        return HStack(spacing: 7) {
            if dot { Circle().fill(dotColor).frame(width: 8, height: 8).background(Circle().fill(dotColor.opacity(0.28)).frame(width: 14, height: 14)) }
            // The glyph keeps the plain tone (system red); only the label text takes the lighter one.
            if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(dotColor) }
            Text(text.uppercased())
                .font(.system(size: TaskDetailMetrics.cardLabel, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                switch model.kind {
                case .failed:
                    #if os(macOS)
                    label(model.label, color: TaskColors.dangerLabel)
                    #else
                    label(model.label, color: TaskColors.dangerLabel, dotColor: TaskColors.danger, icon: "xmark.circle")
                    #endif
                case .running: label(model.label, color: TaskColors.success, dot: true)
                case .paused: label(model.label, color: TaskColors.warning)
                default:
                    if model.secondary == .changeRetryTime {
                        label(model.label, color: TaskColors.accent, icon: "clock")
                    } else {
                        label(model.label, color: TaskColors.grey)
                    }
                }
                Spacer(minLength: 0)
                if let streak = model.streak {
                    Text(streak)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TaskColors.danger)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(TaskPalette.control, in: Capsule())
                        .accessibilityIdentifier("task_failure_streak")
                }
            }
            Text(model.main)
                .font(.system(size: mainSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task_card_main")
            if let sub = model.sub {
                Text(sub)
                    .font(.system(size: TaskDetailMetrics.cardSub))
                    .foregroundStyle(model.kind == .failed ? Color.primary.opacity(0.82) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.kind == .running, let sid = model.sessionID {
                Button { perform(.openSession(sid)) } label: { Text("Open session ›") }
                    .buttonStyle(.plain)
                    .font(.system(size: TaskDetailMetrics.cardSub))
                    .foregroundStyle(TaskColors.accent)
                    .padding(.top, 3)
                    .accessibilityIdentifier("task_card_open_session")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if model.primary != nil || model.secondary != nil {
            HStack(spacing: 10) {
                if let primary = model.primary { actionButton(primary, prominent: true) }
                if let secondary = model.secondary { actionButton(secondary, prominent: false) }
            }
        }
        if model.primary == .retry, model.secondary == .askToFix {
            quietRetryAction(.retryLater)
        }
        if model.secondary == .changeRetryTime {
            quietRetryAction(.cancelRetry)
        }
        if let footnote = model.footnote {
            Divider().overlay(tint?.opacity(0.25) ?? .clear)
            Label(footnote, systemImage: "clock")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.82))
                .labelStyle(TaskIconLabelStyle(spacing: 6))
        }
    }

    private func title(for action: TaskStatusCardModel.Action) -> (String, String, String) {
        switch action {
        case .runNow: ("Run now", "play.fill", "task_run_now")
        case .retry: ("Retry now", "arrow.clockwise", "task_retry")
        case .retryLater: ("Retry later…", "clock", "task_retry_later")
        case .changeRetryTime: ("Change time", "clock", "task_change_retry_time")
        case .cancelRetry: ("Cancel retry", "xmark", "task_cancel_retry")
        case .pause: ("Pause", "pause.fill", "task_pause_resume")
        case .resume: ("Resume", "play.fill", "task_pause_resume")
        case .askToFix: ("Ask to fix", "sparkles", "task_ask_to_fix")
        }
    }

    private func quietRetryAction(_ action: TaskStatusCardModel.Action) -> some View {
        let (text, icon, id) = title(for: action)
        return Button { perform(.action(action)) } label: {
            HStack(spacing: 7) {
                if action != .cancelRetry {
                    Image(systemName: icon).font(.system(size: TaskDetailMetrics.button, weight: .semibold))
                }
                Text(text).font(.system(size: TaskDetailMetrics.button, weight: action == .cancelRetry ? .medium : .semibold))
            }
            .foregroundStyle(action == .cancelRetry ? TaskColors.grey : TaskColors.accent)
            .frame(minHeight: TaskDetailMetrics.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -6).padding(.bottom, -8)
        .disabled(busy).opacity(busy ? 0.5 : 1)
        .accessibilityIdentifier(id)
    }

    private func actionButton(_ action: TaskStatusCardModel.Action, prominent: Bool) -> some View {
        let (text, icon, id) = title(for: action)
        return Button { perform(.action(action)) } label: {
            HStack(spacing: 7) {
                #if os(iOS)
                if action == .askToFix {
                    // The board's outline star, not the filled SF sparkles.
                    TaskSparkleGlyph(size: 16, lineWidth: 1.9, small: false)
                } else {
                    Image(systemName: icon).font(.system(size: (TaskDetailMetrics.button * 0.62).rounded(), weight: .bold))
                }
                #else
                // The board's glyphs are about 60% of the label size.
                Image(systemName: icon).font(.system(size: (TaskDetailMetrics.button * 0.62).rounded(), weight: .bold))
                #endif
                Text(text).font(.system(size: TaskDetailMetrics.button, weight: .semibold))
                #if os(macOS)
                // On the Mac, Ask to fix opens a session in iTerm.
                if action == .askToFix {
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).opacity(0.7)
                }
                #endif
            }
            .frame(maxWidth: .infinity, minHeight: TaskDetailMetrics.buttonHeight)
            .foregroundStyle(prominent ? Color.white : TaskColors.accent)
            .background(prominent ? TaskColors.accentFill : TaskPalette.control, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var waitingContent: some View {
        HStack {
            label(model.label, color: TaskColors.warningLabel, dot: true, dotColor: TaskColors.warningDot)
            Spacer(minLength: 0)
            if let waited = model.waited { Text(waited).font(.system(size: 13)).foregroundStyle(.secondary) }
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(model.main)
                .font(.system(size: TaskDetailMetrics.cardMain - 2, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task_question")
            if let sub = model.sub {
                Text(sub).font(.system(size: TaskDetailMetrics.cardSub)).foregroundStyle(.primary.opacity(0.82))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #if os(iOS)
        if let prompt, let sid = model.sessionID {
            ForEach(prompt.options) { option in
                Button { perform(.answer(sessionID: sid, option: option)) } label: {
                    HStack(spacing: 10) {
                        Text("\(option.index)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(TaskPalette.card, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                            if let d = option.description, !d.isEmpty {
                                Text(d).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .background(TaskPalette.control, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("task_answer_\(option.index)")
            }
            HStack(spacing: 10) {
                TextField("Type a different answer…", text: $reply)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(TaskPalette.control, in: Capsule())
                    .submitLabel(.send)
                    .onSubmit {
                        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        reply = ""
                        perform(.reply(sessionID: sid, text: text))
                    }
                    .accessibilityIdentifier("task_answer_text")
                Button { perform(.openSession(sid)) } label: { Text("Open session ›") }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TaskColors.accent)
                    .fixedSize()
                    .accessibilityIdentifier("task_card_open_session")
            }
        }
        #else
        // The Mac answers in iTerm, never in place (desktop scope).
        if let sid = model.sessionID {
            Button { perform(.openSession(sid)) } label: {
                Label("Answer in iTerm", systemImage: "terminal")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .background(TaskColors.warningFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityIdentifier("task_answer_in_iterm")
            Text("The run’s session is open in tmux\(hostName.isEmpty ? "" : " on \(hostName)"). It continues once you answer there.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .lineSpacing(1)
                .padding(.bottom, 6)
        }
        #endif
    }

    @ViewBuilder
    private func answeredContent(_ picked: String) -> some View {
        label("Running again", color: TaskColors.success, dot: true)
        (Text("You answered ") + Text(picked).bold() + Text(". The result will show here when the run ends."))
            .font(.system(size: TaskDetailMetrics.cardSub + 2))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("task_answered")
        if let sid = model.sessionID {
            Button { perform(.openSession(sid)) } label: { Text("Open session ›") }
                .buttonStyle(.plain)
                .font(.system(size: TaskDetailMetrics.cardSub))
                .foregroundStyle(TaskColors.accent)
        }
    }
}

// MARK: - Runs timeline

/// A Show more / Show less row on the timeline. The rail turns dashed where runs are hidden.
struct RunsToggle {
    var label: String
    var count: String
    /// Hidden runs lie above (upcoming) or below (past) this row.
    var opensUp: Bool
    var opens: Bool
    var identifier: String
    var action: () -> Void
}

struct RunTimelineView: View {
    let entries: [RunTimelineEntry]
    let open: (RunTimelineEntry) -> Void
    /// Above the upcoming runs.
    var later: RunsToggle? = nil
    /// Below the past runs.
    var earlier: RunsToggle? = nil
    /// The Retry button on the newest failed run. The rest of that row still calls `open`.
    var retry: ((RunTimelineEntry) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let later { RunsToggleRow(toggle: later, railAbove: later.opens, railBelow: !entries.isEmpty) }
            runRows
            if let earlier { RunsToggleRow(toggle: earlier, railAbove: !entries.isEmpty, railBelow: earlier.opens) }
        }
    }

    private var runRows: some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                // Upcoming runs are not tappable. A disabled Button would grey them out, so they
                // render as plain rows.
                let tappable = entry.sessionID != nil || entry.tailIsAction || entry.runID != nil
                let row = HStack(alignment: .top, spacing: 12) {
                        // A toggle row continues the rail past the first and last run.
                        node(entry, first: index == 0 && later == nil, last: index == entries.count - 1 && earlier == nil)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(entry.head)
                                    .font(.system(size: TaskDetailMetrics.runHead, weight: .semibold))
                                    .foregroundStyle(entry.node == .upcoming ? TaskColors.grey : TaskColors.ink)
                                Spacer(minLength: 0)
                                Text(Self.tail(entry.tail))
                                    .font(.system(size: TaskDetailMetrics.runTail, weight: .semibold))
                                    .foregroundStyle(entry.tailTone.color)
                                    // Drawn by the Retry button over the row instead, so it keeps its own tap.
                                    .opacity(entry.tailIsAction && retry != nil ? 0 : 1)
                            }
                            .frame(height: TaskDetailMetrics.runLine)
                            if let body = entry.body {
                                Text(body)
                                    .font(.system(size: TaskDetailMetrics.runBody))
                                    .foregroundStyle(entry.bodyTone.color)
                                    .lineLimit(1)
                                    .frame(height: TaskDetailMetrics.runLine)
                            }
                        }
                        .padding(.top, TaskDetailMetrics.runPadTop).padding(.bottom, TaskDetailMetrics.runPadBottom)
                    }
                    .contentShape(Rectangle())
                Group {
                    if tappable { Button { open(entry) } label: { row }.buttonStyle(.plain) }
                    else { row.accessibilityElement(children: .combine) }
                }
                .accessibilityIdentifier(entry.runID.map { "task_run_\($0)" } ?? "task_upcoming_\(index)")
                .overlay(alignment: .topTrailing) {
                    if entry.tailIsAction, let retry { retryButton(entry, retry) }
                }
        }
    }

    /// "Retry" in the tail's place, with a hit area larger than the text.
    private func retryButton(_ entry: RunTimelineEntry, _ retry: @escaping (RunTimelineEntry) -> Void) -> some View {
        let pad: CGFloat = 10
        return Button { retry(entry) } label: {
            Text(entry.tail)
                .font(.system(size: TaskDetailMetrics.runTail, weight: .semibold))
                .foregroundStyle(entry.tailTone.color)
                .frame(height: TaskDetailMetrics.runLine)
                .padding(.leading, 16).padding(.vertical, pad)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: TaskDetailMetrics.runPadTop - pad)
        .accessibilityIdentifier("task_run_retry")
    }

    /// On the Mac a run opens in iTerm, so its "›" becomes "↗".
    private static func tail(_ text: String) -> String {
        #if os(macOS)
        text == "›" ? "↗" : text.replacingOccurrences(of: " ›", with: " ↗")
        #else
        text
        #endif
    }

    private func node(_ entry: RunTimelineEntry, first: Bool, last: Bool) -> some View {
        let line = TaskColors.rail
        let (stroke, fill): (Color, Color) = {
            switch entry.node {
            case .upcoming: return (TaskColors.upcomingNode, .clear)
            case .running: return (TaskColors.successNode, .clear)
            case .success: return (TaskColors.successNode, TaskColors.successNode)
            case .failure: return (TaskColors.dangerNode, TaskColors.dangerNode)
            case .warning: return (TaskColors.warning, TaskColors.warning)
            }
        }()
        return VStack(spacing: 0) {
            Rectangle().fill(first ? Color.clear : line).frame(width: 2, height: TaskDetailMetrics.runTopLine)
            Circle().strokeBorder(stroke, lineWidth: 2).background(Circle().fill(fill))
                .frame(width: TaskDetailMetrics.runNode, height: TaskDetailMetrics.runNode)
            Rectangle().fill(last ? Color.clear : line).frame(width: 2).frame(maxHeight: .infinity)
        }
        .frame(width: TaskDetailMetrics.runRail)
    }
}

/// The toggle row: a small disc with a chevron on the rail, "Show more" and the hidden count.
struct RunsToggleRow: View {
    let toggle: RunsToggle
    let railAbove: Bool
    let railBelow: Bool
    #if os(macOS)
    private let height: CGFloat = 34, disc: CGFloat = 16, glyph: CGFloat = 9, glyphStroke: CGFloat = 3.2
    private let label: CGFloat = 13, count: CGFloat = 12
    private let discFill = Color.white.opacity(0.09)
    /// The boards' dashed border, as Chrome draws it at 2pt.
    private let dash: [CGFloat] = [3.3, 2]
    #else
    private let height: CGFloat = 44, disc: CGFloat = 18, glyph: CGFloat = 11, glyphStroke: CGFloat = 3
    private let label: CGFloat = 15, count: CGFloat = 13
    private let discFill = TaskPalette.card
    private let dash: [CGFloat] = [4, 0.5]
    #endif

    var body: some View {
        Button(action: toggle.action) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    // Dashes start at the end that meets a run, so no gap opens beside the solid rail.
                    rail(railAbove, fromTop: !toggle.opensUp)
                    Circle().fill(discFill).frame(width: disc, height: disc)
                        .overlay {
                            // Up while the hidden runs lie above, as the boards draw it.
                            TaskChevronShape(up: toggle.opensUp == toggle.opens)
                                .stroke(TaskColors.accent, style: StrokeStyle(lineWidth: glyph * glyphStroke / 24, lineCap: .round, lineJoin: .round))
                                .frame(width: glyph, height: glyph)
                        }
                    rail(railBelow, fromTop: !toggle.opensUp)
                }
                .frame(width: TaskDetailMetrics.runRail)
                Text(toggle.label)
                    .font(.system(size: label, weight: .semibold))
                    .foregroundStyle(TaskColors.accent)
                Spacer(minLength: 8)
                Text(toggle.count)
                    .font(.system(size: count))
                    .foregroundStyle(TaskColors.grey)
            }
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toggle.count.isEmpty ? toggle.label : "\(toggle.label), \(toggle.count)")
        .accessibilityIdentifier(toggle.identifier)
    }

    /// Dashed, as the boards draw the rail beside a toggle.
    private func rail(_ shown: Bool, fromTop: Bool) -> some View {
        DashedRail(fromTop: fromTop)
            .stroke(shown ? TaskColors.rail : .clear, style: StrokeStyle(lineWidth: 2, dash: dash))
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }
}

private struct DashedRail: Shape {
    var fromTop: Bool
    func path(in rect: CGRect) -> Path {
        let (start, end) = fromTop ? (rect.minY, rect.maxY) : (rect.maxY, rect.minY)
        return Path { p in p.move(to: CGPoint(x: rect.midX, y: start)); p.addLine(to: CGPoint(x: rect.midX, y: end)) }
    }
}

/// The boards' chevron (`M6 15l6-6 6 6` on a 24-unit grid), pointing up or down.
struct TaskChevronShape: Shape {
    var up: Bool
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let (outer, inner): (CGFloat, CGFloat) = up ? (15, 9) : (9, 15)
        return Path { p in
            p.move(to: CGPoint(x: 6 * s, y: outer * s))
            p.addLine(to: CGPoint(x: 12 * s, y: inner * s))
            p.addLine(to: CGPoint(x: 18 * s, y: outer * s))
        }
    }
}

// MARK: - Sparkle

/// The boards' outline sparkle: a four-point star (and a small one for the Ask bar), drawn on a
/// 24-unit grid from their SVG paths. SF Symbols only offers it filled.
struct TaskSparkleShape: Shape {
    var small = true

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.addLines([pt(12, 3), pt(13.8, 7.7), pt(18.5, 9.5), pt(13.8, 11.3), pt(12, 16), pt(10.2, 11.3), pt(5.5, 9.5), pt(10.2, 7.7)])
        p.closeSubpath()
        if small {
            p.addLines([pt(19, 15), pt(19.8, 17.2), pt(22, 18), pt(19.8, 18.8), pt(19, 21), pt(18.2, 18.8), pt(16, 18), pt(18.2, 17.2)])
            p.closeSubpath()
        }
        return p
    }
}

struct TaskSparkleGlyph: View {
    var size: CGFloat = 20
    var lineWidth: CGFloat = 1.8
    var small = true
    var body: some View {
        TaskSparkleShape(small: small)
            .stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Ask bar

/// "Ask to change this task…": opens the task's chat (phone). Placeholder text varies with the state.
struct TaskAskBar: View {
    let placeholder: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                TaskSparkleGlyph(size: 20).foregroundStyle(TaskColors.accent)
                Text(placeholder).font(.system(size: 17)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(TaskPalette.control, in: Circle())
            }
            .padding(.leading, 18).padding(.trailing, 8)
            .frame(height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .glassOrRaised(in: Capsule(), interactive: true)
        #endif
        .accessibilityIdentifier("task_ask_bar")
    }
}

/// Pick one extra run without editing the task's recurring schedule.
struct TaskRetryLaterSheet: View {
    let task: ScheduledTaskRecord
    let hostName: String
    let client: ScheduledTasksClient
    let saved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduledTaskRetryDraft
    @State private var customMinutes = "90"
    @State private var usesCustomMinutes = false
    @State private var saving = false
    @State private var error: String?
    @FocusState private var minutesFocused: Bool
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    init(task: ScheduledTaskRecord, hostName: String, client: ScheduledTasksClient, saved: @escaping () async -> Void) {
        self.task = task; self.hostName = hostName; self.client = client; self.saved = saved
        _draft = State(initialValue: ScheduledTaskRetryDraft(retryAt: task.retryAt))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let presentation = ScheduledTaskRetryPresentation(draft: draft, now: context.date)
            #if os(macOS)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text("\(task.name) · \(hostName)").font(.system(size: 11)).foregroundStyle(TaskColors.grey)
                        .lineLimit(2)
                }
                configuration(presentation)
                explanation
                errorMessage
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(TaskPalette.control, in: Capsule())
                        .keyboardShortcut(.cancelAction)
                        .disabled(saving).accessibilityIdentifier("task_retry_dismiss")
                    confirmation(presentation)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 360)
            .background(TaskColors.adaptive(light: Color(nsColor: .windowBackgroundColor),
                                           dark: Color(red: 35 / 255, green: 35 / 255, blue: 39 / 255)))
            .fixedSize(horizontal: false, vertical: true)
            #else
            phoneContent(presentation)
            #endif
        }
        .interactiveDismissDisabled(saving)
        .accessibilityIdentifier("task_retry_sheet")
        .onChange(of: draft.mode) { _, _ in minutesFocused = false }
        .onChange(of: minutesFocused) { _, focused in
            if !focused, usesCustomMinutes, let minutes = Int(draft.minutes), [35, 45, 60].contains(minutes) {
                usesCustomMinutes = false
            }
        }
        #if os(iOS)
        .frame(idealWidth: 420, idealHeight: sheetHeight)
        .presentationSizing(.fitted)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(sheetHeight), .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var title: String { task.retryAt == nil ? "Retry later" : "Change retry time" }
    private var sheetHeight: CGFloat {
        (draft.mode == .time || usesCustomMinutes ? 526 : 476) + (error == nil ? 0 : 46)
    }
    private var cardRadius: CGFloat {
        #if os(macOS)
        12
        #else
        20
        #endif
    }
    private var cardFill: Color {
        #if os(macOS)
        TaskPalette.card
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }
    private var chipFill: Color {
        #if os(macOS)
        TaskPalette.control
        #else
        TaskColors.adaptive(light: Color(.tertiarySystemFill), dark: Color(.tertiarySystemGroupedBackground))
        #endif
    }
    private var disabledConfirmationText: Color {
        #if os(iOS)
        Color(.systemGray)
        #else
        TaskColors.grey
        #endif
    }
    private var contentInset: CGFloat {
        #if os(macOS)
        14
        #else
        16
        #endif
    }

    #if os(iOS)
    private func phoneContent(_ presentation: ScheduledTaskRetryPresentation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    configuration(presentation)
                    explanation.padding(.horizontal, 6)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    errorMessage
                    confirmation(presentation)
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("task_retry_dismiss")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(title).font(.headline)
                        Text(task.name).font(.caption).foregroundStyle(TaskColors.grey).lineLimit(1)
                    }
                    .frame(maxWidth: 190)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("task_retry_context")
                }
            }
        }
    }
    #endif

    private func configuration(_ presentation: ScheduledTaskRetryPresentation) -> some View {
        let date = presentation.date
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                modePicker.padding(.horizontal, -2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.sentence)
                        .font(.system(size: TaskFormMetrics.sentence, weight: .semibold))
                        .foregroundStyle(TaskColors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presentation.preview)
                        .font(.system(size: TaskFormMetrics.subline))
                        .foregroundStyle(date == nil ? TaskColors.danger : TaskColors.grey)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(date == nil ? "task_retry_validation" : "task_retry_preview")
                }
                .padding(.top, 12)
                if draft.mode == .minutes {
                    TaskFlowLayout(spacing: 6) {
                        ForEach([35, 45, 60], id: \.self) { minutes in
                            delayChip(minutes == 60 ? "1 hour" : "\(minutes) min",
                                      selected: Int(draft.minutes) == minutes,
                                      id: "task_retry_preset_\(minutes)") {
                                minutesFocused = false; usesCustomMinutes = false; draft.minutes = String(minutes)
                            }
                        }
                        delayChip("Custom", selected: usesCustomMinutes && ![35, 45, 60].contains(Int(draft.minutes) ?? 0),
                                  id: "task_retry_preset_custom") {
                            usesCustomMinutes = true; draft.minutes = customMinutes; minutesFocused = true
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, contentInset).padding(.top, 12).padding(.bottom, 12)
            if draft.mode == .minutes, usesCustomMinutes {
                Divider()
                customRow(valid: date != nil)
            }
            if draft.mode == .time {
                Divider()
                dateRows
            }
            Divider()
            Text(TaskEditorText.zoneLabel(.current, at: date ?? Date()))
                .font(.system(size: TaskFormMetrics.caption - 1))
                .foregroundStyle(TaskColors.grey)
                .padding(.horizontal, contentInset).padding(.vertical, 9)
                .accessibilityIdentifier("task_retry_timezone")
        }
        .background(cardFill, in: RoundedRectangle(cornerRadius: cardRadius))
        .disabled(saving).opacity(saving ? 0.55 : 1)
    }

    @ViewBuilder private var modePicker: some View {
        #if os(macOS)
        TaskSegmentedPicker(selection: $draft.mode, options: [(.minutes, "In minutes"), (.time, "At a time")],
                            identifier: "task_retry_mode", fills: true)
        #else
        Picker("Retry by", selection: $draft.mode) {
            Text("In minutes").tag(ScheduledTaskRetryDraft.Mode.minutes)
            Text("At a time").tag(ScheduledTaskRetryDraft.Mode.time)
        }
        .pickerStyle(.segmented).accessibilityIdentifier("task_retry_mode")
        #endif
    }

    private func delayChip(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(TaskChipButtonStyle(selected: selected, compact: TaskFormMetrics.compactShortcuts,
                                            unselectedFill: chipFill, height: TaskFormMetrics.compactShortcuts ? 26 : 34))
            #if os(iOS)
            .frame(minHeight: 44).contentShape(Rectangle())
            #endif
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    private func customRow(valid: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Minutes from now")
            Spacer(minLength: 4)
            TextField("90", text: $customMinutes)
                .textFieldStyle(.plain)
                .font(.system(size: TaskFormMetrics.sentence - 4, weight: .semibold).monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($minutesFocused)
                #if os(iOS)
                .keyboardType(.numberPad)
                .frame(width: 72, height: 34)
                #else
                .frame(width: 56, height: 28)
                #endif
                .background(TaskPalette.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(valid ? TaskColors.accentFill : TaskColors.danger, lineWidth: 1))
                .onChange(of: customMinutes) { _, text in if usesCustomMinutes { draft.minutes = text } }
                .accessibilityLabel("Minutes from now").accessibilityIdentifier("task_retry_minutes")
            Text("min").foregroundStyle(TaskColors.soft)
        }
        .font(.system(size: TaskDetailMetrics.body))
        .padding(.horizontal, contentInset).padding(.vertical, 8)
    }

    @ViewBuilder private var dateRows: some View {
        #if os(macOS)
        HStack { Text("Date"); Spacer(); TaskDatePill(date: $draft.date, identifier: "task_retry_date") }
            .padding(.horizontal, contentInset).frame(minHeight: 40)
        Divider()
        HStack { Text("Time"); Spacer(); TaskTimePill(date: $draft.date, identifier: "task_retry_time") }
            .padding(.horizontal, contentInset).frame(minHeight: 40)
        #else
        DatePicker("Date", selection: $draft.date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
            .accessibilityIdentifier("task_retry_date")
            .padding(.horizontal, contentInset).padding(.vertical, 7)
        Divider()
        DatePicker("Time", selection: $draft.date, displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("task_retry_time")
            .padding(.horizontal, contentInset).padding(.vertical, 7)
        #endif
    }

    private var explanation: some View {
        Text("Runs once more at this time. The regular schedule stays as it is. \(hostName) must be awake; if it’s asleep, the retry runs when it wakes.")
            #if os(macOS)
            .font(.system(size: 11))
            #else
            .font(.system(size: TaskFormMetrics.caption))
            #endif
            .foregroundStyle(TaskColors.grey)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var errorMessage: some View {
        if let error {
            Text("\(error)\nYour choice is kept. Check the connection and try again.")
                .font(.system(size: TaskFormMetrics.subline)).foregroundStyle(TaskColors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task_retry_error")
        }
    }

    private func confirmation(_ presentation: ScheduledTaskRetryPresentation) -> some View {
        let date = presentation.date
        return Button(action: schedule) {
            HStack(spacing: 8) {
                if saving { ProgressView().controlSize(.small).tint(.white) }
                Text(saving ? "Scheduling…" : presentation.confirmationTitle)
                    #if os(macOS)
                    .font(.system(size: 13, weight: .semibold))
                    #else
                    .font(.system(size: 17, weight: .semibold))
                    #endif
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(date == nil ? disabledConfirmationText : Color.white)
            .padding(.horizontal, 14)
            #if os(macOS)
            .frame(minHeight: 28)
            #else
            .frame(maxWidth: .infinity, minHeight: 50)
            #endif
            .background(date == nil ? chipFill : TaskColors.accentFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(TaskRetryConfirmationStyle()).disabled(saving || date == nil)
        .accessibilityIdentifier("task_retry_schedule")
    }

    private func schedule() {
        guard !saving else { return }
        do {
            let date = try draft.scheduledDate()
            minutesFocused = false; saving = true; error = nil
            Task {
                defer { saving = false }
                do { try await client.scheduleRetry(task.id, at: date); await saved(); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
}

/// Keep the progress button's fill and spinner visible while its action is disabled.
private struct TaskRetryConfirmationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The Mac's version of the Ask bar: one button that opens the task's chat in iTerm.
struct TaskChatButton: View {
    var title = "Change with chat"
    let busy: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bubble.left").font(.system(size: 13)).foregroundStyle(TaskColors.accent)
                    }
                    Text(busy ? "Opening iTerm…" : title).font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(Color.primary.opacity(0.09), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("task_change_with_chat")
            Text("Opens a Claude Code session in iTerm with this task’s settings.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
