import Foundation

/// The three text derivations a transcript row needs, computed once.
///
/// `TextBubble` used to compute all of this inside `body`: it scanned the text
/// for media refs, then compiled an `NSRegularExpression` **per ref** for
/// `prose` and again for `displayText`. Body runs on every SwiftUI update, for
/// every visible row — and Phase-1 finding 1 showed the transcript re-evaluates
/// once per scroll frame, so this was regex compilation per row per frame.
///
/// The derivation is a pure function of the message text, so it is computed here
/// and memoised by stable id at the call site.
public struct TranscriptRowText: Equatable, Sendable {
    /// Files and links found in the text, rendered as cards.
    public let media: [MediaRef]
    /// Assistant markdown without file handoffs that already render as cards.
    public let prose: String
    /// User-bubble text with attachment references stripped (shown as cards).
    public let displayText: String
    /// Standalone assistant follow-up directives, shown as action text below prose.
    public let followups: [FollowupDirective]

    public init(media: [MediaRef], prose: String, displayText: String, followups: [FollowupDirective] = []) {
        self.media = media
        self.prose = prose
        self.displayText = displayText
        self.followups = followups
    }

    /// Extract follow-up directives and replace file handoffs with their cards.
    /// Code examples keep their literal contents.
    public static func derive(from text: String, extractFollowups: Bool = true) -> TranscriptRowText {
        // User bubbles show the user's request, while the raw transcript retains
        // the host's task setup instructions for the agent and diagnostics.
        let text = extractFollowups ? text : ScheduledTaskChatContext.displayedMessage(text)
        let extracted = extractFollowups
            ? FollowupDirectives.extract(from: text)
            : FollowupDirectiveResult(prose: text, followups: [])
        let media = MediaScanner.scan(extracted.prose, includeInlineImages: true)

        let proseText = strippingCardReferences(from: extracted.prose, media: media)

        var display = text
        for ref in media {
            display = strippingMarkdown(ref.raw, from: display)
            display = display.replacingOccurrences(of: ref.raw, with: "")
        }

        return TranscriptRowText(
            media: media,
            prose: trimmingBlankLines(proseText),
            displayText: display.trimmingCharacters(in: .whitespacesAndNewlines),
            followups: extracted.followups
        )
    }

    private static let inlineCode = try! NSRegularExpression(pattern: #"(?<!`)(`+)(?!`)(.*?)\1(?!`)"#)
    private static let listMarker = try! NSRegularExpression(pattern: #"^ *(?:[-*+]|[0-9]{1,9}[.)])( +)(?=\S)"#)

    private static func trimmingBlankLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let hasContent: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.firstIndex(where: hasContent),
              let last = lines.lastIndex(where: hasContent) else { return "" }
        return lines[first...last].joined(separator: "\n")
    }

    private static func strippingCardReferences(from text: String, media: [MediaRef]) -> String {
        guard !media.isEmpty else { return text }
        var fence: (marker: Character, length: Int)?
        var listColumns: [Int] = []
        var previousBlank = true
        var indentedCode = false

        func stripProse(_ text: String) -> String {
            var result = text
            for ref in media {
                result = strippingMarkdown(ref.raw, from: result)
                result = result.replacingOccurrences(of: "<\(ref.raw)>", with: "")
                // A card for a.png must not eat the prefix of a.png.backup.
                let raw = NSRegularExpression.escapedPattern(for: ref.raw)
                result = result.replacingOccurrences(
                    of: "(?<![\\w./~%-])" + raw + "(?!(?:[\\w/~%?=&#+-]|\\.[\\w.]))",
                    with: "", options: .regularExpression
                )
            }
            return result
        }

        return text.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isBlank = trimmed.isEmpty
            defer { previousBlank = isBlank }
            let marker = trimmed.first
            let run = trimmed.prefix { $0 == marker }.count
            if let open = fence {
                if marker == open.marker, run >= open.length,
                   trimmed.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil }
                return line
            }
            if let marker, (marker == "`" || marker == "~"), run >= 3,
               marker != "`" || !trimmed.dropFirst(run).contains("`") {
                fence = (marker, run)
                return line
            }
            // Indentation is relative to the current list item's content.
            // A nested handoff must not be mistaken for an indented code block.
            if !isBlank {
                let indent = line.prefix { $0 == " " }.count
                listColumns.removeAll { $0 > indent }
                if line.hasPrefix("\t") ||
                   (indent >= (listColumns.last ?? 0) + 4 && (previousBlank || indentedCode)) {
                    indentedCode = true
                    return line
                }
                indentedCode = false
                if let marker = listMarker.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let spaces = marker.range(at: 1).length
                    listColumns.append(marker.range.length - spaces + (spaces >= 5 ? 1 : spaces))
                }
            }

            let ns = line as NSString
            var result = ""
            var offset = 0
            for span in inlineCode.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                result += stripProse(ns.substring(with: NSRange(location: offset, length: span.range.location - offset)))
                let code = ns.substring(with: span.range)
                let body = ns.substring(with: span.range(at: 2)).trimmingCharacters(in: .whitespaces)
                // A lone backticked filename is a handoff; commands stay intact.
                if !media.contains(where: { $0.raw == body }) { result += code }
                offset = NSMaxRange(span.range)
            }
            result += stripProse(ns.substring(from: offset))
            if result != line,
               result.trimmingCharacters(in: .whitespaces).range(
                of: #"^(?:[-*+]|\d+[.)])?$"#, options: .regularExpression
               ) != nil { return "" }
            return result
        }.joined(separator: "\n")
    }

    private static func strippingMarkdown(_ raw: String, from text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: raw)
        // Mirrors what `MediaScanner` accepts as a destination: the path may be
        // wrapped in CommonMark angle brackets (how a path containing spaces is
        // written) and may carry a link title. Missing either leaves the raw
        // `![…](…)` in the prose under the card that now renders it.
        guard let re = try? NSRegularExpression(
            pattern: "!?\\[[^\\]]*\\]\\(\\s*<?" + escaped
                + ">?\\s*(?:\"[^\"\\n]*\"|'[^'\\n]*')?\\s*\\)"
        ) else { return text }
        return re.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
