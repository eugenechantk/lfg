import Foundation
import Testing
@testable import LFGCore

@Suite struct SessionRowClockTests {
    @Test(arguments: [
        (0.0, 1_000.0), (45_500, 46_000), (59_999, 60_000),
        (60_000, 120_000), (3_599_000, 3_600_000),
        (3_600_000, 7_200_000), (86_399_000, 86_400_000),
        (86_400_000, 172_800_000), (604_799_000, 604_800_000),
        (604_800_000, 1_209_600_000)
    ])
    func wakesAtTheNextVisibleChange(elapsed: Double, expected: Double) throws {
        let start = 1_790_000_000_123.0
        let next = try #require(SessionRowLine.nextDurationUpdate(from: start, after: start + elapsed))
        #expect(next == start + expected)
        #expect(SessionRowLine.compactDuration(from: start, to: next - 1)
                == SessionRowLine.compactDuration(from: start, to: start + elapsed))
        #expect(SessionRowLine.compactDuration(from: start, to: next)
                != SessionRowLine.compactDuration(from: start, to: next - 1))
    }

    @Test func futureTimestampKeepsZeroUntilItsFirstSecond() {
        #expect(SessionRowLine.nextDurationUpdate(from: 10_000, after: 0) == 11_000)
    }

    @Test func invalidTimestampsDoNotScheduleATimer() {
        #expect(SessionRowLine.nextDurationUpdate(from: .nan, after: 0) == nil)
        #expect(SessionRowLine.nextDurationUpdate(from: 0, after: .infinity) == nil)
    }
}
