import Foundation
import XCTest
@testable import LFGCore

/// Run optimized: swift test -c release --filter ScrollPresentationPerformanceTests.
/// The workload matches the schedule/date work needed as Tasks cells enter view.
final class ScrollPresentationPerformanceTests: XCTestCase {
    func testTaskRowFormatting() throws {
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(#"""
        {"id":"scroll-task","name":"Review project","prompt":"Review progress","cwd":"/workspace",
         "agent":"codex","enabled":true,
         "schedule":{"kind":"cron","expression":"15 9 * * 1-5","timezone":"Asia/Hong_Kong"},
         "nextRunAt":1792202400000,"upcomingRuns":[1792202400000],
         "lastRun":{"id":"run","status":"succeeded","startedAt":1792198800000,"finishedAt":1792199100000}}
        """#.utf8))
        let now = Date(timeIntervalSince1970: 1792198800)
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Hong_Kong"))
        let locale = Locale(identifier: "en_US")
        measure {
            for _ in 0..<100 {
                let row = TaskRowModel.make(task: task, hostName: "Pro", now: now, timeZone: zone, locale: locale)
                XCTAssertFalse(row.time.isEmpty)
                XCTAssertTrue(row.when.contains("Weekdays"))
            }
        }
    }
}
