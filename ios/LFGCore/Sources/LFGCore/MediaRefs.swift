import Foundation

// MARK: - Media references in text
//
// Agents hand files over by writing paths and markdown into their turns, so
// finding the attachments in a transcript is a text-parsing problem. This lives
// in LFGCore (not the SwiftUI layer) because it is pure string work with a lot
// of edge cases, and those deserve tests that run without a simulator.

public enum MediaKind: Equatable, Hashable, Sendable {
    case image, video, pdf, markdown, other

    public static func from(ext: String) -> MediaKind? {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff": return .image
        case "mp4", "mov", "m4v", "webm": return .video
        case "pdf": return .pdf
        case "md", "markdown", "txt": return .markdown
        default: return nil
        }
    }
}

public struct MediaRef: Identifiable, Equatable, Hashable, Sendable {
    public let raw: String          // original path or URL string
    public let kind: MediaKind
    public var label: String?       // friendly name from a markdown link, if any
    public var id: String { raw }
    public var filename: String { label ?? (raw as NSString).lastPathComponent }

    public init(raw: String, kind: MediaKind, label: String? = nil) {
        self.raw = raw; self.kind = kind
        self.label = (label?.isEmpty == false) ? label : nil
    }
}

public enum MediaScanner {
    // Markdown image: ![label](url)
    private static let imageMarkdown = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#)
    // Markdown link: [label](url)
    private static let linkMarkdown = try! NSRegularExpression(pattern: #"(?<!\!)\[([^\]]*)\]\(([^)\s]+)\)"#)
    // Bare file references ending in an extension: http(s) URL, absolute host
    // path, or a multi-segment relative path (resolved against the session cwd).
    // A boundary lookbehind keeps a relative path like `improvement-log/foo.md`
    // from being grabbed mid-token as the bogus absolute `/foo.md` (which 404s) —
    // it's matched whole instead so it can resolve to the real file.
    private static let bareRef = try! NSRegularExpression(
        pattern: #"(?:https?://[^\s)]+|(?<![\w.~/-])(?:/[^\s)]+|[\w.~-]+(?:/[\w.~-]+)+))\.([A-Za-z0-9]{1,5})"#)

    /// Find renderable file references in a message.
    /// - Markdown links → cards for ANY file type (explicit, so low false-positive).
    /// - Markdown images → inline by default (MarkdownUI), or cards when
    ///   `includeInlineImages` is set (user bubbles, which don't render markdown).
    /// - Bare paths/URLs → only known media types, to avoid turning every file
    ///   path mentioned in prose into a card.
    ///
    /// Returned in **document order** — the order the agent wrote them. The three
    /// passes below are by syntax, not position, so collecting them pass-by-pass
    /// put every image ahead of every link regardless of what the turn actually
    /// said: a handoff reading "the clip, then the frame" listed the frame first.
    public static func scan(_ text: String, includeInlineImages: Bool = false) -> [MediaRef] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        struct Candidate {
            let location: Int
            let raw: String
            let label: String?
            let allowAny: Bool
        }
        var candidates: [Candidate] = []
        var inlineImageURLs = Set<String>()

        for m in imageMarkdown.matches(in: text, range: full) where m.numberOfRanges > 2 {
            let label = ns.substring(with: m.range(at: 1))
            let url = ns.substring(with: m.range(at: 2))
            if includeInlineImages {
                candidates.append(Candidate(location: m.range.location, raw: url, label: label, allowAny: true))
            } else {
                inlineImageURLs.insert(url)
            }
        }
        for m in linkMarkdown.matches(in: text, range: full) where m.numberOfRanges > 2 {
            candidates.append(Candidate(location: m.range.location,
                                        raw: ns.substring(with: m.range(at: 2)),
                                        label: ns.substring(with: m.range(at: 1)),
                                        allowAny: true))
        }
        for m in bareRef.matches(in: text, range: full) {
            let raw = ns.substring(with: m.range(at: 0))
            guard !inlineImageURLs.contains(raw) else { continue }
            candidates.append(Candidate(location: m.range.location, raw: raw, label: nil, allowAny: false))
        }

        var seen = Set<String>()
        var refs: [MediaRef] = []
        // A markdown link and the bare path inside it start at different offsets,
        // so ties are broken by which pass found it — markdown first, since it
        // carries the label.
        for candidate in candidates.sorted(by: { $0.location < $1.location }) {
            // Trim trailing sentence punctuation only — a leading dot is significant
            // (e.g. `.claude/notes.md` is a dot-directory, not a stray period).
            var trimmed = candidate.raw
            while let last = trimmed.last, ".,);'\"".contains(last) { trimmed.removeLast() }
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            let ext = (trimmed as NSString).pathExtension
            let kind: MediaKind
            if let known = MediaKind.from(ext: ext) { kind = known }
            else if candidate.allowAny, !ext.isEmpty { kind = .other }
            else { continue }
            seen.insert(trimmed)
            refs.append(MediaRef(raw: trimmed, kind: kind, label: candidate.label))
        }
        return refs
    }
}

// MARK: - Web links

/// An http(s) URL mentioned in a turn that is NOT a file — a dashboard, a PR, a
/// doc. `MediaScanner` only claims URLs ending in a file extension, so these
/// would otherwise be invisible outside the prose that mentions them.
public struct WebLink: Identifiable, Equatable, Hashable, Sendable {
    public let url: String
    public var label: String?
    public var id: String { url }

    public init(url: String, label: String? = nil) {
        self.url = url
        self.label = (label?.isEmpty == false) ? label : nil
    }

    /// What to show as the row title: the markdown label when the agent wrote
    /// one, otherwise the last path segment — a list of links to one site is
    /// otherwise a column of identical hostnames, with the part that actually
    /// distinguishes them truncated away. Falls back to the host for a bare
    /// domain, which has no segment to show.
    public var displayName: String {
        if let label { return label }
        let parsed = URL(string: url)
        if let segment = parsed?.pathComponents.last(where: { $0 != "/" && !$0.isEmpty }) {
            return segment
        }
        return host ?? url
    }

    /// Hostname without `www.`, shown as the row's second line.
    public var host: String? {
        guard let host = URL(string: url)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public enum LinkScanner {
    private static let linkMarkdown = try! NSRegularExpression(pattern: #"(?<!\!)\[([^\]]*)\]\(\s*(https?://[^)\s]+)\s*\)"#)
    // Bare URLs. Closing brackets and quotes end the match so a URL inside
    // markdown or JSON doesn't swallow its own delimiter.
    private static let bareURL = try! NSRegularExpression(pattern: #"https?://[^\s<>)\]}"'`]+"#)

    /// Every http(s) link in the text, markdown labels preserved.
    ///
    /// `excluding` is the set of raws already claimed as media refs — a link to
    /// `…/chart.png` is an attachment, and listing it a second time under Links
    /// would be the same file twice.
    public static func scan(_ text: String, excluding: Set<String> = []) -> [WebLink] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var seen = Set<String>()
        var links: [WebLink] = []

        func add(_ raw: String, label: String?) {
            var trimmed = raw
            while let last = trimmed.last, ".,;:'\"".contains(last) { trimmed.removeLast() }
            guard trimmed.count > "https://".count else { return }
            guard !excluding.contains(trimmed), !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            links.append(WebLink(url: trimmed, label: label))
        }

        for m in linkMarkdown.matches(in: text, range: full) where m.numberOfRanges > 2 {
            add(ns.substring(with: m.range(at: 2)), label: ns.substring(with: m.range(at: 1)))
        }
        for m in bareURL.matches(in: text, range: full) {
            add(ns.substring(with: m.range(at: 0)), label: nil)
        }
        return links
    }
}

// MARK: - Whole-transcript collection

/// One attachment, with the moment it appeared so the sheet can date it.
public struct TranscriptAttachment: Identifiable, Equatable, Hashable, Sendable {
    public let ref: MediaRef
    public let ts: Double?
    public var id: String { ref.raw }

    public init(ref: MediaRef, ts: Double?) {
        self.ref = ref; self.ts = ts
    }
}

public struct TranscriptLink: Identifiable, Equatable, Hashable, Sendable {
    public let link: WebLink
    public let ts: Double?
    public var id: String { link.url }

    public init(link: WebLink, ts: Double?) {
        self.link = link; self.ts = ts
    }
}

public struct TranscriptResources: Equatable, Sendable {
    public var files: [TranscriptAttachment]
    public var links: [TranscriptLink]

    public var isEmpty: Bool { files.isEmpty && links.isEmpty }

    public init(files: [TranscriptAttachment] = [], links: [TranscriptLink] = []) {
        self.files = files; self.links = links
    }
}

public enum TranscriptResourceIndex {
    /// Everything the client can open, gathered from a whole transcript.
    ///
    /// Two deliberate limits:
    ///
    /// 1. **Prose turns only** (`kind == "text"`). Tool calls and their results
    ///    are full of paths — every `Read`, every `Edit`, every `Bash` line that
    ///    mentions a file — and folding those in would bury the handful of files
    ///    actually handed to the user under hundreds of incidental ones. The
    ///    rule matches what the transcript itself renders as an attachment.
    /// 2. **Newest first, newest mention wins.** A file re-referenced in a later
    ///    turn appears once, dated by that latest mention.
    ///
    /// Ordering is an explicit sort on the message timestamp, not the order the
    /// transcript array happens to be in. `TranscriptMerge` does sort by `ts`
    /// today, but "the list is newest-first" is the promise this screen makes,
    /// and it should not quietly depend on an invariant owned elsewhere. Within
    /// one turn, items keep the order the agent wrote them.
    public static func collect(from messages: [SessionMessage]) -> TranscriptResources {
        var files: [TranscriptAttachment] = []
        var links: [TranscriptLink] = []
        var seenFiles = Set<String>()
        var seenLinks = Set<String>()
        // A message with no timestamp (a locally-appended turn that hasn't been
        // echoed back yet) inherits the last one seen — walking newest→oldest,
        // that is the nearest NEWER turn, which is where it belongs.
        var carried: Double?

        for message in messages.reversed() where message.kind == "text" {
            let ts = message.ts ?? carried
            carried = ts
            let refs = MediaScanner.scan(message.text, includeInlineImages: true)
            let claimed = Set(refs.map(\.raw))
            for ref in refs where !seenFiles.contains(ref.raw) {
                seenFiles.insert(ref.raw)
                files.append(TranscriptAttachment(ref: ref, ts: ts))
            }
            for link in LinkScanner.scan(message.text, excluding: claimed) where !seenLinks.contains(link.url) {
                seenLinks.insert(link.url)
                links.append(TranscriptLink(link: link, ts: ts))
            }
        }
        return TranscriptResources(
            files: sortedNewestFirst(files, by: \.ts),
            links: sortedNewestFirst(links, by: \.ts)
        )
    }

    /// Newest first, stable: equal timestamps keep the order they were collected
    /// in, which is newest-turn-first and then document order. Swift's `sort` is
    /// not stable, so the collection index is the tiebreak.
    ///
    /// A still-undated item sorts as newest. Carry-forward above has already
    /// dated any gap that had a newer neighbour, so what's left is the leading
    /// run — a turn appended locally and not yet echoed back, which is by
    /// construction the newest thing in the transcript.
    private static func sortedNewestFirst<T>(_ items: [T], by ts: KeyPath<T, Double?>) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element[keyPath: ts] ?? .greatestFiniteMagnitude
                let r = rhs.element[keyPath: ts] ?? .greatestFiniteMagnitude
                if l != r { return l > r }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
