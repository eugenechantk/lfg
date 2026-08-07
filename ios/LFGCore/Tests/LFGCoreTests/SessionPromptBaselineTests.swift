// `Session.prompt` — the REST baseline for a question the journal already asked.
//
// The journal's `prompt` event is a DELTA, and a client's cursor starts at the
// journal head, so a session already parked at a question when the client
// connected never receives an event for it. `/api/sessions` carried no prompt
// field at all, so there was nothing to recover from: the session rendered as
// plain "Running", with no panel. And because Claude Code does not flush the
// asking turn to its transcript until the question is answered, the prose
// explaining the question was not on screen either — the long-standing "the
// response before the question only appears after I answer it" report.
import Testing
import Foundation
@testable import LFGCore

@Suite("Session prompt baseline")
struct SessionPromptBaselineTests {
    private func decode(_ json: String) throws -> Session {
        try JSONDecoder().decode(Session.self, from: Data(json.utf8))
    }

    @Test("decodes a parked question, including the pane-scraped context")
    func decodesPrompt() throws {
        let s = try decode("""
        {"sessionId":"abc","title":"t","prompt":{
          "question":"Which route should we take?",
          "context":"PARAGRAPH-ONE-STARTS-HERE the tradeoff is reliability against speed.",
          "options":[{"index":1,"label":"ROUTE NORTH","selected":true},
                     {"index":2,"label":"ROUTE SOUTH","selected":false}]}}
        """)
        #expect(s.prompt?.question == "Which route should we take?")
        #expect(s.prompt?.options.count == 2)
        // The context is the whole point: while the question is live it is the
        // ONLY copy of what the model said before asking.
        #expect(s.prompt?.context?.hasPrefix("PARAGRAPH-ONE-STARTS-HERE") == true)
    }

    @Test("a session with no question decodes to nil, not a failure")
    func absentPromptIsNil() throws {
        #expect(try decode(#"{"sessionId":"abc","title":"t"}"#).prompt == nil)
        #expect(try decode(#"{"sessionId":"abc","title":"t","prompt":null}"#).prompt == nil)
    }

    @Test("a malformed prompt does not fail the whole session decode")
    func malformedPromptDoesNotBlankTheRow() throws {
        // Lenient decoding is the house rule — a bad prompt must cost the panel,
        // never the session list.
        let s = try decode(#"{"sessionId":"abc","title":"t","prompt":{"question":42}}"#)
        #expect(s.sessionId == "abc")
        #expect(s.prompt == nil)
    }

    @Test("baseline yields to a fresh journal statement, wins when there is none")
    func arbitration() {
        let now = Date()
        // Never stated by the journal → the snapshot is the only source.
        #expect(JournalFreshness.snapshotWins(journalStatedAt: nil, now: now))
        // Just stated → the event is fresher; the snapshot must not clobber it.
        #expect(!JournalFreshness.snapshotWins(journalStatedAt: now, now: now))
        // Long since stated → a dead pump self-corrects from the snapshot.
        #expect(JournalFreshness.snapshotWins(
            journalStatedAt: now.addingTimeInterval(-JournalFreshness.defaultTTL - 1), now: now))
    }
}
