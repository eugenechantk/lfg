import Testing
@testable import LFG

@Suite struct FilePaneSizingTests {
    @Test func fullWindowUsesThePreferredSnaps() {
        #expect(FilePaneSizing.width(preferred: 720, available: 1200) == 720)
        #expect(FilePaneSizing.width(preferred: 420, available: 1200) == 420)
    }
    @Test func threeColumnsKeepTheWideReaderAtSixHundredPoints() {
        #expect(FilePaneSizing.width(preferred: 720, available: 1036) == 600)
        #expect(FilePaneSizing.width(preferred: 420, available: 1036) == 420)
    }
    @Test func smallerWindowsReserveTheTranscript() {
        #expect(FilePaneSizing.width(preferred: 720, available: 900) == 490)
    }
}
