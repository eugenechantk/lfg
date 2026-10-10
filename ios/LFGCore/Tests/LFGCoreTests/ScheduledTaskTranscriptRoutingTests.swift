import Testing
@testable import LFGCore

@Suite struct ScheduledTaskTranscriptRoutingTests {
    private let source = Host(url: "http://task-host:8898")
    private let peer = Host(url: "http://default-host:8899", isDefault: true)

    @Test func archivedRunReadsTheHostThatFoundItsTranscript() {
        let host = MultiHost.readRouteHost(owner: nil, transcriptHost: source,
            reachable: { _ in true }, agnostic: peer)
        #expect(host == source)
    }

    @Test func liveOwnershipWinsAfterTheSessionMoves() {
        let host = MultiHost.readRouteHost(owner: peer, transcriptHost: source,
            reachable: { _ in true }, agnostic: source)
        #expect(host == peer)
    }

    @Test func unavailableTranscriptHostStillAllowsReadingFromAPeer() {
        let host = MultiHost.readRouteHost(owner: nil, transcriptHost: source,
            reachable: { $0.id == peer.id }, agnostic: peer)
        #expect(host == peer)
    }

    @Test func transcriptHintDoesNotRedirectAgentOperations() {
        let read = MultiHost.readRouteHost(owner: nil, transcriptHost: source,
            reachable: { _ in true }, agnostic: peer)
        let write = MultiHost.routeHost(owner: nil, isClosed: true,
            reachable: { _ in true }, agnostic: peer)
        #expect(read == source)
        #expect(write == peer)
    }
}
