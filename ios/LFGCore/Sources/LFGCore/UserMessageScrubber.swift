import Foundation

/// A stable scroll destination for a transcript entry that renders as a user bubble.
public struct UserMessageAnchor: Identifiable, Equatable, Sendable {
    public let id: String
    public let messageIndex: Int

    public init(id: String, messageIndex: Int) {
        self.id = id
        self.messageIndex = messageIndex
    }
}

/// Pure mapping used by the transcript's trailing-edge user-message index.
public enum UserMessageScrubber {
    /// Returns user-bubble destinations in visual chronological order.
    public static func anchors(in messages: [SessionMessage]) -> [UserMessageAnchor] {
        messages.indices.compactMap { index in
            let message = messages[index]
            guard message.role == "user",
                  message.kind != "tool_use",
                  message.kind != "tool_result",
                  message.kind != "thinking" else { return nil }
            return UserMessageAnchor(id: message.stableID, messageIndex: index)
        }
    }

    /// Maps a vertical point into equal-height anchor bands, clamping overshoot.
    /// Top selects the oldest user turn; bottom selects the newest.
    public static func anchorIndex(
        at verticalPosition: Double,
        height: Double,
        count: Int
    ) -> Int? {
        guard count > 0, height > 0 else { return nil }
        let progress = min(max(verticalPosition / height, 0), 1)
        return min(Int(progress * Double(count)), count - 1)
    }

    /// The inverted transcript renders the newest `window` messages. Grow that
    /// suffix just enough to include an older target before asking SwiftUI to scroll.
    public static func requiredWindow(
        totalMessages: Int,
        targetMessageIndex: Int,
        currentWindow: Int
    ) -> Int {
        guard totalMessages > 0 else { return currentWindow }
        let clampedIndex = min(max(targetMessageIndex, 0), totalMessages - 1)
        return max(currentWindow, totalMessages - clampedIndex)
    }
}
