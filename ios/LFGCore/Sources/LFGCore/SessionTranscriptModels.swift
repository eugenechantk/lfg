import Foundation

// Shared transcript contract for native Sessions and durable Chats.
public struct SessionMessage: Codable, Sendable, Identifiable, Hashable {
    public var id: String?            // transcript uuid; may be null
    public var role: String           // user | assistant | tool | system
    public var kind: String           // text | thinking | tool_use | tool_result | system_notice | memory_citation
    public var text: String
    public var ts: Double?
    public var apiError: Bool?
    public var html: String?
    /// Tool rows (B11): the call id, on both the call and its result, so the
    /// two can be paired. nil on older hosts and on non-tool rows.
    public var toolUseId: String?
    /// A Claude call's tool name and what it acts on (command, file, pattern…).
    public var tool: ToolCallInfo?
    /// A Claude result that failed.
    public var isError: Bool?

    /// Stable identity for SwiftUI lists even when `id` is null.
    public var stableID: String {
        if let id, !id.isEmpty { return id }
        return "\(role)|\(kind)|\(ts ?? 0)|\(text.hashValue)"
    }

    public init(
        id: String? = nil, role: String = "assistant", kind: String = "text",
        text: String = "", ts: Double? = nil, apiError: Bool? = nil, html: String? = nil,
        toolUseId: String? = nil, tool: ToolCallInfo? = nil, isError: Bool? = nil
    ) {
        self.id = id; self.role = role; self.kind = kind; self.text = text
        self.ts = ts; self.apiError = apiError; self.html = html
        self.toolUseId = toolUseId; self.tool = tool; self.isError = isError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        role = (try c.decodeIfPresent(String.self, forKey: .role)) ?? "assistant"
        kind = (try c.decodeIfPresent(String.self, forKey: .kind)) ?? "text"
        text = (try c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        ts = try c.decodeIfPresent(Double.self, forKey: .ts)
        apiError = try c.decodeIfPresent(Bool.self, forKey: .apiError)
        html = try c.decodeIfPresent(String.self, forKey: .html)
        // Decorations: a malformed value must never fail the message.
        toolUseId = try? c.decodeIfPresent(String.self, forKey: .toolUseId)
        tool = (try? c.decodeIfPresent(ToolCallInfo.self, forKey: .tool)) ?? nil
        isError = try? c.decodeIfPresent(Bool.self, forKey: .isError)
    }
}

/// A tool call's name and what it acts on, as the host reports it (B11).
public struct ToolCallInfo: Codable, Sendable, Hashable {
    public var name: String
    public var target: String?
    public init(name: String, target: String? = nil) { self.name = name; self.target = target }
}

public struct MessagesResponse: Codable, Sendable {
    public var id: String?
    public var messages: [SessionMessage]
    public var total: Int?
    public var nextBefore: Int?
}
