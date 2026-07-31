import Foundation

/// Most-recently-used working directories, feeding the new-session directory
/// picker's `RECENT` section.
///
/// Pure list algebra so it can be unit-tested without a simulator; the app target
/// owns only the persistence.
public enum RecentDirs {
    /// How many entries the RECENT section keeps. The design draws three; five
    /// leaves headroom without turning the section into a second full list.
    public static let cap = 5

    /// Returns `existing` with `path` promoted to the front, de-duplicated and
    /// truncated to `cap`.
    ///
    /// - Blank or whitespace-only paths are ignored (returns `existing` unchanged),
    ///   so a failed create can't poison the list with an empty row.
    /// - Re-selecting a directory already in the list *moves* it to the front
    ///   rather than duplicating it — that is what makes it an MRU rather than a
    ///   history log.
    /// - Trailing slashes are normalised away so `/a/b` and `/a/b/` are one entry.
    public static func pushing(_ path: String, onto existing: [String], cap: Int = cap) -> [String] {
        let key = normalize(path)
        guard !key.isEmpty, cap > 0 else { return existing }

        var out = [key]
        for candidate in existing {
            // Check BEFORE appending: testing after the append overshoots by one
            // and makes `cap: 1` return two entries.
            guard out.count < cap else { break }
            let normalized = normalize(candidate)
            guard !normalized.isEmpty, normalized != key else { continue }
            out.append(normalized)
        }
        return out
    }

    /// Drops a path from the list — used when a directory no longer exists on the
    /// host, so the picker doesn't keep offering a dead cwd.
    public static func removing(_ path: String, from existing: [String]) -> [String] {
        let key = normalize(path)
        return existing.filter { normalize($0) != key }
    }

    /// Trim whitespace and collapse a trailing slash (except for root itself).
    static func normalize(_ path: String) -> String {
        var s = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
