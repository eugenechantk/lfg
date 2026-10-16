import Foundation
import Testing
@testable import LFGCore

@Suite("S2 needs-input panel: what each kind of prompt shows")
struct NeedsInputPanelModelTests {
    private func options(_ labels: [String]) -> [PromptOption] {
        labels.enumerated().map { PromptOption(index: $0.offset + 1, label: $0.element) }
    }

    @Test("a question lists its options, offers a typed answer, and can be dismissed")
    func question() {
        let prompt = AgentPrompt(question: "Upload build 205 to TestFlight now?",
                                 options: options(["Yes, upload now", "Internal testers only",
                                                   "No, wait for my review", "Type something.", "Chat about this"]),
                                 detail: "It has the fork fix.", header: "Upload", kind: "question")
        let m = NeedsInputPanelModel(prompt: prompt, agent: "claude", cwd: nil, host: nil)
        #expect(m.label == "Claude is asking · Upload")
        #expect(m.title == "Upload build 205 to TestFlight now?")
        #expect(m.body == "It has the fork fix.")
        #expect(m.canDismiss)
        #expect(m.layout == .question(choices: [
            .init(index: 1, label: "Yes, upload now"),
            .init(index: 2, label: "Internal testers only"),
            .init(index: 3, label: "No, wait for my review"),
        ], allowsTypedAnswer: true))
    }

    @Test("an older server's prompt with no kind reads as a question; Codex names itself")
    func legacyQuestion() {
        let m = NeedsInputPanelModel(prompt: AgentPrompt(question: "Pick one", options: options(["A", "B"])),
                                     agent: "codex", cwd: nil, host: nil)
        #expect(m.label == "Codex is asking")
        #expect(m.layout == .question(choices: [.init(index: 1, label: "A"), .init(index: 2, label: "B")],
                                      allowsTypedAnswer: false))
    }

    @Test("a Claude question from the transcript still offers a typed answer")
    func transcriptQuestionTypedAnswer() {
        // The transcript's AskUserQuestion input lists only the model's options;
        // the TUI always adds "Type something.", and the host types into that
        // row from the pane (live 2026-10-16: "Which license…" had no field).
        let prompt = AgentPrompt(question: "Which license should the LICENSE file use?",
                                 options: options(["MIT (Recommended)", "Apache 2.0", "No license (All rights reserved)"]),
                                 header: "License type", kind: "question")
        let m = NeedsInputPanelModel(prompt: prompt, agent: "claude", cwd: nil, host: nil)
        guard case let .question(choices, typed) = m.layout else { Issue.record("not a question"); return }
        #expect(choices.count == 3)
        #expect(typed)
    }

    @Test("a Bash permission shows the command, where it runs, and maps the three answers")
    func permission() {
        let prompt = AgentPrompt(question: "Do you want to proceed?",
                                 options: options(["Yes",
                                                   "Yes, and don't ask again for fastlane commands in /Users/eugene/dev/personal/lfg",
                                                   "No"]),
                                 kind: "permission",
                                 permission: PromptPermission(tool: "Bash", command: "bundle exec fastlane beta upload:true",
                                                              detail: "Upload the build"))
        let m = NeedsInputPanelModel(prompt: prompt, agent: "claude",
                                     cwd: "/Users/eugene/dev/personal/lfg", host: "Pro")
        #expect(m.label == "Claude needs permission")
        #expect(m.title == "Run this command?")
        #expect(m.layout == .permission(
            command: "bundle exec fastlane beta upload:true",
            place: "In ~/dev/personal/lfg on Pro",
            allow: 1, deny: 3,
            always: .init(index: 2, label: "Always allow fastlane in this folder")))
    }

    @Test("an always-allow label the pane wrapped mid-path is rejoined and reads as this folder")
    func wrappedAlwaysLabel() {
        // Live Claude Code 2.1.280 pane (2026-10-16): option 2 wrapped mid-path,
        // so the pane parser keeps the head as the label and the tail as its
        // "description".
        let cwd = "/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad/fixture-cwd"
        let opts = [
            PromptOption(index: 1, label: "Yes"),
            PromptOption(index: 2, label: "Yes, and always allow access to /private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e",
                         description: "-4a97fab2832f/scratchpad/fixture-cwd from this project"),
            PromptOption(index: 3, label: "No"),
        ]
        let prompt = AgentPrompt(question: "Do you want to proceed?", options: opts, kind: "permission",
                                 permission: PromptPermission(tool: "Bash", command: "echo s2-fixture-check > out.txt"))
        let m = NeedsInputPanelModel(prompt: prompt, agent: "claude", cwd: cwd, host: nil)
        guard case let .permission(_, _, _, _, always) = m.layout else { Issue.record("not a permission"); return }
        #expect(always == .init(index: 2, label: "Always allow access to this folder"))
    }

    @Test("a file permission falls back to the dialog's own question as the card")
    func filePermission() {
        let prompt = AgentPrompt(question: "Do you want to make this edit to Foo.swift?",
                                 options: options(["Yes", "Yes, allow all edits during this session (shift+tab)", "No"]),
                                 kind: "permission",
                                 permission: PromptPermission(tool: "Edit", command: ""))
        let m = NeedsInputPanelModel(prompt: prompt, agent: "claude", cwd: nil, host: "Air")
        #expect(m.title == "Allow this edit?")
        guard case let .permission(command, place, allow, deny, always) = m.layout else {
            Issue.record("expected a permission layout"); return
        }
        #expect(command == "Do you want to make this edit to Foo.swift?")
        #expect(place == "On Air")
        #expect(allow == 1 && deny == 3)
        #expect(always?.label == "Allow all edits during this session")
    }

    @Test("a plan shows its first steps, the full text, and Approve / Keep planning")
    func plan() {
        let text = """
        # Plan: Ship 1.3.1

        ## Steps

        1. Bump the build to 205 and archive
           - keep the signing as is
        2. Run the release checklist on the simulator
        3. **Upload** with fastlane, then post the notes
        4. Tag the release
        """
        let prompt = AgentPrompt(question: "Claude has written up a plan and is ready to execute. Would you like to proceed?",
                                 options: options(["Yes, auto-accept edits", "Yes, manually approve edits",
                                                   "Tell Claude what to change"]),
                                 kind: "plan", plan: PromptPlan(text: text, file: "/Users/eugene/.claude/plans/x.md"))
        let m = NeedsInputPanelModel(prompt: prompt, agent: "claude", cwd: nil, host: nil)
        #expect(m.label == "Plan ready for review")
        #expect(m.title == "Approve this plan?")
        #expect(m.layout == .plan(summary: ["1. Bump the build to 205 and archive",
                                            "2. Run the release checklist on the simulator",
                                            "3. Upload with fastlane, then post the notes"],
                                  fullText: text, approve: 1, keepPlanning: 3))
    }

    @Test("a sign-in has no Dismiss, names the site and where the sign-in goes")
    func signIn() {
        let prompt = AgentPrompt(question: "Sign in to search.google.com on your iPhone", options: [],
                                 header: "Sign in",
                                 signIn: PromptSignIn(requestId: "r1", url: "https://search.google.com",
                                                      website: "search.google.com",
                                                      targetName: "Chrome on Eugenes-MacBook-Air"),
                                 kind: "signIn")
        let m = NeedsInputPanelModel(prompt: prompt, agent: "codex", cwd: nil, host: "Air")
        #expect(m.label == "Sign-in needed")
        #expect(m.title == "Sign in to search.google.com")
        #expect(m.body == "You log in on this iPhone. The sign-in then goes to Chrome on Air, where the agent is waiting.")
        #expect(!m.canDismiss)
        #expect(m.layout == .signIn(website: "search.google.com", target: "To Chrome on Eugenes-MacBook-Air",
                                    initial: "G"))
    }
}
