import XCTest
@testable import LFGCore

/// Cover for the persisted-outbox afterlife: rows from the flaky Cloudflare days
/// re-materialising as red "Not sent" bubbles on every launch, for messages that
/// were actually delivered.
final class OutboxResurrectionTests: XCTestCase {

    private let minute = 60.0 * 1_000
    private let day = 24 * 60.0 * 60 * 1_000

    // MARK: Delivered — the reported bug

    /// The exact case Eugene sees: an ancient failed row whose text IS in the
    /// transcript. It must vanish, not greet him.
    func testAncientRowAlreadyInTranscriptIsRetired() {
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 90 * day, deliveredInTranscript: true),
            .retire)
    }

    /// Delivery outranks age in both directions — including inside the retry
    /// window, where re-POSTing it would duplicate the message.
    func testDeliveredRowIsRetiredAtAnyAge() {
        for age in [0, 1 * minute, 12 * day, 400 * day] {
            XCTAssertEqual(
                OutboxResurrectionPolicy.decide(ageMs: age, deliveredInTranscript: true),
                .retire, "age=\(age)")
        }
    }

    /// A send that landed under a DIFFERENT clientId (the retry generated its
    /// own) still leaves its text in the transcript. The policy takes no
    /// clientId and no row state precisely so this case resolves.
    func testDeliveryUnderADifferentClientIdStillRetires() {
        // The caller matches by text, so "delivered" is true even though the
        // row's own clientId was never acked and its state on disk is `failed`.
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 3 * day, deliveredInTranscript: true),
            .retire)
    }

    // MARK: Not delivered — bounded afterlife

    func testFreshRowIsRetried() {
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 5 * minute, deliveredInTranscript: false),
            .retry)
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 1 * day, deliveredInTranscript: false),
            .retry, "exactly at the retry cap still retries")
    }

    /// Past the retry cap but recent: the user should still see it and be able
    /// to act. This is the behaviour that must NOT regress.
    func testRecentTerminalRowSurfaces() {
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 2 * day, deliveredInTranscript: false),
            .surface)
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 6.9 * day, deliveredInTranscript: false),
            .surface)
    }

    /// The afterlife bound: ancient and unprovable stops asking.
    func testAncientUndeliveredRowIsPruned() {
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 7 * day, deliveredInTranscript: false),
            .prune)
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 90 * day, deliveredInTranscript: false),
            .prune)
    }

    // MARK: Boundaries

    func testWindowBoundariesAreExact() {
        let p = OutboxResurrectionPolicy.self
        XCTAssertEqual(p.decide(ageMs: p.retryWindowMs, deliveredInTranscript: false), .retry)
        XCTAssertEqual(p.decide(ageMs: p.retryWindowMs + 1, deliveredInTranscript: false), .surface)
        XCTAssertEqual(p.decide(ageMs: p.afterlifeMs - 1, deliveredInTranscript: false), .surface)
        XCTAssertEqual(p.decide(ageMs: p.afterlifeMs, deliveredInTranscript: false), .prune)
    }

    /// A clock that went backwards must not make a row immortal.
    func testNegativeAgeIsTreatedAsFresh() {
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: -5 * minute, deliveredInTranscript: false),
            .retry)
    }

    // MARK: The reachable-host drain

    /// The case that bit in independent verification: a row past the retry cap
    /// whose host has just become reachable. The drain must reach the SAME
    /// decision as the launch path — surface it, never re-POST it. A stale
    /// instruction firing days later is exactly what the cap exists to prevent.
    func testReachableDrainDoesNotRetryAStaleRow() {
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 3 * day, deliveredInTranscript: false),
            .surface,
            "a 3-day-old row must not be re-sent just because a host answered")
    }

    /// And the flip side: the drain still exists to send genuinely queued work.
    func testReachableDrainStillRetriesRecentRows() {
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: 30 * minute, deliveredInTranscript: false),
            .retry)
    }

    /// Age must be computed from `createdAt`. Recording a failure rewrites
    /// `updatedAt`, so a row measured that way looks brand new and gets re-sent
    /// — the actual mechanism behind the drain regression.
    func testAgeFromUpdatedAtWouldMisclassifyAStaleRow() {
        let createdAgeMs = 3 * day        // truth: stale
        let updatedAgeMs = 0.0            // what a state-write leaves behind
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: createdAgeMs, deliveredInTranscript: false),
            .surface)
        XCTAssertEqual(
            OutboxResurrectionPolicy.decide(ageMs: updatedAgeMs, deliveredInTranscript: false),
            .retry,
            "documents the trap: measuring age from updatedAt re-arms the send")
    }

    // MARK: The POST-boundary gate

    /// The invariant that replaces call-site gating. `.surface` is the one that
    /// keeps escaping: terminal-but-recent, alive in the UI, and auto-sent by
    /// whichever replay path nobody had enumerated that week.
    func testAutomaticSendsOnlyEverPermitRetry() {
        XCTAssertTrue(OutboxSendGate.permits(.retry, trigger: .automatic))
        for decision: OutboxResurrection in [.surface, .retire, .prune] {
            XCTAssertFalse(
                OutboxSendGate.permits(decision, trigger: .automatic),
                "\(decision) must never be auto-POSTed")
        }
    }

    /// The user tapped Retry on a three-day-old message. They can see it and
    /// asked for it — age is not a reason to refuse them.
    func testUserInitiatedRetryIsAllowedAtAnyAge() {
        for decision: OutboxResurrection in [.retry, .surface, .prune] {
            XCTAssertTrue(
                OutboxSendGate.permits(decision, trigger: .userInitiated),
                "\(decision) should be retryable by hand")
        }
    }

    /// The one thing a human may not do: re-send a turn the transcript already
    /// carries. That duplicates a message demonstrably already delivered — and
    /// the Retry button had no such guard before.
    func testUserInitiatedRetryStillRefusesAProvenDelivery() {
        XCTAssertFalse(OutboxSendGate.permits(.retire, trigger: .userInitiated))
    }

    /// The field failure, end to end: a 3-day-old undelivered row reached by an
    /// automatic path must be refused at the boundary no matter which caller it
    /// came from.
    func testStaleRowIsRefusedAtTheBoundaryForEveryAutomaticCaller() {
        let decision = OutboxResurrectionPolicy.decide(
            ageMs: 3 * day, deliveredInTranscript: false)
        XCTAssertEqual(decision, .surface)
        XCTAssertFalse(OutboxSendGate.permits(decision, trigger: .automatic))
    }

    /// The shallow live-reconcile window is one reason these rows never retired;
    /// the resurrection path must search far enough to find a days-old turn.
    func testResurrectionSearchesFarDeeperThanTheLivePath() {
        XCTAssertGreaterThan(OutboxResurrectionPolicy.resurrectionSearchLimit, 30)
    }
}
