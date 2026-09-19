import XCTest
@testable import LFGCore

/// Pure pieces of the media fast path (`.claude/feature/media-fast-path.md`):
/// rendition URLs, the streaming loader's range/length/type helpers, and the
/// "does this URL get the Access credential" check the video viewer keys on.
final class MediaFastPathTests: XCTestCase {
    private let credential = CloudflareAccessCredential(clientID: "id.access", clientSecret: "secret")

    // MARK: hostFileURL

    func testHostFileURLCarriesPathAndOptionalWidth() throws {
        let client = LFGClient(baseURL: URL(string: "https://lfg-pro.example.com")!)
        let plain = try XCTUnwrap(client.hostFileURL(forPath: "/Users/e/shot.png"))
        let comps = try XCTUnwrap(URLComponents(url: plain, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "/api/file")
        XCTAssertEqual(comps.queryItems, [URLQueryItem(name: "path", value: "/Users/e/shot.png")])

        let sized = try XCTUnwrap(client.hostFileURL(forPath: "/Users/e/shot.png", maxWidth: 1200))
        let sizedComps = try XCTUnwrap(URLComponents(url: sized, resolvingAgainstBaseURL: false))
        XCTAssertEqual(sizedComps.queryItems, [
            URLQueryItem(name: "path", value: "/Users/e/shot.png"),
            URLQueryItem(name: "w", value: "1200"),
        ])
    }

    func testHostFileURLIgnoresNonPositiveWidth() throws {
        let client = LFGClient(baseURL: URL(string: "http://127.0.0.1:8766")!)
        let url = try XCTUnwrap(client.hostFileURL(forPath: "/a b/c.png", maxWidth: 0))
        XCTAssertFalse(url.absoluteString.contains("w="))
        XCTAssertTrue(url.absoluteString.contains("path=/a%20b/c.png"))
    }

    // MARK: authenticatesRequests

    func testAuthenticatesOnlySameOriginWithCredential() {
        let base = URL(string: "https://lfg-pro.example.com")!
        let withCred = LFGClient(baseURL: base, accessCredential: credential)
        XCTAssertTrue(withCred.authenticatesRequests(to: URL(string: "https://lfg-pro.example.com/api/file?path=/x.mov")!))
        XCTAssertTrue(withCred.authenticatesRequests(to: URL(string: "https://LFG-PRO.example.com:443/api/file")!))
        XCTAssertFalse(withCred.authenticatesRequests(to: URL(string: "https://cdn.example.com/x.mov")!))
        XCTAssertFalse(withCred.authenticatesRequests(to: URL(string: "http://lfg-pro.example.com/api/file")!))

        let noCred = LFGClient(baseURL: base)
        XCTAssertFalse(noCred.authenticatesRequests(to: URL(string: "https://lfg-pro.example.com/api/file")!))
    }

    // MARK: StreamingRange

    func testRangeHeaderForBoundedAndOpenRequests() {
        XCTAssertEqual(StreamingRange.header(offset: 0, length: 2, toEnd: false), "bytes=0-1")
        XCTAssertEqual(StreamingRange.header(offset: 1_048_576, length: 65_536, toEnd: false), "bytes=1048576-1114111")
        XCTAssertEqual(StreamingRange.header(offset: 4096, length: 65_536, toEnd: true), "bytes=4096-")
        XCTAssertEqual(StreamingRange.header(offset: 0, length: 0, toEnd: false), "bytes=0-")
        XCTAssertEqual(StreamingRange.header(offset: -5, length: 10, toEnd: false), "bytes=0-9")
    }

    func testTotalLengthPrefersContentRange() {
        XCTAssertEqual(StreamingRange.totalLength(contentRange: "bytes 0-1/235826042", contentLength: 2), 235_826_042)
        XCTAssertEqual(StreamingRange.totalLength(contentRange: " bytes 100-199/5000 ", contentLength: nil), 5000)
        XCTAssertEqual(StreamingRange.totalLength(contentRange: nil, contentLength: 777), 777)
        XCTAssertEqual(StreamingRange.totalLength(contentRange: "bytes */5000", contentLength: nil), 5000) // "*/N" is still a total
        XCTAssertNil(StreamingRange.totalLength(contentRange: "garbage", contentLength: nil))
        XCTAssertNil(StreamingRange.totalLength(contentRange: nil, contentLength: -1))
    }

    func testUniformTypeFromMimeThenExtension() {
        XCTAssertEqual(StreamingRange.uniformType(mimeType: "video/quicktime", pathExtension: "mov"), "com.apple.quicktime-movie")
        XCTAssertEqual(StreamingRange.uniformType(mimeType: "video/mp4; charset=binary", pathExtension: "mov"), "public.mpeg-4")
        XCTAssertEqual(StreamingRange.uniformType(mimeType: "application/octet-stream", pathExtension: "MOV"), "com.apple.quicktime-movie")
        XCTAssertEqual(StreamingRange.uniformType(mimeType: nil, pathExtension: "mp4"), "public.mpeg-4")
        XCTAssertEqual(StreamingRange.uniformType(mimeType: nil, pathExtension: ""), "public.mpeg-4")
    }
}
