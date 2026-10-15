import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTaskRepeatTests {
    private func record(extra: String = "") throws -> ScheduledTaskRecord {
        let json = """
        {"id":"repeat-a","name":"Three days","prompt":"Research","cwd":"/tmp","agent":"codex","enabled":true,
         "schedule":{"kind":"repeat","timezone":"Asia/Hong_Kong","at":"2026-10-14T23:55:00+08:00","everyMinutes":1440,"occurrences":3},
         "nextRunAt":1791993300000\(extra)}
        """
        return try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
    }

    @Test func repeatEditorRoundTripsThreeDailyOccurrences() throws {
        let task = try record()
        var draft = ScheduledTaskDraft(task: task)
        #expect(draft.kind == "repeat")
        #expect(draft.repeatEvery == "1")
        #expect(draft.repeatUnit == .days)
        #expect(draft.repeatOccurrences == "3")
        #expect(draft.isValid)
        draft.name = "Renamed"
        let data = try JSONEncoder().encode(draft.payload)
        let encoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let schedule = encoded["schedule"] as! [String: Any]
        #expect(schedule["kind"] as? String == "repeat")
        #expect(schedule["everyMinutes"] as? Int == 1440)
        #expect(schedule["occurrences"] as? Int == 3)
        #expect(ISO8601DateFormatter().date(from: schedule["at"] as! String) == ISO8601DateFormatter().date(from: task.schedule.at!))
        #expect(schedule["expression"] == nil)
    }

    @Test func repeatValidationRejectsEmptyFractionalNegativeAndOverflowInputs() throws {
        var draft = ScheduledTaskDraft(task: try record())
        for invalid in ["", "0", "-1", "1.5", "1001", "three"] {
            draft.repeatOccurrences = invalid
            #expect(!draft.isValid)
        }
        draft.repeatOccurrences = "3"
        for invalid in ["", "0", "-1", "1.5", "366", String(Int.max)] {
            draft.repeatEvery = invalid
            #expect(!draft.isValid)
        }
        draft.repeatEvery = "365"
        #expect(draft.isValid)
    }

    @Test func unitChangesProduceExactElapsedIntervals() throws {
        var draft = ScheduledTaskDraft(task: try record())
        draft.repeatEvery = "2"; draft.repeatUnit = .hours
        #expect(draft.payload.schedule.everyMinutes == 120)
        draft.repeatUnit = .minutes
        #expect(draft.payload.schedule.everyMinutes == 2)
        draft.repeatUnit = .days
        #expect(draft.payload.schedule.everyMinutes == 2880)
        draft.kind = "once"
        #expect(draft.payload.schedule.occurrences == nil)
        #expect(draft.payload.schedule.everyMinutes == nil)
    }

    @Test func repeatLabelIncludesTotalCountAndReadableInterval() throws {
        #expect(try record().schedule.description() == "3 occurrences · every day")
        #expect(ScheduledTaskSchedule(kind: "repeat", everyMinutes: 120, occurrences: 1).description() == "1 occurrence · every 2 hours")
    }

    @Test func finalRepeatStaysCompletedUnlessItsLastRunIsActive() throws {
        var task = try record()
        task.enabled = false; task.nextRunAt = nil; task.lastRunAt = 1792166100000
        #expect(!task.canResume)
        #expect(task.listGroup == .completed)
        #expect(task.statusLabel == "Completed")
        let run = try JSONDecoder().decode(ScheduledTaskRun.self, from: Data("{\"id\":\"run\",\"status\":\"running\"}".utf8))
        task.currentRun = run
        #expect(task.listGroup == .pending)
        #expect(task.statusLabel == "Running")
    }
}
