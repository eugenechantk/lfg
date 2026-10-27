import Foundation

/// RCDP v2 framing. Each WebSocket binary message holds one complete packet.
public struct SpaceVideoPacket: Sendable {
    public struct Descriptor: Decodable, Sendable {
        public let session_id: String
        public let sequence: UInt64
        public let codec_epoch: Int
        public let width_px: Int
        public let height_px: Int
        public let codec: String
        public let keyframe: Bool
    }
    private struct Header: Decodable { let direction: String; let message: Descriptor }
    public let descriptor: Descriptor
    public let payload: Data
    public init(_ data: Data) throws {
        func invalid() -> MessageSpaceError { MessageSpaceError(message: "Invalid Space video frame") }
        guard data.count >= 8, data.count <= 65 * 1024 * 1024 else { throw invalid() }
        let bytes = [UInt8](data.prefix(8))
        let headerSize = bytes[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        let payloadSize = bytes[4..<8].reduce(0) { ($0 << 8) | Int($1) }
        guard headerSize <= 1024 * 1024, payloadSize <= 64 * 1024 * 1024,
              8 + headerSize + payloadSize == data.count else { throw invalid() }
        let header = try JSONDecoder().decode(Header.self, from: data.subdata(in: 8..<(8 + headerSize)))
        guard header.direction == "video", (1...8192).contains(header.message.width_px),
              (1...8192).contains(header.message.height_px), ["h264", "png", "bgra"].contains(header.message.codec) else { throw invalid() }
        descriptor = header.message
        payload = data.subdata(in: (8 + headerSize)..<data.count)
    }
    /// Split Annex B start codes without assuming three or four byte markers.
    public static func nalUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var ranges: [Range<Int>] = []
        var start: Int?
        var i = 0
        while i + 2 < bytes.count {
            let length: Int
            if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 { length = 3 }
            else if i + 3 < bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 { length = 4 }
            else { i += 1; continue }
            if let start, i > start { ranges.append(start..<i) }
            i += length; start = i
        }
        if let start, start < bytes.count { ranges.append(start..<bytes.count) }
        return ranges.map { Data(bytes[$0]) }
    }
}

extension MessageSpacesClient {
    public func streamRequest(_ id: String) -> URLRequest {
        var request = host.request("/api/message/spaces/\(id)/stream")
        var parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        request.url = parts.url
        request.timeoutInterval = 25
        return request
    }
}
