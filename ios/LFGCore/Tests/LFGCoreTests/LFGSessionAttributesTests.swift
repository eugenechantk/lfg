import Foundation
import XCTest
@testable import LFGCore

final class LFGSessionAttributesTests: XCTestCase {
    func testAttributesDecodeLenientlyWhenSessionIdIsAbsent() throws {
        let attributes = try JSONDecoder().decode(LFGSessionAttributes.self, from: Data("{}".utf8))

        XCTAssertEqual(attributes.sessionId, "")
    }

    func testContentStateDecodesAbsentOptionalFieldsWithDefaults() throws {
        let state = try JSONDecoder().decode(LFGSessionAttributes.ContentState.self, from: Data("{}".utf8))

        XCTAssertEqual(state.state, "working")
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.dir, "")
        XCTAssertEqual(state.host, "")
        XCTAssertEqual(state.since, 0)
        XCTAssertEqual(state.updatedAt, 0)
        XCTAssertNil(state.subtitle)
        XCTAssertNil(state.added)
        XCTAssertNil(state.removed)
        XCTAssertNil(state.files)
    }

    func testUnknownStateStringsMapToWorkingForPresentation() throws {
        let state = try JSONDecoder().decode(
            LFGSessionAttributes.ContentState.self,
            from: Data(#"{"state":"paused"}"#.utf8)
        )

        XCTAssertEqual(state.state, "paused")
        XCTAssertEqual(LFGSessionActivityPresentation.normalizedState(state.state), .working)
    }

    func testFinishedStateMapsForPresentation() throws {
        let state = try JSONDecoder().decode(
            LFGSessionAttributes.ContentState.self,
            from: Data(#"{"state":"finished"}"#.utf8)
        )

        XCTAssertEqual(LFGSessionActivityPresentation.normalizedState(state.state), .finished)
    }

    func testCompactElapsedFormatting() {
        let date = Date(timeIntervalSince1970: 3_900)

        XCTAssertEqual(LFGSessionActivityPresentation.compactElapsed(since: 0, at: date), "now")
        XCTAssertEqual(LFGSessionActivityPresentation.compactElapsed(since: 3_850, at: date), "now")
        XCTAssertEqual(LFGSessionActivityPresentation.compactElapsed(since: 3_840, at: date), "1m")
        XCTAssertEqual(LFGSessionActivityPresentation.compactElapsed(since: 3_000, at: date), "15m")
        XCTAssertEqual(LFGSessionActivityPresentation.compactElapsed(since: 300, at: date), "1h")
        XCTAssertEqual(LFGSessionActivityPresentation.compactElapsed(since: 240, at: date), "1h 1m")
    }

    func testDiffSummaryRequiresAllFields() {
        XCTAssertNil(LFGSessionActivityPresentation.diffSummary(added: 142, removed: nil, files: 6))
        XCTAssertEqual(
            LFGSessionActivityPresentation.diffSummary(added: 142, removed: 38, files: 6),
            "+142 −38 · 6 Files"
        )
    }
}
