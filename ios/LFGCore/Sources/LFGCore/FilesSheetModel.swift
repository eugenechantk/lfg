import Foundation

/// The S2 Files & links sheet (board `s2-files`): files in three sections
/// (Images, Videos, Documents) as plain rows, no previews; links on their own
/// tab. Rows read "fork-before.png" over ".claude/evidence · 6m ago".
public struct FilesSheetModel: Equatable, Sendable {
    public enum Section: String, CaseIterable, Sendable {
        case images = "Images", videos = "Videos", documents = "Documents"
    }

    public struct FileRow: Equatable, Identifiable, Sendable {
        public let id: String
        public let ref: MediaRef
        public let title: String
        public let meta: String
    }

    public struct LinkRow: Equatable, Identifiable, Sendable {
        public let id: String
        public let url: String
        public let title: String
        /// The domain alone (board `s2-files`, Links tab).
        public let meta: String
        /// The domain's first letter, for the row's tile ("G" for github.com).
        public let initial: String
    }

    public struct SectionGroup: Equatable, Identifiable, Sendable {
        public let section: Section
        public let rows: [FileRow]
        public var id: String { section.rawValue }
    }

    public let sections: [SectionGroup]
    public let links: [LinkRow]
    public var fileCount: Int { sections.reduce(0) { $0 + $1.rows.count } }

    public init(_ resources: TranscriptResources, cwd: String?, nowMs: Double) {
        var bySection: [Section: [FileRow]] = [:]
        for item in resources.files {
            let section: Section
            switch item.ref.kind {
            case .image: section = .images
            case .video: section = .videos
            case .pdf, .markdown, .other: section = .documents
            }
            let parts = [Self.folder(item.ref.raw, cwd: cwd), item.ts.map { Self.ago($0, nowMs: nowMs) }]
                .compactMap { $0 }
            bySection[section, default: []].append(
                FileRow(id: item.id, ref: item.ref, title: item.ref.filename, meta: parts.joined(separator: " · ")))
        }
        sections = Section.allCases.compactMap { s in
            guard let rows = bySection[s], !rows.isEmpty else { return nil }
            return SectionGroup(section: s, rows: rows)
        }
        links = resources.links.map { item in
            let host = item.link.host ?? item.link.url
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return LinkRow(id: item.id, url: item.link.url, title: item.link.displayName,
                           meta: host, initial: bare.first.map { String($0).uppercased() } ?? "?")
        }
    }

    /// Where a file lives, relative to the session's folder when it is inside
    /// it (".claude/evidence"), else from home ("~/Downloads"); a URL's host.
    static func folder(_ raw: String, cwd: String?) -> String? {
        if raw.hasPrefix("http"), let host = URL(string: raw)?.host { return host }
        var dir = (raw as NSString).deletingLastPathComponent
        if dir.isEmpty || dir == "." { return nil }
        if let cwd, !cwd.isEmpty {
            let base = cwd.hasSuffix("/") ? cwd : cwd + "/"
            if dir == cwd || dir + "/" == base { return nil }
            if dir.hasPrefix(base) { return String(dir.dropFirst(base.count)) }
        }
        if dir.hasPrefix("./") { dir = String(dir.dropFirst(2)) }
        return dir.replacingOccurrences(of: #"^/Users/[^/]+"#, with: "~", options: .regularExpression)
    }

    /// "6m ago", "1h ago", "just now".
    static func ago(_ ts: Double, nowMs: Double) -> String {
        let seconds = max(0, Int((nowMs - ts) / 1000))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
