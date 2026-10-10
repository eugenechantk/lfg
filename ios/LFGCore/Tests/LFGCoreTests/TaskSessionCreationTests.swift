import Foundation
import XCTest
@testable import LFGCore

final class TaskSessionCreationTests: XCTestCase {
    func testCreationUsesTaskEndpointAndSelectedOptions() async throws {
        TaskCreationProtocol.status = 200
        TaskCreationProtocol.body = Data(#"{"sessionId":"task-setup"}"#.utf8)
        let response = try await client().newSession(.init(cwd: "/project", prompt: "Review every morning",
            agent: "codex", model: "gpt-6.1-sol", user: "Eugene", purpose: .scheduledTask, timezone: "Europe/London"))
        XCTAssertEqual(response.sessionId, "task-setup")
        let request = try XCTUnwrap(TaskCreationProtocol.request)
        XCTAssertEqual(request.url?.absoluteString, "https://source.test/api/scheduled-tasks/chat")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(TaskCreationProtocol.sentBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(payload, ["cwd": "/project", "prompt": "Review every morning", "agent": "codex",
            "model": "gpt-6.1-sol", "user": "Eugene", "timezone": "Europe/London"])
    }

    func testNormalCreationAndOlderSavedRequestsKeepOriginalRoute() async throws {
        TaskCreationProtocol.status = 200
        TaskCreationProtocol.body = Data(#"{"sessionId":"ordinary"}"#.utf8)
        let old = try JSONDecoder().decode(NewSessionRequest.self, from: Data(#"{"cwd":"/project","prompt":"Hello"}"#.utf8))
        XCTAssertNil(old.purpose)
        _ = try await client().newSession(old)
        XCTAssertEqual(TaskCreationProtocol.request?.url?.path, "/api/sessions/new")
        let task = NewSessionRequest(cwd: "/project", prompt: "Schedule", purpose: .scheduledTask, timezone: "UTC")
        let restored = try JSONDecoder().decode(NewSessionRequest.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(restored.purpose, .scheduledTask)
        XCTAssertEqual(restored.timezone, "UTC")
    }

    func testUnsupportedHostDoesNotExecuteRequestAsOrdinarySession() async throws {
        TaskCreationProtocol.status = 404
        TaskCreationProtocol.body = Data(#"{"error":"not found"}"#.utf8)
        do {
            _ = try await client().newSession(.init(cwd: "/project", prompt: "Delete old files tomorrow", purpose: .scheduledTask))
            XCTFail("Unsupported task setup must fail")
        } catch { }
        XCTAssertEqual(TaskCreationProtocol.request?.url?.path, "/api/scheduled-tasks/chat")
    }

    func testSetupInstructionsAreHiddenFromUserBubbleAndAttachmentsPreserved() {
        let wrapper = "Help the user create an LFG scheduled task. Tool: /private/internal/script.ts\nThe user's request follows:\nReview tomorrow\n[notes](/tmp/notes.pdf)"
        let row = TranscriptRowText.derive(from: wrapper, extractFollowups: false)
        XCTAssertFalse(row.displayText.contains("Help the user"))
        XCTAssertFalse(row.displayText.contains("internal"))
        XCTAssertTrue(row.displayText.contains("Review tomorrow"))
        XCTAssertEqual(row.media.count, 1)
        XCTAssertTrue(TranscriptRowText.derive(from: wrapper).prose.contains("Help the user"))
    }

    func testShortKickoffReconcilesAgainstWrappedTranscript() {
        let message = SessionMessage(id: "setup", role: "user", kind: "text",
            text: "Help the user create an LFG scheduled task\nThe user's request follows:\nHi", ts: 1000)
        XCTAssertTrue(OptimisticSendReconciliation.containsMatchingUserTurn(matchText: "Hi", sentAt: 1000, in: [message]))
        XCTAssertFalse(OptimisticSendReconciliation.containsMatchingUserTurn(matchText: "No", sentAt: 1000, in: [message]))
    }

    private func client() -> LFGClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TaskCreationProtocol.self]
        return LFGClient(baseURL: URL(string: "https://source.test")!, session: URLSession(configuration: config))
    }
}

private final class TaskCreationProtocol: URLProtocol {
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
