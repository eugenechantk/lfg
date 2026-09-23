import Testing
@testable import LFGCore

@Suite("Transcript thinking presentation")
struct ThinkingPresentationTests {
    @Test("compaction is a visible static thinking-style label")
    func compactionIsStatic() {
        let presentation = TranscriptThinkingPresentation.resolve(
            text: "Compacting conversation"
        )

        #expect(presentation.title == "Compacting conversation")
        #expect(presentation.detail == nil)
        #expect(presentation.isDisclosure == false)
    }

    @Test("ordinary reasoning keeps the existing expandable Thinking presentation")
    func ordinaryReasoningIsExpandable() {
        let presentation = TranscriptThinkingPresentation.resolve(
            text: "I should inspect the parser first."
        )

        #expect(presentation.title == "Thinking")
        #expect(presentation.detail == "I should inspect the parser first.")
        #expect(presentation.isDisclosure == true)
    }
}
