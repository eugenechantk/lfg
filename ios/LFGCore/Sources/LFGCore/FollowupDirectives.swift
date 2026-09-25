import Foundation

public struct FollowupDirective: Equatable, Sendable {
    public let title: String
    public let prompt: String

    public init(title: String, prompt: String) {
        self.title = title
        self.prompt = prompt
    }
}

public struct FollowupDirectiveResult: Equatable, Sendable {
    public let prose: String
    public let followups: [FollowupDirective]
}

/// Extract only complete standalone directives. Unknown or malformed syntax
/// remains visible so the transcript never silently drops assistant content.
public enum FollowupDirectives {
    private static let directive = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:[-*•][ \t]+)?:codex-followup\[([^\]\n]+)\]\{prompt="((?:\\.|[^"\\])*)"\}[ \t]*$"#
    )

    public static func extract(from markdown: String) -> FollowupDirectiveResult {
        let lines = markdown.components(separatedBy: "\n")
        var proseLines: [String] = []
        var followups: [FollowupDirective] = []
        var fence: (marker: Character, length: Int)?

        for line in lines {
            if let marker = fenceMarker(in: line) {
                if let open = fence {
                    let markerText = line.drop(while: { $0 == " " })
                    let afterMarker = markerText.dropFirst(marker.length)
                    if marker.marker == open.marker && marker.length >= open.length
                        && afterMarker.allSatisfy({ $0 == " " || $0 == "\t" }) {
                        fence = nil
                    }
                } else {
                    fence = marker
                }
                proseLines.append(line)
                continue
            }

            if fence == nil, let followup = parse(line) {
                followups.append(followup)
            } else {
                proseLines.append(line)
            }
        }

        return FollowupDirectiveResult(
            prose: proseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            followups: followups
        )
    }

    private static func parse(_ line: String) -> FollowupDirective? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = directive.firstMatch(in: line, range: range),
              let titleRange = Range(match.range(at: 1), in: line),
              let promptRange = Range(match.range(at: 2), in: line) else { return nil }
        let title = line[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedPrompt = "\"" + line[promptRange] + "\""
        guard !title.isEmpty,
              let prompt = try? JSONDecoder().decode(String.self, from: Data(encodedPrompt.utf8)),
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return FollowupDirective(title: title, prompt: prompt)
    }

    private static func fenceMarker(in line: String) -> (marker: Character, length: Int)? {
        let trimmed = line.drop(while: { $0 == " " })
        guard line.count - trimmed.count <= 3,
              let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        return (marker, length)
    }
}

public enum FollowupDraft {
    public static func adding(_ prompt: String, to draft: String) -> String {
        guard !draft.isEmpty else { return prompt }
        return draft + (draft.hasSuffix("\n") ? "\n" : "\n\n") + prompt
    }
}
