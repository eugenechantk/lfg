import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LFGWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LFGFleetActivityWidget()
    }
}

/// One activity for the whole fleet, not one per session. Beyond matching the
/// design, this removes the per-session ceiling entirely: ActivityKit accepts at
/// most 5 concurrent activities per app, so the old approach had to truncate and
/// drop sessions once six were active.
struct LFGFleetActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LFGFleetAttributes.self) { context in
            FleetActivityCard(state: context.state)
                .activityBackgroundTint(.lfgCardBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(context.state.activeTotal)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.lfgLabelPrimary)
                            .monospacedDigit()
                        Text("Active")
                            .font(.system(size: 14))
                            .foregroundStyle(.lfgLabelSecondary)
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 9) {
                        FleetCounter(state: .working, count: context.state.working)
                        FleetCounter(state: .needsInput, count: context.state.needsInput)
                    }
                    .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // The expanded region has its own, tighter budget than the
                    // lock screen — two rows, not three.
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(context.state.rows.prefix(2), id: \.sid) { row in
                            FleetRowView(row: row)
                        }
                        FleetOverflowText(more: context.state.more + max(0, context.state.rows.count - 2))
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Circle()
                    .fill(context.state.accent)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                Text("\(context.state.activeTotal)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.lfgLabelPrimary)
                    .monospacedDigit()
            } minimal: {
                Circle()
                    .fill(context.state.accent)
                    .frame(width: 8, height: 8)
            }
            .keylineTint(context.state.accent)
        }
    }
}

private extension LFGFleetAttributes.ContentState {
    /// Needs-input dominates: if anything is waiting on you, that is the colour
    /// the collapsed island should carry.
    var accent: Color {
        needsInput > 0 ? .lfgStateNeedsInput : .lfgStateWorking
    }
}
