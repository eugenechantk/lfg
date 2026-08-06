import Foundation
import Testing

@testable import LFGCore

// The regression: a permanent journal veto meant a stopped server pump froze
// every client's `busy` at its last value. Two codex sessions that were mid-turn
// at that instant read "Running" for hours while every `/api/sessions` response
// in between correctly said `busy: false`.
// See `.claude/diagnosis-codex-stuck-running-20260806.md`.
@Suite("JournalFreshness")
struct JournalFreshnessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a session the journal has never spoken for takes the snapshot")
    func neverStated() {
        // Change-only delivery: a session already running before this client
        // connected emits nothing, so the snapshot is the ONLY source there is.
        #expect(JournalFreshness.snapshotWins(journalStatedAt: nil, now: now))
    }

    @Test("a fresh journal value out-votes the snapshot")
    func freshJournalWins() {
        let stated = now.addingTimeInterval(-2)
        #expect(!JournalFreshness.snapshotWins(journalStatedAt: stated, now: now))
    }

    @Test("a journal value past the TTL yields to the snapshot")
    func staleJournalYields() {
        // THE BUG. The pump stopped; this value is the last thing it ever said.
        let stated = now.addingTimeInterval(-90 * 60)
        #expect(JournalFreshness.snapshotWins(journalStatedAt: stated, now: now))
    }

    @Test("the TTL boundary yields, so equality can't latch")
    func boundaryYields() {
        let stated = now.addingTimeInterval(-JournalFreshness.defaultTTL)
        #expect(JournalFreshness.snapshotWins(journalStatedAt: stated, now: now))
    }

    @Test("just inside the TTL still holds the veto")
    func justInsideHolds() {
        let stated = now.addingTimeInterval(-(JournalFreshness.defaultTTL - 1))
        #expect(!JournalFreshness.snapshotWins(journalStatedAt: stated, now: now))
    }

    @Test("a backwards clock reads as fresh, not as an enormous age")
    func clockSkew() {
        // An NTP correction that moves the device clock back must not flip the
        // list to the snapshot for a whole TTL's worth of refreshes.
        let stated = now.addingTimeInterval(30)
        #expect(!JournalFreshness.snapshotWins(journalStatedAt: stated, now: now))
    }

    @Test("a custom TTL is honoured")
    func customTTL() {
        let stated = now.addingTimeInterval(-10)
        #expect(JournalFreshness.snapshotWins(journalStatedAt: stated, now: now, ttl: 5))
        #expect(!JournalFreshness.snapshotWins(journalStatedAt: stated, now: now, ttl: 30))
    }

    @Test("the default TTL comfortably exceeds the pump's sweep interval")
    func ttlExceedsSweep() {
        // The pump sweeps every second (POLL_TICK_MS). The TTL must be far enough
        // above that for ordinary jitter never to expire a live stream.
        #expect(JournalFreshness.defaultTTL >= 30)
    }
}
