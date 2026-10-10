import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTasksTests {
    @Test func activeSchedulesExcludePausedCompletedAndCancelledTasks() throws {
        let cases: [(String, Bool)] = [
            (#"{"id":"a","enabled":true,"schedule":{"kind":"cron","timezone":"UTC"},"lastRunAt":1000}"#, true),
            (#"{"id":"a","enabled":true,"schedule":{"kind":"interval","timezone":"UTC"}}"#, true),
            (#"{"id":"a","enabled":true,"nextRunAt":2000}"#, true),
            (#"{"id":"a","enabled":false,"nextRunAt":2000}"#, false),
            (#"{"id":"a","enabled":true,"lastRunAt":1000}"#, false),
            (#"{"id":"a","enabled":true,"cancelledAt":1000}"#, false),
            (#"{"id":"a","enabled":false,"lastRunAt":1000,"currentRun":{"id":"run","status":"running"}}"#, false)
        ]
        for (json, expected) in cases {
            let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
            #expect(task.isScheduleActive == expected)
        }
    }
    @Test func taskGroupsKeepRecurringPausedAndRunningWorkPending() throws {
        let cases: [(String, ScheduledTaskGroup)] = [
            (#"{"id":"a","schedule":{"kind":"cron","timezone":"UTC"},"lastRunAt":1000}"#, .pending),
            (#"{"id":"a","enabled":false,"schedule":{"kind":"interval","timezone":"UTC"}}"#, .pending),
            (#"{"id":"a","schedule":{"kind":"once","timezone":"UTC"}}"#, .pending),
            (#"{"id":"a","lastRunAt":1000,"schedule":{"kind":"once","timezone":"UTC"}}"#, .completed),
            (#"{"id":"a","cancelledAt":1000}"#, .completed),
            (#"{"id":"a","lastRunAt":1000,"currentRun":{"id":"run","status":"running"},"schedule":{"kind":"once","timezone":"UTC"}}"#, .pending),
            (#"{"id":"a","cancelledAt":1000,"currentRun":{"id":"run","status":"needs_input"}}"#, .pending)
        ]
        for (json, expected) in cases {
            let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
            #expect(task.listGroup == expected)
        }
    }
    @Test func editingChatCannotUseTheCreationEndpointOrAnotherTaskConversation() {
        let creation = ScheduledTaskChatContext()
        let edit = ScheduledTaskChatContext(taskID: "task-a")
        let other = ScheduledTaskChatContext(taskID: "task-b")
        #expect(creation.endpoint == "/api/scheduled-tasks/chat")
        #expect(edit.endpoint == "/api/scheduled-tasks/task-a/chat")
        #expect(creation.savedSessionKey(hostID: "host-a") == "lfg.taskAuthoring.host-a")
        #expect(edit.savedSessionKey(hostID: "host-a") != creation.savedSessionKey(hostID: "host-a"))
        #expect(edit.savedSessionKey(hostID: "host-a") != other.savedSessionKey(hostID: "host-a"))
        #expect(edit.savedSessionKey(hostID: "host-a") != edit.savedSessionKey(hostID: "host-b"))
    }
    @Test func authoringTranscriptShowsOnlyTheRequestForBothModes() {
        for prefix in ["Help the user create an LFG scheduled task", "Help the user edit an existing LFG scheduled task"] {
            let kickoff = "\(prefix) through a short conversation.\nPrivate configuration\nThe user's request follows:\nMove it to 10 AM\nKeep weekdays."
            #expect(ScheduledTaskChatContext.displayedMessage(kickoff) == "Move it to 10 AM\nKeep weekdays.")
        }
        let ordinary = "The user's request follows:\nThis is normal conversation."
        #expect(ScheduledTaskChatContext.displayedMessage(ordinary) == ordinary)
    }
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
