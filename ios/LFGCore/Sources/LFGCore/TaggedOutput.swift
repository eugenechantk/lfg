import Foundation

/// A display-only projection. The original transcript remains the source for task outcomes.
public enum TaggedOutput {
    public enum Part: Equatable, Sendable {
        case prose(String)
        case tag(name: String, content: String)
    }

    private static let block = try! NSRegularExpression(
        pattern: #"(?m)^[ ]{0,3}<([A-Za-z][A-Za-z0-9_-]*)>([\s\S]*?)</\1>[ \t]*(?=\r?$)"#)
    private static let fence = try! NSRegularExpression(pattern: #"^[ ]{0,3}(`{3,}|~{3,})(.*)$"#)
    private static let comment = try! NSRegularExpression(pattern: #"<!--[\s\S]*?(?:-->|$)"#)

    public static func split(_ text: String) -> [Part] {
        guard text.contains("</") else { return [.prose(text)] }
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        var protected = comment.matches(in: text, range: whole).map(\.range)
        var openFence: (character: Character, length: Int, start: Int)?
        var position = 0
        for line in text.components(separatedBy: "\n") {
            let range = NSRange(location: 0, length: (line as NSString).length)
            if let match = fence.firstMatch(in: line, range: range) {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                let tail = (line as NSString).substring(with: match.range(at: 2))
                if let open = openFence {
                    if marker.first == open.character, marker.count >= open.length,
                       tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        protected.append(NSRange(location: open.start, length: position + range.length - open.start))
                        openFence = nil
                    }
                } else if marker.first != "`" || !tail.contains("`") {
                    openFence = (marker.first!, marker.count, position)
                }
            }
            position += range.length + 1
        }
        if let open = openFence {
            protected.append(NSRange(location: open.start, length: source.length - open.start))
        }
        var parts: [Part] = []
        var cursor = 0
        for match in block.matches(in: text, range: whole) {
            guard !protected.contains(where: { NSLocationInRange(match.range.location, $0) }) else { continue }
            if match.range.location > cursor {
                parts.append(.prose(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            parts.append(.tag(name: source.substring(with: match.range(at: 1)),
                              content: source.substring(with: match.range(at: 2))))
            cursor = NSMaxRange(match.range)
        }
        guard !parts.isEmpty else { return [.prose(text)] }
        if cursor < source.length { parts.append(.prose(source.substring(from: cursor))) }
        return parts
    }
}
