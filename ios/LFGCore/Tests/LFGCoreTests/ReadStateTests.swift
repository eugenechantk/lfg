import XCTest
@testable import LFGCore

final class ReadStateTests: XCTestCase {

    // MARK: Identity predicate (live read-state)

    func testNeverSeenButHasMessageIsUnread() {
        XCTAssertTrue(ReadState.isUnread(lastMessageID: "abc", lastSeenMessageID: nil))
    }

    func testNewMessageAfterSeenIsUnread() {
        XCTAssertTrue(ReadState.isUnread(lastMessageID: "def", lastSeenMessageID: "abc"))
    }

    func testSeenTheNewestMessageIsRead() {
        XCTAssertFalse(ReadState.isUnread(lastMessageID: "abc", lastSeenMessageID: "abc"))
    }

    func testNoMessagesIsNeverUnread() {
        XCTAssertFalse(ReadState.isUnread(lastMessageID: nil, lastSeenMessageID: nil))
        XCTAssertFalse(ReadState.isUnread(lastMessageID: nil, lastSeenMessageID: "abc"))
        XCTAssertFalse(ReadState.isUnread(lastMessageID: "", lastSeenMessageID: nil))
    }

    /// The regression this predicate exists for: a long-idle session whose
    /// transcript file is touched (sync daemon rewriting mtime, harness appending a
    /// metadata line) produces no new *message*, so it must stay read. Under the old
    /// mtime-based rule this flipped back to unread on every touch.
    func testTouchedTranscriptWithNoNewMessageStaysRead() {
        let seen = "69be20cc-d9db-4223-884d-7e0fdbda1fa0"
        // Same message id, hours later, file mtime long since moved on.
        XCTAssertFalse(ReadState.isUnread(lastMessageID: seen, lastSeenMessageID: seen))
    }

    /// Read-state must not depend on either clock: a host whose message timestamps
    /// run behind (or ahead of) the device still resolves correctly by id.
    func testIdentityIsImmuneToClockSkew() {
        XCTAssertFalse(ReadState.isUnread(lastMessageID: "same", lastSeenMessageID: "same"))
        XCTAssertTrue(ReadState.isUnread(lastMessageID: "newer", lastSeenMessageID: "older"))
    }

    // MARK: Migration predicate (one-shot, message timestamps only)

    func testMigrationNeverOpenedButHasMessageIsUnread() {
        XCTAssertTrue(ReadState.isUnread(lastMessageAt: 1000, lastOpenedAt: nil))
    }

    func testMigrationMessageAfterOpenIsUnread() {
        XCTAssertTrue(ReadState.isUnread(lastMessageAt: 2000, lastOpenedAt: 1000))
    }

    func testMigrationOpenedAfterMessageIsRead() {
        XCTAssertFalse(ReadState.isUnread(lastMessageAt: 1000, lastOpenedAt: 2000))
    }

    func testMigrationOpenedExactlyAtMessageIsRead() {
        XCTAssertFalse(ReadState.isUnread(lastMessageAt: 1000, lastOpenedAt: 1000))
    }

    func testMigrationNoMessageIsNeverUnread() {
        XCTAssertFalse(ReadState.isUnread(lastMessageAt: nil, lastOpenedAt: nil))
        XCTAssertFalse(ReadState.isUnread(lastMessageAt: 0, lastOpenedAt: nil))
    }

    // MARK: Wire decoding

    /// `last` must decode off `/api/sessions`, and a malformed preview must not take
    /// the whole session down with it (lenient-decoding convention).
    func testSessionDecodesLastMessage() throws {
        let json = """
        {"sessionId":"s1","title":"t","agent":"claude",
         "last":{"id":"uuid-1","role":"assistant","kind":"text","text":"hi","ts":1000}}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(Session.self, from: json)
        XCTAssertEqual(s.last?.id, "uuid-1")
        XCTAssertEqual(s.last?.ts, 1000)
    }

    func testSessionDecodesWithoutLastMessage() throws {
        let json = #"{"sessionId":"s1","title":"t","agent":"claude"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Session.self, from: json)
        XCTAssertNil(s.last)
    }

    func testMalformedLastDoesNotFailSessionDecode() throws {
        let json = #"{"sessionId":"s1","title":"t","agent":"claude","last":"not-an-object"}"#
            .data(using: .utf8)!
        let s = try JSONDecoder().decode(Session.self, from: json)
        XCTAssertEqual(s.sessionId, "s1")
        XCTAssertNil(s.last)
    }
}
