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

/// Network-free visual harness for provider task-notification normalization.
/// Launch with `LFG_TASK_NOTIFICATION_FIXTURE=1`.
struct TaskNotificationFixture: View {
    private let messages = [
        SessionMessage(
            id: "fixture-user-before-task",
            role: "user",
            kind: "text",
            text: "Please audit the transcript rendering."
        ),
        SessionMessage(
            id: "fixture-task-notification",
            role: "system",
            kind: "thinking",
            text: """
            <task-notification>
            <task-id>agent-audit</task-id>
            <status>completed</status>
            <summary>Agent "Audit transcript rendering" finished</summary>
            <result>PASS: task notification rows use thinking presentation.</result>
            </task-notification>
            """
        ),
        SessionMessage(
            id: "fixture-assistant-after-task",
            role: "assistant",
            kind: "text",
            text: "The background audit finished successfully."
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
        .accessibilityIdentifier("taskNotificationFixture")
    }
}
/// Network-free harness for tagged output disclosure interactions.
struct TaggedOutputFixture: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TranscriptMessageView(message: SessionMessage(id: "tagged-output", text: """
                The task finished successfully.
                <lfg_task_result>{"run_id":"fixture-run","status":"completed","summary":"Verified all 45 minutes."}</lfg_task_result>
                The result is ready to review.
                <custom_output>Only the enclosed content appears here.</custom_output>
                """))
                TranscriptMessageView(message: SessionMessage(id: "tagged-example", text: """
                Example:
                ```xml
                <lfg_task_result>Example stays visible.</lfg_task_result>
                ```
                """))
                TranscriptMessageView(message: SessionMessage(id: "tagged-user", role: "user", text: "<user_tag>User text stays visible.</user_tag>"))
            }
            .padding()
        }
        .navigationTitle("Tagged outputs")
        .accessibilityIdentifier("taggedOutputFixture")
    }
}
#endif
