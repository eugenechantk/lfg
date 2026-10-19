import Testing
@testable import LFGCore

@Suite("Directory-first session search order")
struct SessionSearchOrderTests {
    @Test func directoriesLeadTitlesThenOtherMatches() {
        let terms = SessionSearch.terms("  AMBER   notebook ")
        #expect(SessionSearchOrder.priority(terms: terms, cwd: "/work/amber-notebook", project: nil, title: "Other") == 3)
        #expect(SessionSearchOrder.priority(terms: terms, cwd: nil, project: "amber-notebook", title: "Other") == 3)
        #expect(SessionSearchOrder.priority(terms: terms, cwd: "/work", project: nil, title: "Notebook and amber") == 2)
        #expect(SessionSearchOrder.priority(terms: terms, cwd: "/work/amber", project: nil, title: "Notebook") == 1)
        #expect(SessionSearchOrder.priority(terms: [], cwd: "/work", project: nil, title: "Other") == 0)
    }

    @Test func recencyWinsWithinEachMatchGroup() {
        let terms = ["amber"]
        let rows = [
            Session(sessionId: "directory-old", title: "Amber", cwd: "/work/amber", lastActivityAt: 100),
            Session(sessionId: "title-old", title: "Amber", cwd: "/work/other", lastActivityAt: 100),
            Session(sessionId: "directory-new", title: "Other", cwd: "/work/amber", lastActivityAt: 1000),
            Session(sessionId: "title-new", title: "Discuss amber", cwd: "/work/other", lastActivityAt: 2000),
            Session(sessionId: "prose-new", title: "Other", cwd: "/work/other", lastActivityAt: 3000),
        ]
        #expect(SessionSearch.ordered(rows, terms: terms).compactMap(\.sessionId) == [
            "directory-new", "directory-old", "title-new", "title-old", "prose-new",
        ])
    }

    @Test func reconciliationIgnoresLegacyScoresAndSortsAcrossHosts() {
        let rows = SessionSearch.reconcile(perHost: [[
            ResumableSession(sessionId: "title-old", title: "Amber", cwd: "/work/other", mtime: 100, rank: 1200),
            ResumableSession(sessionId: "directory-old", title: "Amber", cwd: "/work/amber", mtime: 100, rank: 1600),
        ], [
            ResumableSession(sessionId: "title-new", title: "Discuss amber", cwd: "/work/other", mtime: 2000, rank: 420),
            ResumableSession(sessionId: "directory-new", title: "Other", cwd: "/work/amber", mtime: 1000, rank: 300),
        ]], terms: ["amber"], liveIds: [])
        #expect(rows.map(\.sessionId) == ["directory-new", "directory-old", "title-new", "title-old"])
    }

    @Test func missingDatesSortLastAndEqualDatesUseStableIds() {
        #expect(SessionSearchOrder.precedes(priority: 3, activity: 100, id: "a", otherPriority: 3, otherActivity: nil, otherID: "b"))
        #expect(SessionSearchOrder.precedes(priority: 2, activity: 100, id: "a", otherPriority: 2, otherActivity: 100, otherID: "b"))
        #expect(!SessionSearchOrder.precedes(priority: 2, activity: 100, id: "a", otherPriority: 3, otherActivity: 1, otherID: "b"))
    }
}
