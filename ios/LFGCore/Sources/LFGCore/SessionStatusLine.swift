import Foundation

/// The line under the session title (S2, canvas board `s2-view`): every state
/// shows here — "Working · 3m 12s · Pro · lfg", "Needs input · 2m", "Air offline
/// · 2m", "· 1 queued" — instead of as banners in the transcript.
public struct SessionStatusLine: Equatable, Sendable {
    /// live = green dot + label, attention = amber, none = no dot or label.
    public enum Tone: Equatable, Sendable { case live, attention, none }

    public enum State: Equatable, Sendable {
        case working(sinceMs: Double?)
        case needsInput(sinceMs: Double?)
        case needsSignIn(sinceMs: Double?)
        case paused(reason: String?)
        case hostOffline(sinceMs: Double?)
        /// A transient client action: "Forking…", "Moving host…".
        case activity(String)
        case idle
    }

    public let tone: Tone
    /// The colored, bold part. nil when idle.
    public let label: String?
    /// The grey rest: "· Pro · lfg".
    public let detail: String

    public init(tone: Tone, label: String?, detail: String) {
        self.tone = tone; self.label = label; self.detail = detail
    }

    public static func resolve(_ state: State, queued: Int, host: String?, project: String?,
                               nowMs: Double) -> SessionStatusLine {
        func elapsed(_ since: Double?, seconds: Bool) -> String? {
            guard let since else { return nil }
            let total = max(0, Int((nowMs - since) / 1000))
            if total < 60 { return "\(total)s" }
            let minutes = total / 60
            if minutes < 60 { return seconds ? "\(minutes)m \(total % 60)s" : "\(minutes)m" }
            let hours = minutes / 60
            if hours < 24 { return "\(hours)h \(minutes % 60)m" }
            return "\(hours / 24)d"
        }
        func labelled(_ base: String, _ time: String?) -> String { time.map { "\(base) · \($0)" } ?? base }

        var showsHost = true
        let tone: Tone
        let label: String?
        switch state {
        case let .working(since):
            tone = .live; label = labelled("Working", elapsed(since, seconds: true))
        case let .needsInput(since):
            tone = .attention; label = labelled("Needs input", elapsed(since, seconds: false))
        case let .needsSignIn(since):
            tone = .attention; label = labelled("Needs sign-in", elapsed(since, seconds: false))
        case let .paused(reason):
            let r = (reason ?? "").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
            tone = .attention; label = r.isEmpty ? "Paused" : "Paused · \(r)"
        case let .hostOffline(since):
            tone = .attention
            label = labelled(host.map { "\($0) offline" } ?? "Host offline", elapsed(since, seconds: false))
            showsHost = false
        case let .activity(text):
            tone = .live; label = text
        case .idle:
            tone = .none; label = nil
        }

        var parts: [String] = []
        if queued > 0 { parts.append("\(queued) queued") }
        if showsHost, let host, !host.isEmpty { parts.append(host) }
        // With messages queued the project drops for room (board `s2-queued`).
        if queued == 0, let project, !project.isEmpty { parts.append(project) }
        let rest = parts.joined(separator: " · ")
        let detail = label == nil ? rest : (rest.isEmpty ? "" : "· \(rest)")
        return SessionStatusLine(tone: tone, label: label, detail: detail)
    }
}
