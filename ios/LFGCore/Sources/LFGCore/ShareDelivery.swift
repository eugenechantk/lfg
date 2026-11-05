import Foundation

/// What a durable chat's send route returns: the accepted turn's request id.
public struct ChatSendAck: Decodable, Sendable, Equatable {
    public struct Turn: Decodable, Sendable, Equatable { public var requestID: String }
    public var turn: Turn
    public var duplicate: Bool?
    public init(requestID: String, duplicate: Bool? = nil) { turn = .init(requestID: requestID); self.duplicate = duplicate }
}

public struct ShareTransport: Sendable {
    public var upload: @Sendable (Host, String, URL, String, String) async throws -> String
    public var send: @Sendable (Host, String, String, String) async throws -> SendResponse
    public var create: @Sendable (Host, NewSessionRequest) async throws -> NewSessionResponse
    /// (host, chat id, text, request id). Chats use their own body and reply.
    public var sendChat: @Sendable (Host, String, String, String) async throws -> ChatSendAck
    public init(upload: @escaping @Sendable (Host, String, URL, String, String) async throws -> String,
                send: @escaping @Sendable (Host, String, String, String) async throws -> SendResponse,
                create: @escaping @Sendable (Host, NewSessionRequest) async throws -> NewSessionResponse,
                sendChat: @escaping @Sendable (Host, String, String, String) async throws -> ChatSendAck = { _, _, _, _ in
                    throw ShareCaptureError.unacknowledged }) {
        self.upload = upload; self.send = send; self.create = create; self.sendChat = sendChat
    }
    public static func live(client: @escaping @Sendable (Host) -> LFGClient?) -> ShareTransport {
        .init(upload: { host, id, file, type, name in
            guard let c = client(host) else { throw LFGError.badURL }
            let (data, response) = try await URLSession.shared.upload(for: c.uploadRequest(id, contentType: type, filename: name), fromFile: file)
            struct UploadResponse: Decodable { var path: String }
            return try JSONDecoder().decode(UploadResponse.self, from: checked(data, response)).path
        }, send: { host, id, text, clientID in
            guard let c = client(host) else { throw LFGError.badURL }
            let data = try await requestData(c.sendMessageRequest(id, text: text, clientId: clientID))
            return LFGClient.decodeSendResponse(data)
        }, create: { host, request in
            guard let c = client(host) else { throw LFGError.badURL }
            let data = try await requestData(c.newSessionRequest(request))
            return try JSONDecoder().decode(NewSessionResponse.self, from: data)
        }, sendChat: { host, id, text, requestID in
            guard let c = client(host) else { throw LFGError.badURL }
            let data = try await requestData(c.chatSendRequest(id, text: text, requestID: requestID))
            return try JSONDecoder().decode(ChatSendAck.self, from: data)
        })
    }
    private static func requestData(_ request: URLRequest) async throws -> Data {
        // Keep the original URLError: the general read client intentionally
        // flattens it, which would make known-offline sends look ambiguous.
        let (data, response) = try await URLSession.shared.data(for: request)
        return try checked(data, response)
    }
    private static func checked(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw ShareCaptureError.unacknowledged }
        guard (200..<300).contains(http.statusCode) else {
            throw LFGError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

}

public struct ShareDelivery: Sendable {
    public let spool: ShareSpool
    public let transport: ShareTransport
    public init(spool: ShareSpool, transport: ShareTransport) { self.spool = spool; self.transport = transport }

    public func deliver(_ id: String, retryFailure: Bool = false) async throws -> ShareJob {
        guard let lease = try spool.lease(id) else { return try spool.load(id) }
        defer { lease.release() }
        var job = try spool.load(id)
        guard job.status != .sent, job.status != .uncertain else { return job }
        // The old process died after persisting the POST boundary. Creation has
        // no host idempotency key; a replay could start a second agent session.
        // A chat send is keyed by its request id, so the host dedupes a replay.
        if job.isChat && job.status == .sending { job.status = .queued }
        if job.status == .creating || job.status == .sending {
            job.status = .uncertain; job.error = ShareCaptureError.unacknowledged.localizedDescription
            try spool.save(job); return job
        }
        guard job.canAutomaticallyDeliver || (retryFailure && job.status == .failed) else { return job }
        if !retryFailure && Date().timeIntervalSince(job.createdAt) * 1000 > OutboxResurrectionPolicy.retryWindowMs {
            job.status = .failed; job.error = "This share is over 24 hours old. Review it before retrying."
            try spool.save(job); return job
        }
        do {
            for index in job.files.indices where job.files[index].uploadedPath == nil {
                job.status = .uploading; try spool.save(job)
                let file = job.files[index]
                let fileURL = spool.fileURL(jobID: id, file: file)
                let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard size == file.byteCount, file.byteCount < ShareSpool.maximumFileBytes else { throw ShareCaptureError.invalidFile }
                // Upload is only a file write; it never submits an agent turn.
                // The existing endpoint accepts a UUID before session creation.
                // A chat id is not a session UUID; the share id stands in, as it
                // does before a new session exists.
                let path = try await transport.upload(job.host, job.isChat ? job.id : (job.sessionID ?? job.id), fileURL, file.contentType, file.filename)
                guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\r") else { throw ShareCaptureError.invalidFile }
                job.files[index].uploadedPath = path; try spool.save(job)
            }
            guard !job.message.isEmpty else { throw ShareCaptureError.empty }
            if var request = job.newSession, job.sessionID == nil {
                request.prompt = job.message
                job.status = .creating; try spool.save(job)
                let response = try await transport.create(job.host, request)
                guard response.ok == true, let sessionID = response.sessionId, !sessionID.isEmpty else { throw ShareCaptureError.unacknowledged }
                job.sessionID = sessionID
            } else if job.isChat, let chatID = job.sessionID {
                job.status = .sending; try spool.save(job)
                do {
                    let ack = try await transport.sendChat(job.host, chatID, job.message, job.id)
                    guard ack.turn.requestID == job.id else { throw ShareCaptureError.unacknowledged }
                    job.waitsForTurn = nil
                } catch LFGError.http(status: 409, _) {
                    // The chat is mid-turn. Nothing was submitted; hold it.
                    job.status = .queued; job.waitsForTurn = true; job.error = nil
                    try spool.save(job); return job
                }
            } else if let sessionID = job.sessionID {
                job.status = .sending; try spool.save(job)
                let response = try await transport.send(job.host, sessionID, job.message, job.id)
                guard response.ok == true,
                      response.clientId == job.id || response.msg?.clientId == job.id,
                      response.msg?.status != "failed" else { throw ShareCaptureError.unacknowledged }
                job.sessionID = response.sessionId ?? sessionID
            } else { throw ShareCaptureError.empty }
            job.status = .sent; job.error = nil
            try spool.save(job)
            spool.removeFiles(job)
        } catch {
            let atSubmission = job.status == .creating || job.status == .sending
            let evidence = SendFailureEvidence.from(error)
            let definitelyOffline: Bool
            switch evidence {
            case .transportFailed(let code):
                definitelyOffline = [URLError.notConnectedToInternet.rawValue, URLError.cannotFindHost.rawValue,
                                     URLError.cannotConnectToHost.rawValue, URLError.dnsLookupFailed.rawValue].contains(code ?? 0)
            default: definitelyOffline = false
            }
            // A chat replay reuses its request id, so a lost answer is retryable.
            var chatRetryable = false
            if job.isChat, atSubmission, !(error is ShareCaptureError), !(error is DecodingError) {
                switch evidence {
                case .transportFailed: chatRetryable = true
                case .serverAnswered(let status): chatRetryable = status >= 500
                default: break
                }
            }
            if definitelyOffline || chatRetryable { job.status = .queued }
            else if atSubmission, case .transportFailed = evidence { job.status = .uncertain }
            else if atSubmission, case .serverAnswered(let status) = evidence, status >= 500 { job.status = .uncertain }
            else if atSubmission, error is ShareCaptureError || error is DecodingError { job.status = .uncertain }
            else { job.status = .failed }
            job.error = (error as? LFGError)?.userMessage ?? error.localizedDescription
            try spool.save(job)
        }
        return job
    }
}
