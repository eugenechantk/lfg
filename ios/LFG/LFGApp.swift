import SwiftUI
import LFGCore

@main
struct LFGApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    @State private var store: SessionStore

    init() {
        let s = AppSettings()
        let st = SessionStore(settings: s)
        _settings = State(initialValue: s)
        _store = State(initialValue: st)
        // Bridge the push manager (used by the UIKit AppDelegate) to the same
        // settings/store the SwiftUI views observe.
        PushManager.shared.configure(settings: s, store: st)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(store)
        }
    }
}

/// Persisted connection + filter settings. The base URL is whatever serves the
/// lfg API — loopback for simulator testing, or a Tailscale MagicDNS https URL.
@MainActor @Observable final class AppSettings {
    private let defaults = UserDefaults.standard
    private static let baseURLKey = "lfg.baseURL"
    private static let ownerKey = "lfg.defaultOwner"

    var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Self.baseURLKey) }
    }

    /// Owner assigned to newly-created sessions (configured in Settings).
    var defaultOwner: String? {
        didSet {
            if let defaultOwner { defaults.set(defaultOwner, forKey: Self.ownerKey) }
            else { defaults.removeObject(forKey: Self.ownerKey) }
        }
    }

    /// Live user filter (not persisted — session-local).
    var userFilter: UserFilter = .all

    var client: LFGClient? { LFGClient(string: baseURLString) }
    var hasConfiguredHost: Bool { client != nil && !baseURLString.isEmpty }

    init() {
        baseURLString = defaults.string(forKey: Self.baseURLKey) ?? ""
        defaultOwner = defaults.string(forKey: Self.ownerKey)
    }
}

enum UserFilter: Equatable, Hashable {
    case all
    case unassigned
    case user(String)

    var label: String {
        switch self {
        case .all: return "All"
        case .unassigned: return "Unassigned"
        case .user(let u): return u
        }
    }

    func matches(_ session: Session) -> Bool {
        switch self {
        case .all: return true
        case .unassigned: return session.assignedUser == nil
        case .user(let u): return session.assignedUser == u
        }
    }
}
