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

    /// An appearance-adaptive color from two literal RGB hexes.
    private static func dot(dark: UInt32, light: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    static func statusColor(_ group: SessionStore.Group) -> Color {
        switch group {
        // Pinned to the design's exact hexes rather than the system palette.
        //
        // Two rounds of measurement got us here. SwiftUI's bare `Color.purple`
        // is not `systemPurple` at all — it read (219,52,242). Switching to
        // `Color(.systemPurple)` was closer but STILL off: on iOS 26.3 it reads
        // (219,52,242) against the design's #BF5AF0 = (191,90,240), and
        // systemBlue reads (0,145,255) against #0A84FF. The design was drawn
        // against an earlier palette, and Apple is free to move theirs again —
        // so the chosen colors are stated here, with the matching light variant.
        case .needsInput: return dot(dark: 0xFF9F0A, light: 0xFF9500)
        case .blocked:    return dot(dark: 0xFFD60A, light: 0xFFCC00)
        case .working:    return dot(dark: 0x30D158, light: 0x34C759)
        case .unread:     return dot(dark: 0xBF5AF0, light: 0xAF52DE)
        case .idle:       return dot(dark: 0x0A84FF, light: 0x007AFF)
        case .closed:     return Color(.tertiaryLabel)
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

    /// Compact list variant: `47s`, `2m`, `1h`, with no trailing "ago".
    var asCompactRelativeFromMillis: String {
        let date = Date(timeIntervalSince1970: self / 1000)
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }

        let days = hours / 24
        if days < 7 { return "\(days)d" }

        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }

        let months = days / 30
        if months < 12 { return "\(months)mo" }

        return "\(days / 365)y"
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
