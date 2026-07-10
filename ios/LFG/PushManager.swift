import SwiftUI
import UserNotifications
import BackgroundTasks
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
        // Escape hatch for UI automation: launching with LFG_SKIP_PUSH set skips
        // the system notification prompt (a modal SpringBoard alert that blocks
        // in-app automation and can't be dismissed from the app process).
        if ProcessInfo.processInfo.environment["LFG_SKIP_PUSH"] != nil { return }
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

    // MARK: Background wake (Phase 2)

    /// A content-available push (or BGAppRefresh, hint = nil) woke the app:
    /// delta-sync via journal cursors. Returns whether new data was applied.
    func handleBackgroundSync(_ hint: PushSyncHint?) async -> Bool {
        guard let store else { return false }
        return await store.backgroundSync(hostId: hint?.hostId)
    }

    private func apply(_ event: PushRegistrationEvent) {
        state = reducePushRegistration(state, event)
    }
}

/// UIKit application delegate, bridged into the SwiftUI app via
/// `@UIApplicationDelegateAdaptor`. Handles APNs token delivery and notification
/// presentation/taps, forwarding everything to `PushManager.shared`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// BGAppRefresh task id — must match BGTaskSchedulerPermittedIdentifiers in
    /// project.yml's Info properties.
    static let refreshTaskID = "com.eugenechan.lfg.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Register for remote notifications UNCONDITIONALLY — registration is
        // promptless and is what routes content-available wakes to the app;
        // user permission only gates visible alerts. Gating this behind the
        // permission flow (the old behavior) silently disabled silent pushes
        // whenever permission was undetermined/denied — caught live in the
        // Phase-2 gate test when a delivered push never reached the delegate.
        UIApplication.shared.registerForRemoteNotifications()
        // Must register before launch completes; the handler hops to the main
        // actor for the sync and completes the task either way.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false); return
            }
            Self.scheduleAppRefresh()   // always keep the next one queued
            let work = Task { @MainActor in
                let new = await PushManager.shared.handleBackgroundSync(nil)
                refresh.setTaskCompleted(success: new)
            }
            refresh.expirationHandler = { work.cancel() }
        }
        return true
    }

    /// Queue the next background refresh. Called on every backgrounding (from
    /// RootView's scenePhase handler) and after each refresh runs. iOS treats
    /// the date as an earliest-not-exact hint and budgets by usage patterns.
    static func scheduleAppRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// A remote notification with content-available arrived (app backgrounded
    /// or foregrounded). Parse the (Sendable) sync hint off the main actor,
    /// then hop for the delta sync. Phase-2 pushes carry {hostId, seq}; older
    /// payloads parse to nil and sync every host.
    ///
    /// The wake path is invisible without logging (no UI, often no debugger) —
    /// keep these lines. Notice level so default log capture shows them.
    ///
    /// MainActor-isolated async variant: the protocol requirement is
    /// @MainActor, so an isolated implementation receives the non-Sendable
    /// userInfo without it ever crossing an actor boundary (a `nonisolated`
    /// impl fails to compile for exactly that reason).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let log = Logger(subsystem: "dev.omg.lfg", category: "push")
        let hint = PushSyncHint(userInfo: userInfo)
        log.notice("remote wake: hint=\(hint.map { "\($0.hostId)@\($0.seq)" } ?? "none", privacy: .public)")
        let new = await PushManager.shared.handleBackgroundSync(hint)
        log.notice("remote wake sync done: newData=\(new, privacy: .public)")
        return new ? .newData : .noData
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
    //
    // Also runs the {hostId, seq} delta sync when the push carries one: a
    // foreground push means the journal moved, the sync is idempotent, and
    // this route is RELIABLE where the remote-notification delegate route is
    // simulator-flaky — belt and braces with didReceiveRemoteNotification
    // (double-sync is a no-op: the second fetch sees cursor == head).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let hint = PushSyncHint(userInfo: notification.request.content.userInfo) {
            Logger(subsystem: "dev.omg.lfg", category: "push")
                .notice("foreground push sync: \(hint.hostId, privacy: .public)@\(hint.seq)")
            Task { @MainActor in
                _ = await PushManager.shared.handleBackgroundSync(hint)
            }
        }
        return [.banner, .sound]
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
