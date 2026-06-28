import SwiftUI
import LFGCore

/// New session presented as an empty session: the agent / model / directory
/// selectors sit directly above the composer, and the first message starts the
/// session. Owner is taken from Settings (the default owner).
struct NewSessionView: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var onCreated: (String?) -> Void

    @State private var agent: AgentKind = .claude
    @State private var model = AgentKind.claude.defaultModel
    @State private var cwd = ""
    @State private var cwdLabel = "Directory"
    @State private var draft = ""
    @State private var starting = false
    @State private var showImportDir = false
    @State private var importPath = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(.orange)
                    Text("Describe a task to start").font(.headline)
                    Text("Your first message kicks off the session.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    configBar
                    MessageComposer(text: $draft, placeholder: "Describe the task…", sending: starting) { text, atts in
                        Task { await start(text: text, attachments: atts) }
                    }
                }
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Add directory", isPresented: $showImportDir) {
                TextField("/Users/you/project", text: $importPath)
                Button("Cancel", role: .cancel) { importPath = "" }
                Button("Use") {
                    let p = importPath.trimmingCharacters(in: .whitespaces); importPath = ""
                    guard !p.isEmpty else { return }
                    cwd = p
                    cwdLabel = (p as NSString).lastPathComponent
                }
            } message: {
                Text("Type the full path to an existing directory on the host.")
            }
            .task {
                if store.repos.isEmpty || store.root.isEmpty { await store.loadCreateMetadata() }
                if cwd.isEmpty {
                    cwd = store.inbox
                    cwdLabel = store.inbox.isEmpty ? "Directory" : "Inbox"
                }
            }
        }
    }

    // MARK: Selectors (directly above the input)

    private var configBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Agent", selection: $agent) {
                        ForEach(AgentKind.allCases) { Text($0.displayName).tag($0) }
                    }
                } label: { pill("cpu", agent.displayName) }
                    .onChange(of: agent) { _, new in model = new.defaultModel }

                Menu {
                    Picker("Model", selection: $model) {
                        ForEach(agent.models, id: \.self) { Text($0).tag($0) }
                    }
                } label: { pill("slider.horizontal.3", model) }

                Menu {
                    Button { select(store.root, "Root") } label: { Label("Root", systemImage: "house") }
                    Button { select(store.inbox, "Inbox") } label: { Label("Inbox", systemImage: "tray") }
                    Button { showImportDir = true } label: { Label("Add directory by path…", systemImage: "folder.badge.plus") }
                    if !store.repos.isEmpty {
                        Divider()
                        ForEach(store.repos) { repo in
                            Button(repo.name) { select(repo.cwd, repo.name) }
                        }
                    }
                } label: { pill("folder", cwdLabel) }
            }
            .padding(.horizontal, 12)
        }
    }

    private func select(_ path: String, _ label: String) {
        cwd = path
        cwdLabel = label
    }

    private func pill(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.subheadline).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func start(text: String, attachments: [ComposerAttachment]) async {
        guard !cwd.isEmpty, !starting else { return }
        starting = true
        let req = NewSessionRequest(cwd: cwd, prompt: text, agent: agent.rawValue,
                                    model: model, user: settings.defaultOwner)
        // Create optimistically: this synthesizes a placeholder session + kickoff
        // bubble and returns its temporary id immediately, firing the real create
        // in the background. We navigate to it right away — no waiting on the
        // network — and the store reconciles the placeholder to the server's id.
        let placeholder = store.startOptimistic(req, attachments: attachments)
        onCreated(placeholder)
        dismiss()
    }
}
