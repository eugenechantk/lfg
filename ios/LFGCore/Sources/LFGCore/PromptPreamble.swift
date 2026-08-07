import Foundation

/// The prose a model wrote immediately before asking a question, promoted out of
/// the prompt panel and into the transcript as an ordinary assistant turn.
///
/// **Why it isn't already a transcript message.** Claude Code does not flush the
/// assistant turn containing an interactive tool (AskUserQuestion, a permission
/// prompt, plan approval) to its JSONL until the question is answered, and it
/// runs in the alternate screen so there is no scrollback. While the question is
/// live that prose exists only on the tmux pane; the server scrapes it into
/// `AgentPrompt.context` (see `src/tmux.ts`), which is the only copy any client
/// can have. See `.claude/diagnosis-question-preamble-invisible-20260807.md`.
///
/// **Why it belongs in the transcript rather than in the panel.** It is the
/// model *answering* — usually the reasoning you need in order to choose. Inside
/// a "Needs your input" card it reads as a form label, gets the panel's flat
/// `.subheadline`, and is visually subordinate to the options it exists to
/// explain. Rendered as a normal assistant bubble it gets the same markdown,
/// typography and media handling as every other turn, and the conversation reads
/// continuously: prose, then the question.
///
/// The synthesized turn is transient. The moment the question is answered Claude
/// flushes the real turn and the real message takes over — `shouldSynthesize`
/// exists to make that handover seamless rather than briefly doubled.
public enum PromptPreamble {
    /// Identity for the synthesized turn. Stable per session so SwiftUI treats a
    /// re-scrape (the pane text can grow as the model streams) as an update to
    /// one row rather than as a new row.
    public static func id(sessionID: String) -> String { "prompt-preamble:\(sessionID)" }

    /// How many trailing transcript messages to check for the real turn. The
    /// flushed turn lands at the very end; a wider scan risks matching unrelated
    /// older prose.
    static let tailWindow = 6

    /// Shortest context worth attributing. Below this, a containment test is
    /// coincidence rather than evidence.
    static let minMatchLength = 24

    /// The assistant turn to render above the prompt panel, or nil when there is
    /// nothing to add.
    ///
    /// Returns nil when the question carries no scraped context, and — critically
    /// — when the real turn has already landed in `transcriptTail`.
    ///
    /// **Why this keys off the transcript and NOT off the prompt disappearing.**
    /// The tempting simplification is "drop the synthetic turn when the panel goes
    /// away" — same lifecycle, one event, no scanning. It is wrong, and measurably
    /// so. On answering, the flushed `msg` and the cleared/replaced `prompt` are
    /// produced by two different pump loops (messages tail at 700ms, pane polls at
    /// 1000ms), so their order is a race. Measured over 14 real answered questions
    /// in the journal: the prose landed FIRST in 9 of them, by up to 0.89s. The
    /// duplication window therefore opens when the prose ARRIVES, and a
    /// panel-disappearance trigger fires after it has already been open for most of
    /// a second — showing the double it was meant to prevent.
    ///
    /// Keying off the transcript makes the handover ordering-independent: whichever
    /// event lands first, the synthetic turn stands down in the same render pass as
    /// the real one appearing.
    public static func message(
        for prompt: AgentPrompt?,
        sessionID: String,
        transcriptTail: [SessionMessage]
    ) -> SessionMessage? {
        guard let context = prompt?.context?.trimmingCharacters(in: .whitespacesAndNewlines),
              !context.isEmpty
        else { return nil }
        guard shouldSynthesize(context: context, transcriptTail: transcriptTail) else { return nil }
        return SessionMessage(id: id(sessionID: sessionID), role: "assistant", kind: "text", text: context)
    }

    /// False once the transcript itself carries this prose.
    static func shouldSynthesize(context: String, transcriptTail: [SessionMessage]) -> Bool {
        let needle = normalized(context)
        guard needle.count >= minMatchLength else { return true }
        for m in transcriptTail.suffix(tailWindow) where m.role == "assistant" && m.kind == "text" {
            // The real turn is a superset of the scrape whenever the pane clipped
            // the top of it, so containment (not equality) is the right test.
            if normalized(m.text).contains(needle) { return false }
        }
        return true
    }

    /// Collapse whitespace and case. The scrape rejoins the pane's hard wrap with
    /// single spaces, so it can never match the flushed turn's original line
    /// breaks byte-for-byte.
    static func normalized(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
