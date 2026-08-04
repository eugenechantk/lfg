import Testing
@testable import LFGCore

/// The precedence table, written once. `src/session-state-parity.test.ts` asserts
/// the SAME table against the server's `sessionDisplayState`, so the two languages
/// cannot drift apart without one of these two files going red.
///
/// Keep the two tables byte-identical in content and order when changing either.
private let table: [(prompt: Bool, blocked: Bool, busy: Bool, expected: SessionDisplayState)] = [
    // prompt wins over everything — it is the only state that needs a human
    (true, true, true, .needsInput),
    (true, true, false, .needsInput),
    (true, false, true, .needsInput),
    (true, false, false, .needsInput),
    // blocked outranks busy: an upstream API error is not "working"
    (false, true, true, .blocked),
    (false, true, false, .blocked),
    // plain busy
    (false, false, true, .working),
    // nothing asserted
    (false, false, false, .idle),
]

@Suite("SessionDisplayState")
struct SessionDisplayStateTests {
    @Test("resolves the full precedence table")
    func precedenceTable() {
        for row in table {
            let got = SessionDisplayState.resolve(
                promptPresent: row.prompt,
                blocked: row.blocked,
                busy: row.busy
            )
            #expect(
                got == row.expected,
                "prompt=\(row.prompt) blocked=\(row.blocked) busy=\(row.busy) → \(got), expected \(row.expected)"
            )
        }
    }

    @Test("the table covers every input combination")
    func tableIsExhaustive() {
        #expect(table.count == 8) // 2^3 — no combination left to drift
    }

    /// The bug this consolidation exists to prevent: the card and the list
    /// disagreeing. Both now route through `resolve`, so a blocked session is
    /// `.blocked` for each of them rather than "working" for one and "paused" for
    /// the other.
    @Test("a blocked session is never reported as working")
    func blockedIsNotWorking() {
        for busy in [true, false] {
            #expect(
                SessionDisplayState.resolve(promptPresent: false, blocked: true, busy: busy) == .blocked
            )
        }
    }
}
