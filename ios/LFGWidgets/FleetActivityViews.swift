import SwiftUI

// Card atoms for the aggregate Live Activity, at the measured tokens of design
// frame `27-live-activity-lock-screen`. See `.claude/fleet-live-activity/plan.md`.

enum FleetRowState: String {
    case working
    case needsInput

    var tint: Color {
        switch self {
        case .working: .lfgStateWorking
        case .needsInput: .lfgStateNeedsInput
        }
    }

    var accessibilityName: String { rawValue }
}

extension LFGFleetAttributes.Row {
    var normalizedState: FleetRowState {
        // Tolerate the retired `"blocked"` spelling from an in-flight activity
        // started by an older build.
        state == "blocked" ? .needsInput : FleetRowState(rawValue: state) ?? .working
    }
}

extension LFGFleetAttributes.ContentState {
    var activeTotal: Int { working + needsInput }
}

/// A `● 2` pair in the header. Hidden at zero — the design's mock happens to have
/// all counters non-zero, and rendering `● 0` reads as noise rather than data.
struct FleetCounter: View {
    let state: FleetRowState
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Circle()
                    .fill(state.tint)
                    .frame(width: 6, height: 6)
                Text("\(count)")
                    .font(.system(size: 13))
                    .foregroundStyle(.lfgLabelTertiary)
                    .monospacedDigit()
            }
            .accessibilityIdentifier("la.counter.\(state.accessibilityName)")
        }
    }
}

struct FleetHeader: View {
    let state: LFGFleetAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(state.activeTotal)")
                .font(.system(size: 20, weight: .semibold))
                .kerning(-0.2)
                .foregroundStyle(.lfgLabelPrimary)
                .monospacedDigit()

            Text("Active")
                .font(.system(size: 15))
                .foregroundStyle(.lfgLabelSecondary)

            Spacer(minLength: 4)

            HStack(spacing: 9) {
                FleetCounter(state: .working, count: state.working)
                FleetCounter(state: .needsInput, count: state.needsInput)
            }
        }
        .accessibilityIdentifier("la.fleet.header")
    }
}

struct FleetRowView: View {
    let row: LFGFleetAttributes.Row

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(row.normalizedState.tint)
                .frame(width: 7, height: 7)

            Text(row.title.isEmpty ? "Session" : row.title)
                .font(.system(size: 15))
                .foregroundStyle(.lfgLabelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            ElapsedTimeText(since: row.since)
                .font(.system(size: 15))
                .foregroundStyle(.lfgLabelTertiary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .accessibilityIdentifier("la.fleet.row.\(row.normalizedState.accessibilityName)")
    }
}

struct FleetOverflowText: View {
    let more: Int

    var body: some View {
        if more > 0 {
            Text("\(more) More")
                .font(.system(size: 15))
                .foregroundStyle(.lfgLabelQuaternary)
                .padding(.leading, 16)
                .accessibilityIdentifier("la.fleet.more")
        }
    }
}

/// The lock-screen card. Row count is capped upstream by
/// `FleetActivitySnapshot.maxRows` — the lock screen is a fixed ~160pt frame that
/// center-clips overheight content, silently dropping this header.
struct FleetActivityCard: View {
    let state: LFGFleetAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FleetHeader(state: state)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(state.rows, id: \.sid) { row in
                    FleetRowView(row: row)
                }
                FleetOverflowText(more: state.more)
            }
            .padding(.top, 9)
        }
        .padding(.top, 13)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .accessibilityIdentifier("la.fleet.card")
    }
}

struct ElapsedTimeText: View {
    let since: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(compactElapsed(since: since, at: context.date))
        }
    }
}

func compactElapsed(since: Double, at date: Date) -> String {
    guard since > 0 else { return "now" }
    let seconds = max(0, Int(date.timeIntervalSince1970 - since))
    guard seconds >= 60 else { return "now" }

    let minutes = seconds / 60
    guard minutes >= 60 else { return "\(minutes)m" }

    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
}

// Declared on `Color` so `Color.lfgX` and Color-typed positions work, then
// re-exposed on `ShapeStyle` so the leading-dot form resolves in
// `.foregroundStyle(.lfgX)` / `.fill(.lfgX)` — a plain `extension Color` does
// NOT reach those, which is what broke the first build.
extension ShapeStyle where Self == Color {
    static var lfgCardBackground: Color { .lfgCardBackground }
    static var lfgLabelPrimary: Color { .lfgLabelPrimary }
    static var lfgLabelSecondary: Color { .lfgLabelSecondary }
    static var lfgLabelTertiary: Color { .lfgLabelTertiary }
    static var lfgLabelQuaternary: Color { .lfgLabelQuaternary }
    static var lfgStateWorking: Color { .lfgStateWorking }
    static var lfgStateNeedsInput: Color { .lfgStateNeedsInput }
}

extension Color {
    static let lfgCardBackground = Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.72)
    static let lfgLabelPrimary = Color.white
    static let lfgLabelSecondary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.70)
    static let lfgLabelTertiary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.60)
    static let lfgLabelQuaternary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.45)
    static let lfgStateWorking = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let lfgStateNeedsInput = Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)
}
