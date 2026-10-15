import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

#if os(macOS)
/// Mac controls for the edit form, sized to the 400pt dA2 boards. The phone uses system pickers instead.

/// A "9:00 AM" pill in accent text; clicking it opens a time field.
struct TaskTimePill: View {
    @Binding var date: Date
    let identifier: String
    @State private var editing = false
    @Environment(\.timeZone) private var zone

    var body: some View {
        Button { editing = true } label: { TaskPillLabel(text: text) }
            .buttonStyle(.plain)
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .padding(12)
            }
            .accessibilityLabel("Time, \(text)")
            .accessibilityIdentifier(identifier)
    }

    private var text: String {
        let f = DateFormatter(); f.timeZone = zone; f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }
}

/// A "Fri, Oct 16" pill in accent text; clicking it opens a calendar.
struct TaskDatePill: View {
    @Binding var date: Date
    let identifier: String
    /// End dates carry the year ("Thu, Dec 31, 2026"); a start date does not.
    var showsYear = false
    @State private var editing = false
    @Environment(\.timeZone) private var zone

    var body: some View {
        Button { editing = true } label: { TaskPillLabel(text: text) }
            .buttonStyle(.plain)
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                TaskMonthCalendar(selection: $date, zone: zone).frame(width: 300).padding(12)
            }
            .accessibilityLabel("Date, \(text)")
            .accessibilityIdentifier(identifier)
    }

    private var text: String {
        let f = DateFormatter(); f.timeZone = zone; f.setLocalizedDateFormatFromTemplate(showsYear ? "EEEMMMdyyyy" : "EEEMMMd")
        return f.string(from: date)
    }
}

/// The boards' segmented control: a tinted track with a lighter pill on the pick.
/// AppKit's segmented control neither stretches nor matches the board's colors.
struct TaskSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    let identifier: String
    /// Stretch to the width given, splitting it evenly (Once / Repeat). Otherwise each segment fits its title.
    var fills = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: on ? .semibold : .medium))
                        .foregroundStyle(TaskColors.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(maxWidth: fills ? .infinity : nil, minHeight: 24)
                        .background(on ? Color.primary.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("\(identifier)_\(option.title)")
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

struct TaskPillLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(TaskColors.accent)
            .padding(.horizontal, 11).frame(height: 28)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

/// A full-width month grid: past days dimmed, today in accent, the pick filled.
/// Picking a day keeps the selection's time of day.
struct TaskMonthCalendar: View {
    @Binding var selection: Date
    let zone: TimeZone
    @State private var month: Date?

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone; cal.firstWeekday = 1
        return cal
    }

    var body: some View {
        let cal = calendar
        let shown = month ?? cal.dateInterval(of: .month, for: selection)!.start
        let today = cal.startOfDay(for: Date())
        VStack(spacing: 8) {
            HStack {
                Text(Self.monthTitle(shown, zone: zone)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(TaskColors.accent)
                Spacer()
                Group {
                    Button { month = cal.date(byAdding: .month, value: -1, to: shown) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month").accessibilityIdentifier("task_calendar_previous")
                    Button { month = cal.date(byAdding: .month, value: 1, to: shown) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month").accessibilityIdentifier("task_calendar_next")
                }
                .foregroundStyle(TaskColors.accent)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.bottom, 8)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cal.shortStandaloneWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(Self.cells(shown, cal: cal).enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        dayCell(day, today: today, cal: cal)
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
            }
        }
        .accessibilityIdentifier("task_once_date")
    }

    private func dayCell(_ day: Date, today: Date, cal: Calendar) -> some View {
        let picked = cal.isDate(day, inSameDayAs: selection)
        let isToday = cal.isDate(day, inSameDayAs: today)
        let past = day < today
        return Button {
            let time = cal.dateComponents([.hour, .minute], from: selection)
            selection = cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 13, weight: picked || isToday ? .bold : .semibold))
                .foregroundStyle(picked ? Color.white : isToday ? TaskColors.accent : past ? Color.secondary.opacity(0.6) : Color.primary)
                .frame(width: 24, height: 24)
                .background(picked ? TaskColors.accentFill : Color.clear, in: Circle())
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(past)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// The month's days, padded with leading blanks so the first lands under its weekday.
    static func cells(_ month: Date, cal: Calendar) -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    static func monthTitle(_ month: Date, zone: TimeZone) -> String {
        let f = DateFormatter(); f.timeZone = zone; f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f.string(from: month)
    }
}
#endif
