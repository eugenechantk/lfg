import Foundation
import Testing
@testable import LFGCore

@Suite struct SpaceVideoPacketTests {
    func packet(width: Int = 1280, sequence: UInt64 = 307803458471) throws -> Data {
        let header = try JSONSerialization.data(withJSONObject: ["direction": "video", "message": ["session_id": "media-test", "sequence": sequence, "codec_epoch": 1, "width_px": width, "height_px": 800, "codec": "h264", "keyframe": true]])
        var data = Data()
        for size in [UInt32(header.count), 4] { var value = size.bigEndian; data.append(Data(bytes: &value, count: 4)) }
        data.append(header); data.append(contentsOf: [0, 0, 1, 0x65]); return data
    }
    @Test func parsesRealWireShapeAndLargeSequences() throws {
        let result = try SpaceVideoPacket(packet())
        #expect(result.descriptor.sequence == 307803458471)
        #expect(result.descriptor.width_px == 1280)
        #expect(result.payload == Data([0, 0, 1, 0x65]))
    }
    @Test func rejectsShortOversizeTruncatedAndInvalidGeometry() throws {
        #expect(throws: (any Error).self) { try SpaceVideoPacket(Data([0])) }
        #expect(throws: (any Error).self) { try SpaceVideoPacket(Data([255,255,255,255,0,0,0,0])) }
        var truncated = try packet(); truncated.removeLast()
        #expect(throws: (any Error).self) { try SpaceVideoPacket(truncated) }
        #expect(throws: (any Error).self) { try SpaceVideoPacket(packet(width: 0)) }
    }
    @Test func extractsMixedAnnexBMarkersAndIgnoresEmptyUnits() {
        #expect(SpaceVideoPacket.nalUnits(Data([0,0,0,1,0x67,2,0,0,1,0x68,3,0,0,0,1,0x65,4])) == [Data([0x67,2]), Data([0x68,3]), Data([0x65,4])])
        #expect(SpaceVideoPacket.nalUnits(Data()).isEmpty)
    }
    @Test func streamUsesSelectedHostAndAuthentication() {
        let client = MessageSpacesClient(host: ScheduledTaskHost(id: "remote", name: "Remote", baseURL: URL(string: "https://remote.example")!, headers: ["Authorization": "Bearer test"]))
        let request = client.streamRequest("owned")
        #expect(request.url?.absoluteString == "wss://remote.example/api/message/spaces/owned/stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test")
    }
}
