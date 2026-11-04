import Foundation
import XCTest
@testable import LFGCore

final class LFGClientLiveActivityTests: XCTestCase {
    override func tearDown() {
        RequestCapturingURLProtocol.reset()
        super.tearDown()
    }

    func testSendMessagePostsClientIdWhenProvided() async throws {
        let client = makeClient()

        _ = try await client.sendMessage("session-123", text: "hello", clientId: "client-1")

        let request = try XCTUnwrap(RequestCapturingURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/sessions/session-123/send")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try requestBody(request), [
            "text": "hello",
            "clientId": "client-1",
        ])
    }

    func testSendMessageRequestBuildsSameClientIdBody() throws {
        let client = makeClient()

        let request = try client.sendMessageRequest("session-123", text: "hello", clientId: "client-1")

        XCTAssertEqual(request.url?.path, "/api/sessions/session-123/send")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try requestBody(request), [
            "text": "hello",
            "clientId": "client-1",
        ])
    }

    func testSendMessageRequestOmitsNilClientId() throws {
        let client = makeClient()

        let request = try client.sendMessageRequest("session-123", text: "hello")

        XCTAssertEqual(try requestBody(request), ["text": "hello"])
    }

    func testRegisterLiveActivityStartTokenPostsExpectedBody() async throws {
        let client = makeClient()

        try await client.registerLiveActivityStartToken("00abc123", env: "dev")

        let request = try XCTUnwrap(RequestCapturingURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/push/live-activity/start-token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try requestBody(request), [
            "token": "00abc123",
            "env": "dev",
        ])
    }

    // Update-token registration is gone: the card is addressed by broadcast
    // channel now, so there is nothing per-card for the phone to hand back — which
    // is what made an idle phone's card freeze. The app only ASKS for the channel.
    func testLiveActivityChannelIsFetchedForTheGivenEnvironment() async throws {
        let client = makeClient(body: #"{"ok":true,"env":"production","channelId":"Y2hhbg=="}"#)

        let channelId = try await client.liveActivityChannel(env: "production")

        let request = try XCTUnwrap(RequestCapturingURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/push/live-activity/channel")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try requestBody(request), ["env": "production"])
        XCTAssertEqual(channelId, "Y2hhbg==")
    }

    // A server whose broadcast capability is not enabled yet answers with a null
    // channel. That is a normal state the app must tolerate — not an error — and
    // it must surface as nil so the app declines to create an unstartable card.
    func testLiveActivityChannelDecodesNullAsNoChannel() async throws {
        let client = makeClient(body: #"{"ok":true,"channelId":null}"#)

        let channelId = try await client.liveActivityChannel(env: "sandbox")

        XCTAssertNil(channelId)
    }

    func testReportLiveActivityStartedCarriesNoPayload() async throws {
        let client = makeClient()

        try await client.reportLiveActivityStarted()

        let request = try XCTUnwrap(RequestCapturingURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/push/live-activity/started")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try requestBody(request), [:])
    }

    // The phone's hidden directories ride along with its token so each host can
    // skip alerts for sessions the phone has hidden. An empty set is sent as []
    // (unmute everything), never omitted — omission means "old build, keep it".
    func testRegisterPushSendsTheHiddenDirectories() async throws {
        let client = makeClient()

        try await client.registerPush(token: "00ab", env: "production", owner: nil,
                                      hiddenDirs: ["/Users/e/.gbrain", "*/scratch-*"])

        let request = try XCTUnwrap(RequestCapturingURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/push/register")
        let object = try requestObject(request)
        XCTAssertEqual(object["token"] as? String, "00ab")
        XCTAssertEqual(object["hiddenDirs"] as? [String], ["/Users/e/.gbrain", "*/scratch-*"])

        try await client.registerPush(token: "00ab", env: "production", owner: nil, hiddenDirs: [])
        let cleared = try requestObject(try XCTUnwrap(RequestCapturingURLProtocol.capturedRequest))
        XCTAssertEqual(cleared["hiddenDirs"] as? [String], [])
    }

    // 2026-11-04: the phone registered at 11:15 with a host still on the old
    // build, which answered 200 and dropped the list; the host restarted on the
    // new build at 11:17 and kept alerting for hidden autopilot sessions,
    // because nothing re-sent. The echo is how the app tells the two apart.
    func testRegisterPushReportsWhetherTheHostStoredTheHiddenSet() async throws {
        let current = makeClient(body: #"{"ok":true,"env":"production","hiddenDirs":2}"#)
        let stored = try await current.registerPush(token: "00ab", env: "production", owner: nil, hiddenDirs: ["/a", "*/b-*"])
        XCTAssertTrue(stored)

        let older = makeClient(body: #"{"ok":true,"env":"production"}"#)
        let dropped = try await older.registerPush(token: "00ab", env: "production", owner: nil, hiddenDirs: ["/a"])
        XCTAssertFalse(dropped)
    }

    private func requestObject(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody ?? requestBodyStreamData(request))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// `body` is the JSON the stub server answers with; the default (nil) keeps
    /// the original empty 204 used by the fire-and-forget registration calls.
    private func makeClient(body: String? = nil) -> LFGClient {
        RequestCapturingURLProtocol.responseBody = body
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RequestCapturingURLProtocol.self]
        return LFGClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
    }

    private func requestBody(_ request: URLRequest) throws -> [String: String] {
        let data = try XCTUnwrap(request.httpBody ?? requestBodyStreamData(request))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: String])
    }

    private func requestBodyStreamData(_ request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}

private final class RequestCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requestStore: URLRequest?
    nonisolated(unsafe) static var responseBody: String?

    static var capturedRequest: URLRequest? { requestStore }

    static func reset() {
        requestStore = nil
        responseBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestStore = request
        let payload = Self.responseBody.map { Data($0.utf8) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: payload == nil ? 204 : 200,
            httpVersion: nil,
            headerFields: payload == nil ? nil : ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
