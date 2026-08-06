import XCTest
@testable import LFGCore

/// The log exists to survive the thing it is recording. These tests pin the two
/// properties that make that true — it stays bounded, and it outlives the
/// process — plus the rendering an investigator actually reads.
final class ConnectionLogTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("connlog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    // MARK: SC1 — bounded ring

    func testRingKeepsTheNewestEntriesAndEvictsTheOldest() {
        let log = ConnectionLog(directory: nil)
        for i in 0..<(ConnectionLog.ringCapacity + 250) {
            log.log(.stream, "event \(i)", at: at(Double(i)))
        }
        let entries = log.recentEntries()
        XCTAssertEqual(entries.count, ConnectionLog.ringCapacity,
                       "the ring must not grow without bound over a long session")
        // Newest-first: entry 0 is the last one recorded.
        XCTAssertEqual(entries.first?.message, "event \(ConnectionLog.ringCapacity + 249)")
        XCTAssertEqual(entries.last?.message, "event 250",
                       "the oldest entries are the ones dropped")
    }

    func testEntriesComeBackNewestFirst() {
        let log = ConnectionLog(directory: nil)
        log.log(.path, "first", at: at(0))
        log.log(.path, "second", at: at(1))
        log.log(.path, "third", at: at(2))
        XCTAssertEqual(log.recentEntries().map(\.message), ["third", "second", "first"])
    }

    // MARK: SC2 — persistence across launches

    func testEntriesWrittenInOneRunAreReadableInTheNext() {
        let runOne = ConnectionLog(directory: dir)
        runOne.log(.path, "path=unsatisfied ifaces=none", at: at(0))
        runOne.log(.state, "live -> noNetwork via networkLost", host: "pro", at: at(1))
        runOne.flush()

        // A fresh instance is what the next launch gets. The evidence from
        // before the kill is precisely what a cellular investigation needs.
        let runTwo = ConnectionLog(directory: dir)
        let text = runTwo.exportText()
        XCTAssertTrue(text.contains("path=unsatisfied ifaces=none"))
        XCTAssertTrue(text.contains("live -> noNetwork via networkLost"))
        XCTAssertTrue(text.contains("[pro]"), "the host column must survive the round trip")
    }

    /// The property a batched writer quietly broke: iOS can kill the app at any
    /// moment, and whatever a batch is holding is by definition the newest
    /// entries — the ones describing the drop. A live capture showed only the
    /// launch banner on disk while ~30 entries sat in memory.
    func testEveryEntryIsOnDiskWithoutAnExplicitFlush() throws {
        let log = ConnectionLog(directory: dir)
        for i in 0..<5 { log.log(.stream, "hb gap=\(i)s", at: at(Double(i))) }
        // No flush() — simulate the process dying right here.
        let onDisk = try String(contentsOf: dir.appendingPathComponent("connection-log.txt"),
                                encoding: .utf8)
        for i in 0..<5 {
            XCTAssertTrue(onDisk.contains("hb gap=\(i)s"),
                          "entry \(i) was lost — a diagnostic that drops its own punchline is worse than none")
        }
    }

    func testExportIncludesEntriesNotYetFlushed() {
        let log = ConnectionLog(directory: dir)
        log.log(.keepalive, "rtt=41ms", at: at(0))
        // No explicit flush: exportText must flush for the caller, or a share
        // taken right after a drop would be missing the drop.
        XCTAssertTrue(log.exportText().contains("rtt=41ms"))
    }

    func testLaunchBannerSeparatesRuns() {
        let runOne = ConnectionLog(directory: dir)
        runOne.logLaunch(version: "1.2.0", build: "202608061000", at: at(0))
        runOne.log(.stream, "connect since=1", at: at(1))
        let runTwo = ConnectionLog(directory: dir)
        runTwo.logLaunch(version: "1.2.0", build: "202608061500", at: at(600))
        let text = runTwo.exportText()
        XCTAssertTrue(text.contains("202608061000"))
        XCTAssertTrue(text.contains("202608061500"),
                      "both launch banners must be present so events are never counted across a restart")
    }

    func testFileIsCappedByDroppingTheOldestBytes() throws {
        let log = ConnectionLog(directory: dir)
        // ~600 bytes per entry × 2000 ≈ 1.2 MB, comfortably past the cap.
        let filler = String(repeating: "x", count: 600)
        for i in 0..<2000 {
            log.log(.stream, "\(i) \(filler)", at: at(Double(i)))
        }
        log.flush()

        let path = dir.appendingPathComponent("connection-log.txt")
        let size = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: path.path))[.size] as? Int)
        XCTAssertLessThanOrEqual(size, ConnectionLog.fileByteCap,
                                 "an unbounded file would eventually be unshareable")

        let text = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(text.contains("1999 "), "the newest entries are the ones kept")
        XCTAssertFalse(text.contains("\n0 "), "the oldest entries are the ones dropped")
        XCTAssertTrue(text.hasPrefix("=== log rotated"),
                      "rotation must announce itself, or the file reads as complete history")
    }

    func testRotationNeverLeavesAPartialFirstLine() throws {
        let log = ConnectionLog(directory: dir)
        let filler = String(repeating: "y", count: 600)
        for i in 0..<2000 { log.log(.probe, "\(i) \(filler)", at: at(Double(i))) }
        log.flush()

        let text = try String(contentsOf: dir.appendingPathComponent("connection-log.txt"),
                              encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        let firstReal = try XCTUnwrap(lines.dropFirst().first)   // skip the rotation banner
        XCTAssertTrue(firstReal.contains("PRB"),
                      "a mid-line trim would open the file on a fragment: \(firstReal.prefix(40))")
    }

    // MARK: SC3 — rendering

    func testRenderedLineCarriesTimeCategoryHostAndMessage() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        let entry = ConnectionLogEntry(at: t0, category: .path, host: "pro",
                                       message: "path=satisfied ifaces=cellular expensive=true")
        XCTAssertEqual(entry.rendered(formatter: f),
                       "22:13:20.000 NET [pro] path=satisfied ifaces=cellular expensive=true")
    }

    func testDeviceWideEntriesOmitTheHostColumn() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        let entry = ConnectionLogEntry(at: t0, category: .lifecycle, host: nil,
                                       message: "foreground after 412s backgrounded")
        XCTAssertEqual(entry.rendered(formatter: f),
                       "22:13:20 APP foreground after 412s backgrounded")
    }

    /// A live capture showed one machine logged as "localhost", "localhost:8766"
    /// and "Eugenes-MacBook-Pro" in a single timeline, because three components
    /// each reached for a different display name and `Host.name` is resolved
    /// from the server *after* connecting. Correlating events across components
    /// is the entire point of the log, so the label has to be one stable value.
    func testEveryComponentNamesTheSameHostIdentically() {
        let host = LFGCore.Host(url: "http://localhost:8766")
        let client = try! XCTUnwrap(LFGClient(string: "http://localhost:8766"))
        XCTAssertEqual(host.logLabel, client.logLabel)
        XCTAssertEqual(host.logLabel, "localhost:8766")
    }

    func testLogLabelIgnoresMutableDisplayNames() {
        // `name` arrives from /api/info mid-session and `displayName` is user
        // editable; neither may rename a host halfway down the timeline.
        var host = LFGCore.Host(url: "https://pro.tail1234.ts.net")
        XCTAssertEqual(host.logLabel, "pro.tail1234.ts.net")
        host.name = "Eugenes-MacBook-Pro"
        host.displayName = "Work laptop"
        XCTAssertEqual(host.logLabel, "pro.tail1234.ts.net",
                       "the log label must not move when display names change")
    }

    func testEveryCategoryHasADistinctGlyph() {
        let glyphs = ConnectionLogCategory.allCases.map(\.glyph)
        XCTAssertEqual(Set(glyphs).count, glyphs.count,
                       "two categories sharing a glyph makes the timeline unreadable")
        XCTAssertTrue(glyphs.allSatisfy { $0.count == 3 }, "the column must stay aligned")
    }
}
