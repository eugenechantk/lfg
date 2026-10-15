import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

/// The boards' dark-mode tokens. Light mode keeps the system colors.
enum TaskColors {
    #if os(macOS)
    static let accent = adaptive(light: .accentColor, dark: Color(red: 0x8F / 255, green: 0xB8 / 255, blue: 1))
    static let accentFill = adaptive(light: .accentColor, dark: Color(red: 0x3B / 255, green: 0x8E / 255, blue: 1))
    /// Next-run chips.
    static let chipText = adaptive(light: .accentColor, dark: Color(red: 0x9C / 255, green: 0xC2 / 255, blue: 1))
    static let chipFill = Color(red: 0x3B / 255, green: 0x8E / 255, blue: 1).opacity(0.16)
    static let page = adaptive(light: Color(nsColor: .windowBackgroundColor), dark: Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1E / 255))
    #else
    static let accent = adaptive(light: .accentColor, dark: Color(red: 0x40 / 255, green: 0x9C / 255, blue: 1))
    static let accentFill = adaptive(light: .accentColor, dark: Color(red: 0x0A / 255, green: 0x6E / 255, blue: 0xE0 / 255))
    static let chipText = adaptive(light: .accentColor, dark: Color(red: 0x64 / 255, green: 0xB0 / 255, blue: 1))
    static let chipFill = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 1).opacity(0.2)
    #endif
    #if os(macOS)
    // The dA2 boards use the lighter red, amber and green everywhere; system orange only fills the
    // "Answer in iTerm" button and the waiting dot.
    static let danger = adaptive(light: .red, dark: Color(red: 1, green: 0x6B / 255, blue: 0x61 / 255))
    static let warning = adaptive(light: .orange, dark: Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255))
    static let success = adaptive(light: .green, dark: Color(red: 0x5B / 255, green: 0xE3 / 255, blue: 0x7A / 255))
    static let dangerLabel = danger
    static let warningLabel = warning
    /// The board's #FF9F0A; macOS 26's system orange renders redder.
    static let warningDot = adaptive(light: .orange, dark: Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255))
    static let warningFill = warningDot
    /// Timeline nodes use their own, deeper pair (#32D74B, #FF5A50).
    static let successNode = adaptive(light: .green, dark: Color(red: 0x32 / 255, green: 0xD7 / 255, blue: 0x4B / 255))
    static let dangerNode = adaptive(light: .red, dark: Color(red: 1, green: 0x5A / 255, blue: 0x50 / 255))
    /// The boards' near-white ink (#F4F4F6), brighter than the Mac's primary label.
    static let ink = adaptive(light: .primary, dark: Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255))
    #else
    // The tA2d boards use system red and amber, with a lighter pair only for the failed and waiting card labels.
    static let danger = Color.red
    static let warning = Color.orange
    static let success = Color.green
    static let dangerLabel = adaptive(light: .red, dark: Color(red: 1, green: 0x69 / 255, blue: 0x61 / 255))
    static let warningLabel = adaptive(light: .orange, dark: Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255))
    static let warningDot = warning
    static let warningFill = warning
    static let successNode = success
    static let dangerNode = danger
    static let ink = Color.primary
    #endif
    #if os(macOS)
    static let chevron = adaptive(light: Color(white: 0.7), dark: Color(red: 0x5A / 255, green: 0x5A / 255, blue: 0x62 / 255))
    #else
    static let chevron = adaptive(light: Color(white: 0.78), dark: Color(red: 0x48 / 255, green: 0x48 / 255, blue: 0x4A / 255))
    #endif

    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #endif
    }
}

/// Tones from `TaskRowModel` and the task view.
extension TaskTone {
    var color: Color {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .warning: TaskColors.warning
        case .danger: TaskColors.danger
        case .success: TaskColors.success
        case .accent: TaskColors.accent
        case .soft: .primary.opacity(0.82)
        }
    }
}

/// Font sizes for the Tasks screens: the phone board uses 17/15/13, the 400pt Mac board 14/12/12.
enum TaskListMetrics {
    #if os(macOS)
    static let time: CGFloat = 15, timeDetail: CGFloat = 11, title: CGFloat = 14, when: CGFloat = 12, result: CGFloat = 12
    static let timeColumn: CGFloat = 58, header: CGFloat = 13, headerHint: CGFloat = 11
    // Line boxes from the board, so rows keep its rhythm.
    static let timeLine: CGFloat = 19, timeDetailLine: CGFloat = 15, titleLine: CGFloat = 19, whenLine: CGFloat = 16, resultLine: CGFloat = 16
    static let rowTop: CGFloat = 9, rowBottom: CGFloat = 10, chevron: CGFloat = 9
    #else
    static let time: CGFloat = 17, timeDetail: CGFloat = 12, title: CGFloat = 17, when: CGFloat = 15, result: CGFloat = 13
    static let timeColumn: CGFloat = 62, header: CGFloat = 15, headerHint: CGFloat = 13
    static let timeLine: CGFloat = 22, timeDetailLine: CGFloat = 16, titleLine: CGFloat = 22, whenLine: CGFloat = 20, resultLine: CGFloat = 18
    static let rowTop: CGFloat = 11, rowBottom: CGFloat = 12, chevron: CGFloat = 10
    #endif
}

/// One task in the list: a time column, then title, schedule line and last result. No buttons.
struct TaskRowView: View {
    let model: TaskRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.time)
                    .font(.system(size: TaskListMetrics.time, weight: .semibold).monospacedDigit())
                    .foregroundStyle(model.timeTone.color)
                    .frame(height: TaskListMetrics.timeLine)
                Text(model.timeDetail)
                    .font(.system(size: TaskListMetrics.timeDetail))
                    .foregroundStyle(.secondary)
                    .frame(height: TaskListMetrics.timeDetailLine)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: TaskListMetrics.timeColumn, alignment: .leading)
            .padding(.top, 1)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: TaskListMetrics.title, weight: titleWeight))
                    .foregroundStyle(.primary)
                    .frame(height: TaskListMetrics.titleLine)
                Text(model.when)
                    .font(.system(size: TaskListMetrics.when))
                    .foregroundStyle(.secondary)
                    .frame(height: TaskListMetrics.whenLine)
                HStack(spacing: 5) {
                    TaskResultGlyphView(glyph: model.glyph)
                    Text(model.result)
                        .font(.system(size: TaskListMetrics.result))
                        .foregroundStyle(model.resultTone.color)
                }
                .frame(height: TaskListMetrics.resultLine)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The hairline starts at the title column.
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            // The system disclosure chevron is larger than the board's (and absent on the Mac); the row draws its own.
            Image(systemName: "chevron.right")
                .font(.system(size: TaskListMetrics.chevron, weight: .bold))
                .foregroundStyle(TaskColors.chevron)
                .frame(maxHeight: .infinity)
                .padding(.leading, 6)
                .accessibilityHidden(true)
        }
        .padding(.top, TaskListMetrics.rowTop)
        .padding(.bottom, TaskListMetrics.rowBottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([model.title, model.when, model.result, [model.time, model.timeDetail].filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private var titleWeight: Font.Weight {
        #if os(macOS)
        .semibold
        #else
        .regular
        #endif
    }
}

struct TaskResultGlyphView: View {
    let glyph: TaskResultGlyph
    #if os(macOS)
    private static let mark: CGFloat = 8, question = "bubble.left"
    #else
    private static let mark: CGFloat = 10, question = "questionmark.bubble"
    #endif
    var body: some View {
        switch glyph {
        case .none: EmptyView()
        case .success: Image(systemName: "checkmark").font(.system(size: Self.mark, weight: .heavy)).foregroundStyle(TaskColors.success)
        case .failure: Image(systemName: "xmark").font(.system(size: Self.mark, weight: .heavy)).foregroundStyle(TaskColors.danger)
        case .question: Image(systemName: Self.question).font(.system(size: Self.mark, weight: .semibold)).foregroundStyle(TaskColors.warning)
        case .running:
            Circle().fill(.green).frame(width: 7, height: 7)
                .background(Circle().fill(.green.opacity(0.25)).frame(width: 13, height: 13))
                .frame(width: 13, height: 13)
        case .paused: Image(systemName: "pause.fill").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// A collapsible group header: chevron, label, count and an optional hint at the right.
struct TaskSectionHeader: View {
    let section: TaskListSection
    let count: Int
    let collapsed: Bool
    let toggle: () -> Void
    #if os(macOS)
    private static let chevronColumn: CGFloat = 9
    #else
    private static let chevronColumn: CGFloat = 13
    #endif

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: TaskListMetrics.header - 6, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.chevronColumn)
                Text(section.title)
                    .font(.system(size: TaskListMetrics.header, weight: .semibold))
                    .foregroundStyle(section == .needsInput ? TaskColors.warning : Color.secondary)
                Text("\(count)")
                    .font(.system(size: TaskListMetrics.header))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !collapsed, let hint = section.hint {
                    Text(hint).font(.system(size: TaskListMetrics.headerHint)).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            #if os(iOS)
            .padding(.leading, 20).padding(.trailing, 16)
            .padding(.top, 14).padding(.bottom, 6)
            #else
            .padding(.leading, 11).padding(.trailing, 8)
            .padding(.top, 12).padding(.bottom, 6)
            #endif
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task_group_\(section.rawValue)")
        .accessibilityLabel("\(section.title), \(count) tasks")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityHint("Double tap to \(collapsed ? "expand" : "collapse") this group")
    }
}
