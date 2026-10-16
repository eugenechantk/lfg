import Foundation
import Testing
@testable import LFGCore

@Suite("S2 session list: sections")
struct SessionListSectionTests {
    @Test("paused folds into Needs input and restarting into Working")
    func folding() {
        #expect(SessionListSection(.needsInput) == .needsInput)
        #expect(SessionListSection(.paused) == .needsInput)
        #expect(SessionListSection(.restarting) == .working)
        #expect(SessionListSection(.working) == .working)
        #expect(SessionListSection(.unread) == .unread)
        #expect(SessionListSection(.idle) == .idle)
        #expect(SessionListSection(.closed) == .closed)
    }

    @Test("titles and order follow the design")
    func titlesAndOrder() {
        #expect(SessionListSection.allCases.map(\.title)
                == ["Needs input", "Working", "Unread", "Idle", "Closed"])
    }

    @Test("Idle and Closed start collapsed")
    func defaultsCollapsed() {
        #expect(SessionListSection.allCases.filter(\.collapsedByDefault) == [.idle, .closed])
    }

    @Test("collapse state round-trips and keeps user choices over defaults")
    func collapseState() {
        var state = SessionListCollapse(stored: nil)
        #expect(state.isCollapsed(.idle))
        #expect(!state.isCollapsed(.needsInput))
        state.toggle(.idle)
        state.toggle(.working)
        let restored = SessionListCollapse(stored: state.stored)
        #expect(!restored.isCollapsed(.idle))
        #expect(restored.isCollapsed(.working))
        #expect(restored.isCollapsed(.closed))
    }

    @Test("a corrupt stored value falls back to the defaults")
    func corruptStored() {
        let state = SessionListCollapse(stored: "not json")
        #expect(state.isCollapsed(.closed))
        #expect(!state.isCollapsed(.unread))
    }
}

@Suite("S2 session list: second line")
struct SessionRowLineTests {
    private let now: Double = 1_760_500_000_000 // ms

    @Test("a question reads 'Asks: …' in the attention tone, on one line")
    func question() {
        let line = SessionRowLine.resolve(.needsInput(question: "Upload build 205\n now?", signInSite: nil), nowMs: now)
        #expect(line == SessionRowLine(icon: .question, text: "Asks: Upload build 205 now?", tone: .attention))
    }

    @Test("a sign-in request names the site")
    func signIn() {
        let line = SessionRowLine.resolve(.needsInput(question: "Sign in", signInSite: "search.google.com"), nowMs: now)
        #expect(line == SessionRowLine(icon: .signIn, text: "Sign in to search.google.com", tone: .attention))
    }

    @Test("a prompt with no text still says it needs input")
    func emptyQuestion() {
        let line = SessionRowLine.resolve(.needsInput(question: "  ", signInSite: nil), nowMs: now)
        #expect(line == SessionRowLine(icon: .question, text: "Needs your input", tone: .attention))
    }

    @Test("paused names the reason")
    func paused() {
        #expect(SessionRowLine.resolve(.paused(reason: "out_of_credits"), nowMs: now)
                == SessionRowLine(icon: .none, text: "Paused · out of credits", tone: .attention))
        #expect(SessionRowLine.resolve(.paused(reason: nil), nowMs: now)
                == SessionRowLine(icon: .none, text: "Paused", tone: .attention))
    }

    @Test("working shows the running time and no step text")
    func working() {
        let line = SessionRowLine.resolve(.working(runningSinceMs: now - 3 * 60_000), nowMs: now)
        #expect(line == SessionRowLine(icon: .liveDot, text: "Working · 3m", tone: .live))
        #expect(SessionRowLine.resolve(.working(runningSinceMs: nil), nowMs: now)
                == SessionRowLine(icon: .liveDot, text: "Working", tone: .live))
    }

    @Test("restarting reads as on its way back")
    func restarting() {
        #expect(SessionRowLine.resolve(.restarting, nowMs: now)
                == SessionRowLine(icon: .liveDot, text: "Restarting…", tone: .live))
    }

    @Test("unread says New reply, never the reply itself")
    func unread() {
        #expect(SessionRowLine.resolve(.unread, nowMs: now)
                == SessionRowLine(icon: .none, text: "New reply", tone: .primary))
    }

    @Test("idle leaves the status slot empty")
    func idle() {
        #expect(SessionRowLine.resolve(.idle, nowMs: now)
                == SessionRowLine(icon: .none, text: "", tone: .secondary))
    }

    @Test("closed leaves the status slot empty regardless of its age")
    func closed() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let nowDate = Date(timeIntervalSince1970: now / 1000)
        func ms(daysAgo: Int) -> Double {
            cal.date(byAdding: .day, value: -daysAgo, to: nowDate)!.timeIntervalSince1970 * 1000
        }
        func text(_ daysAgo: Int) -> String {
            SessionRowLine.resolve(.closed(lastActivityMs: ms(daysAgo: daysAgo)), nowMs: now, calendar: cal).text
        }
        #expect(text(0).isEmpty)
        #expect(text(1).isEmpty)
        #expect(text(3).isEmpty)
        #expect(SessionRowLine.resolve(.closed(lastActivityMs: nil), nowMs: now).text
                == "")
        #expect(SessionRowLine.resolve(.closed(lastActivityMs: ms(daysAgo: 1)), nowMs: now, calendar: cal).tone == .secondary)
    }
}

@Suite("S2 session list: meta line")
struct SessionRowMetaTests {
    @Test("project · model · subagents · time, skipping what is missing")
    func full() {
        #expect(SessionRowMeta.text(project: "lfg", model: "opus", subagents: 2, backgroundProcesses: 0, time: "3m")
                == "lfg · opus · 2 subagents · 3m")
        #expect(SessionRowMeta.text(project: "lfg", model: nil, subagents: 1, backgroundProcesses: 0, time: nil)
                == "lfg · 1 subagent")
        #expect(SessionRowMeta.text(project: "inbox", model: "", subagents: 0, backgroundProcesses: 2, time: "5h")
                == "inbox · 2 background · 5h")
    }

    @Test("the project falls back to the folder name, then a placeholder")
    func project() {
        #expect(SessionRowMeta.projectLabel(cwd: "/Users/e/dev/lfg", project: "x") == "lfg")
        #expect(SessionRowMeta.projectLabel(cwd: nil, project: "inbox") == "inbox")
        #expect(SessionRowMeta.projectLabel(cwd: "", project: nil) == "No directory")
    }
}

@Suite("Task origin decoding")
struct TaskOriginDecodingTests {
    @Test("live and closed rows carry the task that started them")
    func decodes() throws {
        let live = try JSONDecoder().decode(Session.self, from: Data(#"""
        {"sessionId":"s1","title":"Daily repo review","task":{"id":"t1","name":"Daily repo review"}}
        """#.utf8))
        #expect(live.task == TaskOrigin(id: "t1", name: "Daily repo review"))

        let closed = try JSONDecoder().decode(ResumableSession.self, from: Data(#"""
        {"sessionId":"s2","task":{"id":"t2","name":"Readwise sync"}}
        """#.utf8))
        #expect(closed.task == TaskOrigin(id: "t2", name: "Readwise sync"))
    }

    @Test("a missing or malformed task never fails the row")
    func tolerant() throws {
        let none = try JSONDecoder().decode(Session.self, from: Data(#"{"sessionId":"s1"}"#.utf8))
        #expect(none.task == nil)
        let bad = try JSONDecoder().decode(Session.self, from: Data(#"{"sessionId":"s1","task":"oops"}"#.utf8))
        #expect(bad.task == nil)
    }
}
