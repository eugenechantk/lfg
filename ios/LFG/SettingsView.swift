import SwiftUI
import LFGCore

/// Full-screen first-run host setup, shown when no host is configured.
struct ConnectView: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""
    @State private var probe: Reachability?
    @State private var probing = false

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 18) {
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Connect to your lfg host").font(.title2.weight(.semibold))
            Text("Enter the URL that serves the lfg API — a Tailscale MagicDNS https address, or a loopback/LAN URL on the same network.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("https://your-host.ts.net", text: $draft)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            HostProbeRow(probe: probe, probing: probing)

            Button {
                Task { await test() }
            } label: {
                if probing { ProgressView() } else { Text("Test connection") }
            }
            .buttonStyle(.bordered)
            .disabled(draft.isEmpty || probing)

            Button("Save & continue") {
                settings.addHost(draft.trimmingCharacters(in: .whitespaces))
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.isEmpty)

            Text("You can add a second host later in Settings to run and transfer sessions across machines.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Spacer()
        }
        .padding(28)
    }

    private func test() async {
        probing = true
        probe = await LFGClient(string: draft)?.ping() ?? .badResponse("Invalid URL")
        probing = false
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
                                ReachDot(reach: store.reachabilityByHost[host.id])
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
                    Text("The lfg API is unauthenticated by design — its security boundary is your Tailscale tailnet. Keep this device on the tailnet.")
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

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _displayName = State(initialValue: "")
            _url = State(initialValue: "")
        case .edit(let h):
            _displayName = State(initialValue: h.displayName ?? "")
            _url = State(initialValue: h.url)
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
                Text("A Tailscale MagicDNS https URL, or a loopback/LAN address on the same network.")
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
        probing = true
        probe = await LFGClient(string: trimmedURL)?.ping() ?? .badResponse("Invalid URL")
        probing = false
    }

    private func save() {
        let ok: Bool
        switch mode {
        case .add:
            ok = settings.addHost(trimmedURL, displayName: displayName)
        case .edit(let h):
            ok = settings.updateHost(id: h.id, url: trimmedURL, displayName: displayName)
        }
        guard ok else {
            saveError = "That address is blank or already configured on another host."
            return
        }
        store.reconnect()
        Task { await store.resolveHostIdentities() }
        dismiss()
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

/// A small per-host reachability dot (green ok / gray unknown / orange down).
struct ReachDot: View {
    let reach: Reachability?
    private var color: Color {
        switch reach {
        case .ok: return .green
        case .none: return .secondary
        default: return .orange
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
