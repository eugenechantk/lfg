import Foundation

/// A per-device mute list of working directories: any session whose `cwd` is at
/// or under one of these paths is not shown in the session list.
///
/// The motivating population is `gbrain` autopilot sessions, which run in
/// `~/.gbrain` and are indistinguishable from real work by agent, model or title
/// — the working directory is the one stable thing they share. So the primitive
/// is "hide by directory", and `~/.gbrain` is merely its first entry.
///
/// Hiding is a **viewing** preference, not a fact about the session: it lives on
/// the client (so the desktop app and CLI still see everything), spans hosts (a
/// server only knows its own sessions), and never makes a session unreachable —
/// a notification deep-link into a hidden session still opens.
public struct HiddenDirs: Sendable, Equatable {
    /// Normalized, absolute, de-duplicated directory paths in the order the user
    /// added them.
    public let paths: [String]

    public init(_ raw: [String] = []) {
        var seen = Set<String>()
        self.paths = raw.compactMap(Self.normalize).filter { seen.insert($0.lowercased()).inserted }
    }

    public var isEmpty: Bool { paths.isEmpty }

    /// Whether a session in `cwd` should be hidden.
    ///
    /// A session with no `cwd` is never hidden: hiding is an assertion about a
    /// directory, and with no directory there is no assertion to make. Matching
    /// is on path-segment boundaries — a raw `hasPrefix` would let `.gbrain`
    /// swallow `.gbrainstorm` — and case-insensitive, because the hosts are macOS
    /// (case-insensitive FS) and a path typed with the wrong case silently
    /// matching nothing is a worse failure than over-matching.
    ///
    /// An entry containing `*` or `?` is a **pattern** rather than a literal
    /// directory, and matches `cwd` or any of its ancestors. This exists because
    /// the population that motivated the feature does not have a stable path:
    /// `gbrain` autopilot runs each session in `$TMPDIR/gbrain-claude-cli-cwd-<pid>`,
    /// a fresh directory every time. Literal paths alone would mean re-hiding the
    /// same noise on every run — i.e. not solving the problem.
    public func hides(cwd: String?) -> Bool {
        guard let dir = cwd.flatMap(Self.normalize)?.lowercased() else { return false }
        return paths.contains { p in
            let hidden = p.lowercased()
            guard Self.isPattern(hidden) else {
                return dir == hidden || dir.hasPrefix(hidden + "/")
            }
            // A pattern hides everything at or under what it matches, so
            // `*/gbrain-claude-cli-cwd-*` also covers that directory's children.
            var candidate = dir
            while true {
                if Self.glob(pattern: hidden, matches: candidate) { return true }
                guard let slash = candidate.lastIndex(of: "/"), slash != candidate.startIndex else { return false }
                candidate = String(candidate[candidate.startIndex..<slash])
            }
        }
    }

    public static func isPattern(_ s: String) -> Bool { s.contains("*") || s.contains("?") }

    /// Glob match: `*` matches any run of characters (including `/`), `?` matches
    /// exactly one. Iterative with backtracking — no recursion, so a pathological
    /// pattern can't blow the stack on the main actor.
    static func glob(pattern: String, matches text: String) -> Bool {
        let p = Array(pattern), t = Array(text)
        var pi = 0, ti = 0
        var starP = -1, starT = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "*" {
                starP = pi; starT = ti; pi += 1
            } else if pi < p.count, p[pi] == "?" || p[pi] == t[ti] {
                pi += 1; ti += 1
            } else if starP >= 0 {
                // Backtrack: let the last `*` swallow one more character.
                pi = starP + 1; starT += 1; ti = starT
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// A pattern generalizing a per-run directory, or nil when the path looks
    /// stable.
    ///
    /// `$TMPDIR/gbrain-claude-cli-cwd-24267` → `*/gbrain-claude-cli-cwd-*`. The
    /// heuristic is deliberately narrow — a trailing `-<digits>` or `.<digits>`
    /// on the last path component, which is what pid/timestamp-suffixed scratch
    /// directories look like — because a wrong guess here hides real work. It only
    /// ever powers an explicitly-labelled second swipe action; nothing applies it
    /// automatically.
    public static func suggestedPattern(for path: String) -> String? {
        guard let p = normalize(path), !isPattern(p) else { return nil }
        let name = (p as NSString).lastPathComponent
        guard let sep = name.lastIndex(where: { $0 == "-" || $0 == "." }) else { return nil }
        let suffix = name[name.index(after: sep)...]
        guard suffix.count >= 2, suffix.allSatisfy(\.isNumber) else { return nil }
        let stem = String(name[name.startIndex..<sep])
        guard stem.count >= 3 else { return nil }
        return "*/\(stem)\(name[sep])*"
    }

    /// Add a directory. Idempotent (including across case) and order-stable, so
    /// the Settings editor and the row swipe can't produce duplicate entries.
    /// A path that doesn't normalize is ignored rather than stored broken.
    public func adding(_ path: String) -> HiddenDirs {
        guard let p = Self.normalize(path) else { return self }
        guard !paths.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) else { return self }
        return HiddenDirs(paths + [p])
    }

    public func removing(_ path: String) -> HiddenDirs {
        guard let p = Self.normalize(path) else { return self }
        return HiddenDirs(paths.filter { $0.caseInsensitiveCompare(p) != .orderedSame })
    }

    /// Trim and collapse repeated/trailing slashes. An entry must be either an
    /// absolute path or a wildcard pattern.
    ///
    /// `~` is rejected on purpose: this client cannot expand it against a *host's*
    /// home directory, so a stored `~/.gbrain` would match nothing and read as a
    /// bug rather than as a rejected input. Session `cwd`s arrive absolute.
    ///
    /// `/` and a bare `*` are rejected for the same reason: each would empty the
    /// entire list, with nothing on screen explaining why.
    public static func normalize(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") || isPattern(trimmed) else { return nil }
        guard !trimmed.hasPrefix("~") else { return nil }
        let leadingSlash = trimmed.hasPrefix("/")
        let body = trimmed.split(separator: "/").joined(separator: "/")
        guard !body.isEmpty else { return nil }
        let joined = leadingSlash ? "/" + body : body
        // A pattern of nothing but wildcards matches every path.
        guard joined.contains(where: { $0 != "*" && $0 != "?" && $0 != "/" }) else { return nil }
        return joined
    }

    /// Display name for a hidden path — its last component, falling back to the
    /// whole path.
    public static func displayName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}
