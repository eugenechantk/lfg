public struct TranscriptThinkingPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String?
    public let isDisclosure: Bool

    public static func resolve(text: String) -> Self {
        if text == "Compacting conversation" {
            return Self(
                title: text,
                detail: nil,
                isDisclosure: false
            )
        }

        return Self(
            title: "Thinking",
            detail: text,
            isDisclosure: true
        )
    }
}
