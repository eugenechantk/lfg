import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import LFGCore

@Suite struct AccountUsageTests {
    let now = Date(timeIntervalSince1970: 1_792_483_200)

    func provider(id: String? = "a", percent: Double? = 25, at: Date? = nil, status: String = "ok") -> AccountUsageProvider {
        .init(provider: "codex", accountId: id, accountLabel: "Sample account", plan: "ChatGPT Pro", status: status,
              fetchedAt: (at ?? now).timeIntervalSince1970 * 1000,
              windows: [.init(id: "weekly", durationMinutes: 10080, usedPercent: percent, resetsAt: now.addingTimeInterval(3600).timeIntervalSince1970 * 1000)])
    }

    @Test func decoderAcceptsISOWithFractionsAndMissingFields() throws {
        let raw = Data(#"{"providers":[{"provider":"claude","fetchedAt":"2026-10-20T08:00:00.123+00:00","windows":[{"id":"weekly","durationMinutes":10080,"usedPercent":0}]}]}"#.utf8)
        let value = try JSONDecoder().decode(AccountUsageResponse.self, from: raw)
        #expect(value.providers.first?.windows.first?.usedPercent == 0)
        #expect(value.providers.first?.fetchedAt != nil)
        #expect(value.providers.first?.accountId == nil)
    }

    @Test func onlyProvenAccountsMergeAndFreshestReadingWins() {
        let older = provider(at: now.addingTimeInterval(-60))
        let snapshots = [AccountUsageHostSnapshot(host: .init(id: "pro", label: "Pro"), providers: [older]),
                         AccountUsageHostSnapshot(host: .init(id: "air", label: "Air"), providers: [provider(percent: 50)])]
        let cards = AccountUsagePresentation.cards(snapshots)
        #expect(cards.count == 1)
        #expect(cards[0].hosts.map(\.label) == ["Air", "Pro"])
        #expect(cards[0].reading.windows[0].usedPercent == 50)
        let unknown = snapshots.map { AccountUsageHostSnapshot(host: $0.host, providers: [provider(id: nil)]) }
        #expect(AccountUsagePresentation.cards(unknown).count == 2)
    }

    @Test func missingPercentHasNoToneOrBarAndDurationsDetermineNames() {
        let row = AccountUsagePresentation.row(.init(id: "primary", durationMinutes: 10080), now: now)
        #expect(row.title == "Weekly · 7 days")
        #expect(row.percent == nil)
        #expect(row.value == "Not reported")
        #expect(row.tone == .unknown)
    }

    @Test func thresholdsAndPassedResetsStayExplicit() {
        for (percent, tone) in [(0.0, AccountUsageTone.normal), (75, .high), (93, .critical), (100, .exhausted)] {
            let row = AccountUsagePresentation.row(.init(id: "x", durationMinutes: 300, usedPercent: percent,
                                                       resetsAt: now.addingTimeInterval(-60).timeIntervalSince1970 * 1000), now: now)
            #expect(row.tone == tone)
            #expect(row.subtitle.contains("may already have reset"))
        }
    }

    @Test func invalidDurationsCannotCrashTheFormatter() {
        for duration in [Double.nan, .infinity, -1, 1e100] {
            let row = AccountUsagePresentation.row(.init(id: "bad", durationMinutes: duration, usedPercent: 25), now: now)
            #expect(row.percent == nil)
            #expect(row.value == "Not reported")
        }
    }

    @Test func warningWordsRemainWhenNoResetWasReported() {
        for (percent, words) in [(93.0, "Little left"), (100.0, "Used up")] {
            let row = AccountUsagePresentation.row(.init(id: "current", durationMinutes: 300, usedPercent: percent), now: now)
            #expect(row.subtitle.hasPrefix(words))
        }
    }

    @Test func aMissingWindowDoesNotClaimAnObservedDuration() {
        let missing = AccountUsagePresentation.row(.init(id: "missing-300", durationMinutes: 300), now: now)
        #expect(missing.title == "Current window")
        #expect(missing.percent == nil)
        let reported = AccountUsagePresentation.row(.init(id: "codex:primary", durationMinutes: 300), now: now)
        #expect(reported.title == "Current window · 5 h")
    }

    @Test @MainActor func inFlightRefreshKeepsThePreviousNumbers() async {
        let store = AccountUsageStore()
        let host = AccountUsageHost(id: "pro", label: "Pro")
        let initial = provider()
        await store.refresh(hosts: [host]) { _ in AccountUsageResponse(providers: [initial]) }
        let gate = AccountUsageTestGate()
        let task = Task { await store.refresh(hosts: [host]) { _ in await gate.load() } }
        await gate.waitUntilStarted()
        #expect(store.refreshing)
        #expect(store.cards[0].reading.windows[0].usedPercent == 25)
        await gate.finish(AccountUsageResponse(providers: [provider(percent: 50)]))
        await task.value
        #expect(!store.refreshing)
        #expect(store.cards[0].reading.windows[0].usedPercent == 50)
    }

    @Test @MainActor func aLateResponseCannotRestoreAnOldHostConfiguration() async {
        let store = AccountUsageStore()
        let host = AccountUsageHost(id: "old", label: "Old")
        let gate = AccountUsageTestGate()
        let task = Task { await store.refresh(hosts: [host]) { _ in await gate.load() } }
        await gate.waitUntilStarted()
        await store.refresh(hosts: []) { _ in AccountUsageResponse(providers: []) }
        await gate.finish(AccountUsageResponse(providers: [provider()]))
        await task.value
        #expect(store.cards.isEmpty)
        #expect(!store.refreshing)
    }

    @Test @MainActor func refreshRetainsNumbersDuringFailureAndPrunesRemovedHosts() async {
        let store = AccountUsageStore()
        let host = AccountUsageHost(id: "pro", label: "Pro")
        let value = provider()
        await store.refresh(hosts: [host]) { _ in AccountUsageResponse(providers: [value]) }
        await store.refresh(hosts: [host]) { _ in throw URLError(.notConnectedToInternet) }
        #expect(store.cards.count == 1)
        #expect(store.cards[0].reading.windows[0].usedPercent == 25)
        #expect(store.cards[0].offline)
        await store.refresh(hosts: []) { _ in AccountUsageResponse(providers: []) }
        #expect(store.cards.isEmpty)
    }

    @Test @MainActor func changedAccountDoesNotInheritPreviousWindows() async {
        let store = AccountUsageStore()
        let host = AccountUsageHost(id: "pro", label: "Pro")
        let first = provider()
        await store.refresh(hosts: [host]) { _ in AccountUsageResponse(providers: [first]) }
        let next = AccountUsageProvider(provider: "codex", accountId: "different", status: "error")
        await store.refresh(hosts: [host]) { _ in AccountUsageResponse(providers: [next]) }
        #expect(store.cards[0].reading.accountId == "different")
        #expect(store.cards[0].reading.windows.isEmpty)
    }

    @Test @MainActor func theRealClientPreservesOfflineClassification() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountUsageUnavailableProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = LFGClient(baseURL: URL(string: "https://usage.test")!, session: session)
        let host = AccountUsageHost(id: "pro", label: "Pro")
        let initial = provider()
        let store = AccountUsageStore()
        await store.refresh(hosts: [host]) { _ in AccountUsageResponse(providers: [initial]) }
        await store.refresh(hosts: [host]) { _ in try await client.accountUsage() }
        #expect(store.cards[0].offline)
        #expect(store.cards[0].reading.windows[0].usedPercent == 25)
    }
}

private final class AccountUsageUnavailableProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)) }
    override func stopLoading() {}
}

private actor AccountUsageTestGate {
    var started = false
    var waiter: CheckedContinuation<Void, Never>?
    var response: CheckedContinuation<AccountUsageResponse, Never>?
    func load() async -> AccountUsageResponse {
        started = true
        waiter?.resume(); waiter = nil
        return await withCheckedContinuation { response = $0 }
    }
    func waitUntilStarted() async {
        if !started { await withCheckedContinuation { waiter = $0 } }
    }
    func finish(_ value: AccountUsageResponse) { response?.resume(returning: value); response = nil }
}
