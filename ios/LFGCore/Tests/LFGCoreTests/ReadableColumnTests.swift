import Foundation
import Testing
@testable import LFGCore

@Suite("Reading column on wide screens")
struct ReadableColumnTests {
    @Test("phone widths keep the full width")
    func phoneUnchanged() {
        for width: CGFloat in [375, 390, 402, 440] {
            #expect(ReadableColumn.width(in: width) == width)
            #expect(ReadableColumn.sideInset(in: width) == 0)
        }
    }

    @Test("iPad portrait beside the list keeps the full detail width")
    func iPadPortraitDetail() {
        #expect(ReadableColumn.width(in: 494) == 494)
        #expect(ReadableColumn.sideInset(in: 494) == 0)
    }

    @Test("landscape with the list caps at 720 and centers it (board ip-session)")
    func landscapeWithList() {
        #expect(ReadableColumn.width(in: 870) == 720)
        #expect(ReadableColumn.sideInset(in: 870) == 75)
    }

    @Test("landscape with the list hidden centers the same column (board ip-session-full)")
    func landscapeFull() {
        #expect(ReadableColumn.width(in: 1210) == 720)
        #expect(ReadableColumn.sideInset(in: 1210) == 245)
    }

    @Test("an unknown or empty width falls back to the cap, not to zero")
    func degenerateWidths() {
        #expect(ReadableColumn.width(in: 0) == 720)
        #expect(ReadableColumn.width(in: .infinity) == 720)
        #expect(ReadableColumn.sideInset(in: .infinity) == 0)
    }

    @Test("user bubbles grow only inside a wide column")
    func bubbleCap() {
        #expect(ReadableColumn.userBubbleTextCap(columnWidth: 402) == 290)
        #expect(ReadableColumn.userBubbleTextCap(columnWidth: 494) == 290)
        #expect(ReadableColumn.userBubbleTextCap(columnWidth: 599) == 290)
        #expect(ReadableColumn.userBubbleTextCap(columnWidth: 600) == 480)
        #expect(ReadableColumn.userBubbleTextCap(columnWidth: 720) == 480)
    }
}
