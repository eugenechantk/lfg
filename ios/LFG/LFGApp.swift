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

/// Persisted connection + filter settings. Multi-host: the client fans out to
/// every configured `Host` (each an `lfg serve` machine on the Tailscale net),
/// merges their sessions, and routes each op to the owning host. The list
/// migrates from the legacy single `lfg.baseURL` on first launch.
@MainActor @Observable final class AppSettings {
    private let defaults = UserDefaults.standard
    private static let baseURLKey = "lfg.baseURL"   // legacy — migration source only
    private static let hostsKey = "lfg.hosts"
    private static let ownerKey = "lfg.defaultOwner"
    private static let groupModeKey = "lfg.groupMode"

    /// Configured backend hosts. Persisted as JSON; exactly one is `isDefault`.
    var hosts: [Host] {
        didSet { defaults.set(HostStore.encode(hosts), forKey: Self.hostsKey) }
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

    /// Live host filter (not persisted). `nil` = all hosts.
    var hostFilter: String? = nil

    /// How the session list is grouped (by status vs by directory). Persisted so
    /// the chosen lens sticks across launches.
    var groupMode: GroupMode {
        didSet { defaults.set(groupMode.rawValue, forKey: Self.groupModeKey) }
    }

    /// A stateless client for one host.
    func client(for host: Host) -> LFGClient? { LFGClient(string: host.url) }

    /// The default host's client — used for host-agnostic create-flow metadata
    /// (dirs/users/usage) and inline host-file rendering. Falls back to the first
    /// host. Reachability-aware placement is the store's job (`HostStore.defaultHost`).
    var defaultClient: LFGClient? {
        guard let h = hosts.first(where: { $0.isDefault }) ?? hosts.first else { return nil }
        return LFGClient(string: h.url)
    }

    var hasConfiguredHost: Bool { !hosts.isEmpty }

    init() {
        hosts = HostStore.migrate(
            hostsData: defaults.data(forKey: Self.hostsKey),
            legacyBaseURL: defaults.string(forKey: Self.baseURLKey))
        defaultOwner = defaults.string(forKey: Self.ownerKey)
        groupMode = GroupMode(rawValue: defaults.string(forKey: Self.groupModeKey) ?? "") ?? .status
        // Persist the migrated list so later launches read the new key directly
        // (didSet doesn't fire during init; all stored props must be set first).
        defaults.set(HostStore.encode(hosts), forKey: Self.hostsKey)
    }

    // MARK: Host list mutation (Settings editor)

    /// Add a host from a URL string (no-op on blank/duplicate). Marked default
    /// when it's the first host.
    func addHost(_ url: String) {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !hosts.contains(where: { $0.url == u }) else { return }
        hosts = HostStore.normalized(hosts + [Host(url: u, isDefault: hosts.isEmpty)])
    }

    func removeHost(_ id: String) {
        hosts = HostStore.normalized(hosts.filter { $0.id != id })
    }

    /// Make `id` the sole default host for new-session placement.
    func setDefaultHost(_ id: String) {
        hosts = hosts.map { var h = $0; h.isDefault = (h.id == id); return h }
    }

    /// Fold a resolved `/api/info` identity into the stored host.
    func updateHostInfo(_ id: String, info: HostInfo) {
        guard let i = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[i].hostId = info.hostId
        hosts[i].name = info.hostName
    }
}

/// The lens the session list is grouped by.
enum GroupMode: String, CaseIterable, Identifiable {
    case status
    case directory

    var id: String { rawValue }
    var label: String {
        switch self {
        case .status: return "Status"
        case .directory: return "Directory"
        }
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
