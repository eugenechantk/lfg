import Foundation
import Testing
@testable import LFGCore

@MainActor
@Suite(.serialized)
struct SessionTransferFlowTests {
    @Test
    func testRepeatedMovesKeepEveryOpenNavigationAliasOnLatestSession() {
        let created = ["local-draft": "first"]
        let moved = SessionTransfer.redirectedSessionIDs(created, from: "first", to: "second")
        let movedAgain = SessionTransfer.redirectedSessionIDs(moved, from: "second", to: "third")
        #expect(movedAgain["local-draft"] == "third")
        #expect(movedAgain["first"] == "third")
        #expect(movedAgain["second"] == "third")
    }

    @Test
    func testMovingBackToEarlierIDDoesNotCreateRedirectCycle() {
        let moved = SessionTransfer.redirectedSessionIDs(["other": "unrelated"], from: "first", to: "second")
        let returned = SessionTransfer.redirectedSessionIDs(moved, from: "second", to: "first")
        #expect(returned["first"] == nil)
        #expect(returned["second"] == "first")
        #expect(returned["other"] == "unrelated")
        #expect(SessionTransfer.redirectedSessionIDs(returned, from: "first", to: "first") == returned)
    }

    @Test
    func testRefreshStartedBeforeMoveCannotOverwriteNewOwnership() throws {
        let before = Date(timeIntervalSince1970: 10)
        let completed = before.addingTimeInterval(1)
        var fence = SessionTransfer.SnapshotFence()
        #expect(fence.accepts(host: "air", startedAt: before))
        fence.record(hosts: ["pro", "air"], at: completed)
        #expect(!fence.accepts(host: "air", startedAt: before))
        #expect(!fence.accepts(host: "pro", startedAt: before))
        #expect(fence.accepts(host: "air", startedAt: completed))
        #expect(fence.accepts(host: "unrelated", startedAt: before))
        // Cleanup must also invalidate requests started before its completion.
        fence.record(hosts: ["pro"], at: completed.addingTimeInterval(1))
        #expect(!fence.accepts(host: "pro", startedAt: completed))
        #expect(fence.accepts(host: "air", startedAt: completed))
    }

    @Test
    func testRecoveredSourceCannotReclaimRoutingWhileCleanupIsPending() {
        let pro = Host(url: "pro:1"), air = Host(url: "air:1")
        let row = Session(sessionId: "s", title: "Conversation", agent: "codex")
        var cleanup = DeferredSourceCloses()
        cleanup.add(host: pro.id, session: "s")
        // Both hosts are live now; Pro is first configured. Suppression must
        // survive a restart and remain until close confirmation, not just send.
        cleanup = DeferredSourceCloses.decode(cleanup.encoded())
        let merged = MultiHost.mergeSessions([
            (pro, cleanup.keepingActive([row], on: pro.id)),
            (air, cleanup.keepingActive([row], on: air.id)),
        ])
        #expect(merged.hostBySession["s"] == air.id)
        #expect(cleanup.byHost[pro.id] == ["s"])
        cleanup.remove(host: pro.id, session: "s")
        #expect(cleanup.isEmpty)
    }

    @Test
    func testMovingBackCancelsOnlyDestinationsDeferredCleanup() {
        var cleanup = DeferredSourceCloses()
        cleanup.add(host: "pro", session: "s")
        cleanup.add(host: "pro", session: "other")
        cleanup.add(host: "air", session: "s")
        cleanup.remove(host: "pro", session: "s")
        #expect(cleanup.byHost["pro"] == ["other"])
        #expect(cleanup.byHost["air"] == ["s"])
    }

    @Test
    func testPreflightStillProtectsMissingDirectoryAndStaleHistory() {
        #expect(SessionTransfer.preflight(status: .init(found: false), sourceLastActivityAt: 100_000) == .missing)
        #expect(SessionTransfer.preflight(status: .init(found: true, cwd: "/pro-only", cwdExists: false),
                                         sourceLastActivityAt: nil) == .cwdMissing("/pro-only"))
        let stale = SessionTransfer.preflight(status: .init(found: true, lastActivityAt: 1_000),
                                             sourceLastActivityAt: 121_000)
        #expect(stale == .behind(seconds: 120))
        #expect(stale.needsConfirmation)
    }

    @Test
    func testCompletedMoveRemovesOfflineSourceAndPreservesLiveTarget() throws {
        let source = Session(sessionId: "s", title: "Cached Pro", agent: "codex", busy: true)
        let target = Session(sessionId: "s", title: "Live Air", agent: "codex", busy: false)
        let other = Session(sessionId: "other", title: "Unrelated", agent: "claude")
        let response = try JSONDecoder().decode(NewSessionResponse.self,
            from: Data(#"{"ok":true,"sessionId":"s","alreadyLive":true}"#.utf8))
        let moved = SessionTransfer.completedSnapshots(["pro": [source, other], "air": [target]],
            session: source, sourceHost: "pro", targetHost: "air", response: response)
        #expect(moved["pro"] == [other])
        #expect(moved["air"] == [target])
        // These same snapshots are written through for cold-launch hydration.
        let reloaded = try JSONDecoder().decode([String: [Session]].self, from: JSONEncoder().encode(moved))
        #expect(reloaded == moved)
    }

    @Test
    func testNewTargetSnapshotUsesReturnedIdAndClearsSourceLiveClaims() throws {
        let source = Session(sessionId: "old", title: "Conversation", agent: "claude",
                             status: "blocked", tmuxTarget: "pro:0.0", busy: true)
        let response = try JSONDecoder().decode(NewSessionResponse.self,
            from: Data(#"{"ok":true,"sessionId":"new","tmuxName":"air-pane"}"#.utf8))
        let moved = SessionTransfer.completedSnapshots(["pro": [source]], session: source,
            sourceHost: "pro", targetHost: "air", response: response)
        #expect(moved["pro"] == [])
        let target = try #require(moved["air"]?.first)
        #expect(target.sessionId == "new")
        #expect(target.title == "Conversation")
        #expect(target.tmuxName == "air-pane")
        #expect(target.tmuxTarget == nil)
        #expect(target.busy == nil)
        #expect(target.status == nil)
        #expect(!(target.closed))
    }

    @Test
    func testReachableAirWinsOverOfflineProSnapshotWithoutReorderingRows() {
        let pro = Host(url: "pro:1"), air = Host(url: "air:1")
        let stale = Session(sessionId: "moved", title: "Pro cached", agent: "codex")
        let current = Session(sessionId: "moved", title: "Air live", agent: "codex")
        let other = Session(sessionId: "other", title: "Other offline session", agent: "claude")
        let merged = MultiHost.mergeSessions([(pro, [stale, other]), (air, [current])],
                                              unreachableHostIds: [pro.id])
        #expect(merged.sessions.map(\.sessionId) == ["moved", "other"])
        #expect(merged.sessions.first?.title == "Air live")
        #expect(merged.hostBySession["moved"] == air.id)
        #expect(merged.hostBySession["other"] == pro.id)
    }

    @Test
    func testReconciliationKeepsIdStableTransferLiveOnAir() {
        let pro = Host(url: "pro:1"), air = Host(url: "air:1")
        let stale = Session(sessionId: "moved", title: "Pro cached", agent: "codex")
        let current = Session(sessionId: "moved", title: "Air live", agent: "codex")
        let result = MultiHost.reconcileSessionList(
            perHostLive: [(pro, [stale]), (air, [current])], closedPerHost: [],
            unreachableHostIds: [pro.id])
        #expect(result.live.hostBySession["moved"] == air.id)
        #expect(result.liveIds == ["moved"])
        #expect(result.visibleClosed.isEmpty)
    }

    private func client(_ host: String) -> LFGClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferURLProtocol.self]
        return LFGClient(baseURL: URL(string: "https://\(host).test")!,
                         session: URLSession(configuration: configuration))
    }

    private func move(offline: Bool = true) async throws -> SessionTransfer.Completion {
        try await SessionTransfer.perform("session", sourceKnownDown: offline,
                                          source: client("pro"), target: client("air"), sleep: { _ in })
    }

    @Test
    func testOfflineSourceResumesOnAirWithoutContactingPro() async throws {
        TransferURLProtocol.reset()
        let result = try await move()
        #expect(result.response.sessionId == "resumed")
        #expect(result.plan.deferSourceClose)
        #expect(TransferURLProtocol.paths == ["air.test/api/sessions/resume"])
        #expect(TransferURLProtocol.resumeBodies.first?["force"] as? Bool == true)
    }

    @Test
    func testAlreadyLiveOnAirCompletesOfflineMoveWithoutRetrying() async throws {
        TransferURLProtocol.reset(alreadyLive: true)
        let result = try await move()
        #expect(result.response.sessionId == "session")
        #expect(result.plan.deferSourceClose)
        #expect(TransferURLProtocol.paths == ["air.test/api/sessions/resume"])
    }

    @Test
    func testRetryAfterLostResumeResponseReusesAirSession() async throws {
        TransferURLProtocol.reset(targetStatus: 502)
        do {
            _ = try await move()
            Issue.record("A failed target request must not produce completion or deferred cleanup")
        } catch {}
        // The original request started the session but its response was lost.
        TransferURLProtocol.reset(alreadyLive: true)
        let retry = try await move()
        #expect(retry.response.sessionId == "session")
        #expect(TransferURLProtocol.resumeBodies.count == 1)
    }

    @Test
    func testOnlineSourceClosesBeforeUnforcedResume() async throws {
        TransferURLProtocol.reset()
        let result = try await move(offline: false)
        #expect(!(result.plan.deferSourceClose))
        #expect(TransferURLProtocol.paths == [
            "pro.test/api/sessions/session/close", "pro.test/api/sessions", "air.test/api/sessions/resume",
        ])
        #expect(TransferURLProtocol.resumeBodies.first?["force"] as? Bool == nil)
    }

    @Test
    func testOnlineMoveAlsoAcceptsAlreadyLiveDestination() async throws {
        TransferURLProtocol.reset(alreadyLive: true)
        let result = try await move(offline: false)
        #expect(result.response.sessionId == "session")
        #expect(TransferURLProtocol.resumeBodies.count == 1)
        #expect(!(result.plan.deferSourceClose))
    }

    @Test
    func testSourceTransportFailureFallsBackToForcedResume() async throws {
        TransferURLProtocol.reset(sourceUnavailable: true)
        let result = try await move(offline: false)
        #expect(result.plan.deferSourceClose)
        #expect(TransferURLProtocol.resumeBodies.first?["force"] as? Bool == true)
        #expect(TransferURLProtocol.paths.last == "air.test/api/sessions/resume")
    }

    @Test
    func testSourceHTTPRefusalAbortsWithoutTouchingAir() async throws {
        TransferURLProtocol.reset(sourceStatus: 409)
        do {
            _ = try await move(offline: false)
            Issue.record("Source refusal must abort")
        } catch SessionTransfer.Failure.sourceClose(let error) {
            guard case LFGError.http(let status, _) = error else { Issue.record("\(error)"); return }
            #expect(status == 409)
        }
        #expect(TransferURLProtocol.paths == ["pro.test/api/sessions/session/close"])
    }

    @Test
    func testTargetLeaseRefusalDoesNotCompleteMove() async throws {
        TransferURLProtocol.reset(targetStatus: 409)
        do {
            _ = try await move()
            Issue.record("Failed takeover must not produce completion or deferred cleanup")
        } catch LFGError.http(let status, _) {
            #expect(status == 409)
        }
        #expect(TransferURLProtocol.resumeBodies.count == 1)
    }
}

/// Actual LFGClient encoding/decoding with the HTTP boundary replaced. Every
/// test resets the fixture; Swift Testing runs this suite serially.
private final class TransferURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var alreadyLive = false
    nonisolated(unsafe) private static var sourceUnavailable = false
    nonisolated(unsafe) private static var sourceStatus = 200
    nonisolated(unsafe) private static var targetStatus = 200

    static func reset(alreadyLive: Bool = false, sourceUnavailable: Bool = false,
                      sourceStatus: Int = 200, targetStatus: Int = 200) {
        lock.withLock {
            requests = []
            Self.alreadyLive = alreadyLive
            Self.sourceUnavailable = sourceUnavailable
            Self.sourceStatus = sourceStatus
            Self.targetStatus = targetStatus
        }
    }

    static var paths: [String] {
        lock.withLock { requests.map { "\($0.url!.host!)\($0.url!.path)" } }
    }

    static var resumeBodies: [[String: Any]] {
        lock.withLock {
            requests.filter { $0.url?.path == "/api/sessions/resume" }.compactMap {
                guard let data = $0.httpBody else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // URLSession can convert httpBody to a stream before URLProtocol sees it.
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        let (live, unavailable, status) = Self.lock.withLock {
            Self.requests.append(captured)
            let isSource = request.url?.host == "pro.test"
            return (Self.alreadyLive, isSource && Self.sourceUnavailable,
                    isSource ? Self.sourceStatus : Self.targetStatus)
        }
        if unavailable {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let body: String
        if status != 200 {
            body = #"{"error":"test refusal"}"#
        } else if request.url?.path == "/api/sessions/resume" {
            body = live
                ? #"{"ok":true,"sessionId":"session","alreadyLive":true,"tmuxName":"air-pane","agent":"codex"}"#
                : #"{"ok":true,"sessionId":"resumed","tmuxName":"air-pane","agent":"claude"}"#
        } else if request.url?.path == "/api/sessions" {
            body = #"{"sessions":[]}"#
        } else {
            body = #"{"ok":true}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
