// S2 desktop Sessions list — canvas board `dA2-sessions`, a 400pt window:
// a host strip under the title bar, three collapsible groups, and rows with a
// time column, a meta line and a status line. The rules (groups, lines, ages,
// meta) live in LFGCore's DesktopSessionList.swift; this file only draws.

import SwiftUI
import AppKit

/// Board colours. Opaque ones are the board's CSS values; the translucent white
/// fills are the colours the canvas renders (Chrome draws them a few levels
/// brighter than the CSS maths), measured from the board.
enum S2Desk {
    static func color(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    static let background = color(dark: 0x1B1B1E, light: 0xFFFFFF)
    static let title = color(dark: 0xF4F4F6, light: 0x1C1C1E)
    static let meta = color(dark: 0xA8A8B0, light: 0x6C6C72)
    static let secondary = color(dark: 0x8A8A93, light: 0x8A8A93)
    static let attention = color(dark: 0xFFB340, light: 0xC93400)
    static let amber = Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255)
    static let liveDot = color(dark: 0x32D74B, light: 0x28A745)
    static let liveHalo = color(dark: 0x244B2A, light: 0xD4F2DA)
    static let liveTime = color(dark: 0x5BE37A, light: 0x248A3D)
    static let separator = color(dark: 0x2C2C2F, light: 0xE5E5EA)
    /// Switcher track and the round search button (CSS white at 7%).
    static let control = color(dark: 0x2E2E32, light: 0xEDEDF0)
    /// The picked segment (CSS white at 16% over the track).
    static let controlSelected = color(dark: 0x555558, light: 0xFFFFFF)
    /// The "By status" pill (CSS white at 6%).
    static let menuFill = color(dark: 0x2C2C2F, light: 0xEDEDF0)
    static let switcherInk = color(dark: 0xF4F4F6, light: 0x1C1C1E)
    static let switcherInkOff = color(dark: 0xC9CBD3, light: 0x6C6C72)
    static let badgeInk = Color(red: 26 / 255, green: 18 / 255, blue: 6 / 255)
    static let searchInk = color(dark: 0xD6D7DD, light: 0x3A3A3C)

    /// SF at a CSS weight between the named ones (the time column is 650).
    static func font(_ size: CGFloat, weight: CGFloat) -> Font {
        Font(NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: weight)))
    }
}

private extension View {
    /// A single line in a CSS line box: the text centred in `height`, as CSS
    /// half-leading centres it.
    func s2Line(_ height: CGFloat) -> some View {
        lineLimit(1).frame(height: height)
    }
}

// MARK: - Glyphs (from the board's SVGs, 16-unit boxes)

struct S2DeskChevron: Shape {
    var down: Bool
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 16
        var p = Path()
        if down {
            p.move(to: CGPoint(x: 4 * k, y: 6 * k)); p.addLine(to: CGPoint(x: 8 * k, y: 10 * k))
            p.addLine(to: CGPoint(x: 12 * k, y: 6 * k))
        } else {
            p.move(to: CGPoint(x: 6 * k, y: 4 * k)); p.addLine(to: CGPoint(x: 10 * k, y: 8 * k))
            p.addLine(to: CGPoint(x: 6 * k, y: 12 * k))
        }
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct S2DeskMagnifier: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 16
        var p = Path()
        p.addEllipse(in: CGRect(x: 2.5 * k, y: 2.5 * k, width: 9 * k, height: 9 * k))
        p.move(to: CGPoint(x: 10.5 * k, y: 10.5 * k)); p.addLine(to: CGPoint(x: 14 * k, y: 14 * k))
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The needs-input speech bubble:
/// M3 4.5A1.5 1.5 0 0 1 4.5 3h7A1.5 1.5 0 0 1 13 4.5v5a1.5 1.5 0 0 1-1.5 1.5H7l-3 2.5V11A1.5 1.5 0 0 1 3 9.5z
struct S2DeskBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var p = Path()
        p.move(to: pt(3, 4.5))
        p.addArc(center: pt(4.5, 4.5), radius: 1.5 * k, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: pt(11.5, 3))
        p.addArc(center: pt(11.5, 4.5), radius: 1.5 * k, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: pt(13, 9.5))
        p.addArc(center: pt(11.5, 9.5), radius: 1.5 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: pt(7, 11))
        p.addLine(to: pt(4, 13.5))
        p.addLine(to: pt(4, 11))
        p.addArc(center: pt(4.5, 9.5), radius: 1.5 * k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Title bar

/// The round search button at the title bar's right edge (30pt, a 14pt magnifier).
struct S2DeskSearchButton: View {
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            S2DeskMagnifier()
                .stroke(S2Desk.searchInk, style: StrokeStyle(lineWidth: 1.7 * 14 / 16, lineCap: .round))
                .frame(width: 14, height: 14)
                .frame(width: 30, height: 30)
                .background(Circle().fill(active ? S2Desk.controlSelected : S2Desk.control))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search sessions")
        .accessibilityIdentifier("compact_search_toggle")
        .help("Search sessions")
    }
}

// MARK: - Host strip

struct S2DeskHostStrip: View {
    struct HostDot: Identifiable {
        let id: String
        let label: String
        let online: Bool
    }

    let hosts: [HostDot]
    let workingCount: Int
    /// "working" on Sessions, "running" on Tasks.
    var workingLabel: String = "working"
    @Binding var groupMode: GroupMode
    var onHiddenDirectories: () -> Void
    /// A page's own menu section, above Group by (Tasks: the host filter).
    var leadingMenu: AnyView? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                HStack(spacing: 8) {
                    Group {
                        if host.online {
                            Circle().fill(S2Desk.liveDot)
                        } else {
                            Circle().strokeBorder(S2Desk.amber, lineWidth: 1)
                        }
                    }
                    .frame(width: 7, height: 7)
                    Text(host.online ? host.label : "\(host.label) offline")
                        .font(.system(size: 12))
                        .foregroundStyle(host.online ? S2Desk.meta : S2Desk.attention)
                        .s2Line(16.2)
                }
                .padding(.leading, index == 0 ? 0 : 12)
                .accessibilityElement(children: .combine)
            }
            if workingCount > 0 {
                Text("· \(workingCount) \(workingLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(S2Desk.secondary)
                    .s2Line(16.2)
                    .padding(.leading, 8)
            }
            Spacer(minLength: 8)
            Menu {
                if let leadingMenu {
                    leadingMenu
                    Divider()
                }
                Picker("Group by", selection: $groupMode) {
                    ForEach(GroupMode.allCases) { mode in
                        Text("By \(mode.title.lowercased())").tag(mode)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Hidden directories…", action: onHiddenDirectories)
            } label: {
                HStack(spacing: 4) {
                    Text("By \(groupMode.title.lowercased())")
                        .font(.system(size: 11))
                        .foregroundStyle(S2Desk.switcherInkOff)
                    S2DeskChevron(down: true)
                        .stroke(S2Desk.switcherInkOff, style: StrokeStyle(lineWidth: 2 * 9 / 16, lineCap: .round, lineJoin: .round))
                        .frame(width: 9, height: 9)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(S2Desk.menuFill))
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("group_mode_menu")
        }
        .frame(height: 22)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityIdentifier("host_strip")
    }
}

// MARK: - List

struct S2DeskGroupHeader: View {
    let title: String
    let count: Int
    let tint: Color
    var trailing: String? = nil
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                S2DeskChevron(down: expanded)
                    .stroke(S2Desk.secondary, style: StrokeStyle(lineWidth: 2.4 * 11 / 16, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 11)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .s2Line(17.55)
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(S2Desk.secondary)
                    .s2Line(16.2)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(S2Desk.secondary)
                        .s2Line(14.85)
                }
            }
            .padding(.top, 14)
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
    }
}

/// One session row: "2m / ago", then title, meta and status line.
struct S2DeskRow: View {
    let title: String
    let meta: String
    let line: SessionRowLine
    let age: (value: String, suffix: String)
    let group: DesktopListGroup
    let dimmed: Bool

    private var timeColor: Color {
        if dimmed { return S2Desk.secondary }
        switch group {
        case .needsInput: return S2Desk.attention
        case .working: return S2Desk.liveTime
        case .recent: return S2Desk.secondary
        }
    }

    private var lineColor: Color {
        switch line.tone {
        case .attention: return S2Desk.attention
        case .primary: return S2Desk.title
        case .live, .secondary: return S2Desk.meta
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Board: `tabular-nums`, so "1m" lines up with "4m" and "9m".
                Text(age.value)
                    .font(S2Desk.font(14, weight: 0.35).monospacedDigit())
                    .foregroundStyle(timeColor)
                    .s2Line(19)
                Text(age.suffix)
                    .font(.system(size: 11))
                    .foregroundStyle(S2Desk.secondary)
                    .s2Line(15)
            }
            .padding(.top, 10)
            .frame(width: 46, alignment: .leading)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(S2Desk.title)
                        .truncationMode(.tail)
                        .s2Line(18.9)
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(S2Desk.meta)
                        .truncationMode(.tail)
                        .s2Line(16.2)
                    HStack(spacing: 5) {
                        icon
                        Text(line.text)
                            .font(.system(size: 12))
                            .foregroundStyle(lineColor)
                            .truncationMode(.tail)
                    }
                    .s2Line(16.2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
                Rectangle().fill(S2Desk.separator).frame(height: 1)
            }
        }
        .padding(.leading, 16)
        .opacity(dimmed ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        switch line.icon {
        case .question:
            S2DeskBubble()
                .stroke(S2Desk.attention, style: StrokeStyle(lineWidth: 1.6 * 13 / 16, lineCap: .round, lineJoin: .round))
                .frame(width: 13, height: 13)
        case .signIn:
            Image(systemName: "key")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(S2Desk.attention)
                .frame(width: 13, height: 13)
        case .liveDot:
            // Board: a 7pt dot with a 3pt halo (box-shadow, outside the layout box).
            Circle().fill(S2Desk.liveDot)
                .frame(width: 7, height: 7)
                .background(Circle().fill(S2Desk.liveHalo).frame(width: 13, height: 13))
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Row facts

extension SessionItem {
    var s2State: DesktopRowFacts.State {
        switch status {
        case .needsInput: return .needsInput
        case .paused: return .paused
        case .working: return .working
        case .idle: return .idle
        case .closed: return .closed
        }
    }

    /// Board: an offline host's last rows sit in Recent, whatever they were doing.
    var s2Group: DesktopListGroup { hostOffline ? .recent : DesktopSessionList.group(s2State) }

    func s2Facts(moving: Bool) -> DesktopRowFacts {
        DesktopRowFacts(state: s2State, question: session.prompt?.question, promptKind: session.prompt?.kind,
                        permissionCommand: session.prompt?.command, signInWebsite: session.prompt?.website,
                        pausedReason: status == .paused ? session.status : nil,
                        hostLabel: hostLabel, hostOffline: hostOffline, moving: moving)
    }

    var s2Meta: String {
        // The folder's name, as on the phone: a host's `project` can be the
        // transcript folder ("-Users-…-lfg"), the cwd's last part is what people call it.
        DesktopSessionList.meta(project: SessionRowMeta.projectLabel(cwd: session.cwd, project: session.project),
                                host: hostLabel, agent: session.agent,
                                model: session.model, fromTask: session.task != nil)
    }

    /// The time column counts from when the question was asked, else from the last activity.
    var s2AgeAnchorMs: Double? {
        status == .needsInput ? (session.prompt?.askedAt ?? session.lastActivityAt) : session.lastActivityAt
    }
}
