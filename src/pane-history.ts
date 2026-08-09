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
  // Spinner. The glyph rotates through a set Claude Code can extend, so match
  // ANY leading non-word glyph rather than an enumerated class — an unlisted
  // one ("✶ Levitating…") leaked straight into the reconstructed prose.
  /^\W?\s*\w[\w ]*…\s*\(\d+[sm]/,
  /^[╌─—_=-]{5,}$/, // box rule
  /^❯/, // composer / selected option
  /Enter to (select|confirm)/i,
  /↑\/↓ to navigate/i,
  /esc to interrupt/i,
  /bypass permissions on/i,
  /Update available!/i,
  /^\s*⏵⏵/,
  /^\s*⧉/,
  // NOTE: numbered lines and the "☐" box header are deliberately NOT filtered
  // here. They were, and it silently deleted every numbered list from the
  // preamble — "1. Cost at read time" is indistinguishable from a selector
  // option by shape alone, and the agents write numbered lists constantly.
  // `contentAboveSelector` removes the box structurally instead, which is the
  // only way to tell them apart.
  /^\s*←.*✔\s*Submit/, // multi-question nav bar
  // Box-drawing table rows. The TUI re-renders a table repeatedly as it streams
  // and each intermediate width is a distinct line, so keeping them stacks
  // several half-drawn copies of the same table into one unreadable run. The
  // real table arrives correctly formatted once the turn flushes.
  /[│┌┐└┘├┤┬┴┼╭╮╰╯]/,
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
/** A selector option carrying the TUI cursor — "❯ 1. Yes". The cursor is what
 *  distinguishes a live selector from a numbered list in the model's prose. */
const CURSOR_OPT_RE = /^\s*[❯›]\s*\d+\.\s+\S/;

/**
 * Everything above an open selector box.
 *
 * Once the box renders, the question text and the option descriptions sit BELOW
 * the prose but are still plain indented lines, so without this they get
 * recorded as preamble and the client shows the options twice — once as prose,
 * once in the panel (+30% spurious text, measured).
 *
 * Detection keys off the CURSOR ("❯ 1.") rather than a footer string, so it
 * covers AskUserQuestion, permission prompts and plan approval alike — and,
 * critically, so a numbered list in the model's own prose is never mistaken for
 * a selector. Prose lists have no cursor.
 */
export function contentAboveSelector(pane: string): string {
  const lines = pane.split("\n");
  const cursorOpt = lines.findIndex((l) => CURSOR_OPT_RE.test(l));
  if (cursorOpt < 0) return pane;
  for (let i = cursorOpt; i >= 0; i--) {
    if (SEP_RE.test(lines[i].trim())) return lines.slice(0, i).join("\n");
  }
  return lines.slice(0, cursorOpt).join("\n");
}

/** A markdown list item the model wrote: "- x", "* x", "• x", "1. x", "2) x". */
const LIST_ITEM_RE = /^([-*•]|\d+[.)])\s+\S/;

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
        // A separator is usually the model's own "---" rule, and dropping it
        // must not also drop the paragraph break around it — so leave the
        // pending state alone and let the blanks either side still register.
        // Anything else (a spinner, a status line) is transient chrome that
        // appears BETWEEN two prose lines and must not split them.
        if (!SEP_RE.test(key)) {
          pendingBlank = false;
          prev = null;
        }
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
    return rejoinWrap(body);
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

/**
 * Undo the pane's hard wrap without destroying the model's own line structure.
 *
 * The naive version joined every consecutive non-blank line with a space, which
 * turned a bulleted list into one run-on sentence. A list item has to start a
 * new line, and its own wrapped continuations have to fold back into it — the
 * TUI marks that difference with indentation: the marker sits at the item's
 * indent, its wrap sits deeper.
 */
export function rejoinWrap(body: string[]): string | null {
  const out: string[] = []; // finished logical lines; "" is a paragraph break
  let current: string[] = [];
  let itemIndent: number | null = null; // indent of the list item being built

  const flush = () => {
    if (current.length) out.push(current.join(" "));
    current = [];
  };

  for (const raw of body) {
    const t = raw.trim();
    if (!t) {
      flush();
      if (out.length && out[out.length - 1] !== "") out.push("");
      itemIndent = null;
      continue;
    }
    const indent = raw.length - raw.trimStart().length;
    if (LIST_ITEM_RE.test(t)) {
      flush(); // a new item always starts its own line
      itemIndent = indent;
      current.push(t);
      continue;
    }
    // Inside a list item, every following non-marker line is that item's wrap.
    // Indent is NOT a reliable discriminator here: the TUI wraps a list item
    // back to the marker's own column, so an indent test split every wrapped
    // item onto a second line. A blank or the next marker ends the item.
    void indent;
    current.push(t); // wrapped continuation of prose or of the current item
  }
  flush();
  while (out.length && out[out.length - 1] === "") out.pop();
  const text = out.join("\n").trim();
  return text || null;
}
