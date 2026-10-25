import Foundation

public struct ShareTransport: Sendable {
    public var upload: @Sendable (Host, String, URL, String, String) async throws -> String
    public var send: @Sendable (Host, String, String, String) async throws -> SendResponse
    public var create: @Sendable (Host, NewSessionRequest) async throws -> NewSessionResponse
    public init(upload: @escaping @Sendable (Host, String, URL, String, String) async throws -> String,
                send: @escaping @Sendable (Host, String, String, String) async throws -> SendResponse,
                create: @escaping @Sendable (Host, NewSessionRequest) async throws -> NewSessionResponse) {
        self.upload = upload; self.send = send; self.create = create
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
                let path = try await transport.upload(job.host, job.sessionID ?? job.id, fileURL, file.contentType, file.filename)
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
            if definitelyOffline { job.status = .queued }
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
