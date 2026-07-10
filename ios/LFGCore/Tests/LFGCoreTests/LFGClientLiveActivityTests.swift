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

    func testRegisterLiveActivityUpdateTokenPostsExpectedBody() async throws {
        let client = makeClient()

        try await client.registerLiveActivityUpdateToken("ff09", env: "prod", sessionId: "session-123")

        let request = try XCTUnwrap(RequestCapturingURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/push/live-activity/update-token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try requestBody(request), [
            "token": "ff09",
            "env": "prod",
            "sessionId": "session-123",
        ])
    }

    private func makeClient() -> LFGClient {
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

    static var capturedRequest: URLRequest? { requestStore }

    static func reset() {
        requestStore = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestStore = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
