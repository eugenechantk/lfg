import SwiftUI
import LFGCore

/// Visual helpers shared across views. Colors adapt to light/dark automatically
/// via the system semantic colors.
enum Theme {
    static func agentGlyph(_ agent: String) -> String {
        switch agent {
        case "codex": return "chevron.left.forwardslash.chevron.right"
        default: return "sparkle"            // claude
        }
    }

    static func agentTint(_ agent: String) -> Color {
        switch agent {
        case "codex": return .indigo
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
        // Teal: adjacent to Working green (where the row is headed) but clearly
        // not it, and clearly not Idle blue either.
        case .restarting: return dot(dark: 0x64D2FF, light: 0x5AC8FA)
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
        agent.contains("codex") ? "agent-codex" : "agent-claude"
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

extension Theme {
    /// Untinted `.regular` Liquid Glass reads as a bright grey slab over a
    /// black transcript in dark mode. A translucent black tint sinks the
    /// chrome back toward the background while keeping the blur and the
    /// specular rim. Light mode keeps the stock glass: a dark tint there
    /// looks muddy against a white transcript.
    static func glassDim(_ scheme: ColorScheme) -> Color? {
        scheme == .dark ? Color.black.opacity(0.30) : nil
    }
}

@available(iOS 26.0, *)
extension Glass {
    /// Regular glass for session chrome (top fade, composer), dimmed in dark mode.
    static func chrome(_ scheme: ColorScheme) -> Glass {
        if let tint = Theme.glassDim(scheme) { return .regular.tint(tint) }
        return .regular
    }
}

/// The scroll edge treatment for the lists and the session view, drawn by the
/// app instead of the system. Apple's default effect darkens hard when bare text
/// sits in a bar (our host-status line), turning near-black and then clearing
/// within a few points of the bar's edge. The session view's flipped transcript
/// can't use the system effect at all. So both surfaces draw this gentler ramp,
/// shaped after Apple's Settings app (measured on iOS 26.3): darkest at the
/// screen edge, easing through the bar so content stays faintly visible behind
/// it, and running out ~28pt past the bar's border — no hard edge.
///
/// Two layers give the ramp: dimmed Liquid Glass for the blur and a
/// background-coloured scrim for the fade. `barHeight` is the distance from the
/// screen edge to the bar's inner border; the caller places this view against
/// the screen edge named by `edge`.
@available(iOS 26.0, *)
struct ChromeFade: View {
    var edge: VerticalEdge = .top
    let barHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    /// How far past the bar's border the ramp runs out, per edge.
    static func tail(_ edge: VerticalEdge) -> CGFloat { edge == .top ? 28 : 32 }

    /// Strength (0…1) at points measured from the screen edge.
    private var curve: [(point: CGFloat, strength: Double)] {
        let b = barHeight
        switch edge {
        case .top:
            return [(0, 0.95), (max(b - 54, 0), 0.9), (b - 32, 0.78), (b - 16, 0.6),
                    (b, 0.35), (b + 12, 0.15), (b + 28, 0)]
        case .bottom:
            return [(0, 0.9), (max(b - 48, 0), 0.75), (b - 24, 0.5), (b, 0.25),
                    (b + 16, 0.1), (b + 32, 0)]
        }
    }

    var body: some View {
        let total = barHeight + Self.tail(edge)
        let base = Color(.systemBackground)
        // Gradients run from the screen edge inward.
        let start: UnitPoint = edge == .top ? .top : .bottom
        let end: UnitPoint = edge == .top ? .bottom : .top
        let points = curve.map { (location: min(max($0.point / total, 0), 1), strength: $0.strength) }

        let glassMask = LinearGradient(
            stops: points.map { .init(color: .black.opacity($0.strength), location: $0.location) },
            startPoint: start, endPoint: end
        )
        let scrim = LinearGradient(
            stops: points.map { .init(color: base.opacity(0.85 * $0.strength), location: $0.location) },
            startPoint: start, endPoint: end
        )

        // The glass shape is inset negatively so its specular perimeter is
        // rendered outside this field; the mask clips that rim away.
        ZStack {
            Rectangle()
                .fill(.clear)
                .glassEffect(.chrome(colorScheme), in: Rectangle().inset(by: -48))
                .mask(glassMask)
            scrim
        }
        .frame(height: total)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Both `ChromeFade`s for a list that keeps its own safe areas (under a
/// navigation bar, with a `safeAreaBar` dock). Applied inside the dock's bar, so
/// the reader's insets are the chrome: status + navigation bar on top, dock +
/// home indicator below.
@available(iOS 26.0, *)
private struct ListChromeFades: View {
    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            VStack(spacing: 0) {
                if insets.top > 0 { ChromeFade(edge: .top, barHeight: insets.top) }
                Spacer(minLength: 0)
                if insets.bottom > 0 { ChromeFade(edge: .bottom, barHeight: insets.bottom) }
            }
            // Stretch back out over the insets so each fade meets its screen edge.
            .frame(width: proxy.size.width,
                   height: proxy.size.height + insets.top + insets.bottom)
            .offset(y: -insets.top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GlassChromeContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    /// Attach list controls to the scrolling surface so content reaches the
    /// glass, and draw `ChromeFade` at both edges in place of the system effect.
    @ViewBuilder
    func listScrollChrome(footer: AnyView?) -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectHidden(true, for: [.top, .bottom])
                .overlay { ListChromeFades() }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    footer
                }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
    }

    @ViewBuilder
    func glassOrRaised<S: Shape>(
        in shape: S,
        fallback: Color = Color(.secondarySystemBackground),
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.tint(tint), in: shape)
                }
            } else if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(fallback, in: shape)
        }
    }

    @ViewBuilder
    func glassButtonStyleOrPlain() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }
}
