import XCTest
@testable import LFGCore

final class SessionSearchTests: XCTestCase {
    func testTermsLowercasesAndSplitsOnWhitespace() {
        XCTAssertEqual(SessionSearch.terms("  Fix   The Preamble "), ["fix", "the", "preamble"])
    }

    func testEmptyQueryHasNoTerms() {
        XCTAssertEqual(SessionSearch.terms("   "), [])
        XCTAssertEqual(SessionSearch.terms(""), [])
    }

    func testNoTermsMatchesEverything() {
        XCTAssertTrue(SessionSearch.matches(terms: [], fields: [nil, ""]))
    }

    func testMatchesCaseInsensitivelyAcrossFields() {
        let fields: [String?] = ["Fix the Preamble", "lfg", nil, "restart the pump"]
        XCTAssertTrue(SessionSearch.matches(terms: SessionSearch.terms("PREAMBLE"), fields: fields))
        XCTAssertTrue(SessionSearch.matches(terms: SessionSearch.terms("pump"), fields: fields))
        XCTAssertFalse(SessionSearch.matches(terms: SessionSearch.terms("marmalade"), fields: fields))
    }

    func testTermsAndAcrossDifferentFields() {
        // The reason this isn't a plain substring match: each term is allowed to
        // land in a different field.
        let fields: [String?] = ["fix the pump", "lfg", "the preamble is invisible"]
        XCTAssertTrue(SessionSearch.matches(terms: SessionSearch.terms("fix preamble"), fields: fields))
        XCTAssertFalse(SessionSearch.matches(terms: SessionSearch.terms("fix marmalade"), fields: fields))
    }

    func testAllEmptyFieldsMatchNothing() {
        XCTAssertFalse(SessionSearch.matches(terms: ["a"], fields: [nil, "", nil]))
    }

    func testMatchesAPathFragment() {
        let fields: [String?] = ["a title", "/Users/eugene/dev/lfg"]
        XCTAssertTrue(SessionSearch.matches(terms: SessionSearch.terms("dev/lfg"), fields: fields))
    }
}

// MARK: - Cross-host merge

extension SessionSearchTests {
    private func closed(_ id: String, title: String, project: String = "p") -> ResumableSession {
        ResumableSession(sessionId: id, title: title, project: project, mtime: 1)
    }

    func testMergesMatchesFromEveryHost() {
        // Search fans out to all hosts; a match that only exists on the second
        // machine must still reach the list.
        let hostA = [closed("a", title: "preamble on the pro")]
        let hostB = [closed("b", title: "preamble on the air")]

        let out = SessionSearch.reconcile(perHost: [hostA, hostB],
                                          terms: SessionSearch.terms("preamble"),
                                          liveIds: [])

        XCTAssertEqual(out.map(\.sessionId), ["a", "b"])
    }

    func testDedupesTheSameSyncedTranscriptSeenByTwoHosts() {
        // ~/.claude/projects is synced, so both hosts enumerate the same file.
        let row = closed("shared", title: "preamble everywhere")

        let out = SessionSearch.reconcile(perHost: [[row], [row]],
                                          terms: SessionSearch.terms("preamble"),
                                          liveIds: [])

        XCTAssertEqual(out.map(\.sessionId), ["shared"])
    }

    func testDropsASessionLiveOnAnyHost() {
        let out = SessionSearch.reconcile(
            perHost: [[closed("live", title: "preamble running"),
                       closed("dead", title: "preamble finished")]],
            terms: SessionSearch.terms("preamble"),
            liveIds: ["live"])

        XCTAssertEqual(out.map(\.sessionId), ["dead"])
    }

    func testRejectsAnUnfilteredPageFromAHostThatIgnoredTheQuery() {
        // The half-deployed-fleet case: a host predating `?q=` answers with its
        // ordinary newest-first page. Those rows never matched, and merging them
        // would show the user 60 unrelated sessions as though they had.
        let upToDate = [closed("match", title: "the preamble investigation")]
        let staleHost = (0..<60).map { closed("stale-\($0)", title: "unrelated session \($0)") }

        let out = SessionSearch.reconcile(perHost: [upToDate, staleHost],
                                          terms: SessionSearch.terms("preamble"),
                                          liveIds: [])

        XCTAssertEqual(out.map(\.sessionId), ["match"])
    }

    func testAStaleHostStillContributesItsGenuineMatches() {
        // Degrade to "contributes less", not "contributes nothing": a matching
        // row that happens to be inside the stale host's page is still valid.
        let staleHost = [closed("noise", title: "unrelated"),
                         closed("real", title: "preamble by luck")]

        let out = SessionSearch.reconcile(perHost: [staleHost],
                                          terms: SessionSearch.terms("preamble"),
                                          liveIds: [])

        XCTAssertEqual(out.map(\.sessionId), ["real"])
    }
}
