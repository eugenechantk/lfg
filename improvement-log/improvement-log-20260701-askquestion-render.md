# Improvement Log — Session 20260701-askquestion-render

## Tracker

- [ ] 2026-07-01 — Diagnosed the AskQuestion "hidden context" bug from an ANSWERED transcript, built the wrong fix (scroll), then had to revert after live repro showed the real cause
- [ ] 2026-07-01 — Shipped the context-scrape fix verified only against a SHORT one-line preamble; real long preambles returned null (bullet scrolled off) → user still saw the bug
- [ ] 2026-07-01 — Told the user the tool object is "never in the transcript until answered"; user corrected me (qa4 had it) — flush is DELAYED, not never. Over-concluded from repros checked too early.
- [ ] 2026-07-01 — The "capture context without the bullet" change echoed the user's own scrolled-off prompt back as fake "context"; required the bullet to fix.

## Log

### 2026-07-01 — Over-concluded "never in transcript" from repros checked too early

**What happened:** I asserted (in code comments and to the user) that the AskUserQuestion structured object "isn't in the transcript until answered," based on repros where I grepped the transcript right after the prompt appeared and found nothing. The user corrected me: session lfg-qa4 was still pending AND its transcript contained the full object. Truth: Claude Code flushes the pending turn to the JSONL after a DELAY (seconds to minutes), not never — my checks were just too early. `pendingToolPrompt` (transcript path, already preferred by `resolveSessionPrompt`) returns the complete structured object — full question, labels, descriptions — once flushed.

**Why this was wrong:** I generalized "not there yet" into "never there," and baked that false claim into comments and my mental model. It made me over-invest in pane scraping as the only source when the transcript path already solves it for any session pending more than a short window. A single "wait 30–60s then re-check" would have caught the flush.

**What better looks like:** For async/eventually-consistent state, test the steady state AND the transient, and distinguish "not yet" from "never" explicitly before writing either into a comment or telling the user. When the user points at a specific counterexample (qa4), inspect THAT artifact first.

### 2026-07-01 — Pane context scrape echoed the user's own prompt as fake "context"

**What happened:** Round 2's change captured the block above the selector even when the "⏺" assistant bullet wasn't visible (to handle long preambles that scrolled off). But when the agent asks with NO preamble, the block directly above the selector is the USER's own (scrolled-off, marker-gone) prompt — so the panel rendered the user's instruction back to them as the agent's "explanation." Caught it in a live screenshot.

**Why this was wrong:** I removed the only reliable signal (the bullet) that distinguishes assistant prose from the user's prompt, trading a false-negative (long preamble hidden) for a worse false-positive (wrong content shown as authoritative). Both a scrolled-off assistant preamble and a scrolled-off user prompt render as 2-space-indented wrapped lines — indistinguishable without the marker.

**What better looks like:** When two cases are structurally identical after losing their only distinguishing marker, don't guess — require the marker and accept the false-negative. Showing nothing beats confidently showing the wrong thing. (A cleaner future option: pass the known last-user-text into the scraper and discard any "context" that matches it, which would let long scrolled-off preambles be shown safely.)

### Net outcome of the question-component round
Server serves the full structured prompt from the transcript when available (preferred), and the pane fallback now also yields the full wrapped question + per-option descriptions + a correctly-attributed (bullet-gated) context. Verified live: qa5 (no preamble) shows full question + descriptions and NO fake context; qa6 (real preamble) shows the preamble as context. Client already rendered all of this — server-only change, no new TestFlight build required.

### 2026-07-01 — Verified the fix against a trivially short input, not a realistic one

**What happened:** After shipping the pane-scrape context fix to TestFlight, the user reported the response was still hidden. My repro + unit test both used a ONE-LINE preamble ("Status ready, pick the path."), which fit entirely on the visible pane with the `⏺` bullet showing — so my scrape worked and I called it verified. Real sessions have LONG, multi-paragraph preambles. Reproducing that revealed: (1) Claude's TUI is a full-screen (alternate-screen) app so tmux keeps NO scrollback — `capture-pane` only ever returns the visible rows, and the top of a long response is gone; (2) my scrape required finding the `⏺` bullet and capped at 8 lines, so when the bullet scrolled off it returned `null` and nothing rendered. Fixed by capturing the visible block regardless of the bullet, across paragraph breaks.

**Why this was wrong:** I proved the mechanism on the easiest possible input. A one-line preamble can't exhibit the two failure modes that matter (scroll-off + multi-paragraph). "It works on my toy repro" gave false confidence and cost the user a round trip + a wasted TestFlight build cycle.

**What better looks like:** Choose repro inputs that stress the actual failure surface, not the happy path. For anything that reads a bounded viewport (pane scrape, fixed buffers, truncated logs), the FIRST test case should exceed the viewport (long, wrapped, multi-paragraph, scrolled). If the real-world input is "a paragraph of analysis before a question," test with a paragraph, not a sentence.

**Architectural note worth persisting:** lfg can never show the full preamble of a long response *while the question is pending* — the off-screen top isn't in the pane (full-screen TUI, no scrollback) and the whole turn is buffered out of the transcript until answered. The panel shows the visible tail (which holds the actual ask); the complete text appears as a normal bubble once answered. The only ways to capture more are upstream (Claude flushes the turn earlier) or spawning managed tmux sessions with a taller pane so more of the response is on screen.

### 2026-07-01 — Verified the wrong state (answered) before designing the fix

**What happened:** The bug: when an agent asks an AskUserQuestion, the last AI message (the context needed to answer) is hidden until the question is answered. I got ground truth early by inspecting a real transcript — but it was an *already-answered* AskUserQuestion, where the assistant text block sits right before the tool_use. From that I concluded the data was present and the bug was a scroll/layout issue (the tall options panel pushing the context message off the top). I implemented a scroll fix (pin the preceding AI message to the top when a prompt appears), reverted the SessionDetailView changes only after a *live* repro proved it wrong.

**Root cause (actual):** Claude Code does NOT flush the AskUserQuestion turn (explanatory text + tool_use) to the transcript JSONL until the question is answered. While the question is live, the prompt is surfaced from the **tmux pane scrape**, and the preceding assistant prose is ONLY in the pane — never streamed to the client. So the context genuinely isn't in the client's data while pending; it "appears only after answering" because that's when Claude writes the turn. The real fix: scrape the `⏺ …` prose above the selector in `parsePrompt` (tmux.ts), carry it as `PanePrompt.context` → SSE `prompt` payload → `AgentPrompt.context`, and render it above the question in `PromptPanelView`.

**Why this was wrong:** I verified a state *similar to* the bug (answered) instead of the state that *is* the bug (pending). The two differ precisely in the thing that matters — whether the assistant text is in the transcript. A live pending repro (spawn a claude session that blocks on AskUserQuestion, then read the JSONL tail) would have shown the missing turn in ~2 minutes and pointed straight at the pane-scrape fix.

**What better looks like:** When a bug is about a transient/pending state, reproduce and inspect THAT state's ground truth, not a nearby resting state. "Is the data even present in the failing state?" comes before "why isn't the present data displayed correctly?" For lfg specifically: interactive selectors (AskUserQuestion / permission / plan) are pane-scraped precisely because their turn isn't in the transcript while live — that's the signal that any "missing content while a prompt is up" bug is a data-availability problem, not a rendering one.

**Process notes that went right:** built a live repro by spawning a throwaway blocking claude session; restarted the long-lived `serve` process (Bun has no hot-reload) to deploy the tmux.ts change per the project hazard doc; wrote a unit test (`tmux-prompt.test.ts`) for the scrape against the real captured pane; verified the fix on the simulator by tapping the real gesture.
