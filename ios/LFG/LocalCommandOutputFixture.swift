#if DEBUG
import SwiftUI
import LFGCore

/// Network-free visual harness for Codex local-command output normalization.
/// Launch with `LFG_LOCAL_COMMAND_OUTPUT_FIXTURE=1`.
struct LocalCommandOutputFixture: View {
    private let messages = [
        SessionMessage(
            id: "fixture-user-before",
            role: "user",
            kind: "text",
            text: "When I switch model, this message shows"
        ),
        SessionMessage(
            id: "fixture-model-notice",
            role: "system",
            kind: "tool_result",
            text: "Set model to `Fable 5.1` and saved as your default for new sessions"
        ),
        SessionMessage(
            id: "fixture-user-after",
            role: "user",
            kind: "text",
            text: "Can this message render like transcript errors?"
        ),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { message in
                    TranscriptMessageView(message: message)
                        .accessibilityIdentifier(
                            message.id == "fixture-model-notice"
                                ? "localCommandOutputNotice"
                                : "localCommandOutputFixtureUserMessage"
                        )
                }
            }
            .padding()
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("localCommandOutputFixture")
    }
}
#endif
