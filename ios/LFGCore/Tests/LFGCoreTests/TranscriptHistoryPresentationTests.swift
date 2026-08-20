import Testing
@testable import LFGCore

@Suite("Transcript history top-row presentation")
struct TranscriptHistoryPresentationTests {
    @Test("network paging shows an honest loading row even before older rows are buffered")
    func networkPagingShowsLoadingRow() {
        #expect(TranscriptHistoryTopRow.resolve(
            isNetworkLoading: true,
            hasBufferedEarlierMessages: false
        ) == .loadingNetwork)
    }

    @Test("completed history with no buffered earlier rows hides the top row")
    func completedHistoryHidesTopRow() {
        #expect(TranscriptHistoryTopRow.resolve(
            isNetworkLoading: false,
            hasBufferedEarlierMessages: false
        ) == .hidden)
    }

    @Test("buffered earlier rows keep the progressive reveal affordance")
    func bufferedEarlierRowsRemainRevealable() {
        #expect(TranscriptHistoryTopRow.resolve(
            isNetworkLoading: false,
            hasBufferedEarlierMessages: true
        ) == .revealingBuffered)
    }

    @Test("active network paging takes precedence over buffered-row reveal")
    func networkLoadingTakesPrecedence() {
        #expect(TranscriptHistoryTopRow.resolve(
            isNetworkLoading: true,
            hasBufferedEarlierMessages: true
        ) == .loadingNetwork)
    }
}
