import Foundation
import Testing
@testable import LFGCore

@Suite @MainActor
struct IPhonePreviewLifecycleTests {
    @Test func discoveryDoesNotStartCapture() async {
        let transport = PreviewTransport()
        let preview = IPhonePreviewSession(transport: transport)
        await preview.load()
        #expect(preview.selectedDeviceID == "hihi")
        #expect(!preview.isEnabled)
        #expect(preview.frame == nil)
        #expect(await transport.controls.isEmpty)
    }

    @Test func offWaitsForPendingStartAndNeverAcceptsLateFrames() async throws {
        let transport = PreviewTransport()
        await transport.holdStart()
        let preview = IPhonePreviewSession(transport: transport)
        await preview.load()
        let start = preview.setEnabled(true)
        try await wait { await transport.controls == [true] }
        let stop = preview.setEnabled(false)
        #expect(!preview.isEnabled)
        #expect(preview.frame == nil)
        await transport.releaseStart()
        await start.value
        await stop.value
        #expect(await transport.controls == [true, false])
        #expect(await transport.frameCalls == 0)
        #expect(!preview.isEnabled && !preview.isChanging)
    }

    @Test func lateFrameAfterDismissIsDiscarded() async throws {
        let transport = PreviewTransport()
        let preview = IPhonePreviewSession(transport: transport)
        await preview.load()
        await preview.setEnabled(true).value
        try await wait { await transport.frameCalls == 1 }
        preview.stop()
        try await wait { await transport.controls == [true, false] }
        await transport.releaseFrame(Data([0xff, 0xd8, 1, 0xff, 0xd9]))
        for _ in 0..<20 { await Task.yield() }
        #expect(preview.frame == nil)
        #expect(!preview.isEnabled)
    }

    @Test func framesClearOnOffAndMissingFrame() async throws {
        let transport = PreviewTransport()
        let preview = IPhonePreviewSession(transport: transport)
        await preview.load()
        await preview.setEnabled(true).value
        try await wait { await transport.frameCalls == 1 }
        await transport.releaseFrame(Data([1, 2]))
        try await wait { preview.frame != nil }
        try await wait { await transport.frameCalls == 2 }
        await transport.releaseFrame(nil)
        try await wait { preview.frame == nil }
        await preview.setEnabled(false).value
        #expect(!preview.isEnabled)
    }

    @Test func disconnectedFrameStopsAndRequiresExplicitRetry() async throws {
        let transport = PreviewTransport()
        let preview = IPhonePreviewSession(transport: transport)
        await preview.load()
        await preview.setEnabled(true).value
        try await wait { await transport.frameCalls == 1 }
        await transport.failFrame()
        try await wait { preview.error != nil }
        #expect(!preview.isEnabled)
        #expect(preview.frame == nil)
        #expect(await transport.controls == [true, false])
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { throw PreviewTestError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum PreviewTestError: Error { case timeout, disconnected }
private actor PreviewTransport: IPhonePreviewTransport {
    var controls: [Bool] = []
    var frameCalls = 0
    private var blocksStart = false
    private var start: CheckedContinuation<Void, Never>?
    private var frame: CheckedContinuation<Data?, any Error>?
    func holdStart() { blocksStart = true }
    func releaseStart() { start?.resume(); start = nil }
    func releaseFrame(_ data: Data?) { frame?.resume(returning: data); frame = nil }
    func failFrame() { frame?.resume(throwing: PreviewTestError.disconnected); frame = nil }
    func iPhonePreviewDevices() async throws -> [IPhonePreviewDevice] { [.init(id: "hihi", name: "hihi")] }
    func setIPhonePreview(_ device: String, enabled: Bool) async throws {
        controls.append(enabled)
        if enabled && blocksStart { await withCheckedContinuation { start = $0 } }
    }
    func iPhonePreviewFrame(_ device: String) async throws -> Data? {
        frameCalls += 1
        return try await withCheckedThrowingContinuation { frame = $0 }
    }
}

@Suite(.serialized)
struct IPhonePreviewClientTests {
    @Test func transportUsesHostCredentialsAndDoesNotCacheFrames() async throws {
        PreviewURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PreviewURLProtocol.self]
        let client = LFGClient(baseURL: URL(string: "https://owning-host.example")!, session: URLSession(configuration: config),
            accessCredential: .init(clientID: "client", clientSecret: "secret"))
        PreviewURLProtocol.body = Data(#"{"devices":[{"id":"hihi","name":"hihi"}]}"#.utf8)
        #expect(try await client.iPhonePreviewDevices().first?.id == "hihi")
        PreviewURLProtocol.body = Data("{}".utf8)
        try await client.setIPhonePreview("hihi", enabled: true)
        PreviewURLProtocol.body = Data([0xff, 0xd8, 3, 0xff, 0xd9])
        #expect(try await client.iPhonePreviewFrame("hihi") == PreviewURLProtocol.body)
        for request in PreviewURLProtocol.requests {
            #expect(request.url?.host == "owning-host.example")
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "client")
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "secret")
            #expect(request.url?.query == nil)
        }
        #expect(PreviewURLProtocol.requests.last?.cachePolicy == .reloadIgnoringLocalCacheData)
        PreviewURLProtocol.body = Data()
        #expect(try await client.iPhonePreviewFrame("hihi") == nil)
        PreviewURLProtocol.body = Data("<html>login</html>".utf8)
        await #expect(throws: (any Error).self) { try await client.iPhonePreviewFrame("hihi") }
        await #expect(throws: (any Error).self) { try await client.setIPhonePreview("../other", enabled: true) }
    }
}

private final class PreviewURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
