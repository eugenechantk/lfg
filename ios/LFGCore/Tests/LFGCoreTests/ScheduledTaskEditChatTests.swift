import Foundation
import Testing
@testable import LFGCore

@Suite(.serialized) struct ScheduledTaskEditChatTests {
    private func client(status: Int = 200, response: String) -> ScheduledTasksClient {
        EditChatProtocol.status = status
        EditChatProtocol.body = Data(response.utf8)
        EditChatProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EditChatProtocol.self]
        return ScheduledTasksClient(host: .init(id: "air", name: "Air", baseURL: URL(string: "https://task-host.test")!,
            headers: ["Authorization": "fixture-token"]), session: URLSession(configuration: config))
    }

    @Test func startsOneSessionOnTheTaskHostWithoutSavingOrRunningTask() async throws {
        let client = client(response: #"{"sessionId":"new-edit-session"}"#)
        #expect(try await client.startEditingChat("task-a") == "new-edit-session")
        let request = try #require(EditChatProtocol.requests.first)
        #expect(EditChatProtocol.requests.count == 1)
        #expect(request.url?.absoluteString == "https://task-host.test/api/scheduled-tasks/task-a/chat")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "fixture-token")
        let payload = try #require(JSONSerialization.jsonObject(with: EditChatProtocol.sentBody) as? [String: String])
        #expect(Set(payload.keys) == ["prompt"])
        #expect(payload["prompt"]?.contains("Ask me what I would like to change") == true)
    }

    @Test(arguments: [#"{}"#, #"{"sessionId":""}"#, #"{"sessionId":"  "}"#])
    func missingSessionIdentityDoesNotNavigate(_ response: String) async throws {
        let client = client(response: response)
        await #expect(throws: ScheduledTaskClientError.self) { try await client.startEditingChat("task-a") }
        #expect(EditChatProtocol.requests.count == 1)
    }

    @Test func hostErrorIsVisibleWithoutFallbackOrAutomaticRetry() async throws {
        let client = client(status: 409, response: #"{"error":"This task has been cancelled."}"#)
        do {
            _ = try await client.startEditingChat("task-a")
            Issue.record("Expected the host error")
        } catch {
            #expect(error.localizedDescription == "This task has been cancelled.")
        }
        #expect(EditChatProtocol.requests.count == 1)
    }
}

private final class EditChatProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var sentBody = Data()
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        Self.sentBody = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                Self.sentBody.append(buffer, count: count)
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
