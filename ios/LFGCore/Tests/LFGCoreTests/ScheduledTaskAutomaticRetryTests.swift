import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTaskAutomaticRetryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func task(paused: Bool = false, final: Bool = false) throws -> ScheduledTaskRecord {
        let at = now.timeIntervalSince1970 * 1000
        let json = """
        {"id":"task","enabled":\(!paused && !final),"schedule":{"kind":"repeat","at":"\(ISO8601DateFormatter().string(from: now))","everyMinutes":1440,"occurrences":3,"timezone":"UTC"},
        "retryAt":\(at + 86_400_000),"retryOfRunId":"first","retryAutomatic":true,"scheduleDelayMs":86400000,"scheduledRunCount":\(final ? 3 : 1),
        "nextRunAt":\(final ? "null" : String(at + 172_800_000)),"upcomingRuns":\(final ? "[]" : "[\(at + 172_800_000),\(at + 259_200_000)]"),
        "pausedAt":\(paused ? String(at) : "null"),"lastRun":{"id":"first","status":"incomplete","occurrence":\(final ? 3 : 1),"error":"More work remains"}}
        """
        return try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
    }

    @Test func recoveryCardExplainsPreservedOccurrenceAndDeferredSchedule() throws {
        let value = try task()
        let card = TaskStatusCardModel.make(task: value, now: now)
        #expect(card.label == "Retry scheduled")
        #expect(card.footnote?.contains("keeps its scheduled occurrence") == true)
        #expect(card.footnote?.contains("Following run") == true)
        #expect(card.primary == .retry)
        #expect(card.secondary == .changeRetryTime)
        #expect(TaskScheduleSummary.runProgress(value) == "retry of run 1 of 3")
    }

    @Test func pickerStartsAtAssignedRetryAndAllowsEarlierOrLater() throws {
        let value = try task()
        var draft = ScheduledTaskRetryDraft(now: now, retryAt: value.retryAt)
        #expect(draft.mode == .time)
        #expect(try draft.scheduledDate(now: now) == now.addingTimeInterval(86400))
        for seconds in [3600.0, 172800.0] {
            draft.date = now.addingTimeInterval(seconds)
            #expect(try draft.scheduledDate(now: now) == draft.date)
        }
    }

    @Test func finalRecoveryDoesNotClaimTheSeriesFinished() throws {
        let value = try task(final: true)
        let card = TaskStatusCardModel.make(task: value, now: now)
        #expect(value.listSection == .active)
        #expect(card.label == "Retry scheduled")
        #expect(card.footnote?.contains("final occurrence") == true)
    }

    @Test func pausedAutomaticRetryShowsPausedAndCanResume() throws {
        let value = try task(paused: true)
        #expect(value.listSection == .paused)
        #expect(TaskStatusCardModel.make(task: value, now: now).label == "Paused")
    }

    @Test func shiftedScheduleProgressUsesItsEffectiveAnchor() throws {
        var value = try task()
        value.retryAt = nil
        value.retryOfRunId = nil
        value.lastRun?.status = "succeeded"
        #expect(TaskScheduleSummary.runProgress(value) == "run 2 of 3")
    }
}
