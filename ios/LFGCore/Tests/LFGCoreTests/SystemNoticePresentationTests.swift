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

@Suite("Transcript memory citation presentation")
struct MemoryCitationPresentationTests {
    private let payload = """
    Memory sources
    MEMORY.md:265-268\tLFG iOS session and transcript architecture scope
    MEMORY.md:328-333\tLFG transcript normalization and client verification guidance
    Prior sessions: 2
    """

    @Test("parses citation notes, locations, and prior-session count")
    func parsesPayload() {
        let presentation = TranscriptMemoryCitationPresentation.resolve(text: payload)

        #expect(presentation.title == "Memory sources")
        #expect(presentation.summary == "2 citations")
        #expect(presentation.priorSessionCount == 2)
        #expect(presentation.citations == [
            .init(location: "MEMORY.md:265-268", note: "LFG iOS session and transcript architecture scope"),
            .init(location: "MEMORY.md:328-333", note: "LFG transcript normalization and client verification guidance"),
        ])
    }

    @Test("uses a readable fallback for malformed payloads")
    func malformedFallback() {
        let presentation = TranscriptMemoryCitationPresentation.resolve(text: "Unexpected payload")

        #expect(presentation.title == "Memory sources")
        #expect(presentation.summary == "1 citation")
        #expect(presentation.citations == [
            .init(location: "", note: "Unexpected payload"),
        ])
        #expect(presentation.priorSessionCount == 0)
    }
}
