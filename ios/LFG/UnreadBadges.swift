import SwiftUI
import UserNotifications
import os

enum AppBadge {
    private static let log = Logger(subsystem: "dev.omg.lfg", category: "app-badge")

    static func set(_ count: Int) {
        let badgeCount = max(0, count)
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(badgeCount)
            } catch {
                log.error("set badge count failed: \(error.localizedDescription)")
            }
        }
    }
}
