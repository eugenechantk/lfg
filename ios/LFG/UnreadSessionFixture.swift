#if DEBUG
import SwiftUI

/// Network-free harness for the unread-session navigation regression.
/// Launch with `LFG_UNREAD_SESSION_FIXTURE=1`.
struct UnreadSessionFixture: View {
    @Environment(SessionStore.self) private var store

    @State private var selection: String?
    @State private var showSettings = false
    @State private var showNewSession = false
    @State private var focusNewSessionComposer = false

    var body: some View {
        NavigationSplitView {
            SessionListView(
                selection: $selection,
                showSettings: $showSettings,
                showNewSession: $showNewSession,
                focusNewSessionComposer: $focusNewSessionComposer
            )
        } detail: {
            if let selection, let session = store.session(selection) {
                SessionDetailView(
                    session: session,
                    onEnded: { self.selection = nil },
                    onMarkedUnread: { self.selection = nil }
                )
                .id(selection)
            } else {
                DetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("unreadSessionFixture")
        .task {
            guard store.sessions.isEmpty else { return }
            store.installUnreadSessionFixture()
        }
    }
}
#endif
