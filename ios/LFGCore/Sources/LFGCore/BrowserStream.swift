import Foundation

public struct BrowserStreamWindow: Decodable, Identifiable, Sendable, Hashable {
    public let id: Int
    public let app: String
    public let title: String
}

/// Stream protocol is separate from durable session/transcript events.
public struct BrowserStreamMessage: Decodable, Sendable {
    public let type: String
    public let windows: [BrowserStreamWindow]?
    public let accessibility: Bool?
    public let message: String?
    public let enabled: Bool?
    public let frameId: Int?
    public let windowId: Int?
    public let width: Int?
    public let height: Int?
    public let jpeg: Data?
}

public struct BrowserStreamCommand: Encodable, Sendable {
    public var type: String
    public var seq: Int?
    public var frameId: Int?
    public var windowId: Int?
    public var enabled: Bool?
    public var text: String?
    public var key: String?
    public var action: String?
    public var button: String?
    public var x: Double?
    public var y: Double?
    public var dy: Double?
    public init(type: String, seq: Int? = nil, frameId: Int? = nil, windowId: Int? = nil,
                enabled: Bool? = nil, text: String? = nil, key: String? = nil,
                action: String? = nil, button: String? = nil, x: Double? = nil,
                y: Double? = nil, dy: Double? = nil) {
        self.type = type; self.seq = seq; self.frameId = frameId; self.windowId = windowId
        self.enabled = enabled; self.text = text; self.key = key; self.action = action
        self.button = button; self.x = x; self.y = y; self.dy = dy
    }
}
