import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTaskRetryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [1, 35, 45, 60, 525600])
    func minutesResolveFromConfirmationTime(_ minutes: Int) throws {
        var draft = ScheduledTaskRetryDraft(now: now)
        draft.minutes = String(minutes)
        #expect(try draft.scheduledDate(now: now) == now.addingTimeInterval(Double(minutes) * 60))
        #expect(try draft.scheduledDate(now: now.addingTimeInterval(90)) == now.addingTimeInterval(Double(minutes) * 60 + 90))
    }

    @Test(arguments: ["", "0", "-1", "1.5", "later", "525601", "9999999999999999999999999"])
    func invalidMinutesCannotSchedule(_ minutes: String) {
        var draft = ScheduledTaskRetryDraft(now: now); draft.minutes = minutes
        #expect(throws: ScheduledTaskClientError.self) { try draft.scheduledDate(now: now) }
    }

    @Test func exactDateIsAbsoluteAndMustBeFuture() throws {
        var draft = ScheduledTaskRetryDraft(now: now); draft.mode = .time
        draft.date = now.addingTimeInterval(2700)
        #expect(try draft.scheduledDate(now: now) == draft.date)
        draft.date = now
        #expect(throws: ScheduledTaskClientError.self) { try draft.scheduledDate(now: now) }
    }

    @Test func pendingRetryMovesFinishedTaskToActiveAndShowsTime() throws {
        let at = now.addingTimeInterval(2100).timeIntervalSince1970 * 1000
        let json = #"{"id":"t","enabled":false,"retryAt":\#(at),"schedule":{"kind":"once","timezone":"UTC"},"lastRun":{"id":"r","status":"failed"},"consecutiveFailures":1}"#
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8))
        #expect(task.retryAt == at); #expect(task.listSection == .active); #expect(task.listGroup == .pending)
        #expect(task.statusLabel == "Retry scheduled")
        let card = TaskStatusCardModel.make(task: task, now: now)
        #expect(card.label == "Retry scheduled"); #expect(card.primary == .retry); #expect(card.secondary == .changeRetryTime)
        let row = TaskRowModel.make(task: task, hostName: "Mac", now: now)
        #expect(row.result.hasPrefix("Retry "))
    }

    @Test func oldHostResponsesStillDecodeWithoutRetry() throws {
        let task = try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(#"{"id":"old"}"#.utf8))
        #expect(task.retryAt == nil)
    }
}

@Suite struct ScheduledTaskRetryPresentationTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-18T15:50:00Z")!
    let zone = TimeZone(identifier: "Asia/Hong_Kong")!
    let locale = Locale(identifier: "en_US_POSIX")

    @Test func durationUsesReadableUnits() {
        for (minutes, phrase) in [(1, "1 minute"), (35, "35 minutes"), (45, "45 minutes"), (60, "1 hour"), (120, "2 hours")] {
            var draft = ScheduledTaskRetryDraft(now: now); draft.minutes = String(minutes)
            let model = ScheduledTaskRetryPresentation(draft: draft, now: now, timeZone: zone, locale: locale)
            #expect(model.sentence == "Retry in \(phrase)")
            #expect(model.date == now.addingTimeInterval(Double(minutes) * 60))
        }
    }

    @Test func delayAcrossMidnightNamesTomorrowInLocalTime() {
        var draft = ScheduledTaskRetryDraft(now: now); draft.minutes = "35"
        let model = ScheduledTaskRetryPresentation(draft: draft, now: now, timeZone: zone, locale: locale)
        #expect(model.preview.hasPrefix("Tomorrow at "))
        #expect(model.confirmationTitle.hasPrefix("Retry tomorrow at "))
        #expect(model.confirmationTitle.contains("12:25"))
    }

    @Test func invalidInputCannotLookConfirmed() {
        var draft = ScheduledTaskRetryDraft(now: now); draft.minutes = "0"
        var model = ScheduledTaskRetryPresentation(draft: draft, now: now, timeZone: zone, locale: locale)
        #expect(model.date == nil); #expect(model.confirmationTitle == "Retry later")
        #expect(model.preview.contains("whole minutes"))
        draft.mode = .time; draft.date = now
        model = ScheduledTaskRetryPresentation(draft: draft, now: now, timeZone: zone, locale: locale)
        #expect(model.date == nil); #expect(model.preview.contains("future"))
    }

    @Test func relativeTimeAdvancesButExactTimeStaysAbsolute() {
        var draft = ScheduledTaskRetryDraft(now: now); draft.minutes = "45"
        let later = now.addingTimeInterval(60)
        let first = ScheduledTaskRetryPresentation(draft: draft, now: now, timeZone: zone, locale: locale)
        let second = ScheduledTaskRetryPresentation(draft: draft, now: later, timeZone: zone, locale: locale)
        #expect(second.date == first.date?.addingTimeInterval(60))
        draft.mode = .time; draft.date = now.addingTimeInterval(3600)
        let exact = ScheduledTaskRetryPresentation(draft: draft, now: later, timeZone: zone, locale: locale)
        #expect(exact.date == draft.date)
        #expect(exact.confirmationTitle == ScheduledTaskRetryPresentation(draft: draft, now: now, timeZone: zone, locale: locale).confirmationTitle)
    }

    @Test func anotherYearIsVisibleInThePreview() {
        var draft = ScheduledTaskRetryDraft(now: now); draft.mode = .time
        draft.date = ISO8601DateFormatter().date(from: "2027-02-18T01:00:00Z")!
        let model = ScheduledTaskRetryPresentation(draft: draft, now: now, timeZone: zone, locale: locale)
        #expect(model.preview.contains("2027"))
    }
}

@Suite(.serialized) struct ScheduledTaskRetryClientTests {
    @Test func sendsAbsoluteDateAndExplicitNullToSelectedHost() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RetryProtocol.self]
        let client = ScheduledTasksClient(host: .init(id: "test", name: "Test", baseURL: URL(string: "https://retry.test")!, headers: ["Authorization": "test-token"]), session: URLSession(configuration: config))
        RetryProtocol.status = 200
        try await client.scheduleRetry("task", at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(RetryProtocol.url?.absoluteString == "https://retry.test/api/scheduled-tasks/task/retry")
        #expect(RetryProtocol.authorization == "test-token")
        var json = try #require(JSONSerialization.jsonObject(with: RetryProtocol.sent) as? [String: Any])
        #expect(json["at"] as? String == "2027-01-15T08:00:00Z")
        try await client.scheduleRetry("task", at: nil)
        json = try #require(JSONSerialization.jsonObject(with: RetryProtocol.sent) as? [String: Any])
        #expect(json["at"] is NSNull)
    }

    @Test func surfacesHostFailureWithoutRunningTask() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RetryProtocol.self]
        let client = ScheduledTasksClient(host: .init(id: "test", name: "Test", baseURL: URL(string: "https://retry.test")!), session: URLSession(configuration: config))
        RetryProtocol.status = 409
        await #expect(throws: ScheduledTaskClientError.self) { try await client.scheduleRetry("task", at: Date()) }
    }
}

private final class RetryProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var sent = Data()
    nonisolated(unsafe) static var url: URL?
    nonisolated(unsafe) static var authorization: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.url = request.url; Self.authorization = request.value(forHTTPHeaderField: "Authorization")
        Self.sent = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }
                Self.sent.append(buffer, count: count)
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.status == 200 ? "{}" : #"{"error":"Already running"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
