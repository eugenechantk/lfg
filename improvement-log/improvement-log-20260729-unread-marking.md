# Improvement Log — Session 20260729-unread-marking

## Tracker

- [x] 2026-07-29 — Codex delegation failed instantly: ROOT CAUSE was a stale `version` header in config.toml, not an old CLI → fixed + memory [[codex-version-header-pin]]
- [ ] 2026-07-29 — Concurrent lfg session editing the same iOS files during this task (Components.swift diff grew mid-run)
- [ ] 2026-07-29 — New iOS source file from a delegation needed `xcodegen generate`; brief didn't say so
- [ ] 2026-07-29 — Wasted calls trying to flip the sim's Settings notification toggle; erasing a spare sim is the cheap path
- [ ] 2026-07-29 — Chased a UI-layout cause for 3 build cycles when the title `…` was truncated in the API data

## Log

### 2026-07-29 — Codex CLI too old for its default model

**What happened:** First `/codex:rescue --background` delegation died in 18s with
`400 invalid_request_error: The 'gpt-5.6-sol' model requires a newer version of Codex`.
Local `codex-cli` is 0.141.0 (installed 2026-06-19). Relaunching with an explicit
`--model gpt-5.5` worked.
**Why this matters:** The failure is instant and looks like a delegation/plumbing problem,
not a version problem. Without pinning a model, every delegation on this host fails.
**What better looks like:** (a) upgrade the codex CLI (`npm i -g @openai/codex` — global
npm under Homebrew node), (b) until then, always pass `--model gpt-5.5` when delegating
from this machine. Worth a memory entry if it recurs after an upgrade.

### 2026-07-29 — Concurrent session editing the same iOS files

**What happened:** Session `c2bfc033` (busy, same repo) was actively editing
`ios/LFG/Components.swift` / `SessionDetailView.swift` while my Codex delegation edited
`SessionStore.swift` / `SessionDetailView.swift`. The `Components.swift` diff grew from 26
to 56 changed lines mid-run, with no action from my side.
**Why this matters:** A build failure during my verification could be *their* in-flight
code, and attributing it to Codex would waste a debug cycle. Documented hazard in
`.claude/CLAUDE.md`, but the specific tell (diffstat growing while I'm idle) is worth
remembering.
**What better looks like:** Snapshot `git diff --stat` before delegating (done here), and
on a build failure, attribute by file before assuming the delegated work broke it.

### 2026-07-29 — Delegated brief said "don't build", so a missing Xcode-project entry surfaced only in my verification

**What happened:** The brief told Codex not to build (FlowDeck is the house tool and the
supervising session owns the simulator). Codex added `ios/LFG/UnreadBadges.swift` but the
Xcode project didn't include it, so my first build failed with `cannot find 'AppBadge' in
scope`. Fixed with `xcodegen generate` (5 seconds), but it cost a full build cycle.
**Why this matters:** Any delegated iOS task that adds a NEW source file needs
`xcodegen generate` before the first build; the brief didn't say so explicitly.
**What better looks like:** Add to the delegation brief template for this repo: "if you add
a new source file under `ios/`, run `cd ios && xcodegen generate` as the last step."

### 2026-07-29 — Simulator notification permission blocked SC5 and the sim wedged on its lock screen

**What happened:** The app-icon badge can't render when notifications are denied. The
iPhone 17 sim had them denied; the Settings toggle ignored synthetic taps, and my HID
touch attempts left the sim stuck on the lock screen (3 failed unlock attempts).
Switching to an **erased** spare sim (so the real permission prompt re-appeared) verified
it in ~4 steps.
**Why this matters:** I burned ~6 tool calls trying to flip a system Settings toggle. The
project CLAUDE.md already notes the permission prompt only clears with an erase — the
corollary (erase + accept the prompt is cheaper than driving Settings) wasn't recorded.
**What better looks like:** For any sim verification needing notification permission:
erase a spare sim and accept the in-app prompt. Never try to drive the iOS Settings
notification toggle.

### 2026-07-29 — I misdiagnosed the Codex failure as an outdated CLI (it was a stale config header)

**What happened:** `/codex:rescue` died with "The 'gpt-5.6-sol' model requires a newer
version of Codex. Please upgrade to the latest app or CLI." I took the error at face value,
logged it as "CLI too old", and worked around it with `--model gpt-5.5`. When Eugene later
asked me to upgrade codex, I upgraded 0.141.0 → 0.145.0 (npm latest; brew ships the same)
and the error persisted. The real cause was `http_headers = { version = "0.125.0" }` pinned
in `~/.codex/config.toml`'s custom `openai-long-timeout` provider — the server gates model
availability on that header, so the request always claimed to be version 0.125.0.
**Why this was wrong:** The error message named a remedy ("upgrade the CLI") and I adopted
its theory without checking what version the client actually *advertised*. Memory
[[disconfirm-before-declaring-root-cause]] says name the check that would prove the theory
innocent — here that check was one grep of config.toml, and it would have found the pin
immediately. I also had a hint I ignored: the upgrade changed nothing, which should have
invalidated the theory instantly rather than sending me to brew.
**What better looks like:** When a *server* error prescribes a client upgrade, verify what
the client is actually sending (headers/version) before upgrading anything. For codex
specifically: grep `~/.codex/config.toml` for a pinned `version` header first. Saved as
memory [[codex-version-header-pin]].

### 2026-07-29 — Blamed the UI for an ellipsis that was in the data (3 wasted build cycles)

**What happened:** Eugene asked to see the full session title on tap. The nav-bar title
showed `…`, so I assumed truncation was a rendering constraint and iterated: popover →
`lineLimit(nil)` → modifier reorder → custom overlay card. Each cycle was a build + install
+ screenshot (~3 min). The card — where I controlled every dimension — *still* showed `…`,
which finally forced the right question. `Session.title` is truncated server-side:
`TITLE_MAX = 72` in `src/sessions.ts:34` slices the first user prompt and appends a literal
"…". No UI change could ever have fixed it.
**Why this was wrong:** One `curl /api/sessions | len(title)` would have shown 72 chars and
a trailing "…" in under 10 seconds, before any code was written. Memory
[[ground-truth-before-hypothesizing]] says get the literal data first; I had the API one
command away and never looked. I also told Eugene a confident wrong cause twice ("the
toolbar caps popover height") — the line count changed between attempts only because I
changed the card width, which I misread as evidence for the cap theory.
**What better looks like:** When text renders truncated, **print the string's length and
repr from the source of truth before touching layout.** A trailing "…" that survives into a
container you fully control is proof the data is truncated, not the view. Generalize:
"the UI is wrong" claims need one data-side check first.
