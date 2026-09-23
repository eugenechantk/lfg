import Foundation

public struct TranscriptSystemNoticePresentation: Equatable, Sendable {
    public let text: String

    public static func resolve(text: String) -> Self {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(text: trimmed.isEmpty ? "System update" : trimmed)
    }
}
