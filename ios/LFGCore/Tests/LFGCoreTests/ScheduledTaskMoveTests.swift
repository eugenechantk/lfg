import Foundation
import Testing
@testable import LFGCore

/// Changing a task's host in the form moves it: create on the new host, then stop the original.
@Suite(.serialized) struct ScheduledTaskMoveTests {
    private func clients(createStatus: Int = 201, cancelStatus: Int = 200) -> (pro: ScheduledTasksClient, air: ScheduledTasksClient) {
        MoveProtocol.reset(createStatus: createStatus, cancelStatus: cancelStatus)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MoveProtocol.self]
        let session = URLSession(configuration: config)
        return (ScheduledTasksClient(host: .init(id: "pro", name: "Pro", baseURL: URL(string: "https://pro.test")!), session: session),
                ScheduledTasksClient(host: .init(id: "air", name: "Air", baseURL: URL(string: "https://air.test")!), session: session))
    }

    private func task(_ schedule: String, done: Int = 0) throws -> ScheduledTaskRecord {
        let json = #"{"id":"old","name":"Audit","prompt":"p","cwd":"/tmp","agent":"claude","enabled":true,"scheduledRunCount":\#(done),"schedule":\#(schedule)}"#
        return try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
    }

    private func payload(_ t: ScheduledTaskRecord) -> ScheduledTaskPayload {
        .init(name: t.name, prompt: t.prompt, cwd: t.cwd, agent: t.agent, model: nil, schedule: t.schedule, enabled: true)
    }

    @Test func createsOnTheNewHostThenStopsTheOriginal() async throws {
        let (pro, air) = clients()
        let t = try task(#"{"kind":"cron","timezone":"UTC","expression":"0 9 * * *"}"#)
        let moved = try await pro.move(t, as: payload(t), to: air)
        #expect(moved.id == "new")
        #expect(MoveProtocol.requests.map(\.0) == ["POST https://air.test/api/scheduled-tasks", "POST https://pro.test/api/scheduled-tasks/old/cancel"])
    }

    @Test func aFailedCreateLeavesTheOriginalAlone() async throws {
        let (pro, air) = clients(createStatus: 400)
        let t = try task(#"{"kind":"cron","timezone":"UTC","expression":"0 9 * * *"}"#)
        await #expect(throws: ScheduledTaskClientError.self) { try await pro.move(t, as: payload(t), to: air) }
        #expect(MoveProtocol.requests.map(\.0) == ["POST https://air.test/api/scheduled-tasks"])
    }

    @Test func aFailedStopReportsTheCopyThatNowExists() async throws {
        let (pro, air) = clients(cancelStatus: 500)
        let t = try task(#"{"kind":"cron","timezone":"UTC","expression":"0 9 * * *"}"#)
        do {
            _ = try await pro.move(t, as: payload(t), to: air)
            Issue.record("Expected the stop to fail")
        } catch let error as ScheduledTaskMoveError {
            #expect(error.task.id == "new")
            #expect(error.localizedDescription.hasPrefix("Moved, but the original on Pro is still on"))
        }
    }

    /// "After 10 runs" with 4 done moves as 6 left; a changed schedule starts its count again, as on one host.
    @Test func runsLeftCarryOverOnlyWhenTheScheduleIsUnchanged() async throws {
        let (pro, air) = clients()
        let t = try task(#"{"kind":"cron","timezone":"UTC","expression":"0 9 * * *","maxRuns":10}"#, done: 4)
        _ = try await pro.move(t, as: payload(t), to: air)
        #expect(MoveProtocol.createdSchedule?["maxRuns"] as? Int == 6)

        var changed = payload(t); changed.schedule.expression = "0 8 * * *"
        _ = try await pro.move(t, as: changed, to: air)
        #expect(MoveProtocol.createdSchedule?["maxRuns"] as? Int == 10)
    }
}

private final class MoveProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [(String, Data)] = []
    nonisolated(unsafe) static var createStatus = 201
    nonisolated(unsafe) static var cancelStatus = 200
    static func reset(createStatus: Int, cancelStatus: Int) {
        requests = []; self.createStatus = createStatus; self.cancelStatus = cancelStatus
    }
    static var createdSchedule: [String: Any]? {
        guard let body = requests.last(where: { $0.0.hasSuffix("/api/scheduled-tasks") })?.1,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return json["schedule"] as? [String: Any]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
        }
        let url = request.url!.absoluteString
        Self.requests.append(("\(request.httpMethod ?? "GET") \(url)", body))
        let creating = url.hasSuffix("/api/scheduled-tasks")
        let status = creating ? Self.createStatus : Self.cancelStatus
        let json = status >= 300 ? #"{"error":"That directory does not exist on this host."}"#
            : creating ? #"{"task":{"id":"new","name":"Audit","prompt":"p","cwd":"/tmp","agent":"claude","enabled":true}}"#
            : #"{"task":{"id":"old","name":"Audit","prompt":"p","cwd":"/tmp","agent":"claude","enabled":false,"cancelledAt":1}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
