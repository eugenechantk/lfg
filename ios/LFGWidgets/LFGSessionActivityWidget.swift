import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LFGWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LFGSessionActivityWidget()
    }
}

struct LFGSessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LFGSessionAttributes.self) { context in
            LockScreenSessionActivityView(context: context)
                .activityBackgroundTint(.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StateLabel(state: context.state.state)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTimeText(since: context.state.since)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(2)
                }
            } compactLeading: {
                StateDot(state: context.state.state)
            } compactTrailing: {
                Text(titleInitial(context.state.title))
                    .font(.caption.weight(.semibold))
            } minimal: {
                StateDot(state: context.state.state)
            }
            .keylineTint(color(for: context.state.state))
        }
    }
}

private struct LockScreenSessionActivityView: View {
    let context: ActivityViewContext<LFGSessionAttributes>

    var body: some View {
        HStack(spacing: 12) {
            StateDot(state: context.state.state)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    StateLabel(state: context.state.state)
                    Text("/")
                        .foregroundStyle(.tertiary)
                    ElapsedTimeText(since: context.state.since)
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

private struct StateLabel: View {
    let state: String

    var body: some View {
        HStack(spacing: 5) {
            StateDot(state: state)
            Text(displayState(state))
                .font(.caption.weight(.semibold))
        }
    }
}

private struct StateDot: View {
    let state: String

    var body: some View {
        Circle()
            .fill(color(for: state))
            .frame(width: 8, height: 8)
    }
}

private struct ElapsedTimeText: View {
    let since: Double

    var body: some View {
        Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
    }

    private var startDate: Date {
        Date(timeIntervalSince1970: since)
    }
}

private func color(for state: String) -> Color {
    switch state.lowercased() {
    case "working":
        return .accentColor
    case "blocked":
        return .orange
    case "idle":
        return .gray
    default:
        return .gray
    }
}

private func displayState(_ state: String) -> String {
    let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "unknown" : trimmed
}

private func titleInitial(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.first.map { String($0).uppercased() } ?? "L"
}
