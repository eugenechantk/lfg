import Testing
@testable import LFGCore

@Suite("Transcript system notice presentation")
struct SystemNoticePresentationTests {
    @Test("preserves the visible local command while trimming wrapper whitespace")
    func trimsCommand() {
        let presentation = TranscriptSystemNoticePresentation.resolve(text: "  /model opus\n")

        #expect(presentation.text == "/model opus")
    }

    @Test("uses a readable fallback for an empty notice")
    func emptyFallback() {
        let presentation = TranscriptSystemNoticePresentation.resolve(text: " \n ")

        #expect(presentation.text == "System update")
    }
}
