import Foundation
import XCTest
@testable import LFGCore

/// `interrupt` used to discard its response, because the server had nothing
/// useful to say — `{"ok":true}` came from `tmux send-keys`' exit code, which is
/// 0 whenever the pane exists. The server now confirms against the pane and
/// returns `stopped`, and the client has to carry that through or Stop keeps
/// reporting success against a wedged agent.
/// See `.claude/diagnosis-stop-close-noop-20260806.md`.
final class LFGClientInterruptTests: XCTestCase {
    override func tearDown() {
        StubbedResponseURLProtocol.reset()
        super.tearDown()
    }

    func testInterruptPostsToTheSessionsInterruptPath() async throws {
        StubbedResponseURLProtocol.body = Data(#"{"ok":true,"stopped":true}"#.utf8)
        _ = try await makeClient().interrupt("session-123")

        let request = try XCTUnwrap(StubbedResponseURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/sessions/session-123/interrupt")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testReportsStoppedWhenTheTurnActuallyEnded() async throws {
        StubbedResponseURLProtocol.body = Data(#"{"ok":true,"stopped":true}"#.utf8)
        let stopped = try await makeClient().interrupt("s")
        XCTAssertEqual(stopped, true)
    }

    /// THE case: the Escape landed, the agent ignored it. Reported as `false`,
    /// never swallowed into a success.
    func testReportsNotStoppedWhenTheAgentIgnoredTheEscape() async throws {
        StubbedResponseURLProtocol.body = Data(#"{"ok":true,"stopped":false}"#.utf8)
        let stopped = try await makeClient().interrupt("s")
        XCTAssertEqual(stopped, false)
    }

    /// The pane could not be scraped — "unknown", which callers must not treat as
    /// either outcome.
    func testUnscrapeablePaneDecodesAsNil() async throws {
        StubbedResponseURLProtocol.body = Data(#"{"ok":true,"stopped":null}"#.utf8)
        let stopped = try await makeClient().interrupt("s")
        XCTAssertNil(stopped)
    }

    /// An older server that predates the field must not crash or read as stopped.
    func testOlderServerWithoutTheFieldDecodesAsNil() async throws {
        StubbedResponseURLProtocol.body = Data(#"{"ok":true}"#.utf8)
        let stopped = try await makeClient().interrupt("s")
        XCTAssertNil(stopped)
    }

    func testNonJSONBodyDecodesAsNilRatherThanThrowing() async throws {
        StubbedResponseURLProtocol.body = Data("not json".utf8)
        let stopped = try await makeClient().interrupt("s")
        XCTAssertNil(stopped)
    }

    private func makeClient() -> LFGClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubbedResponseURLProtocol.self]
        return LFGClient(baseURL: URL(string: "https://example.test")!,
                         session: URLSession(configuration: config))
    }
}

private final class StubbedResponseURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requestStore: URLRequest?
    nonisolated(unsafe) static var body = Data()

    static var capturedRequest: URLRequest? { requestStore }

    static func reset() {
        requestStore = nil
        body = Data()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestStore = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
