import Foundation
import Testing
@testable import LFGCore

@Suite("Host connection presentation")
struct HostConnectionPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Unproven and transient states are reconnecting")
    func transientStatesAreReconnecting() {
        let states: [HostState?] = [
            nil,
            .unknown,
            .connecting,
            .degraded(since: now, reason: "Connection lost"),
            .noNetwork(since: now),
        ]

        for state in states {
            #expect(HostConnectionPresentation(state: state, isReconnecting: false) == .reconnecting)
        }
    }

    @Test("Live is connected even while the fleet reconnects")
    func liveIsConnected() {
        #expect(HostConnectionPresentation(state: .live, isReconnecting: false) == .connected)
        #expect(HostConnectionPresentation(state: .live, isReconnecting: true) == .connected)
    }

    @Test("Sustained failures are reconnecting during the burst, then offline")
    func sustainedFailuresRespectReconnectActivity() {
        let states: [HostState] = [
            .offline(since: now, reason: "Connection lost"),
            .noNetworkSustained(since: now),
        ]

        for state in states {
            #expect(HostConnectionPresentation(state: state, isReconnecting: true) == .reconnecting)
            #expect(HostConnectionPresentation(state: state, isReconnecting: false) == .offline)
        }
    }
}
