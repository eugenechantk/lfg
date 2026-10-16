import Foundation

/// What the S2 session sheet (board `s2-menu`) shows, worked out from plain
/// session facts. The sheet replaces the old ••• menu, so every action that
/// menu offered has a tile or a row here.
public struct SessionSheetModel: Equatable, Sendable {
    public enum Tile: String, CaseIterable, Sendable {
        case terminal, files, subagents, signIn, browserPreview, iPhonePreview

        public var title: String {
            switch self {
            case .terminal: return "Terminal"
            case .files: return "Files & links"
            case .subagents: return "Subagents"
            case .signIn: return "Sign in"
            case .browserPreview: return "Browser preview"
            case .iPhonePreview: return "iPhone preview"
            }
        }
    }

    public struct TileState: Equatable, Sendable {
        public let tile: Tile
        /// The count in the tile's corner; nil draws none.
        public let badge: Int?
        /// A tile that does not apply right now stays in the grid, dimmed.
        public let enabled: Bool
    }

    /// The Host row: where the session runs and where it can move.
    public enum HostRow: Equatable, Sendable {
        /// One other host: "Pro · move to Air".
        case moveTo(current: String, target: String)
        /// Several other hosts: "Pro", tapping lists them.
        case choose(current: String)
        /// No other host: "Pro", nothing to tap.
        case info(current: String)
    }

    public struct Facts: Sendable {
        public var sessionID: String
        public var externallyOwned = false
        public var hostLabel: String?
        public var cwd: String?
        public var startedAtMs: Double?
        public var tmuxName: String?
        public var fileCount = 0
        public var subagentCount = 0
        public var waitingSignIns = 0
        public var hasBrowserFrame = false
        public var hostOffline = false
        public var otherHosts: [String] = []

        public init(sessionID: String) { self.sessionID = sessionID }
    }

    public let subtitle: String
    public let tiles: [TileState]
    public let hostRow: HostRow?
    /// Footer parts: "tmux lfg-fork-3" and "id 7f3a…c21". Each copies its own value.
    public let footerTmux: String?
    public let footerID: String?

    public init(_ facts: Facts, nowMs: Double) {
        var parts: [String] = []
        if let host = facts.hostLabel, !host.isEmpty { parts.append(host) }
        if let cwd = facts.cwd, !cwd.isEmpty { parts.append(Self.homeRelative(cwd)) }
        if let started = facts.startedAtMs {
            parts.append("started \(Self.age(fromMs: started, toMs: nowMs)) ago")
        }
        subtitle = parts.joined(separator: " · ")

        var tiles: [TileState] = []
        // The old menu hid Terminal and Sign in for sessions another frontend
        // owns; they stay hidden. The rest stay put and dim when they can't act.
        if !facts.externallyOwned {
            tiles.append(TileState(tile: .terminal, badge: nil, enabled: !facts.hostOffline))
        }
        // Files & links always opens: its own empty state explains an empty index.
        tiles.append(TileState(tile: .files, badge: facts.fileCount > 0 ? facts.fileCount : nil,
                               enabled: true))
        tiles.append(TileState(tile: .subagents, badge: facts.subagentCount > 0 ? facts.subagentCount : nil,
                               enabled: facts.subagentCount > 0))
        if !facts.externallyOwned {
            tiles.append(TileState(tile: .signIn, badge: facts.waitingSignIns > 0 ? facts.waitingSignIns : nil,
                                   enabled: true))
        }
        tiles.append(TileState(tile: .browserPreview, badge: nil, enabled: facts.hasBrowserFrame))
        tiles.append(TileState(tile: .iPhonePreview, badge: nil, enabled: true))
        self.tiles = tiles

        if let current = facts.hostLabel, !current.isEmpty {
            switch facts.otherHosts.count {
            case 0: hostRow = .info(current: current)
            case 1: hostRow = .moveTo(current: current, target: facts.otherHosts[0])
            default: hostRow = .choose(current: current)
            }
        } else {
            hostRow = nil
        }

        if let tmux = facts.tmuxName, !tmux.isEmpty { footerTmux = "tmux \(tmux)" } else { footerTmux = nil }
        footerID = facts.sessionID.isEmpty ? nil : "id \(Self.shortID(facts.sessionID))"
    }

    /// The segmented control's label for an effort level ("Med", as on the board).
    public static func effortLabel(_ level: String) -> String {
        switch level {
        case "minimal": return "Min"
        case "medium": return "Med"
        case "xhigh": return "X-High"
        default: return level.prefix(1).uppercased() + level.dropFirst()
        }
    }

    /// "7f3a…c21" for a long id; short ids stay whole.
    public static func shortID(_ id: String) -> String {
        guard id.count > 9 else { return id }
        return "\(id.prefix(4))…\(id.suffix(3))"
    }

    /// "2h", "5m", "3d": how long ago, for "started 2h ago".
    static func age(fromMs start: Double, toMs now: Double) -> String {
        let seconds = max(0, Int((now - start) / 1000))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    static func homeRelative(_ path: String) -> String {
        path.replacingOccurrences(of: #"^/Users/[^/]+"#, with: "~", options: .regularExpression)
    }
}
