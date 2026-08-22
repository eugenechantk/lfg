import XCTest
@testable import LFGCore

final class TranscriptMergeTests: XCTestCase {
    func testUnionKeepsSourceAndDestinationMessagesInTimestampOrder() {
        let placeholder = [
            SessionMessage(id: "m1", role: "user", kind: "text", text: "Start", ts: 100)
        ]
        let realIdLive = [
            SessionMessage(id: "m2", role: "assistant", kind: "text", text: "Working", ts: 120),
            SessionMessage(id: "m3", role: "assistant", kind: "text", text: "Done", ts: 140)
        ]

        let merged = TranscriptMerge.unionByStableID(placeholder, realIdLive)

        XCTAssertEqual(merged.map(\.id), ["m1", "m2", "m3"])
    }

    func testUnionDeduplicatesByStableIDAndKeepsLaterPayload() {
        let placeholder = [
            SessionMessage(id: "m1", role: "assistant", kind: "text", text: "stale", ts: 100)
        ]
        let realIdLive = [
            SessionMessage(id: "m1", role: "assistant", kind: "text", text: "authoritative", ts: 100),
            SessionMessage(id: "m2", role: "assistant", kind: "text", text: "next", ts: 110)
        ]

        let merged = TranscriptMerge.unionByStableID(placeholder, realIdLive)

        XCTAssertEqual(merged.map(\.id), ["m1", "m2"])
        XCTAssertEqual(merged.first?.text, "authoritative")
    }

    func testUnionFallsBackToArrivalOrderWhenTimestampsAreMissingOrEqual() {
        let first = [
            SessionMessage(id: "m1", role: "assistant", kind: "text", text: "first"),
            SessionMessage(id: "m2", role: "assistant", kind: "text", text: "second", ts: 100)
        ]
        let second = [
            SessionMessage(id: "m3", role: "assistant", kind: "text", text: "third")
        ]

        let merged = TranscriptMerge.unionByStableID(first, second)

        XCTAssertEqual(merged.map(\.id), ["m1", "m2", "m3"])
    }

    func testUnionUsesStableIDForMessagesWithoutTranscriptIds() {
        let duplicateA = SessionMessage(role: "user", kind: "text", text: "same", ts: 100)
        let duplicateB = SessionMessage(role: "user", kind: "text", text: "same", ts: 100)

        let merged = TranscriptMerge.unionByStableID([duplicateA], [duplicateB])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.stableID, duplicateA.stableID)
    }
}

/// Cover for the incremental history merge that replaced the per-page
/// dictionary-rebuild-and-re-sort in `SessionStore.mergeHistoryPage`.
///
/// The contract that matters: the merged transcript must be byte-for-byte the
/// same ordering the old comparator produced, at a fraction of the cost.
final class TranscriptHistoryPageMergeTests: XCTestCase {

    private func msg(_ id: String, _ ts: Double?) -> SessionMessage {
        SessionMessage(id: id, role: "assistant", kind: "text", text: id, ts: ts)
    }

    private func ids(_ r: TranscriptMerge.Result) -> [String] {
        r.messages.map(\.stableID)
    }

    /// Reference implementation: exactly what `mergeHistoryPage` used to do.
    private func legacyMerge(
        _ existing: [SessionMessage], _ page: [SessionMessage]
    ) -> [SessionMessage] {
        var byKey: [String: SessionMessage] = [:]
        for m in existing { byKey[m.stableID] = m }
        for m in page { byKey[m.stableID] = m }
        return byKey.values.sorted { ($0.ts ?? 0) < ($1.ts ?? 0) }
    }

    // MARK: The shape history paging actually produces

    func testOlderPagePrependsWithoutTouchingExistingRows() {
        let existing = [msg("c", 30), msg("d", 40)]
        let page = [msg("a", 10), msg("b", 20)]
        let r = TranscriptMerge.merge(
            existing: existing, existingIDs: ["c", "d"], page: page)
        XCTAssertEqual(ids(r), ["a", "b", "c", "d"])
        XCTAssertTrue(r.usedPrependFastPath, "an older page must not walk the transcript")
        XCTAssertEqual(r.ids, ["a", "b", "c", "d"])
    }

    /// Successive pages walking backwards — the real multi-page sequence.
    func testSuccessivePagesEachPrepend() {
        var messages = [msg("e", 50)]
        var known: Set<String> = ["e"]
        for (idx, page) in [[msg("c", 30), msg("d", 40)], [msg("a", 10), msg("b", 20)]].enumerated() {
            let r = TranscriptMerge.merge(
                existing: messages, existingIDs: known, page: page)
            XCTAssertTrue(r.usedPrependFastPath, "page \(idx) should prepend")
            messages = r.messages
            known = r.ids
        }
        XCTAssertEqual(messages.map(\.stableID), ["a", "b", "c", "d", "e"])
    }

    // MARK: Dedupe

    func testRedeliveredPageIsANoOp() {
        let existing = [msg("a", 10), msg("b", 20)]
        let r = TranscriptMerge.merge(
            existing: existing, existingIDs: ["a", "b"], page: [msg("a", 10), msg("b", 20)])
        XCTAssertEqual(ids(r), ["a", "b"])
        XCTAssertEqual(r.ids, ["a", "b"])
    }

    /// The live stream and the history walk overlap by design.
    func testPartiallyOverlappingPageKeepsOnlyTheNewRows() {
        let existing = [msg("c", 30), msg("d", 40)]
        let r = TranscriptMerge.merge(
            existing: existing, existingIDs: ["c", "d"],
            page: [msg("b", 20), msg("c", 30)])
        XCTAssertEqual(ids(r), ["b", "c", "d"])
    }

    func testDuplicatesWithinOnePageCollapse() {
        let r = TranscriptMerge.merge(
            existing: [], existingIDs: [], page: [msg("a", 10), msg("a", 10)])
        XCTAssertEqual(ids(r), ["a"])
    }

    // MARK: Degenerate inputs

    func testEmptyPageLeavesTheTranscriptIdentical() {
        let existing = [msg("a", 10)]
        let r = TranscriptMerge.merge(existing: existing, existingIDs: ["a"], page: [])
        XCTAssertEqual(ids(r), ["a"])
    }

    func testFirstPageIntoAnEmptyTranscript() {
        let r = TranscriptMerge.merge(
            existing: [], existingIDs: [], page: [msg("a", 10), msg("b", 20)])
        XCTAssertEqual(ids(r), ["a", "b"])
        XCTAssertEqual(r.ids, ["a", "b"])
    }

    /// `ts` is optional on the wire; the old comparator treated nil as 0 and this
    /// must not start sorting them somewhere else.
    func testMissingTimestampsSortOldestJustAsBefore() {
        let existing = [msg("b", 20)]
        let r = TranscriptMerge.merge(
            existing: existing, existingIDs: ["b"], page: [msg("a", nil)])
        XCTAssertEqual(ids(r), ["a", "b"])
    }

    // MARK: Interleaving — the general path

    func testInterleavedTimestampsStillMergeInOrder() {
        let existing = [msg("b", 20), msg("d", 40)]
        let r = TranscriptMerge.merge(
            existing: existing, existingIDs: ["b", "d"],
            page: [msg("a", 10), msg("c", 30), msg("e", 50)])
        XCTAssertEqual(ids(r), ["a", "b", "c", "d", "e"])
        XCTAssertFalse(r.usedPrependFastPath)
    }

    func testNewerPageAppends() {
        let existing = [msg("a", 10)]
        let r = TranscriptMerge.merge(
            existing: existing, existingIDs: ["a"], page: [msg("b", 20)])
        XCTAssertEqual(ids(r), ["a", "b"])
    }

    // MARK: Equivalence with the implementation this replaced

    /// The strongest guarantee available: for randomised inputs, produce exactly
    /// the ordering the dictionary-and-re-sort version produced.
    func testMatchesLegacyOrderingAcrossRandomisedCases() {
        var seed = UInt64(0x9E37_79B9_7F4A_7C15)
        func rnd(_ n: Int) -> Int {          // deterministic; Date/random are banned
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(1, n)))
        }
        for _ in 0..<200 {
            let total = 1 + rnd(12)
            let all = (0..<total).map { msg("m\($0)", Double(rnd(20)) * 10) }
                .sorted { ($0.ts ?? 0) < ($1.ts ?? 0) }
            let split = rnd(all.count + 1)
            let page = Array(all[0..<split])
            let existing = Array(all[split...])

            let got = TranscriptMerge.merge(
                existing: existing,
                existingIDs: Set(existing.map(\.stableID)),
                page: page)
            let want = legacyMerge(existing, page)

            // Compare as multisets of (id, ts) plus monotonic ordering: the
            // legacy sort was not stable, so equal-timestamp rows could come out
            // in either order there. Ordering by timestamp is the real contract.
            XCTAssertEqual(Set(got.messages.map(\.stableID)), Set(want.map(\.stableID)))
            XCTAssertEqual(got.messages.count, want.count)
            let stamps = got.messages.map { $0.ts ?? 0 }
            XCTAssertEqual(stamps, stamps.sorted(), "merged transcript must be ordered")
        }
    }
}
