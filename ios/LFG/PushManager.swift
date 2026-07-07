import SwiftUI
import UserNotifications
import LFGCore
import os

/// Owns the device's push-notification lifecycle: requesting permission,
/// receiving the APNs device token from the system, registering it with the lfg
/// server, and routing a tapped notification to its session. The pure transition
/// logic lives in `LFGCore` (`reducePushRegistration`, `PushNotification`); this
/// type is the side-effecting shell around it.
///
/// A `shared` reference exists because UIKit instantiates the `AppDelegate`
/// independently of the SwiftUI `App`, and the delegate's remote-notification
/// callbacks need to reach the same manager the UI observes.
@MainActor
@Observable
final class PushManager {
    static let shared = PushManager()

    private(set) var state: PushRegistrationState = .notDetermined

    // Wired up from LFGApp once settings/store exist.
    private weak var settings: AppSettings?
    private weak var store: SessionStore?

    private var latestToken: String?
    private let log = Logger(subsystem: "dev.omg.lfg", category: "push")

    private init() {}

    func configure(settings: AppSettings, store: SessionStore) {
        self.settings = settings
        self.store = store
    }

    // A Debug build run from Xcode talks to the APNs sandbox; Release
    // (TestFlight/App Store) talks to production. This must match the
    // `aps-environment` entitlement baked into the build.
    private var apnsEnv: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// Ask for permission if we haven't yet, and (if granted) kick off remote
    /// registration. Safe to call on every launch — it reads the current
    /// authorization status first and won't re-prompt.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .denied:
            apply(.permissionDenied)
            return
        case .authorized, .provisional, .ephemeral:
            apply(.permissionGranted)
            registerForRemote()
            return
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    apply(.permissionGranted)
                    registerForRemote()
                } else {
                    apply(.permissionDenied)
                }
            } catch {
                apply(.serverFailed(reason: error.localizedDescription))
            }
        @unknown default:
            break
        }
    }

    private func registerForRemote() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: AppDelegate callbacks

    func didRegister(deviceToken: Data) {
        let hex = apnsTokenHex(deviceToken)
        latestToken = hex
        apply(.gotToken(hex))
        Task { await sendToServer(hex) }
    }

    func didFailToRegister(error: Error) {
        log.error("remote registration failed: \(error.localizedDescription)")
        apply(.serverFailed(reason: error.localizedDescription))
    }

    /// Re-send the current token to the server — used after the host changes, so
    /// a freshly-connected box learns about this device.
    func reregisterIfPossible() {
        guard let token = latestToken else { return }
        Task { await sendToServer(token) }
    }

    private func sendToServer(_ token: String) async {
        // Register the token with EVERY host so any machine can push to this
        // device (multi-host). Accepted if at least one host takes it.
        guard let settings, !settings.hosts.isEmpty else {
            // No host yet — keep the token; reregisterIfPossible() will retry.
            return
        }
        var anyOK = false
        var lastErr: String?
        for host in settings.hosts {
            guard let client = settings.client(for: host) else { continue }
            do {
                try await client.registerPush(token: token, env: apnsEnv, owner: settings.defaultOwner)
                anyOK = true
            } catch {
                lastErr = error.localizedDescription
                log.error("push register on \(host.label) failed: \(error.localizedDescription)")
            }
        }
        if anyOK { apply(.serverAccepted(token: token)) }
        else { apply(.serverFailed(reason: lastErr ?? "no reachable host")) }
    }

    // MARK: Tap routing

    /// Handle a tapped notification: select its session so the UI navigates to it.
    /// Takes an already-parsed (Sendable) `PushNotification` so the delegate can
    /// extract it off the main actor before hopping here.
    func handleTap(_ note: PushNotification) {
        store?.openFromNotification(note.sid, snapshot: note.session)
    }

    private func apply(_ event: PushRegistrationEvent) {
        state = reducePushRegistration(state, event)
    }
}

/// UIKit application delegate, bridged into the SwiftUI app via
/// `@UIApplicationDelegateAdaptor`. Handles APNs token delivery and notification
/// presentation/taps, forwarding everything to `PushManager.shared`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in PushManager.shared.didFailToRegister(error: error) }
    }

    // Show the banner even when the app is foregrounded. `nonisolated` because the
    // protocol requirement is called off the main actor with non-Sendable params.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // The user tapped a notification — route to its session. Parse the (Sendable)
    // payload here, off the main actor, then hop with just that value.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let note = PushNotification(userInfo: response.notification.request.content.userInfo)
        else { return }
        await PushManager.shared.handleTap(note)
    }
}
