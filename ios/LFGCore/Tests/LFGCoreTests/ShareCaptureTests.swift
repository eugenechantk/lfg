import Foundation
import Testing
@testable import LFGCore

@Suite struct ShareCaptureTests {
    let host = Host(url: "https://share.test", name: "Pro", isDefault: true)
    func spool() throws -> ShareSpool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ShareSpool(root: root)
    }
    @Test func preparedShareRequestsPreserveAccessHeadersAndBodies() throws {
        let client = LFGClient(baseURL: URL(string: "https://share.test")!,
            accessCredential: CloudflareAccessCredential(clientID: "test-id", clientSecret: "test-secret"))
        let create = try client.newSessionRequest(.init(cwd: "/work", prompt: "Exact prompt", agent: "codex"))
        #expect(create.url?.path == "/api/sessions/new")
        #expect(create.httpMethod == "POST")
        #expect(create.value(forHTTPHeaderField: "CF-Access-Client-Id") == "test-id")
        #expect(create.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-secret")
        let body = try JSONSerialization.jsonObject(with: #require(create.httpBody)) as? [String: Any]
        #expect(body?["prompt"] as? String == "Exact prompt")
        #expect(body?["model"] is NSNull)
        let upload = client.uploadRequest("target", contentType: "application/pdf", filename: "brief + notes.pdf")
        #expect(upload.url?.path == "/api/sessions/target/upload")
        #expect(upload.httpBody == nil)
        #expect(upload.value(forHTTPHeaderField: "X-LFG-Filename") == "brief%20%2B%20notes.pdf")
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "application/pdf")
        #expect(upload.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "test-secret")
    }
    @Test func recentUsesUserTimeAndHasNoDuplicates() {
        let rows = (1...8).map { i in ShareRecipient(host: host, session: Session(sessionId: "s\(i)", title: "Title \(i)", lastActivityAt: Double(9-i), lastUserAt: Double(i))) }
        let sections = ShareRecipients.sections(rows, query: "")
        #expect(sections.recent.map { $0.session.id } == ["s8", "s7", "s6", "s5", "s4"])
        #expect(sections.all.count == 3)
        #expect(Set((sections.recent + sections.all).map(\.id)).count == 8)
        #expect(ShareRecipients.sections(rows, query: "title 2").all.count == 1)
    }
    @Test func liveOwnerWinsSyncedClosedCopy() {
        let closed = ShareRecipient(host: host, session: Session(sessionId: "same", title: "Closed", closed: true))
        let live = ShareRecipient(host: Host(url: "https://air.test"), session: Session(sessionId: "same", title: "Live"))
        #expect(ShareRecipients.reconciled([closed, live]).map(\.id) == [live.id])
    }
    @Test func persistsTextFilesAndCheckpoints() throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let source = store.root.appendingPathComponent("report.pdf")
        try Data("test pdf".utf8).write(to: source)
        var job = ShareJob(host: host, sessionID: "target", recipientTitle: "Target", text: "Review this\nhttps://example.com")
        let file = try store.stage(source, jobID: job.id, filename: "report.pdf", contentType: "application/pdf")
        job.files = [file]; try store.save(job)
        let restored = try store.load(job.id)
        #expect(restored.text == job.text)
        #expect(restored.files.first?.filename == "report.pdf")
        #expect(try Data(contentsOf: store.fileURL(jobID: job.id, file: file)) == Data("test pdf".utf8))
        job.files[0].uploadedPath = "/host/report.pdf"
        #expect(job.message == "Review this\nhttps://example.com\n/host/report.pdf")
    }
    @Test func leaseExcludesAnotherProcessAndReleases() throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = UUID().uuidString
        let firstLease = try store.lease(id)
        let first = try #require(firstLease)
        #expect(try store.lease(id) == nil)
        first.release()
        #expect(try store.lease(id) != nil)
    }
    @Test func deliveryUsesOriginalHostAndStableClientID() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let job = ShareJob(host: host, sessionID: "target", recipientTitle: "Target", text: "Exact text\nhttps://example.com")
        try store.save(job)
        let calls = ShareTestCalls()
        let service = ShareDelivery(spool: store, transport: ShareTransport(
            upload: { _, _, _, _, _ in Issue.record("Unexpected upload"); return "" },
            send: { host, id, text, clientID in
                await calls.sent(host: host, id: id, text: text, clientID: clientID)
                return LFGClient.decodeSendResponse(Data("{\"ok\":true,\"clientId\":\"\(clientID)\"}".utf8))
            }, create: { _, _ in throw ShareCaptureError.empty }))
        let result = try await service.deliver(job.id)
        #expect(result.status == .sent)
        #expect(await calls.hostURL == host.url)
        #expect(await calls.sessionID == "target")
        #expect(await calls.text == job.text)
        #expect(await calls.clientID == job.id)
        _ = try await service.deliver(job.id)
        #expect(await calls.count == 1)
    }
    @Test func offlineQueuesButAmbiguousSendNeverAutomaticallyReplays() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let job = ShareJob(host: host, sessionID: "target", recipientTitle: "Target", text: "Hello")
        try store.save(job)
        let offline = ShareDelivery(spool: store, transport: .failing(URLError(.notConnectedToInternet)))
        #expect(try await offline.deliver(job.id).status == .queued)
        let uncertain = ShareDelivery(spool: store, transport: .failing(URLError(.timedOut)))
        #expect(try await uncertain.deliver(job.id).status == .uncertain)
        let retry = try await offline.deliver(job.id)
        #expect(retry.status == .uncertain)
    }
    @Test func interruptedCreationNeverCreatesAgain() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        var job = ShareJob(host: host, recipientTitle: "New session", newSession: .init(cwd: "/work", prompt: ""), text: "Hello")
        job.status = .creating; try store.save(job)
        let result = try await ShareDelivery(spool: store, transport: .failing(URLError(.notConnectedToInternet))).deliver(job.id)
        #expect(result.status == .uncertain)
    }
    @Test func unacknowledgedResponseIsNotSuccess() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let job = ShareJob(host: host, sessionID: "target", recipientTitle: "Target", text: "Hello")
        try store.save(job)
        let transport = ShareTransport(upload: { _, _, _, _, _ in "" }, send: { _, _, _, _ in LFGClient.decodeSendResponse(Data("{}".utf8)) }, create: { _, _ in throw ShareCaptureError.empty })
        #expect(try await ShareDelivery(spool: store, transport: transport).deliver(job.id).status == .uncertain)
    }
    @Test func uploadedFilesAreCheckpointedBeforeOfflineSendAndNotUploadedTwice() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let source = store.root.appendingPathComponent("photo.png")
        try Data("photo bytes".utf8).write(to: source)
        var job = ShareJob(host: host, sessionID: "target", recipientTitle: "Target", text: "Review")
        job.files = [try store.stage(source, jobID: job.id, filename: "photo.png", contentType: "image/png")]
        try store.save(job)
        let calls = ShareTestCalls()
        let offline = ShareTransport(upload: { _, _, _, _, _ in await calls.uploaded(); return "/host/photo.png" },
            send: { _, _, _, _ in throw URLError(.notConnectedToInternet) }, create: { _, _ in throw ShareCaptureError.empty })
        let first = try await ShareDelivery(spool: store, transport: offline).deliver(job.id)
        #expect(first.status == .queued)
        #expect(first.files.first?.uploadedPath == "/host/photo.png")
        let online = ShareTransport(upload: { _, _, _, _, _ in Issue.record("Reuploaded checkpoint"); return "" },
            send: { _, _, text, clientID in
                #expect(text == "Review\n/host/photo.png")
                return LFGClient.decodeSendResponse(Data("{\"ok\":true,\"clientId\":\"\(clientID)\"}".utf8))
            }, create: { _, _ in throw ShareCaptureError.empty })
        #expect(try await ShareDelivery(spool: store, transport: online).deliver(job.id).status == .sent)
        #expect(await calls.uploads == 1)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(jobID: job.id, file: job.files[0]).path))
    }
    @Test func newSessionGetsTextAndFilesInFirstPrompt() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        var file = ShareFile(filename: "brief.pdf", contentType: "application/pdf", byteCount: 10)
        file.uploadedPath = "/host/brief.pdf"
        let job = ShareJob(host: host, recipientTitle: "New session", newSession: .init(cwd: "/work", prompt: "", agent: "codex"), text: "Read this", files: [file])
        try store.save(job)
        let transport = ShareTransport(upload: { _, _, _, _, _ in Issue.record("Unexpected upload"); return "" },
            send: { _, _, _, _ in throw ShareCaptureError.empty }, create: { h, request in
                #expect(h.url == host.url)
                #expect(request.cwd == "/work")
                #expect(request.agent == "codex")
                #expect(request.prompt == "Read this\n/host/brief.pdf")
                return try JSONDecoder().decode(NewSessionResponse.self, from: Data("{\"ok\":true,\"sessionId\":\"new-id\"}".utf8))
            })
        let result = try await ShareDelivery(spool: store, transport: transport).deliver(job.id)
        #expect(result.status == .sent)
        #expect(result.sessionID == "new-id")
    }
    @Test func serverFailureAfterSubmissionIsUncertainAndOldQueueNeedsReview() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        var job = ShareJob(host: host, sessionID: "target", recipientTitle: "Target", text: "Hello")
        try store.save(job)
        let transport = ShareTransport(upload: { _, _, _, _, _ in "" },
            send: { _, _, _, _ in throw LFGError.http(status: 500, body: "Internal error") }, create: { _, _ in throw ShareCaptureError.empty })
        #expect(try await ShareDelivery(spool: store, transport: transport).deliver(job.id).status == .uncertain)
        job.id = UUID().uuidString; job.createdAt = Date().addingTimeInterval(-25 * 3600)
        try store.save(job)
        #expect(try await ShareDelivery(spool: store, transport: transport).deliver(job.id).status == .failed)
    }

}

private actor ShareTestCalls {
    var hostURL = "", sessionID = "", text = "", clientID = "", count = 0
    var uploads = 0
    func uploaded() { uploads += 1 }
    func sent(host: LFGCore.Host, id: String, text: String, clientID: String) {
        hostURL = host.url; sessionID = id; self.text = text; self.clientID = clientID; count += 1
    }
}
private extension ShareTransport {
    static func failing(_ error: URLError) -> ShareTransport {
        .init(upload: { _, _, _, _, _ in throw error }, send: { _, _, _, _ in throw error }, create: { _, _ in throw error })
    }
}

// MARK: - Durable chats (2026-11-05)

private actor ShareChatCalls {
    var chatID = "", text = "", requestID = "", uploadKey = "", sends = 0, sessionSends = 0
    func uploaded(_ key: String) { uploadKey = key }
    func sent(_ id: String, _ text: String, _ requestID: String) { chatID = id; self.text = text; self.requestID = requestID; sends += 1 }
    func sessionSent() { sessionSends += 1 }
}

extension ShareCaptureTests {
    private func chatTransport(_ calls: ShareChatCalls, reply: @escaping @Sendable (String) throws -> ChatSendAck) -> ShareTransport {
        ShareTransport(upload: { _, key, _, _, name in await calls.uploaded(key); return "/host/uploads/\(name)" },
                       send: { _, _, _, _ in await calls.sessionSent(); throw ShareCaptureError.empty },
                       create: { _, _ in throw ShareCaptureError.empty },
                       sendChat: { _, id, text, requestID in await calls.sent(id, text, requestID); return try reply(requestID) })
    }

    @Test func chatsGetTheirOwnSectionAfterSessions() {
        let session = ShareRecipient(host: host, session: Session(sessionId: "s1", title: "Mad dash", lastActivityAt: 1))
        var chat = Session(sessionId: "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", title: "Mad Men", lastActivityAt: 9)
        chat.kind = "chat"
        let rows = [ShareRecipient(host: host, session: chat), session]
        let found = ShareRecipients.sections(rows, query: "mad")
        #expect(found.recent.isEmpty)
        #expect(found.sessions.map(\.session.id) == ["s1"])
        #expect(found.chats.map(\.session.title) == ["Mad Men"])
        #expect(found.all.map(\.session.id) == ["s1", chat.id])
        #expect(ShareRecipients.sections(rows, query: "chat").chats.count == 1)
        #expect(ShareRecipients.sections(rows, query: "chat").sessions.isEmpty)
    }

    @Test func busyChatSaysItWaitsInsteadOfJoiningTheTurn() {
        var chat = Session(sessionId: "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", title: "Mad Men")
        chat.kind = "chat"; chat.busy = true
        #expect(ShareRecipient(host: host, session: chat).sendEffect == "Waits for its current turn")
        chat.busy = false
        #expect(ShareRecipient(host: host, session: chat).sendEffect == "Starts its next turn now")
    }

    @Test func chatShareUsesRequestIDAndUploadsUnderTheShareID() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let source = store.root.appendingPathComponent("shot.png"); try Data("png".utf8).write(to: source)
        var job = ShareJob(host: host, sessionID: "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", recipientTitle: "Mad Men",
                           text: "look\nhttps://www.instagram.com/p/x/")
        job.files = [try store.stage(source, jobID: job.id, filename: "shot.png", contentType: "image/png")]
        try store.save(job)
        let calls = ShareChatCalls()
        let result = try await ShareDelivery(spool: store, transport: chatTransport(calls) { ChatSendAck(requestID: $0) }).deliver(job.id)
        #expect(result.status == .sent)
        #expect(await calls.uploadKey == job.id)
        #expect(await calls.chatID == job.sessionID)
        #expect(await calls.requestID == job.id)
        #expect(await calls.text == "look\nhttps://www.instagram.com/p/x/\n/host/uploads/shot.png")
        #expect(await calls.sessionSends == 0)
        let body = try JSONSerialization.jsonObject(with: #require(
            try LFGClient(baseURL: URL(string: "https://share.test")!).chatSendRequest("chat-x", text: "t", requestID: "r").httpBody)) as? [String: String]
        #expect(body == ["text": "t", "requestID": "r"])
    }

    @Test func busyChatQueuesTheShareInsteadOfFailing() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let job = ShareJob(host: host, sessionID: "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", recipientTitle: "Mad Men", text: "hi")
        try store.save(job)
        let calls = ShareChatCalls()
        let busy = chatTransport(calls) { _ in throw LFGError.http(status: 409, body: "{\"error\":\"A turn or child agent is already running.\"}") }
        let result = try await ShareDelivery(spool: store, transport: busy).deliver(job.id)
        #expect(result.status == .queued)
        #expect(result.waitsForTurn == true)
        #expect(result.error == nil)
        #expect(try store.load(job.id).canAutomaticallyDeliver)
    }

    @Test func interruptedChatSendReplaysWithTheSameRequestID() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        var job = ShareJob(host: host, sessionID: "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", recipientTitle: "Mad Men", text: "hi")
        job.status = .sending; try store.save(job)
        let calls = ShareChatCalls()
        let result = try await ShareDelivery(spool: store, transport: chatTransport(calls) { ChatSendAck(requestID: $0, duplicate: true) }).deliver(job.id)
        #expect(result.status == .sent)
        #expect(await calls.requestID == job.id)
        // A lost answer after submission stays retryable for a chat.
        var lost = ShareJob(host: host, sessionID: "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", recipientTitle: "Mad Men", text: "again")
        try store.save(lost)
        lost = try await ShareDelivery(spool: store, transport: chatTransport(calls) { _ in throw URLError(.timedOut) }).deliver(lost.id)
        #expect(lost.status == .queued)
    }

    @Test func chatReplyMustEchoTheShareID() async throws {
        let store = try spool(); defer { try? FileManager.default.removeItem(at: store.root) }
        let job = ShareJob(host: host, sessionID: "chat-0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", recipientTitle: "Mad Men", text: "hi")
        try store.save(job)
        let result = try await ShareDelivery(spool: store, transport: chatTransport(ShareChatCalls()) { _ in ChatSendAck(requestID: "someone-else") }).deliver(job.id)
        #expect(result.status == .uncertain)
    }
}
