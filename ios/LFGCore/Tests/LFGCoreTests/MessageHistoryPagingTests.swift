import Foundation
import Testing
@testable import LFGCore

@Suite("Cloudflare-safe transcript history paging", .serialized)
struct MessageHistoryPagingTests {
    private let credential = CloudflareAccessCredential(
        clientID: "history-device.access",
        clientSecret: "history-secret"
    )

    @Test("yields the newest bounded page before requesting older cursors")
    func yieldsNewestPageFirst() async throws {
        HistoryPagingURLProtocol.reset(messages: Self.messages(count: 5))
        var iterator = makeClient()
            .messageHistoryPages("session-1", limit: 5, pageSize: 2)
            .makeAsyncIterator()

        let newest = try #require(try await iterator.next())
        #expect(newest.compactMap(\.id) == ["m3", "m4"])
        #expect(HistoryPagingURLProtocol.requests().count == 1)

        let middle = try #require(try await iterator.next())
        let oldest = try #require(try await iterator.next())
        #expect(middle.compactMap(\.id) == ["m1", "m2"])
        #expect(oldest.compactMap(\.id) == ["m0"])
        #expect(try await iterator.next() == nil)

        let requests = HistoryPagingURLProtocol.requests()
        #expect(requests.map { $0.queryValue("page") } == ["backward", "backward", "backward"])
        #expect(requests.map { $0.queryValue("limit") } == ["2", "2", "1"])
        #expect(requests.map { $0.queryValue("before") } == [nil, "3", "1"])
        // The FIRST page is deliberately much smaller than the rest: it is the
        // only page the user is waiting on, so it crosses a slow link sooner.
        // Later pages land above content already on screen.
        #expect(requests.map { $0.queryValue("maxBytes") } == ["49152", "262144", "262144"])
    }

    @Test("stops after a server repeats its backward cursor")
    func repeatedCursorCannotLoop() async throws {
        HistoryPagingURLProtocol.reset(
            messages: Self.messages(count: 6),
            repeatsCursor: true
        )
        var pages: [[SessionMessage]] = []

        for try await page in makeClient().messageHistoryPages(
            "session-1",
            limit: 5_000,
            pageSize: 2
        ) {
            pages.append(page)
        }

        #expect(pages.count == 2)
        #expect(HistoryPagingURLProtocol.requests().count == 2)
    }

    @Test("clamps the load to 5000 messages and shrinks the final request")
    func preservesHistoryCap() async throws {
        HistoryPagingURLProtocol.reset(messages: Self.messages(count: 5_001))
        var received = 0

        for try await page in makeClient().messageHistoryPages(
            "session-1",
            limit: 6_000,
            pageSize: 333
        ) {
            received += page.count
        }

        #expect(received == 5_000)
        let requests = HistoryPagingURLProtocol.requests()
        #expect(requests.count == 16)
        #expect(requests.last?.queryValue("limit") == "5")
    }

    @Test("authenticates every history page through Cloudflare Access")
    func authenticatesEveryPage() async throws {
        HistoryPagingURLProtocol.reset(messages: Self.messages(count: 5))

        for try await _ in makeClient().messageHistoryPages(
            "session-1",
            limit: 5,
            pageSize: 2
        ) {}

        let requests = HistoryPagingURLProtocol.requests()
        #expect(requests.count == 3)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == credential.clientID)
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == credential.clientSecret)
        }
    }

    @Test("retries a transient older page at the same cursor instead of restarting at newest")
    func retriesFailedCursorInPlace() async throws {
        HistoryPagingURLProtocol.reset(
            messages: Self.messages(count: 5),
            failRequestNumberOnce: 2
        )
        var pages: [[SessionMessage]] = []

        for try await page in makeClient().messageHistoryPages(
            "session-1",
            limit: 5,
            pageSize: 2,
            pageRetryDelay: .zero
        ) {
            pages.append(page)
        }

        #expect(pages.flatMap { $0 }.compactMap(\.id) == ["m3", "m4", "m1", "m2", "m0"])
        let requests = HistoryPagingURLProtocol.requests()
        #expect(requests.map { $0.queryValue("before") } == [nil, "3", "3", "1"])
    }

    @Test("requests a small first page, then full-size pages through the same cursor")
    func firstPageUsesASmallerByteBudget() async throws {
        HistoryPagingURLProtocol.reset(messages: Self.messages(count: 5))
        for try await _ in makeClient().messageHistoryPages(
            "session-1", limit: 5, pageSize: 2
        ) {}

        let requests = HistoryPagingURLProtocol.requests()
        let budgets = requests.map { $0.queryValue("maxBytes") }
        #expect(budgets.first == "49152")
        #expect(budgets.dropFirst().allSatisfy { $0 == "262144" })
        // The cursor walk itself must be untouched by the smaller first page.
        #expect(requests.map { $0.queryValue("before") } == [nil, "3", "1"])
    }

    @Test("a retry of the first page keeps the small budget")
    func firstPageRetryStaysSmall() async throws {
        HistoryPagingURLProtocol.reset(
            messages: Self.messages(count: 4),
            failRequestNumberOnce: 1
        )
        for try await _ in makeClient().messageHistoryPages(
            "session-1", limit: 4, pageSize: 2, pageRetryDelay: .zero
        ) {}

        let budgets = HistoryPagingURLProtocol.requests().map { $0.queryValue("maxBytes") }
        // Both the failed attempt and its retry are still the first page.
        #expect(budgets.prefix(2).allSatisfy { $0 == "49152" })
    }

    @Test("opting out of the small first page restores one uniform budget")
    func firstPageBudgetIsOptional() async throws {
        HistoryPagingURLProtocol.reset(messages: Self.messages(count: 5))
        for try await _ in makeClient().messageHistoryPages(
            "session-1", limit: 5, pageSize: 2, firstPageByteLimit: nil
        ) {}
        let budgets = HistoryPagingURLProtocol.requests().map { $0.queryValue("maxBytes") }
        #expect(budgets.allSatisfy { $0 == "262144" })
    }

    private func makeClient() -> LFGClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HistoryPagingURLProtocol.self]
        return LFGClient(
            baseURL: URL(string: "https://lfg-pro.example.com")!,
            session: URLSession(configuration: configuration),
            accessCredential: credential
        )
    }

    private static func messages(count: Int) -> [SessionMessage] {
        (0..<count).map {
            SessionMessage(
                id: "m\($0)",
                role: $0.isMultiple(of: 2) ? "user" : "assistant",
                text: "message \($0)",
                ts: Double($0)
            )
        }
    }
}

private final class HistoryPagingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var transcript: [SessionMessage] = []
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) private static var repeatsCursor = false
    nonisolated(unsafe) private static var failRequestNumberOnce: Int?

    static func reset(
        messages: [SessionMessage],
        repeatsCursor: Bool = false,
        failRequestNumberOnce: Int? = nil
    ) {
        lock.withLock {
            transcript = messages
            capturedRequests = []
            self.repeatsCursor = repeatsCursor
            self.failRequestNumberOnce = failRequestNumberOnce
        }
    }

    static func requests() -> [URLRequest] {
        lock.withLock { capturedRequests }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (messages, shouldRepeat, shouldFail): ([SessionMessage], Bool, Bool) = Self.lock.withLock {
            Self.capturedRequests.append(request)
            let requestNumber = Self.capturedRequests.count
            let shouldFail = requestNumber == Self.failRequestNumberOnce
            if shouldFail { Self.failRequestNumberOnce = nil }
            return (Self.transcript, Self.repeatsCursor, shouldFail)
        }
        if shouldFail {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 504,
                httpVersion: "HTTP/2",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"error":"gateway timeout"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let limit = max(1, Int(components?.queryItems?.first { $0.name == "limit" }.flatMap(\.value) ?? "") ?? 220)
        let requestedBefore = Int(
            components?.queryItems?.first { $0.name == "before" }.flatMap(\.value) ?? ""
        )
        let end = max(0, min(messages.count, requestedBefore ?? messages.count))
        let start = max(0, end - limit)
        let nextBefore: Int? = if shouldRepeat, let requestedBefore {
            requestedBefore
        } else {
            start > 0 ? start : nil
        }
        let body = try! JSONEncoder().encode(MessagesResponse(
            id: "session-1",
            messages: Array(messages[start..<end]),
            total: messages.count,
            nextBefore: nextBefore
        ))
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/2",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}
