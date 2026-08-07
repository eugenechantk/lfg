// Promoting a question's preamble out of the prompt panel and into the
// transcript. The hazard is the handover: when the question is answered, Claude
// Code flushes the real turn and the server clears the prompt as two independent
// events in no guaranteed order, so the synthesized turn must stand down the
// moment the real one is visible — not one event later.
import Testing
@testable import LFGCore

@Suite("Prompt preamble")
struct PromptPreambleTests {
    private let prose = """
    PARAGRAPH-ONE-STARTS-HERE The choice between Route North and Route South \
    comes down to what you value in the crossing.
    """

    private func prompt(context: String?) -> AgentPrompt {
        AgentPrompt(
            question: "Which route should we take?",
            options: [PromptOption(index: 1, label: "Route North", selected: true)],
            context: context
        )
    }

    private func assistant(_ text: String) -> SessionMessage {
        SessionMessage(id: "real", role: "assistant", kind: "text", text: text)
    }

    @Test("renders as an ordinary assistant text turn")
    func rendersAsAssistantTurn() {
        let m = PromptPreamble.message(for: prompt(context: prose), sessionID: "s1", transcriptTail: [])
        #expect(m?.role == "assistant")
        // kind "text" is what routes it to TextBubble (markdown), not a tool line.
        #expect(m?.kind == "text")
        #expect(m?.text == prose)
        #expect(m?.id == "prompt-preamble:s1")
    }

    @Test("identity is stable across a re-scrape so the row updates, not duplicates")
    func stableIdentity() {
        let a = PromptPreamble.message(for: prompt(context: prose), sessionID: "s1", transcriptTail: [])
        let b = PromptPreamble.message(for: prompt(context: prose + " More."), sessionID: "s1", transcriptTail: [])
        #expect(a?.stableID == b?.stableID)
    }

    @Test("nothing to render without a question or without context")
    func nothingToRender() {
        #expect(PromptPreamble.message(for: nil, sessionID: "s1", transcriptTail: []) == nil)
        #expect(PromptPreamble.message(for: prompt(context: nil), sessionID: "s1", transcriptTail: []) == nil)
        #expect(PromptPreamble.message(for: prompt(context: "   "), sessionID: "s1", transcriptTail: []) == nil)
    }

    @Test("stands down once the real turn lands, even while the prompt is still set")
    func handsOverToTheRealTurn() {
        // The exact doubled-render window: transcript already flushed, prompt not
        // yet cleared.
        let tail = [assistant(prose)]
        #expect(PromptPreamble.message(for: prompt(context: prose), sessionID: "s1", transcriptTail: tail) == nil)
    }

    @Test("matches the real turn despite the scrape's rewrapping")
    func matchesAcrossRewrap() {
        // The scrape rejoins the pane's hard wrap with single spaces, so it can
        // never equal the flushed turn byte-for-byte.
        let real = assistant("PARAGRAPH-ONE-STARTS-HERE   The choice between Route North\nand Route South\n comes down to what you value in the crossing.")
        #expect(!PromptPreamble.shouldSynthesize(context: prose, transcriptTail: [real]))
    }

    @Test("a clipped scrape still matches — the real turn is its superset")
    func clippedScrapeMatches() {
        let real = assistant("Some earlier sentence the pane could not show. " + prose)
        #expect(!PromptPreamble.shouldSynthesize(context: prose, transcriptTail: [real]))
    }

    @Test("unrelated prose in the tail does not suppress it")
    func unrelatedTailDoesNotSuppress() {
        let tail = [assistant("Completely different earlier answer about deployment.")]
        #expect(PromptPreamble.message(for: prompt(context: prose), sessionID: "s1", transcriptTail: tail) != nil)
    }

    @Test("only the tail is consulted, so old prose can't suppress a repeat question")
    func onlyTailIsConsulted() {
        // Same question asked again much later: the old flushed copy is far back
        // and must not cancel the live one.
        var tail = [assistant(prose)]
        for i in 0..<PromptPreamble.tailWindow { tail.append(assistant("filler \(i)")) }
        #expect(PromptPreamble.message(for: prompt(context: prose), sessionID: "s1", transcriptTail: tail) != nil)
    }

    @Test("a tool line carrying the same text does not count as the real turn")
    func toolLineIsNotTheTurn() {
        let toolEcho = SessionMessage(id: "t", role: "assistant", kind: "tool_use", text: prose)
        #expect(PromptPreamble.message(for: prompt(context: prose), sessionID: "s1", transcriptTail: [toolEcho]) != nil)
    }

    @Test("a very short context is never suppressed by coincidental containment")
    func shortContextNotSuppressed() {
        let short = "Pick one."
        #expect(PromptPreamble.shouldSynthesize(context: short, transcriptTail: [assistant("Pick one. And then pick another.")]))
    }
}
