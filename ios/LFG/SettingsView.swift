import SwiftUI
import LFGCore

/// Full-screen first-run host setup, shown when no host is configured.
struct ConnectView: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft = HostStore.preferredHostURL
    @State private var probe: Reachability?
    @State private var probing = false
    @State private var usesCloudflareAccess = false
    @State private var accessClientID = ""
    @State private var accessClientSecret = ""
    @State private var saveError: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 18) {
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Connect to your lfg host").font(.title2.weight(.semibold))
            Text("Enter the URL that serves the lfg API — a Cloudflare HTTPS hostname, Tailscale MagicDNS address, or a loopback/LAN URL on the same network.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("https://your-host.ts.net", text: $draft)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Toggle("Use Cloudflare Access", isOn: $usesCloudflareAccess)
                .accessibilityIdentifier("connect_access_toggle")

            if usesCloudflareAccess {
                TextField("Access Client ID", text: $accessClientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("connect_access_client_id_field")
                SecureField("Access Client Secret", text: $accessClientSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    // This is an API credential, not a website password. Avoid
                    // offering to copy it into the system Passwords store.
                    .textContentType(.oneTimeCode)
                    .accessibilityIdentifier("connect_access_client_secret_field")
                Text("Use a per-device Service Auth token. Its secret is saved only in this device's Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HostProbeRow(probe: probe, probing: probing)

            Button {
                Task { await test() }
            } label: {
                if probing { ProgressView() } else { Text("Test connection") }
            }
            .buttonStyle(.bordered)
            .disabled(draft.isEmpty || probing)

            Button("Save & continue") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.isEmpty)

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.caption)
            }

            Text("You can add a second host later in Settings to run and transfer sessions across machines.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Spacer()
        }
        .padding(28)
    }

    private func test() async {
        saveError = nil
        guard let credential = draftAccessCredential() else { return }
        probing = true
        probe = await LFGClient(string: draft, accessCredential: credential)?.ping()
            ?? .badResponse("Invalid URL")
        probing = false
    }

    private func save() {
        saveError = nil
        guard let credential = draftAccessCredential() else { return }
        let url = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.addHost(url, displayName: nil) else {
            saveError = "That address is blank or already configured."
            return
        }
        guard let credential else { return }
        do {
            try settings.saveAccessCredential(credential, forHostURL: url)
        } catch {
            settings.removeHost(url)
            saveError = error.localizedDescription
        }
    }

    /// Outer nil means validation failed; `.some(nil)` means Access is disabled.
    private func draftAccessCredential() -> CloudflareAccessCredential?? {
        guard usesCloudflareAccess else { return .some(nil) }
        let clientID = accessClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = accessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !secret.isEmpty else {
            saveError = "Enter both the Cloudflare Access Client ID and Client Secret."
            return nil
        }
        return .some(CloudflareAccessCredential(clientID: clientID, clientSecret: secret))
    }
}

/// In-app settings sheet for changing the host later.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var inboxDraft = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    ForEach(settings.hosts) { host in
                        NavigationLink {
                            HostEditView(mode: .edit(host))
                        } label: {
                            HStack(spacing: 10) {
                                ReachDot(state: store.hostStateByHost[host.id])
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.label).foregroundStyle(.primary)
                                    Text(host.url).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if host.isDefault {
                                    Text("Default").font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                settings.removeHost(host.id); store.reconnect()
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                    NavigationLink {
                        HostEditView(mode: .add)
                    } label: {
                        Label("Add host", systemImage: "plus.circle")
                    }
                } header: { Text("Hosts") } footer: {
                    Text("The client shows sessions from every host and can transfer a session between them (⋯ menu). Tap a host to edit its name or address, test it, or make it the default for new sessions.")
                }

                Section("Sessions") {
                    Picker("Show", selection: $settings.userFilter) {
                        Text("All").tag(UserFilter.all)
                        Text("Unassigned").tag(UserFilter.unassigned)
                        ForEach(store.users, id: \.self) { Text($0).tag(UserFilter.user($0)) }
                    }
                    Picker("Default owner", selection: $settings.defaultOwner) {
                        Text("Unassigned").tag(String?.none)
                        ForEach(store.users, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }

                Section {
                    NavigationLink {
                        ConnectionLogView()
                    } label: {
                        Label("Connection Log", systemImage: "waveform.path.ecg")
                    }
                    .accessibilityIdentifier("connectionLogLink")
                } header: { Text("Diagnostics") } footer: {
                    Text("A timestamped record of every network path change, host state transition and event-stream connect. Kept across launches — open it after a drop and share it.")
                }

                Section {
                    NotificationStatusRow(state: PushManager.shared.state)
                } header: { Text("Notifications") } footer: {
                    Text("Get a push when one of your sessions finishes a turn or needs your input. Requires the host to have APNs configured (LFG_APNS_*).")
                }

                Section {
                    LabeledContent("Root") {
                        Text(store.root.isEmpty ? "—" : store.root)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head)
                    }
                    HStack {
                        TextField("Inbox path", text: $inboxDraft)
                            .font(.caption.monospaced())
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Set") {
                            let p = inboxDraft.trimmingCharacters(in: .whitespaces)
                            guard !p.isEmpty else { return }
                            Task { await store.setInbox(p) }
                        }.font(.caption)
                    }
                } header: { Text("Directories") } footer: {
                    Text("Root is the scanned repos folder (set via LFG_REPOS_ROOT on the host). Inbox is a fallback scratch folder for ad-hoc sessions.")
                }

                Section {
                    Text("Each host must stay behind a private network or an authenticated HTTPS gateway. Cloudflare Access credentials are kept in this device's Keychain and are never stored with the host list.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                if store.root.isEmpty { await store.loadCreateMetadata() }
                inboxDraft = store.inbox
                await store.resolveHostIdentities()
            }
        }
    }
}

/// The directory filter panel: which working directories are kept out of this
/// device's session list, plus the two ways to add one.
///
/// Reached from the session list's header button, NOT from Settings — which
/// directories you want to look at is a display choice that changes with the
/// task, like grouping and sorting, not a client setting you configure once.
///
/// The picker of seen directories is the important half. The motivating case —
/// `gbrain` autopilot filling the list with `~/.gbrain` sessions — is a directory
/// the client is already staring at, so muting it should be a tap on a name, not
/// a hand-typed absolute path. The text field is the fallback for a directory no
/// session has surfaced yet.
struct HiddenDirectoriesView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @State private var pathDraft = ""

    private var addable: [String] {
        store.knownDirectories.filter { !settings.hiddenDirs.hides(cwd: $0) }
    }

    var body: some View {
        Form {
            Section {
                if settings.hiddenDirs.isEmpty {
                    Text("Nothing hidden — every session shows.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(settings.hiddenDirs.paths, id: \.self) { dir in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HiddenDirs.displayName(for: dir))
                            Text(dir).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                settings.unhideDirectory(dir)
                            } label: { Label("Show", systemImage: "eye") }
                        }
                        .accessibilityIdentifier("hiddenDir-\(dir)")
                    }
                }
            } header: { Text("Hidden") } footer: {
                Text("Sessions in a hidden directory (and its subdirectories) stay out of the list, the counts and search on this device. They keep running, and a notification still opens them. Swipe a directory to show it again.")
            }

            if !addable.isEmpty {
                Section {
                    ForEach(addable, id: \.self) { dir in
                        Button {
                            settings.hideDirectory(dir)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(HiddenDirs.displayName(for: dir)).foregroundStyle(.primary)
                                    Text(dir).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.head)
                                }
                                Spacer()
                                Image(systemName: "eye.slash").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("hideCandidate-\(dir)")
                        .swipeActions {
                            if let pattern = HiddenDirs.suggestedPattern(for: dir) {
                                Button {
                                    settings.hideDirectory(pattern)
                                } label: { Label("Hide all like this", systemImage: "eye.slash.circle") }
                                    .tint(.orange)
                            }
                        }
                    }
                } header: { Text("Directories in use") } footer: {
                    Text("Every directory this device has seen a session in, across all hosts. Tap to hide one; swipe a per-run scratch folder to hide the whole family.")
                }
            }

            Section {
                HStack {
                    TextField("/Users/you/some/dir  or  */scratch-*", text: $pathDraft)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("hiddenDirPathField")
                    Button("Hide") {
                        settings.hideDirectory(pathDraft)
                        pathDraft = ""
                    }
                    .font(.caption)
                    .disabled(HiddenDirs.normalize(pathDraft) == nil)
                }
            } header: { Text("Add by path or pattern") } footer: {
                Text("An absolute path on the host — this device can't resolve ~ against a host's home directory. Or a pattern: * matches anything, ? one character. Use a pattern for directories that change every run, e.g. */gbrain-claude-cli-cwd-* for gbrain autopilot's temp folders.")
            }
        }
        .navigationTitle("Filter directories")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Add or edit a single host: change its friendly name and address, test the
/// connection, set it as default, or remove it. Pushed from the Hosts section.
struct HostEditView: View {
    enum Mode { case add, edit(Host) }

    let mode: Mode
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var url: String
    @State private var probe: Reachability?
    @State private var probing = false
    @State private var saveError: String?
    @State private var usesCloudflareAccess: Bool
    @State private var accessClientID: String
    @State private var accessClientSecret = ""
    private let savedAccessCredential: CloudflareAccessCredential?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            savedAccessCredential = nil
            _displayName = State(initialValue: "")
            _url = State(initialValue: "")
            _usesCloudflareAccess = State(initialValue: false)
            _accessClientID = State(initialValue: "")
        case .edit(let h):
            let credential = HostCredentialStore.shared.credential(forHostURL: h.url)
            savedAccessCredential = credential
            _displayName = State(initialValue: h.displayName ?? "")
            _url = State(initialValue: h.url)
            _usesCloudflareAccess = State(initialValue: credential != nil)
            _accessClientID = State(initialValue: credential?.clientID ?? "")
        }
    }

    private var isAdd: Bool { if case .add = mode { return true }; return false }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespaces) }

    /// The live stored host (edit mode), so the default state reflects taps.
    private var storedHost: Host? {
        guard case .edit(let h) = mode else { return nil }
        return settings.hosts.first(where: { $0.id == h.id })
    }

    /// Placeholder for the name field: the resolved machine hostname (so the
    /// user sees what the pill falls back to), else a generic hint.
    private var namePlaceholder: String {
        if let n = storedHost?.name, !n.isEmpty { return n }
        return "Friendly name (optional)"
    }

    var body: some View {
        Form {
            Section {
                TextField(namePlaceholder, text: $displayName)
                    .autocorrectionDisabled()
            } header: { Text("Name") } footer: {
                Text("Shown as the host's pill on sessions. Leave blank to use the machine's own hostname.")
            }
            Section {
                TextField("host.ts.net:8766", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: url) { probe = nil; saveError = nil }
            } header: { Text("Address") } footer: {
                Text("A Cloudflare HTTPS hostname, Tailscale MagicDNS URL, or loopback/LAN address.")
            }

            Section {
                Toggle("Use Cloudflare Access", isOn: $usesCloudflareAccess)
                    .accessibilityIdentifier("host_access_toggle")
                if usesCloudflareAccess {
                    TextField("Client ID", text: $accessClientID)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("host_access_client_id_field")
                    SecureField(savedAccessCredential == nil ? "Client Secret" : "Saved — enter to replace",
                                text: $accessClientSecret)
                        .font(.caption.monospaced())
                        .textContentType(.oneTimeCode)
                        .accessibilityIdentifier("host_access_client_secret_field")
                }
            } header: { Text("Cloudflare Access") } footer: {
                if usesCloudflareAccess {
                    Text("Use a per-device Service Auth token. The secret is saved in Keychain and is never shown again; leave it blank to keep the saved secret.")
                } else {
                    Text("Leave off for hosts protected by Tailscale or a trusted local network.")
                }
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack { Text("Test connection"); Spacer(); if probing { ProgressView() } }
                }
                .disabled(trimmedURL.isEmpty || probing)
                HostProbeRow(probe: probe, probing: probing)
            }

            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.subheadline)
                }
            }

            if let host = storedHost {
                Section {
                    if host.isDefault {
                        Label("Default host for new sessions", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Set as default host") { settings.setDefaultHost(host.id) }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        settings.removeHost(host.id); store.reconnect(); dismiss()
                    } label: { Text("Remove host") }
                }
            }
        }
        .navigationTitle(isAdd ? "Add host" : "Edit host")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(trimmedURL.isEmpty)
            }
        }
    }

    private func test() async {
        saveError = nil
        guard let accessCredential = draftAccessCredential() else { return }
        probing = true
        probe = await LFGClient(string: trimmedURL, accessCredential: accessCredential)?.ping()
            ?? .badResponse("Invalid URL")
        probing = false
    }

    private func save() {
        saveError = nil
        guard let accessCredential = draftAccessCredential() else { return }
        let ok: Bool
        switch mode {
        case .add:
            ok = settings.addHost(trimmedURL, displayName: displayName)
        case .edit(let h):
            ok = settings.updateHost(id: h.id, url: trimmedURL, displayName: displayName)
        }
        guard ok else {
            saveError = "That address is blank, already configured, or its saved credential could not be moved."
            return
        }
        do {
            if usesCloudflareAccess, let accessCredential {
                try settings.saveAccessCredential(accessCredential, forHostURL: trimmedURL)
            } else {
                try settings.removeAccessCredential(forHostURL: trimmedURL)
            }
        } catch {
            if isAdd { settings.removeHost(trimmedURL) }
            saveError = error.localizedDescription
            return
        }
        store.reconnect()
        Task { await store.resolveHostIdentities() }
        dismiss()
    }

    /// Outer nil means validation failed; `.some(nil)` means Access is
    /// intentionally disabled; `.some(credential)` is ready to use.
    private func draftAccessCredential() -> CloudflareAccessCredential?? {
        guard usesCloudflareAccess else { return .some(nil) }
        let clientID = accessClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        var secret = accessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if secret.isEmpty, savedAccessCredential?.clientID == clientID {
            secret = savedAccessCredential?.clientSecret ?? ""
        }
        guard !clientID.isEmpty, !secret.isEmpty else {
            saveError = "Enter both the Cloudflare Access Client ID and Client Secret."
            return nil
        }
        return .some(CloudflareAccessCredential(clientID: clientID, clientSecret: secret))
    }
}

/// Reflects the device's push registration state in Settings.
struct NotificationStatusRow: View {
    let state: PushRegistrationState

    var body: some View {
        switch state {
        case .registered:
            Label("On — this device is registered", systemImage: "bell.fill")
                .foregroundStyle(.green).font(.subheadline)
        case .authorizing:
            Label("Registering…", systemImage: "bell.badge").font(.subheadline)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Off — notifications denied", systemImage: "bell.slash")
                    .foregroundStyle(.orange).font(.subheadline)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }.font(.caption)
            }
        case .failed(let reason):
            Label("Couldn't register — \(reason)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red).font(.subheadline)
        case .notDetermined:
            Label("Not enabled yet", systemImage: "bell").font(.subheadline)
        }
    }
}

/// A small per-host health dot (green live / gray unknown / yellow connecting
/// or degraded / orange down). `degraded` gets its own colour rather than
/// borrowing "down": during the grace window the host may well be fine, and
/// showing orange there is what made the dot contradict a fresh manual ping.
struct ReachDot: View {
    let state: HostState?
    private var color: Color {
        switch state {
        case .live: return .green
        case .none, .unknown: return .secondary
        // `noNetwork` is the pre-grace path blip: still amber, because the app
        // has no reason yet to claim anything is wrong.
        case .connecting, .degraded, .noNetwork: return .yellow
        case .offline, .noNetworkSustained: return .orange
        }
    }
    var body: some View { Circle().fill(color).frame(width: 9, height: 9) }
}

struct HostProbeRow: View {
    let probe: Reachability?
    let probing: Bool
    var body: some View {
        switch probe {
        case .none: EmptyView()
        case .ok:
            Label("Reachable", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
        case .hostUnreachable(let d):
            Label("Unreachable — \(d)", systemImage: "wifi.slash").foregroundStyle(.orange).font(.subheadline)
        case .badResponse(let d):
            Label("Bad response — \(d)", systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.subheadline)
        }
    }
}
