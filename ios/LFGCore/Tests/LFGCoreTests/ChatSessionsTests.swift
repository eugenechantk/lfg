import Foundation
import Testing
@testable import LFGCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite(.serialized) struct ChatSessionsTests {
    @Test func chatListKeepsRuntimeStatusSeparateFromHostConnectivityAndPrivateSettings() throws {
        var chat = try JSONDecoder().decode(ChatSessionRecord.self, from: Data(Self.sessionJSON.utf8))
        #expect(ChatPresentation.states == ["blocked", "working", "idle"])
        #expect(ChatPresentation.preview(chat) == "Ready for your message")
        chat.lastMessage = ChatMessagePreview(text: "Here is your reading list", role: "assistant")
        #expect(ChatPresentation.preview(chat) == "Here is your reading list")
        #expect(ChatPresentation.preview(chat, offline: true) == "Here is your reading list")
        #expect(ChatPresentation.matches(chat, query: "READING"))
        #expect(!ChatPresentation.matches(chat, query: "Pip"))
        chat.state = "working"
        #expect(ChatPresentation.preview(chat) == "Working…")
        chat.state = "blocked"; chat.error = "Sign in on the host"
        #expect(ChatPresentation.preview(chat) == "Sign in on the host")
        #expect(ChatPresentation.title(for: chat.state) == "Paused")
        #expect(ChatPresentation.modelLabel(nil) == "Claude · Default")
    }
    @Test func activityTimesStayCompactAndHandleClockSkew() {
        let now = Date(timeIntervalSince1970: 200_000)
        #expect(ChatPresentation.activityLabel(200_000_000, now: now) == "1m")
        #expect(ChatPresentation.activityLabel(201_000_000, now: now) == "1m")
        #expect(ChatPresentation.activityLabel(199_280_000, now: now) == "12m")
        #expect(ChatPresentation.activityLabel(185_600_000, now: now) == "4h")
        #expect(ChatPresentation.activityLabel(27_200_000, now: now) == "2d")
    }
    @Test func decodesDurableSessionAndKeepsMessageIdentityWhenTextStreams() throws {
        let session = try JSONDecoder().decode(ChatSessionRecord.self, from: Data(Self.sessionJSON.utf8))
        #expect(session.canSend)
        #expect(session.instructions == "Be concise")
        #expect(session.memory == "Pip is my dog")
        let first = ChatMessageRecord(id: "one", sequence: 1, role: "assistant", text: "Hi", ts: 1, requestID: "request")
        let updated = ChatMessageRecord(id: "one", sequence: 1, role: "assistant", text: "Hi there", ts: 2, requestID: "request")
        #expect(ChatHistoryMerge.merge([first], [updated]).map(\.text) == ["Hi there"])
    }
    @Test func sendAndSettingsUseDurableSessionRoutesAndHostAuthentication() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatURLProtocol.self]
        let host = ScheduledTaskHost(id: "host", name: "Pro", baseURL: URL(string: "http://chat.test")!, headers: ["CF-Access-Client-Id": "fixture"])
        let client = ChatSessionsClient(host: host, session: URLSession(configuration: config))
        ChatURLProtocol.status = 202; ChatURLProtocol.response = "{}"
        try await client.send("chat-one", text: "Hello", requestID: "stable-request")
        #expect(ChatURLProtocol.url?.path == "/api/sessions/chat-one/send")
        #expect(ChatURLProtocol.header == "fixture")
        let body = try JSONSerialization.jsonObject(with: ChatURLProtocol.sent) as? [String: Any]
        #expect(body?["requestID"] as? String == "stable-request")
        ChatURLProtocol.status = 200; ChatURLProtocol.response = "{\"session\":" + Self.sessionJSON + "}"
        let record = try JSONDecoder().decode(ChatSessionRecord.self, from: Data(Self.sessionJSON.utf8))
        _ = try await client.save(record, name: "Scout", instructions: "Updated", memory: "Private", model: "")
        #expect(ChatURLProtocol.url?.path == "/api/sessions/chat-test/settings")
        let edit = try JSONSerialization.jsonObject(with: ChatURLProtocol.sent) as? [String: Any]
        #expect(edit?["revision"] as? Int == 1)
        #expect(edit?["memory"] as? String == "Private")
    }
    @Test func creationSavesPrivateContextAndSelectedModelTogether() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ChatURLProtocol.self]
        let client = ChatSessionsClient(host: ScheduledTaskHost(id: "h", name: "Pro", baseURL: URL(string: "http://chat.test")!), session: URLSession(configuration: config))
        ChatURLProtocol.status = 201; ChatURLProtocol.response = "{\"session\":" + Self.sessionJSON + "}"
        _ = try await client.create(name: "Scout", instructions: "Be concise", memory: "Private", model: "opus")
        #expect(ChatURLProtocol.url?.path == "/api/sessions/chats")
        let input = try JSONSerialization.jsonObject(with: ChatURLProtocol.sent) as? [String: Any]
        #expect(input?["instructions"] as? String == "Be concise")
        #expect(input?["memory"] as? String == "Private")
        #expect(input?["model"] as? String == "opus")
    }
    @Test func oldHostNeverReceivesAnUnstableOfflineCreation() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ChatURLProtocol.self]
        let client = ChatSessionsClient(host: ScheduledTaskHost(id: "h", name: "Pro", baseURL: URL(string: "http://chat.test")!), session: URLSession(configuration: config))
        ChatURLProtocol.status = 404; ChatURLProtocol.response = "{}"
        do {
            _ = try await client.create(name: "Offline", instructions: "", memory: "", id: "chat-11111111-1111-4111-8111-111111111111")
            Issue.record("An older host must not receive a create POST")
        } catch let error as ChatClientError { #expect(error.status == 426) }
        #expect(ChatURLProtocol.url?.path == "/api/sessions/chats/capabilities")
        #expect(ChatURLProtocol.sent.isEmpty)
    }
    @Test func modelsUseOwningHostCatalogAndAuthentication() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ChatURLProtocol.self]
        let host = ScheduledTaskHost(id: "catalog-host", name: "Pro", baseURL: URL(string: "http://chat.test")!, headers: ["CF-Access-Client-Id": "catalog-fixture"])
        let client = ChatSessionsClient(host: host, session: URLSession(configuration: config))
        ChatURLProtocol.status = 200
        ChatURLProtocol.response = #"{"agents":{"claude":{"defaultModel":"claude-opus-future","models":["claude-opus-future","claude-fable-future","claude-sonnet-future","claude-haiku-future"]},"codex":{"models":["gpt-future"]}}}"#
        let catalog = try await client.models()
        #expect(ChatURLProtocol.url?.path == "/api/models")
        #expect(ChatURLProtocol.header == "catalog-fixture")
        #expect(catalog.models(for: .claude) == ["claude-opus-future", "claude-fable-future", "claude-sonnet-future", "claude-haiku-future"])
    }
    @Test func settingsConflictsAndOfflineFailuresPreserveActionableErrors() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ChatURLProtocol.self]
        let client = ChatSessionsClient(host: ScheduledTaskHost(id: "h", name: "Pro", baseURL: URL(string: "http://chat.test")!), session: URLSession(configuration: config))
        ChatURLProtocol.status = 409; ChatURLProtocol.response = "{\"error\":\"Settings changed. Reload before saving.\"}"
        do { try await client.send("chat-one", text: "Hello", requestID: "same"); Issue.record("Expected rejection") }
        catch { #expect(error.localizedDescription.contains("Settings changed")) }
    }
    @Test func chatSessionsCannotBeEndedAsTerminalProcesses() throws {
        let s = try JSONDecoder().decode(Session.self, from: Data(#"{"sessionId":"chat-test","kind":"chat","agent":"claude","title":"Scout"}"#.utf8))
        #expect(s.kind == "chat")
        #expect(!SessionCloseTracking.canEnd(s))
        let pushSnapshot = try JSONDecoder().decode(Session.self, from: Data(#"{"sessionId":"chat-test","title":"Scout"}"#.utf8))
        #expect(pushSnapshot.isChat)
        #expect(!SessionCloseTracking.canEnd(pushSnapshot))
    }
    static let sessionJSON = #"{"id":"chat-test","kind":"chat","name":"Scout","agent":"claude","instructions":"Be concise","memory":"Pip is my dog","summary":"","summaryThrough":0,"createdAt":1,"lastActivityAt":1,"revision":1,"nextTurn":1,"state":"idle"}"#
}

private final class ChatURLProtocol: URLProtocol {
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
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; Self.sent.append(buffer, count: n) }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension ChatSessionsTests {
    @Test func jobClientUsesOwningHostAndKeepsStableCreateReceipt() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ChatURLProtocol.self]
        let host = ScheduledTaskHost(id: "jobs", name: "Pro", baseURL: URL(string: "http://chat.test")!, headers: ["CF-Access-Client-Id": "jobs-fixture"])
        let client = ChatJobsClient(host: host, session: URLSession(configuration: config))
        var draft = ChatJobDraft(); draft.name = "Review"; draft.instructions = "Check until approved"; draft.action = "run"; draft.repeats = true; draft.stopOnNotify = true
        ChatURLProtocol.status = 201; ChatURLProtocol.response = "{}"
        try await client.create(chatId: "chat-owner", draft: draft)
        #expect(ChatURLProtocol.url?.path == "/api/scheduled-tasks")
        #expect(ChatURLProtocol.header == "jobs-fixture")
        let body = try JSONSerialization.jsonObject(with: ChatURLProtocol.sent) as? [String: Any]
        #expect(body?["chatId"] as? String == "chat-owner")
        #expect(body?["action"] as? String == "chat")
        #expect(body?["requestID"] as? String == draft.requestID)
        #expect(body?["stopOnNotify"] as? Bool == true)
        #expect((body?["schedule"] as? [String: Any])?["kind"] as? String == "interval")
        ChatURLProtocol.status = 200; ChatURLProtocol.response = #"{"tasks":[]}"#
        #expect(try await client.list(chatId: "chat-owner").isEmpty)
        #expect(ChatURLProtocol.url?.query == "chatId=chat-owner")
    }
    @Test func jobStatusAndPushRouteRetainChatIdentity() throws {
        let json = #"{"id":"job","chatId":"chat-owner","name":"Review","prompt":"Check","action":"chat","schedule":{"kind":"interval","timezone":"UTC","everyMinutes":60},"notification":"requested","stopOnNotify":true,"enabled":false,"revision":2,"lastRun":{"id":"run","status":"succeeded","summary":"Approved"},"notificationState":"accepted"}"#
        let job = try JSONDecoder().decode(ChatJobRecord.self, from: Data(json.utf8))
        #expect(job.statusLabel == "Finished")
        let shared: ScheduledTaskRecord = job
        #expect(shared.prompt == "Check")
        #expect(shared.isChatTask)
        #expect(job.deliveryLabel == "Notification sent")
        let push = PushNotification(userInfo: ["sid": "chat-owner", "kind": "job", "notificationId": "run", "session": ["id": "chat-owner", "kind": "chat", "title": "Scout"]])
        #expect(push?.sid == "chat-owner")
        #expect(push?.kind == .job)
        #expect(push?.session?.isChat == true)
        var draft = ChatJobDraft(job: job); draft.name = "Updated"; draft.instructions = "New condition"
        #expect(draft.action == "run")
        #expect(draft.repeats)
        var queued = job
        queued.lastRun?.status = "queued"
        #expect(queued.canPauseOrResume)
        #expect(queued.statusLabel == "Waiting for chat")
        queued.pausedAt = 1
        #expect(queued.statusLabel == "Paused")
        #expect(queued.canPauseOrResume)
        queued.cancelledAt = 2
        #expect(!queued.canPauseOrResume)
    }
}
