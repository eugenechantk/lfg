import Testing
@testable import LFGCore

struct FollowupDirectivesTests {
    @Test func extractsMixedBulletStylesInOrder() {
        let text = """
        I completed the form.

        :codex-followup[Complete personal fields]{prompt="Add my date and place of birth, Chinese personal name, and previous-name status to the PDF."}
        • :codex-followup[Prepare signing copy]{prompt="Review the entire form and prepare the final signing copy with all available fields completed."}
        - :codex-followup[Draft return email]{prompt="Draft the email returning this form to View Well and asking them to confirm the remaining fields and charges."}
        """
        let result = FollowupDirectives.extract(from: text)

        #expect(result.prose == "I completed the form.")
        #expect(result.followups.map(\.title) == [
            "Complete personal fields", "Prepare signing copy", "Draft return email",
        ])
        #expect(result.followups[0].prompt.hasPrefix("Add my date"))
        #expect(!result.prose.contains(":codex-followup"))
    }

    @Test func decodesEscapedPrompt() {
        let text = #":codex-followup[Review]{prompt="Check \"quoted\" fields and line\nbreaks."}"#
        let result = FollowupDirectives.extract(from: text)
        #expect(result.followups == [FollowupDirective(
            title: "Review", prompt: "Check \"quoted\" fields and line\nbreaks."
        )])
    }

    @Test func malformedAndFencedDirectivesRemainVisible() {
        let text = """
        :codex-followup[Missing prompt]{prompt=oops}

        ```text
        :codex-followup[Example]{prompt="Do not use this"}
        ```swift
        :codex-followup[Still example]{prompt="Do not use this either"}
        ```

        :codex-followup[Valid]{prompt="Use this"}
        """
        let result = FollowupDirectives.extract(from: text)
        #expect(result.followups.map(\.title) == ["Valid"])
        #expect(result.prose.contains(":codex-followup[Missing prompt]"))
        #expect(result.prose.contains(":codex-followup[Example]"))
        #expect(result.prose.contains(":codex-followup[Still example]"))
    }

    @Test func doesNotAlterUserTextWhenExtractionDisabled() {
        let text = #":codex-followup[Literal]{prompt="Shown as typed"}"#
        let row = TranscriptRowText.derive(from: text, extractFollowups: false)
        #expect(row.prose == text)
        #expect(row.displayText == text)
        #expect(row.followups.isEmpty)
    }

    @Test func draftAdditionPreservesExistingText() {
        #expect(FollowupDraft.adding("Prompt", to: "") == "Prompt")
        #expect(FollowupDraft.adding("Prompt", to: "My notes") == "My notes\n\nPrompt")
        #expect(FollowupDraft.adding("Prompt", to: "My notes\n") == "My notes\n\nPrompt")
    }
}
