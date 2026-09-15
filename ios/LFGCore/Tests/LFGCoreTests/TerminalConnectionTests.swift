import XCTest
@testable import LFGCore

final class TerminalConnectionTests: XCTestCase {
    private let credential = CloudflareAccessCredential(clientID: "id.access", clientSecret: "secret")

    func testHTTPSHostBecomesWSSWithSessionAndSize() throws {
        let client = LFGClient(baseURL: URL(string: "https://lfg-pro.example.com")!, accessCredential: credential)
        let request = client.terminalRequest(session: "phone", cols: 48, rows: 30)
        let url = try XCTUnwrap(request.url)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.scheme, "wss")
        XCTAssertEqual(comps.host, "lfg-pro.example.com")
        XCTAssertEqual(comps.path, "/api/term")
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q, ["session": "phone", "cols": "48", "rows": "30"])
    }

    func testHTTPHostWithPortBecomesWS() throws {
        let client = LFGClient(baseURL: URL(string: "http://127.0.0.1:8791")!)
        let url = try XCTUnwrap(client.terminalRequest(session: "phone", cols: 80, rows: 24).url)
        XCTAssertEqual(url.scheme, "ws")
        XCTAssertEqual(url.port, 8791)
        XCTAssertEqual(url.path, "/api/term")
    }

    func testTerminalRequestCarriesAccessHeaders() {
        let client = LFGClient(baseURL: URL(string: "https://lfg-pro.example.com")!, accessCredential: credential)
        let request = client.terminalRequest(session: "phone", cols: 80, rows: 24)
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "id.access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "secret")
    }

    func testNoCredentialMeansNoAccessHeaders() {
        let client = LFGClient(baseURL: URL(string: "http://127.0.0.1:8791")!)
        let request = client.terminalRequest(session: "phone", cols: 80, rows: 24)
        XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Id"))
    }

    func testBasePathIsPreserved() throws {
        let client = LFGClient(baseURL: URL(string: "https://host.example.com/lfg")!)
        let url = try XCTUnwrap(client.terminalRequest(session: "phone", cols: 80, rows: 24).url)
        XCTAssertEqual(url.path, "/lfg/api/term")
    }

    func testResizeControlFrameMatchesServerFormat() throws {
        let text = TerminalControl.resize(cols: 120, rows: 40)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(obj["t"] as? String, "resize")
        XCTAssertEqual(obj["cols"] as? Int, 120)
        XCTAssertEqual(obj["rows"] as? Int, 40)
    }

    func testDimensionsAreClampedToServerRange() {
        XCTAssertEqual(TerminalControl.clamp(0), 1)
        XCTAssertEqual(TerminalControl.clamp(9999), 500)
        XCTAssertEqual(TerminalControl.clamp(80), 80)
    }

    func testCloseCodesMapToDisconnectReasons() {
        XCTAssertEqual(TerminalDisconnect(closeCode: .normalClosure, error: nil), .shellExited)
        XCTAssertEqual(TerminalDisconnect(closeCode: .invalid, error: "The network connection was lost."),
                       .network("The network connection was lost."))
        XCTAssertEqual(TerminalDisconnect(closeCode: .invalid, error: nil), .network(nil))
        XCTAssertEqual(TerminalDisconnect(httpStatus: 403), .forbidden)
    }

    func testNetworkDisconnectShowsPlainMessage() {
        XCTAssertEqual(TerminalDisconnect.network("The operation couldn’t be completed. Socket is not connected").message,
                       "Connection lost")
        XCTAssertEqual(TerminalDisconnect.shellExited.message, "Shell exited")
    }

    func testHostLabelsAreDisambiguatedOnlyWhenTheyClash() throws {
        let data = Data(#"""
        [{"url":"http://127.0.0.1:9982","name":"Eugenes-MacBook-Pro","isDefault":true},
         {"url":"https://lfg-pro.example.com","name":"Eugenes-MacBook-Pro","isDefault":false},
         {"url":"https://air.example.com","name":"Eugenes-MacBook-Air","isDefault":false}]
        """#.utf8)
        let hosts = try JSONDecoder().decode([LFGCore.Host].self, from: data)
        XCTAssertEqual(hosts[0].disambiguatedLabel(among: hosts), "Eugenes-MacBook-Pro (127.0.0.1:9982)")
        XCTAssertEqual(hosts[1].disambiguatedLabel(among: hosts), "Eugenes-MacBook-Pro (lfg-pro.example.com)")
        XCTAssertEqual(hosts[2].disambiguatedLabel(among: hosts), "Eugenes-MacBook-Air")
        XCTAssertEqual(hosts[0].disambiguator(among: hosts), "127.0.0.1:9982")
        XCTAssertNil(hosts[2].disambiguator(among: hosts))
    }

    /// Real seam: a live `/api/term` socket. Runs only when LFG_TERM_TEST_URL
    /// points at a server (e.g. `http://127.0.0.1:8791`).
    func testLiveTerminalRoundTrip() async throws {
        guard let base = ProcessInfo.processInfo.environment["LFG_TERM_TEST_URL"],
              let client = LFGClient(string: base) else {
            throw XCTSkip("set LFG_TERM_TEST_URL to run against a live server")
        }
        let socket = TerminalSocket(request: client.terminalRequest(session: "swifttest", cols: 80, rows: 24))
        var output = ""
        let got = expectation(description: "echo output")
        let box = OutputBox()
        socket.onOutput = { data in
            if box.append(data).contains("SWIFT_42"), box.markFulfilled() { got.fulfill() }
        }
        socket.connect()
        try await Task.sleep(for: .seconds(2))
        socket.send(Data("echo SWIFT_$((40+2))\r".utf8))
        socket.resize(cols: 100, rows: 30)
        await fulfillment(of: [got], timeout: 10)
        output = box.text
        XCTAssertTrue(output.contains("SWIFT_42"))
        socket.disconnect()
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func append(_ data: Data) -> String {
        lock.lock(); defer { lock.unlock() }
        buffer += String(decoding: data, as: UTF8.self)
        return buffer
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return buffer }
    private var fulfilled = false
    /// True exactly once, so an expectation is fulfilled a single time.
    func markFulfilled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fulfilled { return false }
        fulfilled = true
        return true
    }
}
