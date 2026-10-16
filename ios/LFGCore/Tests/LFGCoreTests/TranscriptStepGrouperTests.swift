import Foundation
import Testing
@testable import LFGCore

private func use(_ id: String, _ name: String?, target: String?, text: String, ts: Double = 0, useId: String? = nil) -> SessionMessage {
    SessionMessage(id: id, role: "assistant", kind: "tool_use", text: text, ts: ts,
                   toolUseId: useId, tool: name.map { ToolCallInfo(name: $0, target: target) })
}

private func result(_ id: String, _ text: String, ts: Double = 0, useId: String? = nil, isError: Bool? = nil) -> SessionMessage {
    SessionMessage(id: id, role: "user", kind: "tool_result", text: text, ts: ts, toolUseId: useId, isError: isError)
}

private func prose(_ id: String, _ text: String) -> SessionMessage {
    SessionMessage(id: id, role: "assistant", kind: "text", text: text)
}

@Suite("Transcript step grouping")
struct TranscriptStepGrouperTests {
    @Test("thinking rows are omitted while visible message indices stay stable")
    func thinkingRowsAreHidden() {
        let messages = [
            SessionMessage(id: "empty", role: "assistant", kind: "thinking", text: ""),
            prose("before", "Visible before"),
            SessionMessage(id: "detail", role: "assistant", kind: "thinking", text: "Reasoning detail"),
            SessionMessage(id: "compacting", role: "system", kind: "thinking", text: "Compacting conversation"),
            prose("after", "Visible after"),
        ]
        #expect(TranscriptStepGrouper.items(for: messages) == [.message(1), .message(4)])
        #expect(messages.count == 5)
    }

    @Test("hidden thinking does not lose a tool result arriving after its call", arguments: [true, false])
    func thinkingBetweenCallAndResult(hasIDs: Bool) {
        let messages = [
            use("call", "Read", target: "a.swift", text: "Read", useId: hasIDs ? "read-a" : nil),
            SessionMessage(id: "thinking", role: "assistant", kind: "thinking", text: ""),
            result("output", "File content", useId: hasIDs ? "read-a" : nil),
            prose("answer", "Finished"),
        ]
        let items = TranscriptStepGrouper.items(for: messages)
        #expect(items.count == 2)
        guard case .steps(let group) = items.first else { Issue.record("missing tool step"); return }
        #expect(group.calls.count == 1)
        #expect(group.calls[0].result == "File content")
        #expect(items.last == .message(3))
    }

    @Test("consecutive tool rows fold into one step; prose stays a message")
    func folding() {
        let messages = [
            prose("p1", "I'll trace fork first."),
            use("u1", "Bash", target: "rg -n forkSession", text: "Bash: …", useId: "t1"),
            result("r1", "6 lines", useId: "t1"),
            use("u2", "Read", target: "/repo/ios/LFG/SessionStore.swift", text: "Read: …", useId: "t2"),
            result("r2", "file body", useId: "t2"),
            prose("p2", "Small forks wait…"),
        ]
        let items = TranscriptStepGrouper.items(for: messages)
        #expect(items.count == 3)
        guard case .message(0) = items[0], case .steps(let g) = items[1], case .message(5) = items[2] else {
            Issue.record("unexpected items \(items)"); return
        }
        #expect(g.indices == 1...4)
        #expect(g.calls.count == 2)
        #expect(g.summary == "Ran 1 command, read 1 file")
        #expect(g.id == "u1")
    }

    @Test("a step ends after edits; calls before an edit stay with it")
    func editsSplit() {
        let messages = [
            use("u1", "Edit", target: "/repo/a.swift", text: "Edit: …", useId: "t1"),
            result("r1", "ok", useId: "t1"),
            use("u2", "Edit", target: "/repo/b.swift", text: "Edit: …", useId: "t2"),
            result("r2", "ok", useId: "t2"),
            use("u3", "Bash", target: "bun test src/sessions.test.ts", text: "Bash: …", useId: "t3"),
            result("r3", "12 pass", useId: "t3"),
            use("u4", "Read", target: "/repo/c.swift", text: "Read: …", useId: "t4"),
            result("r4", "body", useId: "t4"),
            use("u5", "Write", target: "/repo/d.swift", text: "Write: …", useId: "t5"),
            result("r5", "ok", useId: "t5"),
        ]
        let groups = TranscriptStepGrouper.items(for: messages).compactMap { item -> ToolStepGroup? in
            if case .steps(let g) = item { return g } else { return nil }
        }
        #expect(groups.map(\.indices) == [0...3, 4...9])
        #expect(groups.map(\.summary) == ["Edited 2 files", "Ran 1 command, read 1 file, edited 1 file"])
    }

    @Test("parallel calls whose results are still out stay in one step")
    func parallelMixedStaysTogether() {
        let messages = [
            use("u1", "Read", target: "/repo/a.swift", text: "Read: …", useId: "t1"),
            use("u2", "Edit", target: "/repo/b.swift", text: "Edit: …", useId: "t2"),
            result("r1", "body", useId: "t1"),
            result("r2", "ok", useId: "t2"),
        ]
        let items = TranscriptStepGrouper.items(for: messages)
        #expect(items.count == 1)
        guard case .steps(let g) = items.first else { Issue.record("expected one step"); return }
        #expect(g.calls.map(\.result) == ["body", "ok"])
    }

    @Test("a Read of part of a file names its line range")
    func readRange() {
        let messages = [
            use("u1", "Read", target: "/repo/a.swift", text: "Read: {\n  \"file_path\": \"/repo/a.swift\",\n  \"offset\": 1600,\n  \"limit\": 61\n}", useId: "t1"),
            use("u2", "Read", target: "/repo/b.swift", text: "Read: {\n  \"file_path\": \"/repo/b.swift\"\n}", useId: "t2"),
        ]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: messages).first else { Issue.record("no step"); return }
        #expect(g.calls.map(\.inputDetail) == ["lines 1600–1660", nil])
    }

    @Test("summaries list the most frequent kind first")
    func summaryRanking() {
        let messages = [
            use("a", "Bash", target: "rg fork", text: ""), use("b", "Read", target: "a.swift", text: ""),
            use("c", "Read", target: "b.swift", text: ""),
        ]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: messages).first else { Issue.record("no group"); return }
        #expect(g.summary == "Read 2 files, ran 1 command")
    }

    @Test("summaries count each kind; ties keep the order they first appear")
    func summaries() {
        let messages = [
            use("a", "Read", target: "a.swift", text: ""), use("b", "Read", target: "b.swift", text: ""),
            use("c", "Bash", target: "bun test", text: ""), use("d", "Read", target: "c.swift", text: ""),
            use("e", "Bash", target: "git status", text: ""), use("f", "Edit", target: "a.swift", text: ""),
            use("g", "Grep", target: "fork", text: ""), use("h", "WebFetch", target: "https://x.dev", text: ""),
            use("i", "Agent", target: "Audit tests", text: ""), use("j", "TodoWrite", target: nil, text: ""),
        ]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: messages).first else { Issue.record("no group"); return }
        #expect(g.summary == "Read 3 files, ran 2 commands, edited 1 file, searched 1 pattern, fetched 1 page, started 1 agent, used 1 tool")
    }

    @Test("a single call reads as verb + target, and keeps its result")
    func singleCall() {
        let messages = [
            use("u1", "Bash", target: "bun test src/sessions.test.ts", text: "", ts: 1_000, useId: "t1"),
            result("r1", "42 pass", ts: 2_800, useId: "t1"),
        ]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: messages).first else { Issue.record("no group"); return }
        #expect(g.isSingleCall)
        #expect(g.summary == "Ran bun test src/sessions.test.ts")
        let call = g.calls[0]
        #expect(call.verb == "Ran")
        #expect(call.target == "bun test src/sessions.test.ts")
        #expect(call.result == "42 pass")
        #expect(call.durationMs == 1_800)
        #expect(call.kind == .command)
    }

    @Test("results pair by id, else with the nearest unanswered call before them")
    func pairing() {
        let byId = [
            use("u1", "Read", target: "a", text: "", useId: "t1"),
            use("u2", "Read", target: "b", text: "", useId: "t2"),
            result("r2", "B", useId: "t2"),
            result("r1", "A", useId: "t1"),
        ]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: byId).first else { Issue.record("no group"); return }
        #expect(g.calls.map(\.result) == ["A", "B"])

        let legacy = [
            use("u1", nil, target: nil, text: "Bash: {\"command\":\"ls\"}"),
            result("r1", "a b c"),
            use("u2", nil, target: nil, text: "Read: {\"file_path\":\"/x.swift\"}"),
            result("r2", "body"),
        ]
        guard case .steps(let l) = TranscriptStepGrouper.items(for: legacy).first else { Issue.record("no group"); return }
        #expect(l.calls.map(\.result) == ["a b c", "body"])
        #expect(l.calls.map(\.kind) == [.command, .read])
        #expect(l.calls[0].target == "ls")
        #expect(l.calls[1].target == "/x.swift")
    }

    @Test("a failed result marks its call")
    func failure() {
        let messages = [use("u1", "Bash", target: "make", text: "", useId: "t1"), result("r1", "Exit code 2", useId: "t1", isError: true)]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: messages).first else { Issue.record("no group"); return }
        #expect(g.calls[0].isError)
    }

    @Test("Codex rows classify by their own labels")
    func codexLabels() {
        let messages = [
            use("c1", nil, target: nil, text: "Ran\nbun test src/x.ts", useId: "call_1"),
            result("c2", "ok", useId: "call_1"),
            use("c3", nil, target: nil, text: "Explored\nRead SessionStore.swift\nSearch fork in ios"),
            use("c4", nil, target: nil, text: "Edited ios/LFG/RootView.swift +12 -3"),
            use("c5", nil, target: nil, text: "Searching the web"),
        ]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: messages).first else { Issue.record("no group"); return }
        #expect(g.calls.map(\.kind) == [.command, .explore, .edit, .web])
        #expect(g.calls[0].target == "bun test src/x.ts")
        #expect(g.calls[1].target == "Read SessionStore.swift")
        #expect(g.calls[2].target == "ios/LFG/RootView.swift +12 -3")
        #expect(g.summary == "Ran 1 command, explored 1 time, edited 1 file, fetched 1 page")
    }

    @Test("an agent launch row is a call, labelled from its description")
    func agentLaunch() {
        let messages = [use("a1", nil, target: nil, text: "Started agent · Audit the fork tests")]
        guard case .steps(let g) = TranscriptStepGrouper.items(for: messages).first else { Issue.record("no group"); return }
        #expect(g.calls[0].kind == .agent)
        #expect(g.summary == "Started agent · Audit the fork tests")
    }

    @Test("an orphan result with no call still renders, as its own step")
    func orphanResult() {
        let messages = [prose("p", "x"), result("r", "stray output")]
        let items = TranscriptStepGrouper.items(for: messages)
        guard items.count == 2, case .steps(let g) = items[1] else { Issue.record("unexpected \(items)"); return }
        #expect(g.calls.count == 1)
        #expect(g.calls[0].result == "stray output")
    }

    @Test("a result split from its call by an absorbed message joins the call's step")
    func resultAfterAbsorbedMessage() {
        // Live transcript shape (Claude Code 2.1.280): a message sent mid-tool is
        // absorbed at the tool boundary, so its synthesised user turn lands
        // between the Bash call and that call's result.
        let messages = [
            use("u1", "Bash", target: "python3 loop.py", text: "", ts: 1_000, useId: "t1"),
            SessionMessage(id: "queued:2", role: "user", kind: "text", text: "Reply with ok too.", ts: 41_000),
            result("r1", "0\n1\n2", ts: 41_100, useId: "t1"),
            prose("p", "ok"),
        ]
        let items = TranscriptStepGrouper.items(for: messages)
        guard items.count == 3, case .steps(let g) = items[0], case .message(1) = items[1], case .message(3) = items[2] else {
            Issue.record("unexpected \(items)"); return
        }
        #expect(g.calls.count == 1)
        #expect(g.calls[0].result == "0\n1\n2")
        #expect(g.calls[0].durationMs == 40_100)
        #expect(g.summary == "Ran python3 loop.py")
    }

    @Test("an answered question reads as Asked · the question, not a bare Used")
    func askedQuestion() {
        // The host's row (2026-10-16): `tool` names AskUserQuestion with no
        // target; the question is only inside the call's JSON.
        let call = SessionMessage(
            id: "q1", role: "assistant", kind: "tool_use",
            text: "AskUserQuestion: {\n  \"questions\": [\n    {\n      \"question\": \"Which colour would you like to use?\",\n      \"header\": \"Colour\"\n    }\n  ]\n}",
            toolUseId: "t1", tool: ToolCallInfo(name: "AskUserQuestion", target: nil))
        let answer = result("r1", "The user answered: \"Which colour would you like to use?\"=\"Teal\".", useId: "t1")
        guard case .steps(let g) = TranscriptStepGrouper.items(for: [call, answer]).first else { Issue.record("no group"); return }
        #expect(g.calls[0].kind == .ask)
        #expect(g.summary == "Asked · Which colour would you like to use?")
        let two = TranscriptStepGrouper.items(for: [call, answer,
            use("u2", "Bash", target: "ls", text: "", useId: "t2"), result("r2", "a", useId: "t2")])
        guard case .steps(let g2) = two.first else { Issue.record("no group"); return }
        #expect(g2.summary == "Asked 1 question, ran 1 command")
    }

    @Test("result previews: commands show the tail, everything else the head")
    func previews() {
        let text = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let tail = ToolCallPreview.lines(of: text, kind: .command, limit: 3)
        #expect(tail.lines == ["line 18", "line 19", "line 20"])
        #expect(tail.total == 20)
        #expect(tail.fromEnd)
        let head = ToolCallPreview.lines(of: text, kind: .read, limit: 3)
        #expect(head.lines == ["line 1", "line 2", "line 3"])
        #expect(!head.fromEnd)
        let short = ToolCallPreview.lines(of: "a\nb\n", kind: .command, limit: 8)
        #expect(short.lines == ["a", "b"])
        #expect(short.total == 2)
    }
}
