import Foundation
import Testing
@testable import LFGCore

@Suite struct MessageSpacesTests {
    private func decode(_ changes: String = "") throws -> MessageSpace {
        try JSONDecoder().decode(MessageSpace.self, from: Data("""
        {"id":"a","name":"Scout","spaceID":"local:a","agent":"claude-code","powerState":"running","messages":[],"createdAt":1\(changes)}
        """.utf8))
    }
    @Test func confirmedSpaceAcceptsWork() throws { #expect(try decode().canSend) }
    @Test func uncertainOperationBlocksAnotherSend() throws { #expect(try !decode(",\"pending\":\"request\"").canSend) }
    @Test func stoppedSpaceCannotAcceptWork() throws {
        var space = try decode(); space.powerState = "stopped"; #expect(!space.canSend)
        space.powerState = "running"; space.spaceID = nil; #expect(!space.canSend)
    }
    @Test func eventsHideInternalThoughts() throws {
        let data = Data("{\"seq\":1,\"kind\":\"message\",\"text\":\"Done\",\"ts_ms\":100}".utf8)
        var event = try JSONDecoder().decode(SpaceAgentEvent.self, from: data)
        #expect(event.displayText == "Done"); #expect(event.isVisible)
        event.kind = "thought"; #expect(!event.isVisible)
    }
}

@Suite(.serialized) struct MessageSpacesClientTests {
    private func client() -> MessageSpacesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessageSpaceProtocol.self]
        return MessageSpacesClient(host: ScheduledTaskHost(id: "air", name: "Air", baseURL: URL(string: "https://air.test")!,
            headers: ["CF-Access-Client-Id": "test-client"]), session: URLSession(configuration: configuration))
    }
    @Test func sendsToSelectedHostWithCredentialsAndStableRequestID() async throws {
        MessageSpaceProtocol.status = 200
        MessageSpaceProtocol.response = #"{"space":{"id":"a","name":"Scout","spaceID":"local:a","agent":"claude-code","powerState":"running","messages":[],"createdAt":1}}"#
        let space = try await client().send("a", text: "Read the docs", requestID: "one-message")
        #expect(space.id == "a")
        #expect(MessageSpaceProtocol.url?.absoluteString == "https://air.test/api/message/spaces/a/messages")
        #expect(MessageSpaceProtocol.header == "test-client")
        let payload = try JSONSerialization.jsonObject(with: MessageSpaceProtocol.sent) as? [String: String]
        #expect(payload?["requestID"] == "one-message")
        #expect(payload?["text"] == "Read the docs")
    }
    @Test func displaysProviderSetupFailureWithoutDecodingItAsAConversation() async throws {
        MessageSpaceProtocol.status = 503
        MessageSpaceProtocol.response = #"{"error":"Configure a provider key in Cua"}"#
        do {
            _ = try await client().send("a", text: "Work", requestID: "missing-auth")
            Issue.record("Expected a setup error")
        } catch {
            #expect(error.localizedDescription == "Configure a provider key in Cua")
        }
    }
}

private final class MessageSpaceProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var response = "{}"
    nonisolated(unsafe) static var sent = Data()
    nonisolated(unsafe) static var url: URL?
    nonisolated(unsafe) static var header: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.url = request.url; Self.header = request.value(forHTTPHeaderField: "CF-Access-Client-Id")
        Self.sent = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                Self.sent.append(buffer, count: count)
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite struct MessageSpaceTranscriptTests {
    @Test func joinsStreamedWordsAndHidesRawToolResults() throws {
        let data = Data(#"[{"seq":1,"kind":"message","text":"The page","ts_ms":1},{"seq":2,"kind":"message","text":" is Example Domain.","ts_ms":2},{"seq":3,"kind":"tool_call","summary":"Tool mcp__cua-driver__get_window_state","ts_ms":3},{"seq":4,"kind":"tool_update","text":"HUGE RAW ACCESSIBILITY TREE","ts_ms":4},{"seq":5,"kind":"message","text":"Done.","ts_ms":5}]"#.utf8)
        let events = try JSONDecoder().decode([SpaceAgentEvent].self, from: data)
        let rows = MessageSpaceTranscript.rows(messages: [], events: events)
        #expect(rows.map(\.text) == ["The page is Example Domain.", "Inspecting the browser", "Done."])
        #expect(rows.map(\.id) == ["event-1", "event-3", "event-5"])
    }
    @Test func turnBoundariesKeepRepliesSeparate() throws {
        let data = Data(#"[{"seq":1,"kind":"message","text":"First","ts_ms":1},{"seq":2,"kind":"turn_ended","ts_ms":2},{"seq":3,"kind":"turn_started","category":"user","text":"Second request","ts_ms":3},{"seq":4,"kind":"message","text":"Second","ts_ms":4}]"#.utf8)
        let events = try JSONDecoder().decode([SpaceAgentEvent].self, from: data)
        #expect(MessageSpaceTranscript.rows(messages: [], events: events).map(\.text) == ["First", "Second"])
    }
}
