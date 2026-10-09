import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTasksTests {
    @Test func oneTimePayloadUsesAbsoluteInstant() throws {
        var draft = ScheduledTaskDraft()
        draft.kind = "once"; draft.date = Date(timeIntervalSince1970: 1_800_000_000)
        draft.name = "Review"; draft.prompt = "Review changes"; draft.cwd = "/tmp"
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.payload)) as? [String: Any])
        let schedule = try #require(object["schedule"] as? [String: Any])
        #expect(schedule["kind"] as? String == "once")
        #expect((schedule["at"] as? String)?.hasSuffix("Z") == true)
        #expect(object["model"] is NSNull)
    }
    @Test func decodingToleratesNewOrMissingFields() throws {
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(#"{"id":"a","name":"Review","extra":true}"#.utf8))
        #expect(task.name == "Review")
        #expect(task.agent == "claude")
        #expect(task.statusLabel == "Paused")
        #expect(task.recentRuns.isEmpty)
        #expect(task.modelLabel == "Claude default")
    }
    @Test func rowHistoryAndHostIdentityRemainSeparate() throws {
        let data = Data(#"{"id":"same","agent":"codex","model":"gpt-6.1-sol","recentRuns":[{"id":"run-b","sessionId":"session-b"},{"id":"run-a","sessionId":"session-a"}],"runCount":8}"#.utf8)
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: data)
        #expect(task.recentRuns.map(\.sessionId) == ["session-b", "session-a"])
        #expect(task.runCount == 8)
        #expect(task.modelLabel == "gpt-6.1-sol")
        let url = try #require(URL(string: "http://localhost:8897"))
        let a = HostedScheduledTask(task: task, host: .init(id: "a", name: "Air", baseURL: url))
        let b = HostedScheduledTask(task: task, host: .init(id: "b", name: "Pro", baseURL: url))
        #expect(a.id != b.id)
    }
    @Test func olderHostsStillExposeTheirLatestSession() throws {
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(#"{"id":"a","agent":"codex","lastRun":{"id":"last","sessionId":"session"}}"#.utf8))
        #expect(task.recentRuns.first?.sessionId == "session")
        #expect(task.modelLabel == "Codex default")
    }
    @Test func completedOnceAndCancelledTasksHaveDistinctStates() throws {
        let json = #"{"id":"a","enabled":false,"lastRunAt":1000,"schedule":{"kind":"once","timezone":"UTC"}}"#
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
        #expect(task.statusLabel == "Completed")
        #expect(!task.canResume)
    }
    @Test func formValidationRequiresMeaningfulFieldsAndPositiveInterval() {
        var draft = ScheduledTaskDraft()
        #expect(!draft.isValid)
        draft.name = "Review"; draft.prompt = "Review changes"; draft.cwd = "/tmp"; draft.kind = "interval"
        draft.intervalMinutes = "0"; #expect(!draft.isValid)
        draft.intervalMinutes = "30"; #expect(draft.isValid)
    }
    @Test func editingCompletedTaskPreservesFractionalTimestamp() throws {
        let json = #"{"id":"a","enabled":false,"lastRunAt":1000,"schedule":{"kind":"once","timezone":"UTC","at":"2026-10-10T01:00:00.000Z"},"lastRun":{"id":"run","status":"failed"}}"#
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
        #expect(ScheduledTaskDraft(task: task).date.timeIntervalSince1970 == 1791594000)
        #expect(task.statusLabel == "Failed")
    }
}
