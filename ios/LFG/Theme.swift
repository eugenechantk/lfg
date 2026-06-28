import SwiftUI
import LFGCore

/// Visual helpers shared across views. Colors adapt to light/dark automatically
/// via the system semantic colors.
enum Theme {
    static func agentGlyph(_ agent: String) -> String {
        switch agent {
        case "codex", "codex-aisdk": return "chevron.left.forwardslash.chevron.right"
        case "opencode": return "curlybraces"
        default: return "sparkle"            // claude / aisdk
        }
    }

    static func agentTint(_ agent: String) -> Color {
        switch agent {
        case "codex", "codex-aisdk": return .indigo
        case "opencode": return .teal
        default: return .orange
        }
    }

    static func statusColor(_ group: SessionStore.Group) -> Color {
        switch group {
        case .needsInput: return .blue
        case .blocked: return .orange
        case .working: return .green
        case .idle: return .secondary
        }
    }
}

extension Double {
    /// Server timestamps are JS epoch millis.
    var asRelativeFromMillis: String {
        let date = Date(timeIntervalSince1970: self / 1000)
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

struct AgentBadge: View {
    let agent: String

    private var logoName: String {
        if agent.contains("codex") { return "agent-codex" }     // codex + codex-aisdk
        if agent.contains("opencode") { return "agent-opencode" }
        return "agent-claude"                                    // claude / aisdk
    }

    var body: some View {
        Image(logoName)
            .resizable()
            .scaledToFit()
            .padding(3)
            .frame(width: 28, height: 28)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct ModelBadge: View {
    let model: String
    var body: some View {
        Text(model)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

struct StatusDot: View {
    let group: SessionStore.Group
    var body: some View {
        Circle()
            .fill(Theme.statusColor(group))
            .frame(width: 8, height: 8)
    }
}
