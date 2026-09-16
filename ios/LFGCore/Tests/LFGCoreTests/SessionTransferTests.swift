import XCTest
@testable import LFGCore

final class SessionTransferTests: XCTestCase {

    // MARK: plan (SC1, SC5)

    func testReachableSourceClosesFirstAndDoesNotForce() {
        XCTAssertEqual(SessionTransfer.plan(sourceKnownDown: false), .normal)
        XCTAssertTrue(SessionTransfer.Plan.normal.closeSource)
        XCTAssertFalse(SessionTransfer.Plan.normal.force)
        XCTAssertFalse(SessionTransfer.Plan.normal.deferSourceClose)
    }

    func testKnownDownSourceSkipsCloseForcesResumeAndDefersClose() {
        let plan = SessionTransfer.plan(sourceKnownDown: true)
        XCTAssertEqual(plan, .sourceUnreachable)
        XCTAssertFalse(plan.closeSource)
        XCTAssertTrue(plan.force)
        XCTAssertTrue(plan.deferSourceClose)
    }

    // MARK: close failure classification (SC2)

    func testCloseFailureClassification() {
        XCTAssertTrue(SessionTransfer.closeFailureIsUnreachable(LFGError.notReachable(underlying: "timed out")))
        XCTAssertTrue(SessionTransfer.closeFailureIsUnreachable(LFGError.transport(code: -1001, underlying: "timed out")))
        XCTAssertFalse(SessionTransfer.closeFailureIsUnreachable(LFGError.http(status: 404, body: "no such session")))
        XCTAssertFalse(SessionTransfer.closeFailureIsUnreachable(LFGError.http(status: 500, body: "boom")))
        XCTAssertFalse(SessionTransfer.closeFailureIsUnreachable(LFGError.decoding("x")))
        struct Other: Error {}
        XCTAssertFalse(SessionTransfer.closeFailureIsUnreachable(Other()))
    }

    // MARK: deferred closes (SC4)

    func testDeferredClosesAddIsIdempotentAndTakeIsOneShot() {
        var d = DeferredSourceCloses()
        XCTAssertTrue(d.isEmpty)
        d.add(host: "air", session: "s1")
        d.add(host: "air", session: "s1")
        d.add(host: "air", session: "s2")
        d.add(host: "pro", session: "s3")
        XCTAssertEqual(d.byHost["air"], ["s1", "s2"])
        XCTAssertEqual(d.take(host: "air"), ["s1", "s2"])
        XCTAssertEqual(d.take(host: "air"), [])
        XCTAssertEqual(d.byHost["pro"], ["s3"])
        XCTAssertFalse(d.isEmpty)
    }

    func testDeferredClosesForgetDropsSessionEverywhere() {
        var d = DeferredSourceCloses()
        d.add(host: "air", session: "s1")
        d.add(host: "air", session: "s2")
        d.forget(session: "s1")
        XCTAssertEqual(d.byHost["air"], ["s2"])
        d.forget(session: "s2")
        XCTAssertNil(d.byHost["air"])
        XCTAssertTrue(d.isEmpty)
    }

    func testDeferredClosesRoundTripAndTolerateGarbage() {
        var d = DeferredSourceCloses()
        d.add(host: "air", session: "s1")
        let back = DeferredSourceCloses.decode(d.encoded())
        XCTAssertEqual(back, d)
        XCTAssertEqual(DeferredSourceCloses.decode(nil), DeferredSourceCloses())
        XCTAssertEqual(DeferredSourceCloses.decode(Data("nope".utf8)), DeferredSourceCloses())
    }

    // MARK: request wire shape (SC3 client half)

    func testResumeRequestCarriesForceOnlyWhenSet() throws {
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ResumeRequest(sessionId: "x"))) as? [String: Any]
        XCTAssertNil(plain?["force"])
        let forced = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ResumeRequest(sessionId: "x", force: true))) as? [String: Any]
        XCTAssertEqual(forced?["force"] as? Bool, true)
    }

    // MARK: pre-flight (SC7–SC9)

    func testPreflightMissingTranscriptBlocks() {
        let p = SessionTransfer.preflight(status: TranscriptStatus(found: false), sourceLastActivityAt: 1_000)
        XCTAssertEqual(p, .missing)
        XCTAssertTrue(p.blocks)
        XCTAssertFalse(p.needsConfirmation)
    }

    func testPreflightMissingCwdBlocksWithPath() {
        let st = TranscriptStatus(found: true, cwd: "/Users/x/repo", cwdExists: false, lastActivityAt: 1_000)
        XCTAssertEqual(SessionTransfer.preflight(status: st, sourceLastActivityAt: 1_000), .cwdMissing("/Users/x/repo"))
    }

    func testPreflightFreshCopyIsReady() {
        let now = Date().timeIntervalSince1970 * 1000
        let st = TranscriptStatus(found: true, cwd: "/r", cwdExists: true, lastActivityAt: now - 20_000)
        XCTAssertEqual(SessionTransfer.preflight(status: st, sourceLastActivityAt: now), .ready)
    }

    func testPreflightStaleCopyAsksInsteadOfBlocking() {
        let now = Date().timeIntervalSince1970 * 1000
        let st = TranscriptStatus(found: true, cwd: "/r", cwdExists: true, lastActivityAt: now - 14 * 60_000)
        let p = SessionTransfer.preflight(status: st, sourceLastActivityAt: now)
        guard case .behind(let seconds) = p else { return XCTFail("expected .behind, got \(p)") }
        XCTAssertEqual(seconds, 14 * 60, accuracy: 1)
        XCTAssertFalse(p.blocks)
        XCTAssertTrue(p.needsConfirmation)
    }

    func testPreflightWithoutTimestampsIsReadyNotStale() {
        let st = TranscriptStatus(found: true, cwd: "/r", cwdExists: true, lastActivityAt: nil)
        XCTAssertEqual(SessionTransfer.preflight(status: st, sourceLastActivityAt: 5), .ready)
        let st2 = TranscriptStatus(found: true, cwd: "/r", cwdExists: true, lastActivityAt: 5)
        XCTAssertEqual(SessionTransfer.preflight(status: st2, sourceLastActivityAt: nil), .ready)
    }

    func testBehindLabel() {
        XCTAssertEqual(SessionTransfer.behindLabel(30), "under a minute")
        XCTAssertEqual(SessionTransfer.behindLabel(14 * 60), "14 min")
        XCTAssertEqual(SessionTransfer.behindLabel(2 * 3600), "2 h")
        XCTAssertEqual(SessionTransfer.behindLabel(3 * 86400), "3 days")
    }

    func testTranscriptStatusDecodesLenientlyAndFoundDefaultsFalse() throws {
        let missing = try JSONDecoder().decode(TranscriptStatus.self, from: Data("{\"found\":false}".utf8))
        XCTAssertFalse(missing.found)
        let garbage = try JSONDecoder().decode(TranscriptStatus.self, from: Data("{\"bytes\":\"x\"}".utf8))
        XCTAssertFalse(garbage.found)
        XCTAssertNil(garbage.bytes)
        let full = try JSONDecoder().decode(TranscriptStatus.self, from: Data(
            "{\"found\":true,\"agent\":\"claude\",\"cwd\":\"/r\",\"cwdExists\":true,\"bytes\":12,\"mtimeMs\":1.5,\"lastActivityAt\":1700000000000}".utf8))
        XCTAssertEqual(full, TranscriptStatus(found: true, agent: "claude", cwd: "/r", cwdExists: true, bytes: 12, mtimeMs: 1.5, lastActivityAt: 1_700_000_000_000))
    }
}
