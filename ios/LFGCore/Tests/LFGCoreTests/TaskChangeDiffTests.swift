import Foundation
import Testing
@testable import LFGCore

@Suite struct TaskChangeDiffTests {
    private func task(_ fields: String) throws -> ScheduledTaskRecord {
        let json = #"{"id":"t","cwd":"/tmp","enabled":true,\#(fields)}"#
        return try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
    }

    @Test func listsEachChangedFieldOldToNew() throws {
        let before = try task(#""name":"Daily repo review","prompt":"Review","agent":"claude","model":"opus","schedule":{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 9 * * 1-5"}"#)
        let after = try task(#""name":"Daily repo review","prompt":"Review","agent":"codex","model":"gpt-6-astra","schedule":{"kind":"cron","timezone":"Asia/Hong_Kong","expression":"0 8 * * 2-5"}"#)
        let changes = TaskChangeDiff.changes(before: before, after: after, timeZone: TimeZone(identifier: "Asia/Hong_Kong")!, locale: Locale(identifier: "en_US"))
        #expect(changes.map(\.field) == ["Schedule", "Agent", "Model"])
        #expect(changes[0].from.replacingOccurrences(of: "\u{202F}", with: " ") == "Every weekday at 9:00 AM")
        #expect(changes[0].to.replacingOccurrences(of: "\u{202F}", with: " ") == "Tue–Fri at 8:00 AM")
        #expect(changes[1] == TaskChange(field: "Agent", from: "Claude Code", to: "Codex"))
        #expect(changes[2] == TaskChange(field: "Model", from: "Opus", to: "GPT-6 Astra"))
    }

    /// A closed edit chat comes back from `/api/sessions/resumable` tagged, and the tag survives the cache.
    @Test func closedEditChatsKeepTheirTag() throws {
        let json = #"{"sessionId":"chat-1","title":"Change task","agent":"claude","purpose":"task-edit"}"#
        let r = try JSONDecoder().decode(ResumableSession.self, from: Data(json.utf8))
        #expect(r.purpose == "task-edit")
        let round = try JSONDecoder().decode(ResumableSession.self, from: JSONEncoder().encode(r))
        #expect(round.purpose == "task-edit")
        let plain = try JSONDecoder().decode(ResumableSession.self, from: Data(#"{"sessionId":"w","title":"Work"}"#.utf8))
        #expect(plain.purpose == nil)
    }

    @Test func modelNamesReadAsPeopleWriteThem() {
        #expect(ModelName.display("gpt-6-astra") == "GPT-6 Astra")
        #expect(ModelName.display("gpt-6.1-sol") == "GPT-6.1 Sol")
        #expect(ModelName.display("claude-opus-5-5") == "Claude Opus 5.5")
        #expect(ModelName.display("opus") == "Opus")
        #expect(ModelName.display("Claude default") == "Claude default")
    }

    @Test func noChangesWhenOnlyRunStateMoved() throws {
        let before = try task(#""name":"A","prompt":"p","agent":"claude","schedule":{"kind":"cron","timezone":"UTC","expression":"0 9 * * *"},"nextRunAt":1"#)
        let after = try task(#""name":"A","prompt":"p","agent":"claude","schedule":{"kind":"cron","timezone":"UTC","expression":"0 9 * * *"},"nextRunAt":2,"runCount":4"#)
        #expect(TaskChangeDiff.changes(before: before, after: after).isEmpty)
    }

    @Test func instructionsAndPauseShowAsShortValues() throws {
        let before = try task(#""name":"A","prompt":"Old first line\nmore","agent":"claude","schedule":{"kind":"cron","timezone":"UTC","expression":"0 9 * * *"}"#)
        var after = before; after.prompt = "New first line\nmore"; after.enabled = false
        let changes = TaskChangeDiff.changes(before: before, after: after)
        #expect(changes == [TaskChange(field: "Instructions", from: "Old first line", to: "New first line"),
                            TaskChange(field: "Status", from: "On", to: "Paused")])
    }
}
