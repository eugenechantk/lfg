import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

/// Sizes for the edit form. Phone values follow the tA2d boards; the Mac uses the 400pt dA2 boards.
enum TaskFormMetrics {
    #if os(macOS)
    static let sentence: CGFloat = 16, subline: CGFloat = 12
    static let chipFont: CGFloat = 12, chipHeight: CGFloat = 28
    static let dayWidth: CGFloat = 30, dayHeight: CGFloat = 26, dayFont: CGFloat = 13
    static let nextFont: CGFloat = 12, nextHeight: CGFloat = 22
    static let caption: CGFloat = 12, endsWidth: CGFloat = 196, shortcutFont: CGFloat = 12
    static let compactShortcuts = true
    #else
    static let sentence: CGFloat = 21, subline: CGFloat = 14
    static let chipFont: CGFloat = 14, chipHeight: CGFloat = 32
    static let dayWidth: CGFloat = 38, dayHeight: CGFloat = 38, dayFont: CGFloat = 15
    static let nextFont: CGFloat = 13, nextHeight: CGFloat = 26
    static let caption: CGFloat = 13, endsWidth: CGFloat = 222, shortcutFont: CGFloat = 13
    static let compactShortcuts = false
    #endif
}

/// The "When" section of the edit form: Once or Repeat, the sentence, the controls for the pick,
/// Ends, and the next runs the host will use. All schedule logic lives in `ScheduleDraft`.
/// The phone renders it as a Form section; the Mac as one card with divided rows.
struct ScheduleEditorSection: View {
    @Binding var draft: ScheduleDraft
    let preview: SchedulePreview?
    let changeTimezone: () -> Void

    private var zone: TimeZone { TimeZone(identifier: draft.timezone) ?? .current }
    #if os(macOS)
    private static let sentenceGap: CGFloat = 5
    #else
    private static let sentenceGap: CGFloat = 2
    #endif

    var body: some View {
        #if os(macOS)
        macCard.environment(\.timeZone, zone)
        #else
        Section {
            // One block on the board: mode, sentence, presets and days, with no separators between them.
            VStack(alignment: .leading, spacing: 0) {
                modePicker
                sentence.padding(.top, 14)
                if draft.mode == .repeating {
                    presetRow.padding(.top, 10)
                    if draft.preset == .weekly || draft.preset == .weekdays { daysRow.padding(.top, 10) }
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 11, trailing: 16))
            if draft.mode == .once { onceRows } else { repeatRows }
            zoneLine.taskFormRow(vertical: 9)
        } header: {
            Text("When")
        }
        .environment(\.timeZone, zone)
        #endif
    }

    @ViewBuilder
    private var modePicker: some View {
        #if os(macOS)
        TaskSegmentedPicker(selection: $draft.mode, options: [(.once, "Once"), (.repeating, "Repeat")],
                            identifier: "task_schedule_mode", fills: true)
        #else
        Picker("Schedule type", selection: $draft.mode) {
            Text("Once").tag(ScheduleDraft.Mode.once)
            Text("Repeat").tag(ScheduleDraft.Mode.repeating)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("task_schedule_mode")
        #endif
    }

    private var sentence: some View {
        VStack(alignment: .leading, spacing: Self.sentenceGap) {
            Text(draft.sentence())
                .font(.system(size: TaskFormMetrics.sentence, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task_schedule_sentence")
            Text(draft.subline())
                .font(.system(size: TaskFormMetrics.subline))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("task_schedule_subline")
        }
    }

    private var zoneLine: some View {
        HStack(spacing: 4) {
            Text(TaskEditorText.zoneLabel(zone))
            Text("·")
            Button("Change", action: changeTimezone)
                .buttonStyle(.plain)
                .foregroundStyle(TaskColors.accent)
                .accessibilityIdentifier("task_timezone")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    #if os(macOS)
    /// One card: the pick on top, then divided rows down to the time zone line.
    private var macCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                sentence
                if draft.mode == .repeating {
                    // The strip scrolls to the card's edge, not the content inset.
                    presetRow.padding(.horizontal, -14)
                    if draft.preset == .weekly || draft.preset == .weekdays { daysRow.padding(.top, -4) }
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 9)
            if draft.mode == .once {
                TaskMonthCalendar(selection: $draft.start, zone: zone)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
                macRow { HStack { Text("Time"); Spacer(); TaskTimePill(date: $draft.start, identifier: "task_once_time") } }
                macRow {
                    VStack(alignment: .leading, spacing: 8) {
                        onceShortcuts
                        Text("Runs once, then the task moves to Closed.")
                            .font(.system(size: TaskFormMetrics.caption)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                }
            } else {
                if draft.preset.everyUnit != nil { macRow { everyRow } }
                if !draft.isClockAligned { macRow { startsRow } }
                if hasAtRow { macRow { atRow } }
                if draft.preset == .custom { macRow { customRow.padding(.vertical, 10) } }
                // Ends and its sub-row are one block on the board.
                macRow {
                    VStack(alignment: .leading, spacing: 0) {
                        endsRow.frame(minHeight: 43)
                        if draft.ends == .after { countRow.padding(.bottom, 10) }
                        if draft.ends == .onDate { endDateRow.padding(.bottom, 10) }
                    }
                }
                if preview?.nextRuns.isEmpty == false { macRow { nextRunsRow.padding(.vertical, 8) } }
            }
            macRow(minHeight: 35) { zoneLine }
        }
        .font(.system(size: 13))
        .background(TaskPalette.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func macRow<Content: View>(minHeight: CGFloat = 43, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }

    private var hasAtRow: Bool {
        switch draft.preset {
        case .hourly, .daily: draft.isClockAligned
        case .weekdays, .weekly, .monthly: true
        default: false
        }
    }
    #endif

    /// Full labels that wrap to a second line rather than truncate, as on the board.
    private var onceShortcuts: some View {
        TaskFlowLayout(spacing: 6) {
            ForEach(TaskEditorText.onceShortcuts(zone: zone), id: \.label) { shortcut in
                Button(shortcut.label) { draft.start = shortcut.date }
                    .buttonStyle(TaskChipButtonStyle(selected: false, size: TaskFormMetrics.shortcutFont, compact: TaskFormMetrics.compactShortcuts))
                    .accessibilityIdentifier("task_once_shortcut_\(shortcut.label)")
            }
        }
    }

    // MARK: Once

    @ViewBuilder
    private var onceRows: some View {
        DatePicker("Date", selection: $draft.start, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .accessibilityIdentifier("task_once_date")
        DatePicker("Time", selection: $draft.start, displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("task_once_time")
        VStack(alignment: .leading, spacing: 6) {
            onceShortcuts
            Text("Runs once, then the task moves to Closed.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    // MARK: Repeat

    /// The phone's rows below the top block (presets and days live in that block). Rows use the
    /// board's tighter padding; Ends keeps its sub-row in the same block.
    @ViewBuilder
    private var repeatRows: some View {
        if draft.preset.everyUnit != nil { everyRow.taskFormRow() }
        if !draft.isClockAligned { startsRow.taskFormRow() }
        if hasAtRowPhone { atRow.taskFormRow() }
        if draft.preset == .custom { customRow.taskFormRow(vertical: 10) }
        VStack(alignment: .leading, spacing: 8) {
            endsRow
            if draft.ends == .after { countRow }
            if draft.ends == .onDate { endDateRow }
        }
        .taskFormRow()
        nextRunsRow.taskFormRow()
    }

    private var hasAtRowPhone: Bool {
        switch draft.preset {
        case .hourly, .daily: draft.isClockAligned
        case .weekdays, .weekly, .monthly: true
        default: false
        }
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ScheduleDraft.Preset.allCases) { preset in
                    Button(preset.title) {
                        draft.preset = preset
                        if preset == .weekdays { draft.days = [1, 2, 3, 4, 5] }
                    }
                    .buttonStyle(TaskChipButtonStyle(selected: draft.preset == preset))
                    .accessibilityIdentifier("task_preset_\(preset.rawValue)")
                    .accessibilityAddTraits(draft.preset == preset ? .isSelected : [])
                }
            }
            #if os(macOS)
            .padding(.horizontal, 14)
            #endif
        }
        .listRowSeparator(.hidden, edges: .top)
    }

    @ViewBuilder
    private var everyRow: some View {
        if let unit = draft.preset.everyUnit {
            HStack {
                Text("Every")
                Spacer()
                // Field and unit hug the right edge; the field moves with the unit's length.
                TaskNumberField(value: everyBinding, range: 1...unit.limit, identifier: "task_every")
                Text(everyBinding.wrappedValue == 1 ? unit.singular : unit.plural)
                    .foregroundStyle(TaskTone.soft.color)
            }
        }
    }

    private var daysRow: some View {
        WeekdayPicker(days: Binding(get: { draft.days }, set: { draft.days = $0; draft.preset = .weekly }))
    }

    private var startsRow: some View {
        HStack {
            Text("Starts")
            Spacer()
            #if os(macOS)
            TaskDatePill(date: $draft.start, identifier: "task_start_date")
            TaskTimePill(date: $draft.start, identifier: "task_start_time")
            #else
            DatePicker("Start date", selection: $draft.start, displayedComponents: .date).labelsHidden()
            DatePicker("Start time", selection: $draft.start, displayedComponents: .hourAndMinute).labelsHidden()
            #endif
        }
        .accessibilityIdentifier("task_starts")
    }

    private var customRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cron expression").font(.system(size: TaskFormMetrics.caption)).foregroundStyle(.secondary)
            // A bordered input on the card, as on both boards.
            TextField("0 9 * * 1-5", text: $draft.customExpression)
                .autocorrectionDisabled()
                #if os(iOS)
                .font(.system(size: 17, design: .monospaced))
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12).frame(height: 40)
                #else
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).frame(height: 28)
                #endif
                .background(TaskPalette.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TaskColors.accentFill, lineWidth: 1))
                .accessibilityIdentifier("task_cron_expression")
        }
    }

    private var endsRow: some View {
        HStack {
            Text("Ends")
            Spacer()
            #if os(macOS)
            TaskSegmentedPicker(selection: $draft.ends, options: ScheduleDraft.Ends.allCases.map { ($0, $0.title) },
                                identifier: "task_ends")
                .fixedSize()
            #else
            Picker("Ends", selection: $draft.ends) {
                ForEach(ScheduleDraft.Ends.allCases) { ends in Text(ends.title).tag(ends) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: TaskFormMetrics.endsWidth)
            .accessibilityIdentifier("task_ends")
            #endif
        }
    }

    private var countRow: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Text("Number of runs")
                Spacer()
                TaskNumberField(value: $draft.count, range: 1...1000, identifier: "task_run_count")
            }
            lastRunLine
        }
    }

    private var endDateRow: some View {
        VStack(alignment: .trailing, spacing: 6) {
            #if os(macOS)
            HStack {
                Text("End date")
                Spacer()
                TaskDatePill(date: $draft.endDate, identifier: "task_end_date", showsYear: true)
            }
            #else
            DatePicker("End date", selection: $draft.endDate, in: Date()..., displayedComponents: .date)
                .accessibilityIdentifier("task_end_date")
            #endif
            lastRunLine
        }
    }

    @ViewBuilder
    private var lastRunLine: some View {
        if let last = preview?.lastRun {
            Text("Last run: \(draft.dayAndTime(last))")
                .font(.system(size: TaskFormMetrics.caption)).foregroundStyle(.secondary)
                .accessibilityIdentifier("task_last_run")
        }
    }

    @ViewBuilder
    private var nextRunsRow: some View {
        if let runs = preview?.nextRuns, !runs.isEmpty {
            let chips = draft.chips(runs)
            VStack(alignment: .leading, spacing: 6) {
                Text("Next runs").font(.system(size: TaskFormMetrics.caption)).foregroundStyle(.secondary)
                // The board's count for this schedule, or as many as fit on one line.
                ViewThatFits(in: .horizontal) {
                    ForEach(Array(stride(from: chips.count, through: 1, by: -1)), id: \.self) { count in
                        HStack(spacing: 6) {
                            ForEach(Array(chips.prefix(count).enumerated()), id: \.offset) { _, text in NextRunChip(text: text) }
                        }
                    }
                }
                .accessibilityIdentifier("task_next_runs")
            }
        }
    }

    @ViewBuilder
    private var atRow: some View {
        switch draft.preset {
        case .hourly where draft.isClockAligned:
            HStack {
                Text("At minute")
                Spacer()
                Menu {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                        Button(String(format: ":%02d", m)) { draft.minute = m }
                    }
                } label: {
                    Text(String(format: ":%02d", draft.minute)).monospacedDigit()
                        .padding(.horizontal, 11).frame(height: TaskFormMetrics.chipHeight + 2)
                        .background(TaskPalette.control, in: RoundedRectangle(cornerRadius: 9))
                }
                #if os(macOS)
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                #endif
                .accessibilityIdentifier("task_at_minute")
            }
        case .daily where draft.isClockAligned, .weekdays, .weekly:
            #if os(macOS)
            HStack { Text("Time"); Spacer(); TaskTimePill(date: timeBinding, identifier: "task_time") }
            #else
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("task_time")
            #endif
        case .monthly:
            #if os(macOS)
            // One label on the board ("On the 1st at"); the day still opens a menu.
            HStack(spacing: 8) {
                Menu {
                    ForEach(1...28, id: \.self) { d in Button(TaskTimeFormat.ordinal(d)) { draft.dayOfMonth = d } }
                } label: {
                    Text("On the \(TaskTimeFormat.ordinal(draft.dayOfMonth)) at").contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityIdentifier("task_month_day")
                Spacer()
                TaskTimePill(date: timeBinding, identifier: "task_time")
            }
            #else
            // One label on the board ("On the 1st at"); the day still opens a menu.
            HStack(spacing: 8) {
                Menu {
                    ForEach(1...28, id: \.self) { d in Button(TaskTimeFormat.ordinal(d)) { draft.dayOfMonth = d } }
                } label: {
                    Text("On the \(TaskTimeFormat.ordinal(draft.dayOfMonth)) at")
                }
                .tint(TaskColors.ink)
                .accessibilityIdentifier("task_month_day")
                Spacer()
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute).labelsHidden()
            }
            #endif
        default:
            EmptyView()
        }
    }

    private var everyBinding: Binding<Int> {
        Binding(get: {
            switch draft.preset { case .minutes: draft.everyMinutes; case .hourly: draft.everyHours; default: draft.everyDays }
        }, set: { n in
            switch draft.preset { case .minutes: draft.everyMinutes = n; case .hourly: draft.everyHours = n; default: draft.everyDays = n }
        })
    }

    /// The pick's time of day as a Date the time picker can edit.
    private var timeBinding: Binding<Date> {
        Binding(get: {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
            return cal.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: draft.start) ?? draft.start
        }, set: { date in
            var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
            let c = cal.dateComponents([.hour, .minute], from: date)
            draft.hour = c.hour ?? 9; draft.minute = c.minute ?? 0
        })
    }
}

struct NextRunChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: TaskFormMetrics.nextFont).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(TaskColors.chipText)
            .padding(.horizontal, 8).frame(height: TaskFormMetrics.nextHeight)
            .background(TaskColors.chipFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A typed number field, no − / + buttons. Out-of-range values clamp when editing ends.
struct TaskNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let identifier: String
    @FocusState private var focused: Bool
    #if os(macOS)
    private static let font: CGFloat = 13, size = CGSize(width: 56, height: 28)
    #else
    private static let font: CGFloat = 17, size = CGSize(width: 64, height: 34)
    #endif

    var body: some View {
        TextField("", value: $value, format: .number)
            .font(.system(size: Self.font, weight: .semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            #if os(iOS)
            .keyboardType(.numberPad)
            #else
            .textFieldStyle(.plain)
            #endif
            .focused($focused)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(TaskPalette.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TaskColors.accentFill, lineWidth: 1))
            .onChange(of: focused) { _, isFocused in
                if !isFocused { value = min(max(value, range.lowerBound), range.upperBound) }
            }
            .accessibilityIdentifier(identifier)
    }
}

/// Seven day dots, Monday first. 0 = Sunday.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>
    private static let order = [1, 2, 3, 4, 5, 6, 0]

    var body: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let names = Calendar.current.standaloneWeekdaySymbols
        HStack {
            ForEach(Self.order, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(symbols[day])
                        .font(.system(size: TaskFormMetrics.dayFont, weight: .semibold))
                        .foregroundStyle(on ? Color(white: 0.05) : Color.secondary)
                        .frame(width: TaskFormMetrics.dayWidth, height: TaskFormMetrics.dayHeight)
                        .background(on ? TaskColors.ink : TaskPalette.control, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day])
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("task_day_\(day)")
                if day != 0 { Spacer(minLength: 0) }
            }
        }
    }
}

extension View {
    /// A form row with the board's padding instead of the system's taller default.
    @ViewBuilder
    func taskFormRow(vertical: CGFloat = 8) -> some View {
        #if os(iOS)
        self.listRowInsets(EdgeInsets(top: vertical, leading: 16, bottom: vertical, trailing: 16))
        #else
        self
        #endif
    }

    /// Save as a filled blue capsule, as on the form boards.
    @ViewBuilder
    func prominentSaveStyle() -> some View {
        // The board's fill and a white label, not the system tint's.
        if #available(iOS 26.0, macOS 26.0, *) { self.buttonStyle(.glassProminent).tint(TaskColors.accentFill).foregroundStyle(.white) }
        else { self.buttonStyle(.borderedProminent).tint(TaskColors.accentFill).foregroundStyle(.white) }
    }
}

/// Lays children left to right and wraps to a new line when the next one does not fit.
struct TaskFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map { $0.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map { row in row.map { subviews[$0].sizeThatFits(.unspecified).width }.reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0)) }.max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for index in subviews.indices {
            let w = subviews[index].sizeThatFits(.unspecified).width
            if !rows[rows.count - 1].isEmpty, x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append(index)
            x += w + spacing
        }
        return rows
    }
}

struct TaskChipButtonStyle: ButtonStyle {
    let selected: Bool
    var size: CGFloat = TaskFormMetrics.chipFont
    /// Shortcut chips are a little smaller than the preset chips on the Mac board.
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, compact ? 10 : 12).frame(height: compact ? TaskFormMetrics.chipHeight - 2 : TaskFormMetrics.chipHeight)
            .contentShape(Capsule())
            .background(selected ? TaskColors.accentFill : TaskPalette.control, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

enum TaskEditorText {
    /// "Hong Kong time (GMT+8)".
    static func zoneLabel(_ zone: TimeZone) -> String {
        let name = zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
        let seconds = zone.secondsFromGMT()
        let h = seconds / 3600, m = abs(seconds % 3600) / 60
        let offset = m == 0 ? "GMT\(h >= 0 ? "+" : "")\(h)" : String(format: "GMT%@%d:%02d", h >= 0 ? "+" : "-", abs(h), m)
        let city = name.replacingOccurrences(of: " Standard Time", with: " time").replacingOccurrences(of: " Time", with: " time")
        return "\(city) (\(offset))"
    }

    /// Tomorrow 9 AM, the coming Monday 9 AM, and next week's Friday 9 AM.
    static func onceShortcuts(zone: TimeZone, now: Date = Date()) -> [(label: String, date: Date)] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let today = cal.startOfDay(for: now)
        func at9(_ d: Date) -> Date { cal.date(bySettingHour: 9, minute: 0, second: 0, of: d)! }
        let tomorrow = at9(cal.date(byAdding: .day, value: 1, to: today)!)
        let monday = at9(cal.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!)
        let comingFriday = cal.nextDate(after: today, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)!
        let nextFriday = at9(cal.date(byAdding: .day, value: 7, to: comingFriday)!)
        return [("Tomorrow 9 AM", tomorrow), ("Monday 9 AM", monday), ("Next Friday", nextFriday)]
    }
}

/// Full-screen editor for a task's instructions, pushed from the form.
struct TaskInstructionsEditor: View {
    @Binding var text: String
    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 17))
            .padding(.horizontal, 12)
            .navigationTitle("Instructions")
            .accessibilityIdentifier("task_prompt")
    }
}
