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
    /// Hosts (by `Host.id`) whose last registration failed. A host that was
    /// down when a directory was hidden would otherwise keep alerting for it
    /// until the next launch; `retryFailedRegistrations` runs on foreground.
    private var unregisteredHosts: Set<String> = []
    /// The registration in flight. Sends run one at a time, in order, and each
    /// reads the hidden set when it runs — so the last request a host receives
    /// always carries the newest set, even after a quick hide/unhide.
    private var registration: Task<Void, Never>?
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
        enqueueRegistration(hex, only: nil)
    }

    func didFailToRegister(error: Error) {
        log.error("remote registration failed: \(error.localizedDescription)")
        apply(.serverFailed(reason: error.localizedDescription))
    }

    /// Re-send the current token to the server — used after the host changes, so
    /// a freshly-connected box learns about this device.
    func reregisterIfPossible() {
        guard let token = latestToken else { return }
        enqueueRegistration(token, only: nil)
    }

    /// Re-send to the hosts that missed the last registration. Cheap no-op
    /// when every host is current, so it is safe on every foreground.
    func retryFailedRegistrations() {
        guard let token = latestToken, !unregisteredHosts.isEmpty else { return }
        enqueueRegistration(token, only: unregisteredHosts)
    }

    private func enqueueRegistration(_ token: String, only: Set<String>?) {
        let previous = registration
        registration = Task {
            await previous?.value
            await sendToServer(token, only: only)
        }
    }

    /// `only` limits the send to those hosts (a retry); nil means every host.
    private func sendToServer(_ token: String, only: Set<String>?) async {
        // Register the token with EVERY host so any machine can push to this
        // device (multi-host). Accepted if at least one host takes it.
        guard let settings, !settings.hosts.isEmpty else {
            // No host yet — keep the token; reregisterIfPossible() will retry.
            return
        }
        var anyOK = false
        var lastErr: String?
        for host in settings.hosts where only?.contains(host.id) ?? true {
            guard let client = settings.client(for: host) else { continue }
            do {
                try await client.registerPush(token: token, env: apnsEnv, owner: settings.defaultOwner,
                                              hiddenDirs: settings.hiddenDirs.paths)
                anyOK = true
                unregisteredHosts.remove(host.id)
            } catch {
                lastErr = error.localizedDescription
                unregisteredHosts.insert(host.id)
                log.error("push register on \(host.label) failed: \(error.localizedDescription)")
            }
        }
        // Hosts removed from settings must not be retried forever.
        unregisteredHosts.formIntersection(settings.hosts.map(\.id))
        if anyOK { apply(.serverAccepted(token: token)) }
        // A failed retry says nothing new: the full send already reported it.
        else if only == nil { apply(.serverFailed(reason: lastErr ?? "no reachable host")) }
    }

    // MARK: Tap routing

    /// Handle a tapped notification: select its session so the UI navigates to it.
    /// Takes an already-parsed (Sendable) `PushNotification` so the delegate can
    /// extract it off the main actor before hopping here.
    func handleTap(_ note: PushNotification) {
        store?.openFromNotification(note.sid, snapshot: note.session)
    }

    /// A push about a session in a directory this device hides. Hosts skip
    /// such devices; this catches one still running an older server build.
    func isMuted(_ note: PushNotification) -> Bool {
        settings.map { note.isMuted(by: $0.hiddenDirs) } ?? false
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
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        SpaceControlOrientation.supported
    }

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
        //
        // `using:` MUST be .main: this closure is MainActor-isolated (inferred
        // from the @MainActor AppDelegate context), and with `using: nil`
        // BGTaskScheduler invokes it on its own queue — the Swift 6 runtime
        // isolation check then traps at closure entry (dispatch_assert_queue,
        // EXC_BREAKPOINT), crashing every background refresh launch. Seen live
        // in TestFlight crash 2026-07-11. The expiration handler runs on the
        // same queue, so it is covered too.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: .main) { task in
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

    /// A background URLSession we own finished its work while we were dead or
    /// suspended — iOS relaunched us to process the results. Recreating the
    /// session (via `shared`) reattaches the delegate; the handler is called
    /// once its events drain (urlSessionDidFinishEvents).
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundSender.sessionIdentifier else {
            completionHandler(); return
        }
        BackgroundSender.shared.systemCompletionHandler = completionHandler
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
        if let note = PushNotification(userInfo: notification.request.content.userInfo),
           await PushManager.shared.isMuted(note) {
            return []
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
