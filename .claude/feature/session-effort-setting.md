# Feature: session-effort-setting

## User Story

As Eugene driving Claude Code and Codex sessions from the phone, I want to change a live
session's reasoning effort from its ⋯ (more options) menu, so I can turn thinking up for a
hard problem or down for a quick edit without opening the terminal — and without changing
the default every other session starts with.

## User Flow

1. Open a live Claude Code or Codex session.
2. Tap ⋯ → **Effort** (subtitle shows the current level, e.g. "High").
3. The submenu lists the levels the session's current model supports, with a checkmark on
   the current one (Claude: Low / Medium / High / Extra high / Max; Codex: whatever
   `model/list` reports for the model, e.g. … / Max / Ultra).
4. Tap a level. The menu title reads "Changing effort…" while it applies.
5. The session keeps its conversation and model; the next ⋯ shows the new level checked.
6. If the session is mid-turn, has queued sends, or has an open question, the change is
   refused with a banner explaining what to wait for.

## Success Criteria

- [x] SC1: `GET /api/sessions` rows carry `effort` for live Claude and Codex sessions,
  matching what the CLI is running. — **Verify by:** unit tests `claudeSessionEffort`
  precedence + `codexEffortFromPane`; live: compare API rows against pane footers (Codex)
  and transcripts / argv (Claude).
- [x] SC2: `GET /api/models` carries per-model effort levels for both agents (Claude from
  the model-catalog cache `thinking.effort_options`, Haiku = none; Codex from `model/list`
  `supportedReasoningEfforts`). — **Verify by:** unit tests on both parsers; live `curl
  /api/models?refresh=1`.
- [x] SC3: Changing a live Codex session's effort drives Codex's native picker and applies
  it **for this session only** (`s`), including Max/Ultra behind "More reasoning…";
  `~/.codex/config.toml` is untouched. — **Verify by:** unit tests on picker parsing with
  real captured panes; live against a scratch Codex pane (high → low → max → ultra),
  footer + config.toml hash before/after.
- [x] SC4: Changing a live Claude session's effort relaunches the pane with
  `--resume <id> --effort <level>`, keeping its current model; the row reports the new
  effort immediately; `~/.claude/settings.json` is untouched. — **Verify by:** unit test
  on relaunch argv; live against a scratch Claude pane: `ps` argv, API row, settings hash.
- [x] SC5: Guards — busy / queued / prompting → 409 with a readable reason; unknown or
  unsafe effort → 400; non-Claude/Codex or pane-less session → 409. — **Verify by:** unit
  test on the blocker + validator; live `curl` with a bad effort → 400.
- [x] SC6: A model switch on a Claude session launched with `--effort` keeps that effort.
  — **Verify by:** unit test on relaunch argv with carried effort.
- [x] SC7: iOS ⋯ menu shows **Effort** for live, directly-controlled Claude/Codex sessions
  whose model supports effort; levels come from the host catalog; checkmark on current;
  tapping applies it and the checkmark moves. Hidden for closed / external sessions and
  for models with no levels (Haiku). — **Verify by:** LFGCore unit tests
  (`efforts(for:model:)`, display names); simulator: open a live session → ⋯ → Effort →
  pick a level → screenshots before/after.

## Platform & Stack

- **Platform:** Bun server (`src/`) + iOS client (`ios/LFG`, `ios/LFGCore`)
- **Language:** TypeScript, Swift
- **Key frameworks:** bun:test, tmux; SwiftUI + UIKit `UIMenu`, Swift Testing / XCTest

## Steps to Verify

1. `bun test src/session-effort.test.ts src/model-catalog.test.ts src/codex-model-switch.test.ts`
2. `cd ios/LFGCore && swift test --filter Effort`
3. Live server: scratch tmux panes (Codex in `~/dev/inbox`, Claude in the scratchpad),
   drive the effort functions against them, then the HTTP route once deployed.
4. Simulator (FlowDeck, iPhone 17 Pro): ⋯ → Effort → choose → screenshot.

## Implementation Phases

### Phase 1: Server
- `src/session-effort.ts` (pure): effort vocabulary, validation, Claude precedence,
  Codex footer parse, picker-label mapping, switch blocker.
- `model-catalog.ts`: `efforts` per model for both agents.
- `sessions.ts`: `effort` on rows.
- `codex-model-switch.ts`: `switchCodexEffort` (native picker, session-only).
- `tmux.ts`: relaunch carries `--effort` (`claudeRelaunchArgv`); Ultra's `»` composer.
- `pane-drive.ts`: suppress scraped prompts on panes lfg is driving.
- `serve.ts`: `POST /api/sessions/:id/effort`; model route carries effort.
- Gate: bun tests green, live pane drives.

### Phase 2: iOS
- LFGCore: `Session.effort`, catalog `efforts`, `efforts(for:model:)`, `EffortLevel`
  display names, `LFGClient.setEffort`.
- `SessionStore.setEffort`, ⋯ menu submenu.
- Gate: swift tests green, simulator tap-through.

## Decision Log

- **Claude applies effort by relaunching, not by typing `/effort`.** Claude Code 2.1.280's
  `/effort <level>` saves the level "as your default for new sessions" (settings.json
  `effortLevel`, which Syncthing also pushes to the Air). The `--effort` launch flag is
  documented as "for the current session". Relaunch (`respawn-pane … --resume <id>
  --effort <level>`) is also exactly how model switching already works, so the idle-only
  guard and UX carry over. Cost: a few seconds of restart.
- **Codex applies effort through its native `/model` picker with `s` (session).** Probed
  live on codex-cli 0.156.0: the reasoning screen reads `enter default · s session · esc
  back`; `s` printed "Model changed to gpt-6-sol max for this session only" and left
  `config.toml` untouched. Max/Ultra sit behind "More reasoning…". Digit keys select
  immediately (= Enter = save default), so navigation is arrow keys only. If a Codex
  build lacks the `s` shortcut, refuse rather than silently change the global default.
- **Current Claude effort = transcript unless the process was launched after it.** Every
  assistant line carries `effort`, but a relaunch doesn't write one until the next turn.
  So: transcript value if its timestamp ≥ process start, else the `--effort` flag, else
  the (older) transcript value.
- **Relaunch pins the current model precisely.** Uses the same precedence to pick the live
  full model id (transcript vs `--model`), so an effort change never silently upgrades
  e.g. `claude-opus-5` to the `opus` alias.
- **Model switch carries effort only when the process was launched with `--effort`.**
  Carrying a transcript-derived value would pin an effort nobody chose (Claude's
  per-model defaults differ).
- **Effort is live-only on the client** — not persisted in GRDB. On cold launch the menu
  shows no checkmark until the first poll (~3 s). Avoids a schema migration.
- **No `ultracode`.** It is a Claude TUI mode, not a `--effort` value.
- **A Codex model switch resets effort to the new model's default** (Codex's own
  picker highlights the default level). Left as is: it is the CLI's semantics, and
  Codex's "More reasoning…" levels vary per model anyway.
- **Suppress pane-scraped prompts while lfg drives a pane** (`src/pane-drive.ts`).
  Found in verification: the journal emitted "Select Model and Effort" as a live
  question mid-drive and the push watcher runs the same scrape (a needs-input push
  whenever its tick lands in the 1–3.5 s drive). Enforced at all three consumers
  (journal pump, push watcher, status summary) with a 3 s grace for a capture read
  after the drive ends. Also fixes the same exposure in Codex model switching.
- **Codex Ultra's `»` composer is a composer** (`CODEX_PROMPT` in `tmux.ts`).
  Without it every Codex pane read (composer, busy chrome, background count) fails
  for an Ultra session, and the menu could put a session into Ultra and not back.
- **Claude effort chip `◈ max · /effort` is chrome** (`pane-history.ts`). Explicit
  efforts make Claude Code 2.1.280 draw it; the old `●`-only filter leaked it into
  question preambles (confirmed by running the new test against the old regex).
- **Claude relaunch replies once the new process owns the row** (`awaitRelaunched`).
  The client refreshes on the reply; before this it read the exiting process (or a
  row-less gap) and showed the old effort for ~15 s. Replies now take 2–10 s.
- **Claude model row uses the same launch-vs-transcript precedence.** The follow-up
  below reproduced live (switched to Opus, row still said Sonnet); one-line fix
  with the helper this feature added, so the row reports the relaunched model at once.
  (It does NOT fix the Switch-model checkmark for Claude — see Follow-ups.)

## Verification Evidence

Artifacts: `.claude/feature/session-effort-evidence/`. Scratch sessions only
(`probe-effort` Codex in `~/dev/inbox`, `probe-effort-claude`); two one-word turns
total. Config hashes checked before/after every live change.

| SC | Method | Result |
|----|--------|--------|
| SC1 | `bun test src/session-effort.test.ts` (precedence, footer); live `/api/sessions` vs every pane | 10/10 pass; all Codex rows match their footers; Claude Opus rows `xhigh` (settings `modelSettings`), probe `max` after relaunch — `sc1-rows-vs-panes.txt` |
| SC2 | `bun test src/model-catalog.test.ts`; `curl /api/models?refresh=1` | 4/4 pass; live: Haiku `[]`, Opus/Sonnet/Fable low…max, gpt-6-sol …ultra, gpt-6-luna …max, gpt-5.5 …xhigh |
| SC3 | picker tests from real panes; live `switchCodexEffort` matrix; HTTP route | 15/15 live cases right incl. Max/Ultra via submenu, leaving Ultra, Luna's one-row Max screen, Luna Ultra refused, draft refused; `~/.codex/config.toml` sha1 `70d3145f…` unchanged — `codex-live-matrix.txt`, `sc3-http-after-suppression.txt` |
| SC3 (side effect) | journal events during 5 HTTP drives vs a hand-opened picker | drives: 0 prompt events; manual `/model`: prompt + retraction — `journal-no-prompt.txt`, `journal-manual-picker-control.txt` |
| SC4 | `claudeRelaunchArgv` tests; live relaunch via function + HTTP | same session id, new pid, argv `--model claude-sonnet-5 --effort max`; HTTP low/medium/max/xhigh each read back correctly on the immediate GET; `~/.claude/settings.json` sha1 `1c256b4e…` unchanged — `claude-relaunch.txt`, `claude-relaunch-no-lag.txt` |
| SC5 | unit blocker/validator; live curl | bogus/ultra-for-Claude/missing/injection → 400; pane-less external Codex row → 409; unknown id → 404; busy/queued blocker unit-tested only — `sc5-http-guards.txt` |
| SC6 | argv test; live `POST /model {opus}` on a `--effort low` session | argv `--model opus --effort low` — `sc6-model-switch-carries-effort.txt` |
| SC7 | `swift test` (LFGCore 602 XCTest + 213 Swift Testing, 0 failures; 6 new effort cases); simulator iPhone 17 Pro tap-through | Codex probe: ⋯ shows "Effort · Medium", submenu Low…Max (no Ultra on Luna) with ✓ Medium → tap Max → pane footer `max`, reopened menu ✓ Max. Claude probe: ✓ Low → Extra high shows "Changing effort…", settles to "Effort, Extra high", argv `--effort xhigh` — `ios-01…05` |

| SC7 (independent) | `ios_visual_evidence_auditor` on sim 316F555D, current build + current server | **PASS** 5/5: Codex Max→Low recorded (`03-codex-effort-change-max-to-low.mov`), footer + API + config agree; Claude Extra high→Medium, argv `--effort medium`; Effort hidden on Haiku (catalog `[]`, not merely unknown); hidden on closed Codex and Claude sessions — `.codex/evidence/20260927-203112-ios-visual-audit/evidence.md` |

Server suite: 1052 tests; one pre-existing, load-sensitive flake
(`sessions-resumable-closed.test.ts` "fresh lease", real-data scan at the 5 s
timeout; passes/fails intermittently in isolation, touches no effort code).

## Bugs

Found and fixed during verification (none open):

1. Codex `s session` hint follows the highlighted row → checked too early when the
   current level sat under "More reasoning…". Fixed: highlight, then read the hint.
2. `parsePrompt` ignores one-row selectors → Luna's Advanced screen (Max only) was
   invisible. Fixed: dedicated `reasoningScreen` parser.
3. Ultra's `»` composer unrecognised → could not leave Ultra. Fixed in `CODEX_PROMPT`.
4. lfg's own picker drive journaled as a user question (and could push). Fixed:
   `pane-drive.ts` suppression.
5. Client showed the pre-change effort for ~15 s after a Claude change. Fixed:
   `awaitRelaunched`.

## Follow-ups (out of scope, found during audit)

- **Switch-model checkmark never shows for Claude sessions** (pre-existing): the row
  carries an alias (`opus`) and the menu compares it exactly against catalog ids
  (`claude-opus-5-5`, `SessionDetailView.swift` Switch-model `state:`). Fix: compare
  by family, as `ModelCatalogResponse.efforts(for:model:)` already does.
- A model switch to Haiku carries an explicit `--effort` onto a model with no effort
  control (the row then reports an effort; the menu correctly hides). Could drop the
  flag when the target model's catalog entry is `[]`.
- While a change is in flight the subtitle shows the old level for Codex but can show
  the new one for Claude (cosmetic).

## Residual risks

- Busy/queued/prompting refusals are unit-tested, not exercised live (would need a
  running turn). Also not exercised: Ultra from the phone (driven live at the API
  level only), hiding for externally owned sessions.
- iPad placement of the submenu not checked (UIMenu is system chrome, same as the
  existing Switch model submenu).
- The client keeps `effort` live-only; after a cold launch the menu has no subtitle
  or checkmark until the first poll.
