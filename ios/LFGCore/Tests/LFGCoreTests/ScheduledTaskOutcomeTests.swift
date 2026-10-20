import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTaskOutcomeTests {
    @Test func incompleteRunsRequireAttentionAndOfferRetry() throws {
        let json = #"{"id":"task","enabled":false,"lastRunAt":1000,"schedule":{"kind":"once","timezone":"UTC","at":"2026-10-15T00:00:00Z"},"lastRun":{"id":"run","status":"incomplete","sessionId":"session","startedAt":1000,"finishedAt":2000,"error":"Only 12 of 45 minutes completed. Login is required."},"consecutiveFailures":1}"#
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
        #expect(task.lastRun?.statusLabel == "Incomplete")
        #expect(task.listSection == .needsInput)
        let row = TaskRowModel.make(task: task, hostName: "Pro")
        #expect(row.result.hasPrefix("Incomplete"))
        let card = TaskStatusCardModel.make(task: task)
        #expect(card.kind == .failed)
        #expect(card.label == "Last run incomplete")
        #expect(card.sub?.contains("12 of 45 minutes") == true)
        #expect(card.primary == .retry)
        let entries = RunTimelineEntry.entries(task: task, runs: [task.lastRun!])
        #expect(entries[0].body?.hasPrefix("Incomplete") == true)
        #expect(entries[0].tail == "Retry")
        #expect(entries[0].tailIsAction)
    }
}
