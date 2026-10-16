import Foundation

// MARK: - Frame → LiveEvent decoding

private struct MsgPayload: Decodable { let sid: String; let m: SessionMessage }
private struct ResetPayload: Decodable { let sid: String }
private struct PromptPayload: Decodable { let sid: String; let prompt: AgentPrompt? }
private struct BusyPayload: Decodable { let sid: String; let busy: Bool }
private struct QueuePayload: Decodable { let sid: String; let queue: [QueueItem] }

public enum LiveEventDecoder {
    /// Decode a parsed SSE frame into a typed `LiveEvent`, or nil if it's a
    /// heartbeat-only comment we don't surface / an unknown event.
    public static func decode(_ frame: SSEFrame, sessionIdHint: String? = nil) -> LiveEvent? {
        if frame.isComment { return .heartbeat }
        guard let data = frame.data.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        switch frame.event {
        case "msg":
            if let p = try? dec.decode(MsgPayload.self, from: data) {
                return .message(sid: p.sid, message: p.m)
            }
        case "reset":
            if let p = try? dec.decode(ResetPayload.self, from: data) {
                return .reset(sid: p.sid)
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
            if var ack = try? dec.decode(QueueAck.self, from: data),
               !ack.kind.isEmpty,
               !ack.clientId.isEmpty {
                ack.sid = ack.sid ?? sessionIdHint
                return .queueAck(sid: ack.sid, ack: ack)
            }
            if let p = try? dec.decode(QueuePayload.self, from: data) {
                return .queue(sid: p.sid, queue: p.queue)
            }
        case "browser_frame":
            if let frame = try? dec.decode(BrowserFrame.self, from: data) {
                return .browserFrame(frame)
            }
        default:
            return nil
        }
        return nil
    }
}
