import Foundation

/// One dispatched Server-Sent-Event frame.
public struct SSEFrame: Sendable, Equatable {
    public var event: String     // event name ("message" if unspecified)
    public var data: String      // joined data lines
    public var isComment: Bool   // a `:`-prefixed keep-alive line

    public init(event: String, data: String, isComment: Bool = false) {
        self.event = event; self.data = data; self.isComment = isComment
    }
}

/// Incremental SSE parser. Feed it raw text chunks (handles partial lines) or
/// whole lines; it emits frames as blank-line dispatch boundaries are reached.
/// Pure value type so it's trivially testable without a network.
public struct SSEParser: Sendable {
    private var buffer = ""
    private var dataLines: [String] = []
    private var eventName = ""

    public init() {}

    /// Feed an arbitrary text chunk (may contain 0..n newlines / partial line).
    ///
    /// Splits on the Unicode scalar `\n` rather than `Character`: in Swift a
    /// CRLF (`\r\n`) is a *single* grapheme cluster, so `firstIndex(of: "\n")`
    /// would never match CRLF-terminated SSE lines. Scalar-level splitting fixes
    /// that; the trailing `\r` is then stripped per line.
    public mutating func feed(_ text: String) -> [SSEFrame] {
        buffer += text
        var frames: [SSEFrame] = []
        while let nl = buffer.unicodeScalars.firstIndex(of: "\n") {
            let lineView = buffer.unicodeScalars[buffer.unicodeScalars.startIndex..<nl]
            var line = String(String.UnicodeScalarView(lineView))
            let after = buffer.unicodeScalars.index(after: nl)
            buffer = String(String.UnicodeScalarView(buffer.unicodeScalars[after...]))
            if line.hasSuffix("\r") { line.removeLast() }
            if let f = process(line: line) { frames.append(f) }
        }
        return frames
    }

    /// Feed a single already-split line (e.g. from `URLSession.bytes.lines`).
    public mutating func feedLine(_ rawLine: String) -> SSEFrame? {
        var line = rawLine
        if line.hasSuffix("\r") { line.removeLast() }
        return process(line: line)
    }

    private mutating func process(line: String) -> SSEFrame? {
        if line.isEmpty {
            guard !dataLines.isEmpty || !eventName.isEmpty else { return nil }
            let frame = SSEFrame(
                event: eventName.isEmpty ? "message" : eventName,
                data: dataLines.joined(separator: "\n"),
                isComment: false
            )
            eventName = ""
            dataLines = []
            return frame
        }
        if line.hasPrefix(":") {
            let body = String(line.dropFirst())
            return SSEFrame(event: "", data: stripLeadingSpace(body), isComment: true)
        }
        let (field, value) = splitField(line)
        switch field {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break   // id / retry / unknown fields: ignored for our purposes
        }
        return nil
    }

    private func splitField(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        let field = String(line[line.startIndex..<colon])
        let value = stripLeadingSpace(String(line[line.index(after: colon)...]))
        return (field, value)
    }

    private func stripLeadingSpace(_ s: String) -> String {
        s.hasPrefix(" ") ? String(s.dropFirst()) : s
    }
}

// MARK: - Frame → LiveEvent decoding

private struct MsgPayload: Decodable { let sid: String; let m: SessionMessage }
private struct PromptPayload: Decodable { let sid: String; let prompt: AgentPrompt? }
private struct BusyPayload: Decodable { let sid: String; let busy: Bool }
private struct QueuePayload: Decodable { let sid: String; let queue: [QueueItem] }

public enum LiveEventDecoder {
    /// Decode a parsed SSE frame into a typed `LiveEvent`, or nil if it's a
    /// heartbeat-only comment we don't surface / an unknown event.
    public static func decode(_ frame: SSEFrame) -> LiveEvent? {
        if frame.isComment { return .heartbeat }
        guard let data = frame.data.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        switch frame.event {
        case "msg":
            if let p = try? dec.decode(MsgPayload.self, from: data) {
                return .message(sid: p.sid, message: p.m)
            }
        case "prompt":
            if let p = try? dec.decode(PromptPayload.self, from: data) {
                return .prompt(sid: p.sid, prompt: p.prompt)
            }
        case "busy":
            if let p = try? dec.decode(BusyPayload.self, from: data) {
                return .busy(sid: p.sid, busy: p.busy)
            }
        case "queue":
            if let p = try? dec.decode(QueuePayload.self, from: data) {
                return .queue(sid: p.sid, queue: p.queue)
            }
        default:
            return nil
        }
        return nil
    }
}
