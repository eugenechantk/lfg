import XCTest
@testable import LFGCore

final class CloudflareAccessTests: XCTestCase {
    private let credential = CloudflareAccessCredential(
        clientID: "device-id.access",
        clientSecret: "device-secret"
    )

    override func setUp() {
        super.setUp()
        AccessCapturingURLProtocol.reset()
    }

    func testPreparedBackgroundSendCarriesAccessHeaders() throws {
        let client = makeClient()

        let request = try client.sendMessageRequest("session-1", text: "hello")

        assertCredential(on: request)
    }

    func testRESTAndUploadRequestsCarryAccessHeaders() async throws {
        let client = makeClient()

        _ = await client.ping()
        assertCredential(on: try XCTUnwrap(AccessCapturingURLProtocol.lastRequest))

        AccessCapturingURLProtocol.responseBody = Data(#"{"path":"/tmp/upload.png"}"#.utf8)
        _ = try await client.upload(
            "session-1",
            data: Data([0x89, 0x50]),
            contentType: "image/png",
            filename: "upload.png"
        )
        assertCredential(on: try XCTUnwrap(AccessCapturingURLProtocol.lastRequest))
    }

    func testEventStreamCarriesAccessHeaders() async throws {
        AccessCapturingURLProtocol.responseHeaders = ["Content-Type": "text/event-stream"]
        AccessCapturingURLProtocol.responseBody = Data(": hb 0\n\n".utf8)
        let client = makeClient()

        var iterator = client.events(since: 0).makeAsyncIterator()
        _ = try await iterator.next()

        assertCredential(on: try XCTUnwrap(AccessCapturingURLProtocol.lastRequest))
    }

    func testSameOriginResourceRequestCarriesCredential() throws {
        let client = makeClient()

        let request = client.resourceRequest(
            for: URL(string: "https://lfg-pro.omg.dev/api/file?path=%2Ftmp%2Fx.png")!
        )

        assertCredential(on: request)
    }

    func testExternalResourceNeverReceivesCredential() {
        let client = makeClient()

        let request = client.resourceRequest(
            for: URL(string: "https://images.example.com/public.png")!
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Id"))
        XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"))
    }

    func testDifferentPortIsNotTreatedAsSameOrigin() {
        let client = makeClient()

        let request = client.resourceRequest(
            for: URL(string: "https://lfg-pro.omg.dev:8443/api/file")!
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Id"))
        XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"))
    }

    func testClientWithoutCredentialPreservesExistingRequests() throws {
        let client = LFGClient(baseURL: URL(string: "http://100.64.0.1:8766")!)

        let request = try client.sendMessageRequest("session-1", text: "hello")

        XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Id"))
        XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"))
    }

    private func makeClient() -> LFGClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccessCapturingURLProtocol.self]
        return LFGClient(
            baseURL: URL(string: "https://lfg-pro.omg.dev")!,
            session: URLSession(configuration: config),
            accessCredential: credential
        )
    }

    private func assertCredential(on request: URLRequest,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "CF-Access-Client-Id"),
            credential.clientID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "CF-Access-Client-Secret"),
            credential.clientSecret,
            file: file,
            line: line
        )
    }
}

private final class AccessCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var responseBody = Data(#"{"ok":true,"seq":0}"#.utf8)
    nonisolated(unsafe) static var responseHeaders = ["Content-Type": "application/json"]

    static func reset() {
        lastRequest = nil
        responseBody = Data(#"{"ok":true,"seq":0}"#.utf8)
        responseHeaders = ["Content-Type": "application/json"]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: Self.responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
