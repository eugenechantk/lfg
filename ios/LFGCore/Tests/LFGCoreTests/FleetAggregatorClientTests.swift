import XCTest
@testable import LFGCore

final class FleetAggregatorClientTests: XCTestCase {
    private let config = FleetAggregatorConfig(url: URL(string: "https://agg.example.workers.dev")!, secret: "k3y")
    private var client: FleetAggregatorClient { FleetAggregatorClient(config: config) }

    private func object(_ req: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(req.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The string-valued fields; `hiddenDirs` (an array) is asserted on its own.
    private func body(_ req: URLRequest) throws -> [String: String] {
        try object(req).compactMapValues { $0 as? String }
    }

    func testStartTokenGoesStraightToTheWorkerWithTheDeviceId() throws {
        let req = client.startTokenRequest("ab12", env: "production", deviceId: "DEV-1", hiddenDirs: [])
        XCTAssertEqual(req.url?.absoluteString, "https://agg.example.workers.dev/v1/start-token")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k3y")
        XCTAssertEqual(try body(req), ["token": "ab12", "env": "production", "deviceId": "DEV-1"])
    }

    func testStartTokenOmitsAMissingDeviceId() throws {
        XCTAssertEqual(try body(client.startTokenRequest("ab12", env: "sandbox", deviceId: nil, hiddenDirs: [])), ["token": "ab12", "env": "sandbox"])
        XCTAssertEqual(try body(client.startTokenRequest("ab12", env: "sandbox", deviceId: "", hiddenDirs: [])), ["token": "ab12", "env": "sandbox"])
    }

    // 2026-11-05: autopilot runs hidden in the phone's list still started the
    // card for ~20 s. The Worker can only leave them out if it has the list.
    func testStartTokenCarriesTheHiddenDirectoriesEvenWhenEmpty() throws {
        let req = client.startTokenRequest("ab12", env: "production", deviceId: "DEV-1", hiddenDirs: ["*/lfg-autopilot-claude-cwd-*"])
        XCTAssertEqual(try object(req)["hiddenDirs"] as? [String], ["*/lfg-autopilot-claude-cwd-*"])
        let cleared = client.startTokenRequest("ab12", env: "production", deviceId: "DEV-1", hiddenDirs: [])
        XCTAssertEqual(try object(cleared)["hiddenDirs"] as? [String], [])
    }

    func testOnlyAnEchoedCountConfirmsTheListWasStored() {
        XCTAssertTrue(FleetAggregatorClient.confirmsHiddenDirs(Data(#"{"ok":true,"hiddenDirs":1}"#.utf8)))
        XCTAssertTrue(FleetAggregatorClient.confirmsHiddenDirs(Data(#"{"ok":true,"hiddenDirs":0}"#.utf8)))
        XCTAssertFalse(FleetAggregatorClient.confirmsHiddenDirs(Data(#"{"ok":true}"#.utf8)))
        XCTAssertFalse(FleetAggregatorClient.confirmsHiddenDirs(Data()))
    }

    func testChannelIsAGetWithARealQueryString() {
        let req = client.channelRequest(env: "production")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString, "https://agg.example.workers.dev/v1/channel?env=production")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k3y")
        XCTAssertNil(req.httpBody)
    }

    func testStartedAndEndedReportsCarryTheEnvironment() throws {
        let started = client.startedRequest(env: "sandbox")
        XCTAssertEqual(started.url?.path, "/v1/started")
        XCTAssertEqual(started.httpMethod, "POST")
        XCTAssertEqual(try body(started), ["env": "sandbox"])
        let ended = client.endedRequest(env: "production")
        XCTAssertEqual(ended.url?.path, "/v1/ended")
        XCTAssertEqual(ended.value(forHTTPHeaderField: "Authorization"), "Bearer k3y")
        XCTAssertEqual(try body(ended), ["env": "production"])
    }

    func testConfigRoundTripsThroughItsCache() {
        XCTAssertEqual(FleetAggregatorConfig.decode(config.encoded()), config)
        XCTAssertNil(FleetAggregatorConfig.decode(nil))
        XCTAssertNil(FleetAggregatorConfig.decode(Data("garbage".utf8)))
    }

    func testHostResponseParsing() {
        let ok = Data(#"{"ok":true,"url":"https://agg.example.workers.dev","secret":"k3y"}"#.utf8)
        XCTAssertEqual(FleetAggregatorConfig.fromHostResponse(ok), config)
        // No aggregator configured on this deployment.
        XCTAssertNil(FleetAggregatorConfig.fromHostResponse(Data(#"{"ok":true,"url":null}"#.utf8)))
        // Never trust a plaintext endpoint with the bearer.
        XCTAssertNil(FleetAggregatorConfig.fromHostResponse(Data(#"{"url":"http://agg.example","secret":"k3y"}"#.utf8)))
        XCTAssertNil(FleetAggregatorConfig.fromHostResponse(Data(#"{"url":"https://agg.example","secret":""}"#.utf8)))
        // A server that predates the route answers 404 HTML or an error object.
        XCTAssertNil(FleetAggregatorConfig.fromHostResponse(Data("<!doctype html>".utf8)))
    }
}
