import Testing
@testable import LFGCore

@Suite("User message scrubber")
struct UserMessageScrubberTests {
    @Test("anchors include only rendered user bubbles in chronological order")
    func anchorsIncludeOnlyRenderedUserBubblesInChronologicalOrder() {
        let messages = [
            SessionMessage(id: "assistant", role: "assistant", kind: "text", text: "A"),
            SessionMessage(id: "first", role: "user", kind: "text", text: "First"),
            SessionMessage(id: "tool", role: "user", kind: "tool_result", text: "Tool"),
            SessionMessage(id: "thinking", role: "user", kind: "thinking", text: "Thinking"),
            SessionMessage(id: "second", role: "user", kind: "text", text: "Second"),
        ]

        #expect(UserMessageScrubber.anchors(in: messages) == [
            UserMessageAnchor(id: "first", messageIndex: 1),
            UserMessageAnchor(id: "second", messageIndex: 4),
        ])
    }

    @Test("position maps across all anchors and clamps at edges")
    func positionMapsAcrossAllAnchorsAndClampsAtEdges() {
        #expect(UserMessageScrubber.anchorIndex(at: -20, height: 100, count: 4) == 0)
        #expect(UserMessageScrubber.anchorIndex(at: 24.9, height: 100, count: 4) == 0)
        #expect(UserMessageScrubber.anchorIndex(at: 25, height: 100, count: 4) == 1)
        #expect(UserMessageScrubber.anchorIndex(at: 74.9, height: 100, count: 4) == 2)
        #expect(UserMessageScrubber.anchorIndex(at: 75, height: 100, count: 4) == 3)
        #expect(UserMessageScrubber.anchorIndex(at: 120, height: 100, count: 4) == 3)
    }

    @Test("position returns nil without usable anchors or height")
    func positionReturnsNilWithoutUsableAnchorsOrHeight() {
        #expect(UserMessageScrubber.anchorIndex(at: 10, height: 100, count: 0) == nil)
        #expect(UserMessageScrubber.anchorIndex(at: 10, height: 0, count: 4) == nil)
        #expect(UserMessageScrubber.anchorIndex(at: 10, height: -1, count: 4) == nil)
    }

    @Test("required window expands only for older targets")
    func requiredWindowExpandsOnlyForOlderTargets() {
        #expect(UserMessageScrubber.requiredWindow(
            totalMessages: 1_000, targetMessageIndex: 899, currentWindow: 200
        ) == 200)
        #expect(UserMessageScrubber.requiredWindow(
            totalMessages: 1_000, targetMessageIndex: 500, currentWindow: 200
        ) == 500)
        #expect(UserMessageScrubber.requiredWindow(
            totalMessages: 1_000, targetMessageIndex: 0, currentWindow: 200
        ) == 1_000)
    }
}
