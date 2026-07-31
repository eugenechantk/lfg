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
        ActivityConfiguration(for: LFGFleetAttributes.self) { context in
            LockScreenFleetActivityView(context: context)
                .activityBackgroundTint(.black.opacity(0.84))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FleetIslandHeader(state: context.state)
                        // Same edge-to-edge clipping as the bottom region: without
                        // this the island's corner shaves the first character.
                        .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(context.state.rows.prefix(2), id: \.sid) { row in
                            ActiveFleetRow(row: row)
                        }
                    }
                    // The expanded region runs edge-to-edge; without this the
                    // island's rounded corners clip the first glyph of each title
                    // and the trailing elapsed time.
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                StateDot(state: context.state.needsInput > 0 ? "blocked" : "working", size: 9)
            } compactTrailing: {
                CompactCountView(state: context.state)
            } minimal: {
                StateDot(state: context.state.needsInput > 0 ? "blocked" : "working", size: 9)
            }
            .keylineTint(fleetAccent(for: context.state))
        }
    }
}

private struct LockScreenFleetActivityView: View {
    let context: ActivityViewContext<LFGFleetAttributes>

    var body: some View {
        Group {
            if context.state.needsInput > 0, let hero = blockedRow {
                AttentionFleetView(state: context.state, hero: hero)
            } else {
                ActiveFleetView(state: context.state)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var blockedRow: LFGFleetAttributes.Row? {
        context.state.rows.first { $0.state.lowercased() == "blocked" }
            ?? context.state.rows.first
    }
}

private struct ActiveFleetView: View {
    let state: LFGFleetAttributes.ContentState

    private var visibleRows: [LFGFleetAttributes.Row] {
        Array(state.rows.prefix(3))
    }

    private var overflowCount: Int {
        max(0, state.working + state.needsInput - visibleRows.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ActiveHeader(count: state.working)

            ForEach(visibleRows, id: \.sid) { row in
                ActiveFleetRow(row: row)
            }

            if overflowCount > 0 {
                Text("+\(overflowCount) More")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct AttentionFleetView: View {
    let state: LFGFleetAttributes.ContentState
    let hero: LFGFleetAttributes.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AttentionLabel(count: state.needsInput)

            Text(hero.title.isEmpty ? "Session" : hero.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .layoutPriority(1)

            HStack(spacing: 12) {
                AttentionMeta(state: state, hero: hero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                if let destination = URL(string: "lfg://session/\(hero.sid)") {
                    Link(destination: destination) {
                        Text("Reply")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }
}

private struct ActiveHeader: View {
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Active")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AttentionLabel: View {
    let count: Int

    var body: some View {
        Text(count > 1 ? "\(count) need you" : "Needs input")
            .font(.footnote)
            .foregroundStyle(count > 1 ? Color.orange : Color.secondary)
    }
}

private struct AttentionMeta: View {
    let state: LFGFleetAttributes.ContentState
    let hero: LFGFleetAttributes.Row

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(metaText(at: context.date))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func metaText(at date: Date) -> String {
        var parts = [displayHostName(hero.host), compactElapsed(since: hero.since, at: date)]
        if state.working > 0 {
            parts.append("\(state.working) working")
        }
        if state.needsInput > 1 {
            parts.append("+\(state.needsInput - 1) more need you")
        }
        return parts.joined(separator: " · ")
    }
}

private struct FleetIslandHeader: View {
    let state: LFGFleetAttributes.ContentState

    var body: some View {
        Group {
            if state.needsInput > 0 {
                // Summary only. The expanded island's leading region is narrow —
                // pairing the label with the hero title there scaled both down to
                // an unreadable, double-clipped line. The titles are already the
                // rows in the bottom region.
                AttentionLabel(count: state.needsInput)
            } else {
                ActiveHeader(count: state.working)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct ActiveFleetRow: View {
    let row: LFGFleetAttributes.Row

    var body: some View {
        HStack(spacing: 8) {
            Text(row.title.isEmpty ? "Session" : row.title)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 8)

            ElapsedTimeText(since: row.since)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct ElapsedTimeText: View {
    let since: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(compactElapsed(since: since, at: context.date))
        }
    }
}

private struct CompactCountView: View {
    let state: LFGFleetAttributes.ContentState

    var body: some View {
        let count = state.needsInput > 0 ? state.needsInput : state.working
        if state.needsInput > 0 {
            HStack(spacing: 5) {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                Image(systemName: "triangle.fill")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.orange))
        } else {
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}

private struct StateDot: View {
    let state: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color(for: state))
            .frame(width: size, height: size)
            .shadow(color: color(for: state).opacity(0.55), radius: 5)
    }
}

private func compactElapsed(since: Double, at date: Date) -> String {
    guard since > 0 else { return "now" }
    let seconds = max(0, Int(date.timeIntervalSince1970 - since))
    guard seconds >= 60 else { return "now" }

    let minutes = seconds / 60
    guard minutes >= 60 else { return "\(minutes)m" }

    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
}

private func color(for state: String) -> Color {
    switch state.lowercased() {
    case "working":
        return .blue
    case "blocked":
        return .orange
    case "idle":
        return .gray
    default:
        return .gray
    }
}

private func fleetAccent(for state: LFGFleetAttributes.ContentState) -> Color {
    state.needsInput > 0 ? .orange : .blue
}

private func displayHostName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "lfg" : trimmed
}
