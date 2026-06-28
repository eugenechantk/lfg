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
                settings.baseURLString = draft.trimmingCharacters(in: .whitespaces)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.isEmpty)

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

    @State private var draft = ""
    @State private var probe: Reachability?
    @State private var probing = false
    @State private var inboxDraft = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("https://your-host.ts.net", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        Task { probing = true; probe = await LFGClient(string: draft)?.ping() ?? .badResponse("Invalid URL"); probing = false }
                    } label: {
                        HStack { Text("Test connection"); Spacer(); if probing { ProgressView() } }
                    }
                    HostProbeRow(probe: probe, probing: probing)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.baseURLString = draft.trimmingCharacters(in: .whitespaces)
                        store.reconnect()
                        dismiss()
                    }.disabled(draft.isEmpty)
                }
            }
            .task {
                draft = settings.baseURLString
                if store.root.isEmpty { await store.loadCreateMetadata() }
                inboxDraft = store.inbox
            }
        }
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
