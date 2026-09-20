import XCTest
@testable import LFGCore

final class FleetAggregatorClientTests: XCTestCase {
    private let config = FleetAggregatorConfig(url: URL(string: "https://agg.example.workers.dev")!, secret: "k3y")
    private var client: FleetAggregatorClient { FleetAggregatorClient(config: config) }

    private func body(_ req: URLRequest) throws -> [String: String] {
        let data = try XCTUnwrap(req.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    func testStartTokenGoesStraightToTheWorkerWithTheDeviceId() throws {
        let req = client.startTokenRequest("ab12", env: "production", deviceId: "DEV-1")
        XCTAssertEqual(req.url?.absoluteString, "https://agg.example.workers.dev/v1/start-token")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k3y")
        XCTAssertEqual(try body(req), ["token": "ab12", "env": "production", "deviceId": "DEV-1"])
    }

    func testStartTokenOmitsAMissingDeviceId() throws {
        XCTAssertEqual(try body(client.startTokenRequest("ab12", env: "sandbox", deviceId: nil)), ["token": "ab12", "env": "sandbox"])
        XCTAssertEqual(try body(client.startTokenRequest("ab12", env: "sandbox", deviceId: "")), ["token": "ab12", "env": "sandbox"])
    }

    func testChannelIsAGetWithARealQueryString() {
        let req = client.channelRequest(env: "production")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString, "https://agg.example.workers.dev/v1/channel?env=production")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k3y")
        XCTAssertNil(req.httpBody)
    }

    func testStartedAndEndedReports() {
        XCTAssertEqual(client.startedRequest().url?.path, "/v1/started")
        XCTAssertEqual(client.startedRequest().httpMethod, "POST")
        XCTAssertEqual(client.endedRequest().url?.path, "/v1/ended")
        XCTAssertEqual(client.endedRequest().value(forHTTPHeaderField: "Authorization"), "Bearer k3y")
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
