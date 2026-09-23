import Foundation
import XCTest
@testable import LFGCore

final class LFGClientHandoffTests: XCTestCase {
    func testHandoffTargetsSourceHostAndReturnsNewCodexIdentity() async throws {
        HandoffProtocol.body = Data(#"{"ok":true,"sessionId":"new-codex","agent":"codex","cwd":"/project","tmuxName":"lfg-new"}"#.utf8)
        HandoffProtocol.status = 200
        let result = try await client().handoff(sessionId: "source-claude", to: AgentModelSelection(agent: .codex, model: "gpt-5.6-sol"))
        XCTAssertEqual(result.sessionId, "new-codex")
        let request = try XCTUnwrap(HandoffProtocol.request)
        XCTAssertEqual(request.url?.absoluteString, "https://source.test/api/sessions/handoff")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 90)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testReverseHandoffForwardsSelectedClaudeModel() async throws {
        HandoffProtocol.body = Data(#"{"ok":true,"sessionId":"new-claude","agent":"claude"}"#.utf8)
        HandoffProtocol.status = 200
        let result = try await client().handoff(sessionId: "source-codex", to: AgentModelSelection(agent: .claude, model: "claude-sonnet-5"))
        XCTAssertEqual(result.sessionId, "new-claude")
        let body = try XCTUnwrap(HandoffProtocol.sentBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["sessionId"] as? String, "source-codex")
        XCTAssertEqual(payload["agent"] as? String, "claude")
        XCTAssertEqual(payload["model"] as? String, "claude-sonnet-5")
    }

    func testInvalidSuccessNeverSelectsSourceOrUnboundSession() async throws {
        HandoffProtocol.status = 200
        for body in [
            #"{"ok":true,"sessionId":null,"agent":"codex"}"#,
            #"{"ok":true,"sessionId":"source","agent":"codex"}"#,
            #"{"ok":false,"sessionId":"new","agent":"codex"}"#,
            #"{"ok":true,"sessionId":"new","agent":"claude"}"#,
        ] {
            HandoffProtocol.body = Data(body.utf8)
            do {
                _ = try await client().handoff(sessionId: "source", to: AgentModelSelection(agent: .codex, model: "gpt-5.6-sol"))
                XCTFail("Invalid handoff response was accepted")
            } catch { }
        }
    }

    func testOlderHostAndMissingSourceSurfaceErrors() async throws {
        HandoffProtocol.status = 404
        HandoffProtocol.body = Data(#"{"error":"not found"}"#.utf8)
        do {
            _ = try await client().handoff(sessionId: "source", to: AgentModelSelection(agent: .codex, model: "gpt-5.6-sol"))
            XCTFail("404 was swallowed")
        } catch { }
    }

    private func client() -> LFGClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HandoffProtocol.self]
        return LFGClient(baseURL: URL(string: "https://source.test")!, session: URLSession(configuration: config))
    }
}

private final class HandoffProtocol: URLProtocol {
    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var sentBody: Data?
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        Self.sentBody = request.httpBody
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            Self.sentBody = data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
