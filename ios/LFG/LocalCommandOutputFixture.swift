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
            id: "fixture-model-command",
            role: "system",
            kind: "system_notice",
            text: "/model opus"
        ),
        SessionMessage(
            id: "fixture-model-notice",
            role: "system",
            kind: "system_notice",
            text: "Set model to `Opus 5.5` and saved as your default for new sessions"
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
                            message.kind == "system_notice"
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

/// Network-free visual harness for Codex memory citation rendering.
/// Launch with `LFG_MEMORY_CITATION_FIXTURE=1`.
struct MemoryCitationFixture: View {
    private let messages = [
        SessionMessage(
            id: "fixture-answer",
            role: "assistant",
            kind: "text",
            text: "The iOS transcript now preserves the answer and renders its memory provenance separately."
        ),
        SessionMessage(
            id: "fixture-memory-citation",
            role: "assistant",
            kind: "memory_citation",
            text: """
            Memory sources
            MEMORY.md:265-268\tLFG iOS session and transcript architecture scope
            MEMORY.md:328-333\tLFG transcript normalization and client verification guidance
            Prior sessions: 2
            """
        ),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { message in
                    TranscriptMessageView(message: message)
                }
            }
            .padding()
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("memoryCitationFixture")
    }
}
#endif
