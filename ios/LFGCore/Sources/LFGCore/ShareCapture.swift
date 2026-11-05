import Foundation

/// A recipient's host is part of its identity: never route a live share to an
/// unrelated default host just because its owner is offline.
public struct ShareRecipient: Codable, Sendable, Hashable, Identifiable {
    public var host: Host
    public var session: Session
    public var isReachable: Bool
    public var id: String { host.id + "|" + session.id }

    public init(host: Host, session: Session, isReachable: Bool = true) {
        self.host = host; self.session = session; self.isReachable = isReachable
    }

    public var isChat: Bool { session.isChat }

    public var sendEffect: String {
        if !isReachable { return "Queues until \(host.label) is back" }
        // A chat never folds input into a running turn; LFG holds the message.
        if isChat { return session.busy == true ? "Waits for its current turn" : "Starts its next turn now" }
        if session.closed { return "Resumes it" }
        if session.prompt != nil { return "Runs after you answer its question" }
        if session.busy == true { return "Joins its current turn" }
        return "Starts its next turn now"
    }

    public var status: String {
        if !isReachable { return "\(host.label) is offline" }
        if session.closed { return "Ended" }
        if session.isBlocked { return "Paused" }
        if session.prompt != nil { return "Needs you" }
        return session.busy == true ? "Working" : "Idle"
    }
}

public enum ShareRecipients {
    public static func reconciled(_ recipients: [ShareRecipient]) -> [ShareRecipient] {
        let live = Set(recipients.filter { !$0.session.closed }.map { $0.session.id })
        var seen = Set<String>()
        return recipients.filter {
            guard $0.session.sessionId != nil, !$0.session.isExternallyOwned,
                  $0.session.parentSessionId == nil, $0.session.purpose != "task-edit",
                  !$0.session.id.hasPrefix("local-") else { return false }
            if $0.session.closed && live.contains($0.session.id) { return false }
            // Transcripts are synced across hosts. Prefer the first configured
            // copy of a closed session; live owners always win over that copy.
            return seen.insert($0.session.id).inserted
        }
    }

    /// Recent (no query), then sessions, then chats. Chats keep their own
    /// section so a search for both never mixes them or puts chats first.
    public static func sections(_ recipients: [ShareRecipient], query: String) -> ShareSections {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = reconciled(recipients).filter { recipient in
            let haystack = [recipient.session.title, recipient.session.cwd ?? "", recipient.host.label,
                            recipient.session.agent, recipient.isChat ? "chat" : "session"].joined(separator: " ")
            return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
        let recent = words.isEmpty ? Array(matches.filter { ($0.session.lastUserAt ?? 0) > 0 }
            .sorted { ($0.session.lastUserAt ?? 0) > ($1.session.lastUserAt ?? 0) }.prefix(5)) : []
        let ids = Set(recent.map(\.id))
        let rest = matches.filter { !ids.contains($0.id) }.sorted {
            if $0.session.closed != $1.session.closed { return !$0.session.closed }
            let a = $0.session.lastActivityAt ?? 0, b = $1.session.lastActivityAt ?? 0
            return a == b ? $0.id < $1.id : a > b
        }
        return ShareSections(recent: recent, sessions: rest.filter { !$0.isChat }, chats: rest.filter(\.isChat))
    }
}

public struct ShareSections: Sendable {
    public var recent: [ShareRecipient]
    public var sessions: [ShareRecipient]
    public var chats: [ShareRecipient]
    public var all: [ShareRecipient] { sessions + chats }
    public var isEmpty: Bool { recent.isEmpty && sessions.isEmpty && chats.isEmpty }
}

public struct ShareConfiguration: Codable, Sendable {
    public var hosts: [Host]
    public var recipients: [ShareRecipient]
    public var hiddenDirs: [String]
    public var model: String?
    public var recentDirs: [String]
    public var agent: String
    public var owner: String?
    public init(hosts: [Host] = [], recipients: [ShareRecipient] = [], recentDirs: [String] = [],
                agent: String = "claude", owner: String? = nil, hiddenDirs: [String] = [], model: String? = nil) {
        self.hosts = hosts; self.recipients = recipients; self.recentDirs = recentDirs
        self.agent = agent; self.owner = owner; self.hiddenDirs = hiddenDirs; self.model = model
    }
}

public struct ShareFile: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var filename: String
    public var contentType: String
    public var byteCount: Int
    public var uploadedPath: String?
    public init(id: String = UUID().uuidString, filename: String, contentType: String, byteCount: Int) {
        self.id = id; self.filename = filename; self.contentType = contentType; self.byteCount = byteCount
    }
}

public struct ShareJob: Codable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case queued, uploading, creating, sending, failed, uncertain, sent
    }
    public var id: String
    public var host: Host
    public var sessionID: String?
    public var recipientTitle: String
    public var newSession: NewSessionRequest?
    public var text: String
    public var files: [ShareFile]
    public var status: Status = .queued
    public var error: String?
    public var createdAt: Date = Date()
    /// A busy chat refused the turn (409). The app hands the share to that
    /// chat's own queue, which sends it after the turn.
    public var waitsForTurn: Bool?
    public init(id: String = UUID().uuidString, host: Host, sessionID: String? = nil,
                recipientTitle: String, newSession: NewSessionRequest? = nil, text: String, files: [ShareFile] = []) {
        self.id = id; self.host = host; self.sessionID = sessionID; self.recipientTitle = recipientTitle
        self.newSession = newSession; self.text = text; self.files = files
    }
    public var message: String {
        ([text.trimmingCharacters(in: .whitespacesAndNewlines)] + files.compactMap(\.uploadedPath))
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
    public var canAutomaticallyDeliver: Bool { status == .queued || status == .uploading }
    /// Chat ids are minted as `chat-<uuid>`; the chat route owns them.
    public var isChat: Bool { sessionID?.hasPrefix("chat-") == true && newSession == nil }
    public var filesUploaded: Bool { files.allSatisfy { $0.uploadedPath != nil } }
}

public enum ShareCaptureError: LocalizedError, Sendable {
    case unavailable, invalidFile, tooLarge, empty, unacknowledged, hostRemoved
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Open LFG once to finish setting up sharing."
        case .invalidFile: return "This attachment could not be read. Share it again from its original app."
        case .tooLarge: return "Each file must be smaller than 64 MB. Share up to 10 files, with 128 MB in total."
        case .empty: return "Add a message or an attachment."
        case .unacknowledged: return "The host did not confirm delivery. Open LFG to check before sending again."
        case .hostRemoved: return "This host was removed from LFG. Add it again before retrying."
        }
    }
}
