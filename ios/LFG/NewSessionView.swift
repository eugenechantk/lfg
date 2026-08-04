import LFGCore
import SwiftUI

enum ActiveSheet: String, Equatable, Identifiable {
    case directory
    case host
    case model

    var id: String { rawValue }

    /// Detent for this picker. Directory and model are long, searchable lists and
    /// want the full sheet; the host list is a couple of rows, so a system medium
    /// detent keeps it near the design's short panel without a fixed pixel height.
    var detents: Set<PresentationDetent> {
        switch self {
        case .directory, .model: [.large]
        case .host: [.medium]
        }
    }
}

/// A full-screen new-session draft. The first message starts the session and
/// owner continues to come from Settings.
struct NewSessionView: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var autofocusComposer = false
    var onCreated: (String?) -> Void

    // Agent remains part of creation state even though the standalone picker is
    // intentionally absent. Phase B's grouped model picker will update it.
    @State private var agent: AgentKind = .claude
    @State private var model = AgentKind.claude.defaultModel
    @State private var cwd = ""
    @State private var cwdLabel = "Directory"
    @State private var draft = ""
    @State private var starting = false
    @State private var activeSheet: ActiveSheet?
    @State private var edgeSwipeDismissed = false
    /// Snapshot taken when a sheet opens so ✕ can revert. Selection is applied
    /// live as rows are tapped, so "confirm" is really dismiss-and-keep.
    @State private var revertState: (cwd: String, label: String, host: Host?, agent: AgentKind, model: String)?
    @State private var showAddDirectory = false
    @State private var addDirectoryPath = ""

    /// The host the session will be created on (multi-host). Defaults to the
    /// default host, or a reachable one when the default is offline.
    @State private var selectedHost: Host?

    private var selectedHostIsReachable: Bool {
        guard let selectedHost else { return false }
        return store.hostStateByHost[selectedHost.id]?.isLive == true
    }

    var body: some View {
        ZStack(alignment: .top) {
            NewSessionPalette.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                NavRow { dismiss() }

                EmptyDraftState()
                    .padding(.top, 74)

                Spacer(minLength: 0)
            }
        }
        // The hidden navigation bar prevents UIKit edge recognizers from seeing
        // this screen's left-edge touch. Keep the fallback in SwiftUI and attach
        // it before the composer safe-area inset so text editing stays isolated.
        .modifier(CompactEdgeSwipeDismissModifier(
            isEnabled: horizontalSizeClass != .regular,
            activeSheet: activeSheet,
            showAddDirectory: showAddDirectory,
            didDismiss: $edgeSwipeDismissed,
            dismiss: dismiss
        ))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NewSessionComposer(
                text: $draft,
                activeSheet: $activeSheet,
                directoryLabel: cwdLabel,
                hostLabel: selectedHost?.label ?? "Host",
                hostIsReachable: selectedHostIsReachable,
                modelLabel: model,
                sending: starting,
                autofocus: autofocusComposer
            ) { text, attachments in
                Task { await start(text: text, attachments: attachments) }
            }
            .padding(.horizontal, 12)
        }
        .sheet(item: $activeSheet) { kind in
            sheet(for: kind)
                .presentationDetents(kind.detents)
        }
        .onChange(of: activeSheet) { _, new in
            // Snapshot on open so ✕ can revert; clear on close.
            if new != nil, revertState == nil {
                revertState = (cwd, cwdLabel, selectedHost, agent, model)
            } else if new == nil {
                revertState = nil
            }
        }
        .alert("Add directory", isPresented: $showAddDirectory) {
            TextField("/Users/you/project", text: $addDirectoryPath)
            Button("Cancel", role: .cancel) { addDirectoryPath = "" }
            Button("Use") {
                let p = addDirectoryPath.trimmingCharacters(in: .whitespaces)
                addDirectoryPath = ""
                guard !p.isEmpty else { return }
                cwd = p
                cwdLabel = (p as NSString).lastPathComponent
                closeSheet()
            }
        } message: {
            Text("Type the full path to an existing directory on the host.")
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        // Deliberately NO `.accessibilityIdentifier` on this container: SwiftUI
        // propagates a container's identifier to every descendant element, which
        // made all ten child ids report "newSession.root" and left the whole
        // automation contract unqueryable.
        .task {
            if store.repos.isEmpty || store.root.isEmpty {
                await store.loadCreateMetadata()
            }
            if cwd.isEmpty {
                cwd = store.inbox
                cwdLabel = store.inbox.isEmpty ? "Directory" : "Inbox"
            }
            if selectedHost == nil {
                selectedHost = HostStore.defaultHost(settings.hosts) {
                    store.hostStateByHost[$0.id]?.isLive == true
                } ?? settings.hosts.first { $0.isDefault } ?? settings.hosts.first
            }
        }
    }

    // MARK: Pickers

    /// Every directory the picker can offer: the Root/Inbox fallbacks the shipping
    /// menu had, plus the host's scanned repos.
    private var allDirectories: [DirectoryEntry] {
        var out: [DirectoryEntry] = []
        if !store.root.isEmpty { out.append(DirectoryEntry(name: "Root", path: store.root)) }
        if !store.inbox.isEmpty { out.append(DirectoryEntry(name: "Inbox", path: store.inbox)) }
        out.append(contentsOf: store.repos.map { DirectoryEntry(name: $0.name, path: $0.cwd) })
        return out
    }

    /// MRU entries, resolved to a display name. Falls back to the last path
    /// component for directories added by path that aren't in `allDirectories`.
    private var recentDirectories: [DirectoryEntry] {
        settings.recentDirs.map { path in
            allDirectories.first { $0.path == path }
                ?? DirectoryEntry(name: (path as NSString).lastPathComponent, path: path)
        }
    }

    @ViewBuilder
    private func sheet(for kind: ActiveSheet) -> some View {
        switch kind {
        case .directory:
            DirectorySheet(
                recents: recentDirectories,
                all: allDirectories,
                selectedPath: cwd,
                onSelect: { entry in cwd = entry.path; cwdLabel = entry.name },
                onAddByPath: { showAddDirectory = true },
                onConfirm: closeSheet,
                onCancel: revertSheet
            )
        case .host:
            HostSheet(
                hosts: settings.hosts,
                hostStates: store.hostStateByHost,
                selectedHostID: selectedHost?.id,
                onSelect: { selectedHost = $0 },
                onConfirm: closeSheet,
                onCancel: revertSheet
            )
        case .model:
            ModelSheet(
                selectedAgent: agent,
                selectedModel: model,
                onSelect: { kind, name in agent = kind; model = name },
                onConfirm: closeSheet,
                onCancel: revertSheet
            )
        }
    }

    private func closeSheet() {
        activeSheet = nil
    }

    /// ✕ and scrim-tap restore whatever was selected when the sheet opened.
    private func revertSheet() {
        if let r = revertState {
            cwd = r.cwd
            cwdLabel = r.label
            selectedHost = r.host
            agent = r.agent
            model = r.model
        }
        closeSheet()
    }

    private func start(text: String, attachments: [ComposerAttachment]) async {
        guard !cwd.isEmpty, !starting else { return }
        starting = true
        let req = NewSessionRequest(cwd: cwd, prompt: text, agent: agent.rawValue,
                                    model: model, user: settings.defaultOwner)
        // Preserve the load-bearing optimistic path and its navigation order.
        // Promote this cwd in the MRU list so it surfaces under RECENT next time.
        settings.noteRecentDir(cwd)
        let placeholder = store.startOptimistic(req, on: selectedHost, attachments: attachments)
        onCreated(placeholder)
        dismiss()
    }
}

private struct CompactEdgeSwipeDismissModifier: ViewModifier {
    let isEnabled: Bool
    let activeSheet: ActiveSheet?
    let showAddDirectory: Bool
    @Binding var didDismiss: Bool
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(edgeSwipeDismissGesture)
        } else {
            content
        }
    }

    private var edgeSwipeDismissGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onChanged { value in
                guard shouldDismissFromEdgeSwipe(value) else { return }
                didDismiss = true
                dismiss()
            }
            .onEnded { _ in
                didDismiss = false
            }
    }

    private func shouldDismissFromEdgeSwipe(_ value: DragGesture.Value) -> Bool {
        activeSheet == nil
            && !showAddDirectory
            && !didDismiss
            && value.startLocation.x <= 24
            && value.translation.width >= 80
            && abs(value.translation.height) <= value.translation.width * 0.6
    }
}
