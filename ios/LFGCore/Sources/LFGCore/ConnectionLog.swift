import Foundation
import os

/// What part of the connection stack an entry came from. Kept coarse on purpose
/// — the point of a category is to let a human scan a 2000-line timeline for
/// "what did the *path* do around 14:32", not to build a taxonomy.
public enum ConnectionLogCategory: String, Sendable, Codable, CaseIterable {
    /// `NWPathMonitor` updates: status, interfaces, expensive/constrained.
    case path
    /// `HostState` transitions, with the signal that caused them.
    case state
    /// `HostLink` state machine: dial, backoff, redial decisions.
    case link
    /// The `/api/events` stream itself: connect, first byte, heartbeat, end.
    case stream
    /// REST reachability probes from the reconcile loop.
    case probe
    /// Keepalive pings and their RTT.
    case keepalive
    /// App lifecycle: foreground, background, launch, suspension gaps.
    case lifecycle
    /// Outbound sends and their routing.
    case send

    /// Single-letter column for the rendered line — keeps the timeline narrow
    /// enough to read on a phone.
    var glyph: String {
        switch self {
        case .path: return "NET"
        case .state: return "STA"
        case .link: return "LNK"
        case .stream: return "STR"
        case .probe: return "PRB"
        case .keepalive: return "KAL"
        case .lifecycle: return "APP"
        case .send: return "SND"
        }
    }
}

/// One timestamped line of the connection timeline.
public struct ConnectionLogEntry: Sendable, Equatable {
    public let at: Date
    public let category: ConnectionLogCategory
    /// Short host label (`Host.label`), or nil for device-wide events.
    public let host: String?
    public let message: String

    public init(at: Date, category: ConnectionLogCategory, host: String?, message: String) {
        self.at = at
        self.category = category
        self.host = host
        self.message = message
    }

    /// The persisted / exported representation. One line, parseable by eye:
    /// `14:32:07.412 NET [pro] path=satisfied ifaces=cellular expensive=true`
    public func rendered(formatter: DateFormatter) -> String {
        let stamp = formatter.string(from: at)
        let who = host.map { " [\($0)]" } ?? ""
        return "\(stamp) \(category.glyph)\(who) \(message)"
    }
}

/// A bounded, persistent record of everything the connection layer does.
///
/// This exists because the "iOS client disconnects" symptom has now had three
/// separate diagnosis documents written against it, each reasoning from a
/// verbally-reported symptom plus server-side logs, because **the client emits
/// no connection timeline**. One of those rounds asserted a root cause that was
/// later retracted. The cure for that is not a better theory; it is a record.
///
/// Two storage tiers, deliberately:
///   - an in-memory ring (`entries`) that the in-app viewer renders, bounded so
///     a long session cannot grow unbounded;
///   - an append-only file that **outlives the process**, because on cellular
///     the interesting window is very often the one right before iOS suspends
///     or kills us. A ring buffer alone would lose exactly the evidence we came
///     for.
///
/// Every entry is also mirrored to `os.Logger`, so a tethered device streams the
/// same timeline live (`flowdeck logs`) without anyone opening Settings.
public final class ConnectionLog: @unchecked Sendable {
    /// In-memory entries kept for the viewer. ~2000 lines is a couple of hours
    /// of a healthy connection and far longer than any drop investigation needs.
    public static let ringCapacity = 2000

    /// Bytes of on-disk history to keep. Sized so a full file is still
    /// shareable over Messages/Mail without truncation.
    public static let fileByteCap = 512 * 1024

    /// After a rotation, how much of the tail survives. Keeping less than the
    /// cap is what makes rotation amortised — otherwise every subsequent write
    /// would re-trigger it.
    public static let fileBytesAfterRotate = 256 * 1024

    public static let shared = ConnectionLog()

    private let lock = NSLock()
    private var ring: [ConnectionLogEntry] = []
    /// Rendered lines not yet written to disk.
    private var pending: [String] = []
    private let fileURL: URL?
    private let logger = Logger(subsystem: "com.eugenechan.lfg", category: "connection")

    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let fullStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// - Parameter directory: where the persistent file lives. `nil` disables
    ///   persistence (used by tests that only exercise the ring).
    public init(directory: URL? = ConnectionLog.defaultDirectory()) {
        self.fileURL = directory?.appendingPathComponent("connection-log.txt")
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Application Support is the right home: it is backed up, not purged under
    /// storage pressure the way Caches is, and not user-visible in Files.
    public static func defaultDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    // MARK: Recording

    public func log(_ category: ConnectionLogCategory, _ message: String,
                    host: String? = nil, at: Date = Date()) {
        let entry = ConnectionLogEntry(at: at, category: category, host: host, message: message)
        let line = entry.rendered(formatter: stamp)
        lock.lock()
        ring.append(entry)
        if ring.count > Self.ringCapacity {
            ring.removeFirst(ring.count - Self.ringCapacity)
        }
        pending.append(line)
        lock.unlock()
        logger.log("\(line, privacy: .public)")
        // Flush EVERY entry rather than batching.
        //
        // Batching was the first design and a live capture immediately showed
        // why it is wrong here: iOS can suspend or kill the app at any moment,
        // and the entries a batch is holding are by definition the most recent
        // ones — i.e. exactly the ones describing the drop we are trying to
        // catch. A diagnostic that reliably loses its own punchline is worse
        // than none, because it looks complete.
        //
        // The cost is genuinely small: the loggers here are heartbeats and
        // keepalives (one per 10s per host), path changes, and state
        // transitions. Stream replay logs only its FIRST event, not every one,
        // so even a large catch-up is a handful of lines. That is well under
        // one ~80-byte append per second.
        flush()
    }

    /// Write a launch banner. Called once at startup so a shared log makes it
    /// obvious where one run ends and the next begins — the single most common
    /// misreading of these files is counting events across a restart boundary.
    public func logLaunch(version: String, build: String, at: Date = Date()) {
        log(.lifecycle,
            "=== launch v\(version) (\(build)) — \(fullStamp.string(from: at)) ===",
            at: at)
        flush()
    }

    // MARK: Reading

    /// Newest-first, for the viewer.
    public func recentEntries() -> [ConnectionLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return ring.reversed()
    }

    /// The full shareable text: everything on disk (including previous runs)
    /// followed by anything not yet flushed.
    public func exportText() -> String {
        flush()
        lock.lock(); defer { lock.unlock() }
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return ring.map { $0.rendered(formatter: stamp) }.joined(separator: "\n")
        }
        return text
    }

    // MARK: Persistence

    /// Append pending lines to the file, rotating if it has outgrown the cap.
    /// Safe to call from anywhere; a no-op when there is nothing to write.
    public func flush() {
        lock.lock()
        guard !pending.isEmpty, let fileURL else { lock.unlock(); return }
        let chunk = pending.joined(separator: "\n") + "\n"
        pending.removeAll(keepingCapacity: true)
        lock.unlock()

        guard let data = chunk.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
        rotateIfNeeded()
    }

    /// Keep the file bounded by dropping the OLDEST bytes — the tail is what
    /// matters, since an investigation always starts from "it just dropped".
    /// Trims forward to the next newline so the file never opens mid-line.
    private func rotateIfNeeded() {
        guard let fileURL else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > Self.fileByteCap else { return }
        guard var data = try? Data(contentsOf: fileURL) else { return }
        data = data.suffix(Self.fileBytesAfterRotate)
        if let nl = data.firstIndex(of: 0x0A) {
            data = data.suffix(from: data.index(after: nl))
        }
        var out = Data("=== log rotated — older entries dropped ===\n".utf8)
        out.append(data)
        try? out.write(to: fileURL)
    }

    /// Test seam: drop everything, on disk and in memory.
    public func reset() {
        lock.lock()
        ring.removeAll()
        pending.removeAll()
        let url = fileURL
        lock.unlock()
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
