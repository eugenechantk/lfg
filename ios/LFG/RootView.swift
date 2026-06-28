import SwiftUI
import LFGCore

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store

    @State private var selection: String?
    @State private var showSettings = false
    @State private var showNewSession = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        Group {
            if settings.hasConfiguredHost {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SessionListView(selection: $selection,
                                    showSettings: $showSettings,
                                    showNewSession: $showNewSession)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
                } detail: {
                    if let selection, let session = store.session(selection) {
                        SessionDetailView(session: session)
                            .id(selection)
                    } else {
                        DetailPlaceholder()
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                ConnectView()
            }
        }
        .environment(\.hostFiles, settings.client.map { HostFiles(baseURL: $0.baseURL) })
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewSession) {
            NewSessionView { newID in selection = newID }
        }
        .task(id: settings.baseURLString) {
            guard settings.hasConfiguredHost else { return }
            store.start()
            await store.loadCreateMetadata()
            // Register for push once we have a host to register against.
            await PushManager.shared.requestAuthorizationIfNeeded()
        }
        .onChange(of: store.requestedSelection) { _, requested in
            guard let requested else { return }
            selection = requested
            store.clearRequestedSelection()
        }
    }
}

struct DetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "No session selected",
            systemImage: "sparkles",
            description: Text("Pick a session from the list, or start a new one.")
        )
    }
}

/// Reachability strip shown above the list when not healthy.
struct ConnectionBanner: View {
    let reachability: Reachability?

    var body: some View {
        switch reachability {
        case .ok, .none:
            EmptyView()
        case .hostUnreachable(let detail):
            banner(icon: "wifi.exclamationmark", tint: .orange,
                   title: "Host unreachable",
                   detail: "Check that this device is on the same Tailscale tailnet and the host is running. \(detail)")
        case .badResponse(let detail):
            banner(icon: "exclamationmark.triangle.fill", tint: .red,
                   title: "Connection problem", detail: detail)
        }
    }

    private func banner(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
