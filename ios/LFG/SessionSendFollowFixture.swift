#if DEBUG
import SwiftUI
import LFGCore

/// Network-free UI harness for the session send-follow contract.
/// Launch with `LFG_SEND_FOLLOW_FIXTURE=1`.
struct SessionSendFollowFixture: View {
    @Environment(SessionStore.self) private var store
    @State private var session: Session?

    var body: some View {
        NavigationStack {
            if let session {
                SessionDetailView(
                    session: session,
                    onEnded: {},
                    onMarkedUnread: {},
                    debugInitialDraft: ProcessInfo.processInfo.environment[
                        "LFG_SEND_FOLLOW_FIXTURE_LONG_DRAFT"
                    ] == "1"
                        ? "This is a longer outgoing message that wraps across several lines above the composer"
                        : ""
                )
            } else {
                ProgressView()
            }
        }
        .accessibilityIdentifier("sessionSendFollowFixture")
        .task {
            guard session == nil else { return }
            session = store.installSendFollowFixture()
        }
    }
}
#endif
