// A scrollback for panes that have none.
//
// Claude Code does not flush the assistant turn containing an interactive tool
// (AskUserQuestion, permission, plan approval) to its transcript until the user
// answers, so while a question is live the prose the model wrote before asking
// exists ONLY on the pane. And Claude runs in the ALTERNATE SCREEN, so the pane
// has `history_size == 0`: `capture-pane -S -N` returns exactly the visible
// grid and nothing older.
//
// That makes a single capture structurally insufficient. Measured on a real
// 78x59 pane (the size an iTerm-hosted `cy` session gets): a ~700-word answer
// occupies more rows than the pane has, so by the time the question renders the
// top of the turn — including the `⏺` bullet that marks where it began — has
// been overwritten. The scrape returns a mid-sentence tail of roughly 40%, or
// nothing at all.
//
// But the head WAS on screen, earlier. While the model streams, the message
// grows from the top; the pump already captures the pane about once a second.
// Measured over one such turn (35 captures): frame 5 contained
// `⏺ STITCHMARK — the push versus pull decision…`, the answer's first words,
// while the final frame contained no bullet at all. The information is not
// missing, it is merely not retained.
//
// This class retains it: feed it every capture and it reconstructs the text
// that scrolled away. Cost is one pass over an already-taken capture, so it
// adds no tmux calls to the poll loop.

/** Lines kept per session. ~600 rows at 78 cols is ~4,500 words of preamble —
 *  far more than any realistic pre-question explanation — and bounds memory to
 *  tens of KB per session, which matters on a box that has OOMed before. */
export const MAX_LINES = 600;

/** The assistant message bullet the Claude TUI prints ("⏺ <text>"). */
const ASSISTANT_BULLET = "⏺";

/**
 * Pane chrome that redraws constantly and must never enter the reconstruction:
 * spinners with elapsed time, the composer box, the status/hint footer, box
 * rules, and the update nag. Without this filter the buffer fills with hundreds
 * of near-identical spinner lines and the real prose is buried.
 */
const CHROME = [
  /^[✻✽✢✳*·⏺]?\s*\w+…\s*\(\d+[sm]/, // "✽ Fermenting… (27s · ↓ 1.2k tokens)"
  /^[╌─—_=-]{5,}$/, // box rule
  /^❯/, // composer / selected option
  /Enter to (select|confirm)/i,
  /↑\/↓ to navigate/i,
  /esc to interrupt/i,
  /bypass permissions on/i,
  /Update available!/i,
  /^\s*⏵⏵/,
  /^\s*⧉/,
  /^\s*\d+\.\s/, // selector option lines
  /^\s*☐/, // question box header
  /^\s*←.*✔\s*Submit/, // multi-question nav bar
  /^\s*\/\w+$/, // "/rc" hint
  /^●\s+\w+\s+·\s+\/effort/, // model/effort chip
];

/** Blank lines are handled by `consume` as paragraph breaks, not here. */
function isChrome(line: string): boolean {
  const t = line.trim();
  if (!t) return false;
  return CHROME.some((re) => re.test(t));
}

const SEP_RE = /^[╌─—_=-]{5,}$/;
const OPT_LINE_RE = /^\s*(❯|›)?\s*\d+\.\s+\S/;

/**
 * Everything above an open question box.
 *
 * Once the selector renders, the question text and the option descriptions sit
 * BELOW the prose but are still plain indented lines — so without this they get
 * recorded as part of the preamble and the client shows the options twice: once
 * as prose, once in the panel. Measured at +30% spurious text.
 */
export function contentAboveSelector(pane: string): string {
  if (!/Enter to select/i.test(pane)) return pane;
  const lines = pane.split("\n");
  const firstOpt = lines.findIndex((l) => OPT_LINE_RE.test(l));
  if (firstOpt < 0) return pane;
  for (let i = firstOpt; i >= 0; i--) {
    if (SEP_RE.test(lines[i].trim())) return lines.slice(0, i).join("\n");
  }
  return lines.slice(0, firstOpt).join("\n");
}

/**
 * Rebuilds a pane's lost scrollback from successive captures.
 *
 * Dedup is by line CONTENT in first-seen order, not by diffing consecutive
 * frames. Frame-to-frame overlap matching is the obvious approach and it does
 * not work here: the bottom rows (spinner, composer, token counter) change on
 * every capture, so the tail of the reconstruction is never a stable anchor to
 * match against. Content dedup is immune to that, and prose lines are unique
 * enough in practice that dropping an exact repeat costs nothing.
 */
export class PaneStitcher {
  private lines: string[] = [];
  private seen = new Set<string>();

  /** Fold one capture into the reconstruction. Null/empty captures are ignored. */
  consume(pane: string | null): void {
    if (!pane) return;
    pane = contentAboveSelector(pane);
    // Blank lines are paragraph breaks and must survive — without them the
    // preamble renders as one run-on wall of text. They can't go through the
    // content dedup (every blank is identical, so a Set keeps exactly one), so
    // they're carried as a pending flag and emitted only *between* newly added
    // content. That way a blank inside an already-seen region can't inject a
    // stray break into text we recorded on an earlier frame.
    let pendingBlank = false;
    let prev: string | null = null; // last content line seen in THIS frame
    for (const raw of pane.split("\n")) {
      const line = raw.trimEnd();
      const key = line.trim();
      if (!key) {
        // Honor this blank only if it sits exactly at the reconstruction's tail.
        // A frame re-shows text we already have, and a real paragraph break in
        // that already-recorded region would otherwise be deferred to whatever
        // new line comes next — which is typically several lines further on, in
        // the middle of a sentence. That produced a break every ~2 pane rows.
        pendingBlank = prev !== null && this.tail() === prev;
        continue;
      }
      if (isChrome(line)) {
        // A spinner or status line between two prose lines is not a paragraph
        // break ("✻ Brewed for 27s" comes and goes mid-stream).
        pendingBlank = false;
        prev = null;
        continue;
      }
      if (this.seen.has(key)) {
        prev = key;
        pendingBlank = false;
        continue;
      }
      if (pendingBlank) {
        this.push("");
        pendingBlank = false;
      }
      this.seen.add(key);
      this.push(line);
      prev = key;
    }
  }

  /** Trimmed content of the last non-blank reconstructed line. */
  private tail(): string | null {
    for (let i = this.lines.length - 1; i >= 0; i--) {
      const t = this.lines[i].trim();
      if (t) return t;
    }
    return null;
  }

  private push(line: string): void {
    this.lines.push(line);
    if (this.lines.length > MAX_LINES) {
      const dropped = this.lines.shift();
      if (dropped) this.seen.delete(dropped.trim());
    }
  }

  /**
   * The current turn's assistant prose: everything from the LAST assistant
   * bullet onward, wrap-rejoined into paragraphs.
   *
   * Returns null when no bullet has been seen — meaning we never witnessed the
   * start of this turn (the pump began watching mid-answer), and guessing where
   * the prose begins would risk surfacing the user's own text as the model's.
   */
  preamble(): string | null {
    let start = -1;
    for (let i = this.lines.length - 1; i >= 0; i--) {
      if (this.lines[i].trim().startsWith(ASSISTANT_BULLET)) {
        start = i;
        break;
      }
    }
    if (start < 0) return null;
    const body = this.lines
      .slice(start)
      .map((l, i) =>
        i === 0 ? l.trim().replace(new RegExp(`^${ASSISTANT_BULLET}\\s*`), "") : l,
      );
    // Rejoin the pane's hard wrap. A line indented two spaces is a continuation
    // of the paragraph above it; anything flush-left starts a new one.
    const paragraphs: string[] = [];
    let current: string[] = [];
    for (const line of body) {
      const t = line.trim();
      if (!t) {
        if (current.length) paragraphs.push(current.join(" "));
        current = [];
        continue;
      }
      current.push(t);
    }
    if (current.length) paragraphs.push(current.join(" "));
    const text = paragraphs.join("\n\n").trim();
    return text || null;
  }

  /** Start a fresh turn. Called on the idle→busy edge, so one turn's prose can
   *  never leak into the next one's question. */
  reset(): void {
    this.lines = [];
    this.seen.clear();
  }

  /** Reconstructed line count — for tests and diagnostics. */
  size(): number {
    return this.lines.length;
  }
}
