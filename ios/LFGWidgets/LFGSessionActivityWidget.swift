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
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        Divider().overlay(.white.opacity(0.14))
                        ForEach(context.state.rows.prefix(2), id: \.sid) { row in
                            FleetRowView(row: row, hosts: context.state.hosts, compact: true)
                            if row.sid != context.state.rows.prefix(2).last?.sid {
                                Divider().overlay(.white.opacity(0.10))
                            }
                        }
                    }
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

    // Lock-screen Live Activities have a tight fixed height budget (~160pt); more
    // than header + 2 rows + overflow gets center-clipped by the system (which
    // silently drops the header). Cap at 2 rows — rows arrive needs-input-first,
    // so the actionable sessions stay visible; the rest fold into "+N more".
    private var visibleRows: [LFGFleetAttributes.Row] {
        Array(context.state.rows.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FleetHeaderView(state: context.state)

            VStack(spacing: 0) {
                ForEach(visibleRows, id: \.sid) { row in
                    FleetRowView(row: row, hosts: context.state.hosts, compact: false)
                    if row.sid != visibleRows.last?.sid {
                        Divider().overlay(.white.opacity(0.12))
                    }
                }
            }

            if overflowCount > 0 {
                Text("+\(overflowCount) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
    }

    private var overflowCount: Int {
        max(0, context.state.working + context.state.needsInput - visibleRows.count)
    }
}

private struct FleetHeaderView: View {
    let state: LFGFleetAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            LFGMark(size: 26, cornerRadius: 7, font: .caption.weight(.black))

            VStack(alignment: .leading, spacing: 1) {
                SummaryText(state: state)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct FleetIslandHeader: View {
    let state: LFGFleetAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            LFGMark(size: 24, cornerRadius: 6, font: .caption2.weight(.black))
            VStack(alignment: .leading, spacing: 1) {
                SummaryText(state: state)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
    }
}

private struct SummaryText: View {
    let state: LFGFleetAttributes.ContentState

    var body: some View {
        let total = state.working + state.needsInput
        let need = state.needsInput
        let accent = fleetAccent(for: state)
        if need > 0 {
            (Text("\(total) agents · ") + Text("\(need) need you").foregroundColor(accent))
                .foregroundStyle(.white)
        } else {
            (Text("\(total) agents · ") + Text("working").foregroundColor(accent))
                .foregroundStyle(.white)
        }
    }
}

private struct FleetRowView: View {
    let row: LFGFleetAttributes.Row
    let hosts: [LFGFleetAttributes.ContentState.HostStatus]
    let compact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 9 : 11) {
            StateDot(state: row.state, size: compact ? 8 : 9)

            Text(row.title.isEmpty ? "Session" : row.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)

            HostPill(name: row.host, offline: isHostOffline(row.host, in: hosts))

            Spacer(minLength: 0)

            if row.state.lowercased() == "blocked" {
                NeedsInputPill()
            }
        }
        .padding(.vertical, compact ? 7 : 6)
    }
}

private struct HostPill: View {
    let name: String
    let offline: Bool

    var body: some View {
        HStack(spacing: 3) {
            if offline {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
            }
            Text(displayHostName(name))
                .lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(offline ? Color.orange.opacity(0.15) : Color(.tertiarySystemFill), in: Capsule())
        .foregroundStyle(offline ? Color.orange : Color.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct NeedsInputPill: View {
    var body: some View {
        Text("needs input")
            .font(.caption.weight(.bold))
            .foregroundStyle(.orange)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.orange.opacity(0.20)))
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

private struct LFGMark: View {
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 8
    // Retained for call-site compatibility; the app icon carries its own glyph.
    var font: Font = .subheadline.weight(.black)

    var body: some View {
        Image("AppMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

private func isHostOffline(_ host: String, in hosts: [LFGFleetAttributes.ContentState.HostStatus]) -> Bool {
    let label = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let status = hosts.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == label }) else {
        return true
    }
    return !status.online
}

private func displayHostName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "lfg" : trimmed
}
