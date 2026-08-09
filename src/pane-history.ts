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

import { stripAnsi } from "./tmux.ts";

/** Drop the markdown markers we added, to recover the plain text a dedup key
 *  and the blank-line anchor must compare against. */
function stripMarkers(md: string): string {
  return md.replace(/\*\*/g, "").replace(/`/g, "");
}

/** Lines kept per session. ~600 rows at 78 cols is ~4,500 words of preamble —
 *  far more than any realistic pre-question explanation — and bounds memory to
 *  tens of KB per session, which matters on a box that has OOMed before. */
export const MAX_LINES = 600;

/** The assistant message bullet the Claude TUI prints ("⏺ <text>"). */
const ASSISTANT_BULLET = "⏺";
/** The bullet, possibly behind markdown markers we recovered from styling. */
const BULLET_PREFIX_RE = /^((?:\*\*|`)*)⏺\s*/;

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
  /^\W?\s*[\w'’ -]+…\s*\(\d+[sm]/,
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
/** The question box's header chip ("☐ Retry strategy") and its footer hint. */
const BOX_HEADER_RE = /^☐\s+\S/;
const BOX_FOOTER_RE = /Enter to (select|confirm)|Esc to cancel/i;

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
  return lines.slice(0, selectorCutIndex(lines.map(stripAnsi))).join("\n");
}

/**
 * Index at which to cut, given PLAIN lines.
 *
 * Separate from `contentAboveSelector` because `consume` now feeds the stitcher
 * STYLED captures: every pattern here (the cursor, the "☐" chip, the footer)
 * sits behind an escape sequence in that form and silently stops matching, so
 * the whole question box leaked back into the prose. Decide the cut on the
 * plain text, apply it to the styled lines.
 */
export function selectorCutIndex(lines: string[]): number {
  // The box paints in stages: header and options can be on screen for a beat
  // before the cursor is drawn. Keying on the cursor alone let that frame
  // record the entire question box as prose. Take the EARLIEST sign of a box.
  let box = -1;
  let anchorIsOption = false;
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    const isOption = CURSOR_OPT_RE.test(lines[i]);
    if (isOption || BOX_HEADER_RE.test(t) || BOX_FOOTER_RE.test(t)) {
      box = i;
      anchorIsOption = isOption;
      break;
    }
  }
  if (box < 0) return lines.length;
  // Prefer the box's own top rule.
  for (let i = box; i >= 0; i--) {
    if (SEP_RE.test(lines[i].trim())) return i;
  }
  // No rule in view (it scrolled off). Only an OPTION anchor has box content
  // above it — the question text — worth dropping; the header and footer are
  // already the top and bottom of the box, so cutting at them is exact. Getting
  // this wrong the other way deleted the preamble entirely.
  if (!anchorIsOption) return box;
  let i = box - 1;
  while (i >= 0 && !lines[i].trim()) i--;
  while (i >= 0 && lines[i].trim()) i--;
  return Math.max(0, i + 1);
}

/** A markdown list item the model wrote: "- x", "* x", "• x", "1. x", "2) x". */
const LIST_ITEM_RE = /^([-*•]|\d+[.)])\s+\S/;

// ---------------------------------------------------------------------------
// Recovering the markdown the TUI already rendered away
//
// By the time text reaches the pane, `**bold**` is SGR 1 and `` `code` `` is a
// 256-colour span — the asterisks and backticks are gone. A plain capture
// therefore yields flat prose, which is exactly how a recovered preamble read.
// Captured WITH `-e`, the styling survives and maps back cleanly. Verified
// against a live pane:
//
//   4. \e[1mWhole-file retry versus resumable chunks.\e[0m For files above…
//   - Always honor \e[38;5;153mRetry-After\e[39m when the server sends it…
//
// CAVEAT: the colour numbers are the TUI's theme, not a protocol. SGR 1 for
// bold is standard and safe; the inline-code colour is not, and a Claude Code
// theme change will silently stop backticks being recovered. That degrades to
// today's behaviour (plain text), never to corruption — which is why this is
// worth doing despite the fragility.
// ---------------------------------------------------------------------------

/** 256-colour foreground the TUI uses for inline code spans. */
const INLINE_CODE_FG = "38;5;153";
/** Foreground colours syntax highlighting uses inside fenced code blocks. */
const SYNTAX_FG = new Set(["31", "32", "33", "34", "36", "35"]);
const SGR_RE = /\x1b\[([0-9;]*)m/g;
/** Rows that belong to an already-open code fence even without syntax colour:
 *  closing braces, and lines with code punctuation but no sentence ending. */
const CODE_CONTINUATION_RE = /^[)}\];,]|[{};]$|=>|\breturn\b|^\s{2,}\S/;
const ANY_ESC_RE = /\x1b\[[0-9;]*[A-Za-z]/g;

/** True when this styled line is a syntax-highlighted code-block row. */
export function isCodeLine(styled: string): boolean {
  let n = 0;
  for (const m of styled.matchAll(SGR_RE)) if (SYNTAX_FG.has(m[1])) n++;
  return n >= 2; // one stray colour is not a code block
}

/**
 * Turn one styled pane line back into markdown.
 *
 * Emits `**…**` for bold runs and `` `…` `` for inline-code runs, then drops
 * every remaining escape. Runs are closed at the matching reset (SGR 0/22/39)
 * and force-closed at end of line, so a span the pane wrapped mid-way can't
 * leak an unbalanced marker into the output.
 */
export function ansiToMarkdown(styled: string): string {
  let out = "";
  let last = 0;
  let bold = false;
  let code = false;
  const close = () => {
    if (code) { out += "`"; code = false; }
    if (bold) { out += "**"; bold = false; }
  };
  for (const m of styled.matchAll(SGR_RE)) {
    out += styled.slice(last, m.index);
    last = m.index + m[0].length;
    for (const p of (m[1] || "0").split(";")) void p; // params handled below
    const params = m[1] || "0";
    if (params === "1" && !bold) { out += "**"; bold = true; continue; }
    if (params === INLINE_CODE_FG && !code) { out += "`"; code = true; continue; }
    if (params === "0" || params === "") { close(); continue; }
    if (params === "22" && bold) { out += "**"; bold = false; continue; }
    if (params === "39" && code) { out += "`"; code = false; continue; }
  }
  out += styled.slice(last);
  close(); // never leave a span open across a line break
  return out.replace(ANY_ESC_RE, "");
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
type Kept = {
  /** Markdown-recovered text (indent preserved for list-wrap detection). */
  md: string;
  /** A syntax-highlighted code-block row: never wrap-joined, fenced on output. */
  code: boolean;
};

export class PaneStitcher {
  private lines: Kept[] = [];
  private seen = new Set<string>();

  /** Fold one capture into the reconstruction. Null/empty captures are ignored. */
  consume(pane: string | null): void {
    if (!pane) return;
    const styledLines = pane.split("\n");
    const cut = selectorCutIndex(styledLines.map(stripAnsi));
    const frame = styledLines.slice(0, cut);
    // Blank lines are paragraph breaks and must survive — without them the
    // preamble renders as one run-on wall of text. They can't go through the
    // content dedup (every blank is identical, so a Set keeps exactly one), so
    // they're carried as a pending flag and emitted only *between* newly added
    // content. That way a blank inside an already-seen region can't inject a
    // stray break into text we recorded on an earlier frame.
    let pendingBlank = false;
    let prev: string | null = null; // last content line seen in THIS frame
    for (const styled of frame) {
      // Every decision (chrome, dedup, blanks) is made on the PLAIN text; only
      // what we keep carries the recovered markdown.
      const line = stripAnsi(styled).trimEnd();
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
        this.push({ md: "", code: false });
        pendingBlank = false;
      }
      this.seen.add(key);
      const indent = line.length - line.trimStart().length;
      this.push({
        md: " ".repeat(indent) + ansiToMarkdown(styled).trim(),
        code: isCodeLine(styled),
      });
      prev = key;
    }
  }

  /** Trimmed content of the last non-blank reconstructed line. */
  private tail(): string | null {
    for (let i = this.lines.length - 1; i >= 0; i--) {
      const t = stripMarkers(this.lines[i].md).trim();
      if (t) return t;
    }
    return null;
  }

  private push(line: Kept): void {
    this.lines.push(line);
    if (this.lines.length > MAX_LINES) {
      const dropped = this.lines.shift();
      if (dropped) this.seen.delete(stripMarkers(dropped.md).trim());
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
    // Detect on the marker-stripped text: if the TUI styles the bullet line,
    // `ansiToMarkdown` puts a "**" in front of the bullet and a naive
    // startsWith stops finding the turn at all — which reads as "no preamble".
    let start = -1;
    for (let i = this.lines.length - 1; i >= 0; i--) {
      if (stripMarkers(this.lines[i].md).trim().startsWith(ASSISTANT_BULLET)) {
        start = i;
        break;
      }
    }
    if (start < 0) return null;
    const body = this.lines.slice(start).map((l, i) =>
      i === 0
        ? { ...l, md: l.md.trim().replace(BULLET_PREFIX_RE, "$1") }
        : l,
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
/**
 * Repair a markdown span the pane split across two rows.
 *
 * `ansiToMarkdown` force-closes an open span at end of line (an unbalanced
 * marker would corrupt everything after it), so a bold phrase that wrapped
 * comes back as "**all **" + "**failures**". Rejoining the wrap has to close
 * that seam or the reader sees stray asterisks mid-phrase.
 */
export function healSpans(line: string): string {
  // Absorb the whitespace on BOTH sides of the seam, or healing "all ** **more"
  // leaves a double space where the wrap used to be. The pane hard-wraps at
  // spaces, so a single space is always the right joint.
  return line
    .replace(/\s?\*\*\s*\*\*\s?/g, " ")
    .replace(/\s?`\s*`\s?/g, " ");
}

export function rejoinWrap(body: Array<{ md: string; code: boolean }>): string | null {
  const out: string[] = []; // finished logical lines; "" is a paragraph break
  let current: string[] = [];
  let inList = false;
  let inCode = false;

  const flush = () => {
    if (current.length) out.push(healSpans(current.join(" ")));
    current = [];
  };
  const closeCode = () => {
    if (inCode) {
      out.push("```");
      inCode = false;
    }
  };

  for (const { md, code } of body) {
    const t = md.trim();
    // Once a fenced run is open, keep rows in it unless they clearly return to
    // prose. A bare "}" or a mostly-plain continuation carries too few syntax
    // colours to be detected on its own, and treating it as prose closed the
    // fence and reopened another one two lines later.
    const inRun = inCode && !!t && (code || CODE_CONTINUATION_RE.test(t));
    if (code || inRun) {
      // Code rows are never wrap-joined — folding them together turned a
      // multi-line function into one unreadable line — and a run of them is
      // fenced so the client renders it as a code block rather than prose.
      flush();
      if (!inCode) {
        if (out.length && out[out.length - 1] !== "") out.push("");
        out.push("```");
        inCode = true;
      }
      out.push(md.replace(/^\s{0,2}/, ""));
      inList = false;
      continue;
    }
    if (!t) {
      flush();
      // A blank inside a fenced block is part of the code, not a break.
      if (inCode) { out.push(""); continue; }
      if (out.length && out[out.length - 1] !== "") out.push("");
      inList = false;
      continue;
    }
    closeCode();
    if (LIST_ITEM_RE.test(t)) {
      flush(); // a new item always starts its own line
      inList = true;
      current.push(t);
      continue;
    }
    // Inside a list item, every following non-marker line is that item's wrap.
    // Indent is NOT a reliable discriminator: the TUI wraps a list item back to
    // the marker's own column, so an indent test split every wrapped item in
    // two. A blank line or the next marker ends the item.
    void inList;
    current.push(t);
  }
  flush();
  closeCode();
  while (out.length && out[out.length - 1] === "") out.pop();
  const text = out.join("\n").trim();
  return text || null;
}
