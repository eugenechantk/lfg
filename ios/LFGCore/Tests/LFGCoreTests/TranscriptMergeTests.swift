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
