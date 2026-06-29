import Foundation

/// Pure, testable push-notification helpers shared by the app target. The actual
/// `UNUserNotificationCenter` / `UIApplicationDelegate` wiring lives in the app
/// (`PushManager`); everything that can be reasoned about without Apple's
/// notification runtime lives here so it can be unit-tested.

public enum PushEventKind: String, Sendable, Equatable {
    case needsInput = "needs-input"
    case finished = "finished"
}

/// A decoded push payload. The server sends `{ aps: {...}, sid, kind }`, so the
/// routing fields sit at the top level of `userInfo`.
public struct PushNotification: Sendable, Equatable {
    public let sid: String
    public let kind: PushEventKind?
    /// Compact session snapshot the server embeds so the app can render the
    /// session screen the instant the notification is tapped, before the
    /// reconnect + refresh completes. Nil for older/foreign payloads.
    public let session: Session?

    public init(sid: String, kind: PushEventKind?, session: Session? = nil) {
        self.sid = sid
        self.kind = kind
        self.session = session
    }

    /// Parse the `sid` (and optional `kind` + `session`) out of a notification's
    /// userInfo. Returns nil when there's no usable session id — a foreign/
    /// malformed push shouldn't drive navigation.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let sid = userInfo["sid"] as? String, !sid.isEmpty else { return nil }
        self.sid = sid
        self.kind = (userInfo["kind"] as? String).flatMap(PushEventKind.init(rawValue:))
        self.session = Self.parseSession(userInfo["session"], sid: sid)
    }

    private static func parseSession(_ raw: Any?, sid: String) -> Session? {
        guard let d = raw as? [AnyHashable: Any],
              let id = d["id"] as? String, id == sid else { return nil }
        let activity = (d["lastActivityAt"] as? NSNumber)?.doubleValue ?? (d["lastActivityAt"] as? Double)
        return Session(
            sessionId: id,
            title: (d["title"] as? String) ?? "",
            agent: (d["agent"] as? String) ?? "claude",
            model: d["model"] as? String,
            project: d["project"] as? String,
            cwd: d["cwd"] as? String,
            status: d["status"] as? String,
            lastActivityAt: activity
        )
    }
}

/// Format a raw APNs device token (`Data`) as the lowercase hex string the
/// server stores and uses in the `/3/device/<token>` path.
public func apnsTokenHex(_ token: Data) -> String {
    token.map { String(format: "%02x", $0) }.joined()
}

/// Lifecycle of this device's push registration. A small explicit state machine
/// so the app's flow (and Settings UI) is driven by something unit-testable
/// rather than scattered booleans.
public enum PushRegistrationState: Sendable, Equatable {
    /// Permission hasn't been requested yet.
    case notDetermined
    /// The user denied notification permission — nothing more we can do in-app.
    case denied
    /// Authorized, but we don't yet have an APNs token (registration in flight).
    case authorizing
    /// Authorized and the token has been sent to the server.
    case registered(token: String)
    /// Authorized + got a token, but sending it to the server failed.
    case failed(reason: String)

    public var isActive: Bool {
        if case .registered = self { return true }
        return false
    }
}

public enum PushRegistrationEvent: Sendable, Equatable {
    case permissionGranted
    case permissionDenied
    case gotToken(String)
    case serverAccepted(token: String)
    case serverFailed(reason: String)
}

/// Pure transition function for the registration state machine. Keeping it
/// separate from the side-effecting `PushManager` makes the flow testable.
public func reducePushRegistration(
    _ state: PushRegistrationState,
    _ event: PushRegistrationEvent
) -> PushRegistrationState {
    switch (state, event) {
    case (_, .permissionDenied):
        return .denied
    case (_, .permissionGranted):
        // Granted but no token yet — waiting on APNs.
        if case .registered = state { return state }
        return .authorizing
    case (_, .gotToken):
        return .authorizing
    case (_, .serverAccepted(let token)):
        return .registered(token: token)
    case (_, .serverFailed(let reason)):
        return .failed(reason: reason)
    }
}
