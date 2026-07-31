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
            SessionActivityCard(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(.lfgCardBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        SessionStateGlyph(state: context.state.normalizedState)
                        StatusLabel(state: context.state.normalizedState)
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTimeText(since: context.state.since)
                        .font(.subheadline)
                        .foregroundStyle(.lfgLabelTertiary)
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        SessionActivityTitle(title: context.state.title)
                        SessionActivityFooter(attributes: context.attributes, state: context.state)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                SessionStateGlyph(state: context.state.normalizedState)
            } compactTrailing: {
                if context.state.normalizedState == .blocked {
                    Circle()
                        .fill(Color.lfgStateNeedsInput)
                        .frame(width: 8, height: 8)
                } else {
                    ElapsedTimeText(since: context.state.since)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            } minimal: {
                SessionStateGlyph(state: context.state.normalizedState)
            }
            .keylineTint(context.state.normalizedState.tint)
        }
    }
}
