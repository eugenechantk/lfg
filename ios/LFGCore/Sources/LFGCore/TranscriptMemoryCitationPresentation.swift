import Foundation

public struct TranscriptMemoryCitationPresentation: Equatable, Sendable {
    public struct Citation: Equatable, Sendable {
        public let location: String
        public let note: String

        public init(location: String, note: String) {
            self.location = location
            self.note = note
        }
    }

    public let title: String
    public let citations: [Citation]
    public let priorSessionCount: Int

    public var summary: String {
        "\(citations.count) citation\(citations.count == 1 ? "" : "s")"
    }

    public static func resolve(text: String) -> Self {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var citations: [Citation] = []
        var priorSessionCount = 0
        for line in lines.dropFirst() {
            if line.hasPrefix("Prior sessions:"),
               let count = Int(line.dropFirst("Prior sessions:".count).trimmingCharacters(in: .whitespaces)) {
                priorSessionCount = count
                continue
            }
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                citations.append(Citation(location: String(parts[0]), note: String(parts[1])))
            }
        }

        if citations.isEmpty {
            let fallback = text.trimmingCharacters(in: .whitespacesAndNewlines)
            citations = [Citation(location: "", note: fallback.isEmpty ? "Saved memory" : fallback)]
        }
        return Self(title: "Memory sources", citations: citations, priorSessionCount: priorSessionCount)
    }
}
