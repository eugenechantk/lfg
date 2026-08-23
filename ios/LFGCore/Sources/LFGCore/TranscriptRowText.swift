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
    /// Assistant markdown with inline image markdown removed — the image shows
    /// as a card below instead, so leaving `![alt](path)` would double-render it.
    public let prose: String
    /// User-bubble text with attachment references stripped (shown as cards).
    public let displayText: String

    public init(media: [MediaRef], prose: String, displayText: String) {
        self.media = media
        self.prose = prose
        self.displayText = displayText
    }

    /// Byte-for-byte the behaviour the two computed properties had, including
    /// the `!?` difference between them: `prose` strips image markdown only,
    /// `displayText` strips any ref's markdown *and* a bare leftover path.
    public static func derive(from text: String) -> TranscriptRowText {
        let media = MediaScanner.scan(text, includeInlineImages: true)

        var proseText = text
        for ref in media where ref.kind == .image {
            proseText = strippingMarkdown(ref.raw, from: proseText, imageOnly: true)
        }

        var display = text
        for ref in media {
            display = strippingMarkdown(ref.raw, from: display, imageOnly: false)
            display = display.replacingOccurrences(of: ref.raw, with: "")
        }

        return TranscriptRowText(
            media: media,
            prose: proseText.trimmingCharacters(in: .whitespacesAndNewlines),
            displayText: display.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func strippingMarkdown(
        _ raw: String, from text: String, imageOnly: Bool
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: raw)
        let prefix = imageOnly ? "!" : "!?"
        guard let re = try? NSRegularExpression(
            pattern: prefix + "\\[[^\\]]*\\]\\(\\s*" + escaped + "\\s*\\)"
        ) else { return text }
        return re.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
