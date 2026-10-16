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
        // S2 board `s2-list`: an opaque grey. tertiaryLabel is translucent and
        // read #464649 on black, too dark against the board's #636366.
        case .closed:     return dot(dark: 0x636366, light: 0xAEAEB2)
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

/// A soft backdrop behind session chrome. Transcript content continues beneath
/// the header, gaining blur gradually as it approaches the navigation controls.
struct TranscriptTopFade: View {
    let barHeight: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let bar = max(barHeight, 1)
        let height = bar + 36
        let base = Color(.systemBackground)
        let stops: [(location: CGFloat, strength: Double)] = [
            (0, 1), (max(bar - 36, 0) / height, 1),
            (bar / height, 0.8), ((bar + 16) / height, 0.3), (1, 0),
        ]
        let mask = LinearGradient(
            stops: stops.map { .init(color: .black.opacity($0.strength), location: $0.location) },
            startPoint: .top, endPoint: .bottom)
        ZStack {
            if !reduceTransparency {
                Rectangle().fill(.regularMaterial).mask(mask)
            }
            LinearGradient(
                stops: stops.map {
                    .init(color: base.opacity($0.strength * (reduceTransparency ? 1 : 0.16)), location: $0.location)
                }, startPoint: .top, endPoint: .bottom)
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The scroll edge treatment for the lists, drawn by the
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
    /// S2 session view: an opaque scrim down to the bar's bottom edge (the
    /// board clips the transcript there), then the tail of its gradient over
    /// the next 12pt, with no glass.
    var solid = false
    @Environment(\.colorScheme) private var colorScheme

    /// How far past the bar's border the ramp runs out, per edge.
    static func tail(_ edge: VerticalEdge) -> CGFloat { edge == .top ? 28 : 32 }

    /// Strength (0…1) at points measured from the screen edge.
    private var curve: [(point: CGFloat, strength: Double)] {
        let b = barHeight
        if solid {
            switch edge {
            case .top: return [(0, 1), (b, 1), (b + 0.5, 0.34), (b + 12, 0)]
            case .bottom: return [(0, 1), (b + 10, 1), (b + 10.5, 0.37), (b + 26, 0)]
            }
        }
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
            stops: points.map { .init(color: base.opacity((solid ? 1 : 0.85) * $0.strength), location: $0.location) },
            startPoint: start, endPoint: end
        )
        Group {
            if solid {
                scrim
            } else {
                // The glass shape is inset negatively so its specular perimeter
                // is rendered outside this field; the mask clips that rim away.
                ZStack {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.chrome(colorScheme), in: Rectangle().inset(by: -48))
                        .mask(glassMask)
                    scrim
                }
            }
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

/// Shared close control for the custom headers in session action sheets.
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button("Close", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .glassButtonStyleOrPlain()
            .frame(minWidth: 44, minHeight: 44)
    }
}

/// S2 session-view palette (canvas boards `s2-view`, `s2-queued`, `s2-tools-*`).
/// Dark values are the boards' hexes; light values are their counterparts.
enum S2 {
    static func color(dark: UInt32, light: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    static let live = color(dark: 0x30D158, light: 0x248A3D)
    static let attention = color(dark: 0xFF9F0A, light: 0xC93400)
    static let failed = color(dark: 0xFF453A, light: 0xD70015)
    static let ink = color(dark: 0xF2F2F7, light: 0x1C1C1E)
    /// Pure white on dark: titles, menu labels, panel titles and options
    /// (prose, pills and secondary buttons use `ink`).
    static let white = color(dark: 0xFFFFFF, light: 0x000000)
    static let secondaryInk = color(dark: 0xA1A1A6, light: 0x6C6C70)
    static let metaInk = color(dark: 0x8E8E93, light: 0x8E8E93)
    /// Composer and pill surfaces.
    static let surface = color(dark: 0x1C1C1E, light: 0xFFFFFF)
    static let surfaceBorder = color(dark: 0x38383A, light: 0xD1D1D6)
    static let chip = color(dark: 0x2C2C2E, light: 0xF2F2F7)
    static let chipInk = color(dark: 0xD1D1D6, light: 0x3A3A3C)
    static let ringTrack = color(dark: 0x3A3A3C, light: 0xE5E5EA)
    static let send = color(dark: 0x0A6EE0, light: 0x0A6EE0)
    /// The Stop button inverts the surface: a light disc with a dark square.
    static let stopDisc = color(dark: 0xF2F2F7, light: 0x1C1C1E)
    static let stopSquare = color(dark: 0x000000, light: 0xFFFFFF)
}

extension View {
    /// Lays text out in the boards' CSS line box (`font-size` / `line-height`).
    /// SwiftUI `Text` has no line-height: its line is the font's natural height
    /// (~1.19x the size for SF), so a CSS box taller than that needs the extra
    /// split as half-leading above and below the text, plus the same extra
    /// between lines. Use the board's two numbers as they are.
    func cssLineBox(size: CGFloat, lineHeight: CGFloat, weight: UIFont.Weight = .regular,
                    monospaced: Bool = false) -> some View {
        let natural = (monospaced ? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
                                  : UIFont.systemFont(ofSize: size, weight: weight)).lineHeight
        let extra = max(0, lineHeight - natural)
        return self
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}
