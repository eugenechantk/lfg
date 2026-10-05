# Feature: new-session-deep-link

## User Story

As Eugene, I want a deep link that opens lfg's New Session screen with my prompt (and optionally
the project) already filled in, so an Action-button Shortcut (dictate → on-device model decides
it's a task) can hand a spoken task to lfg and I only have to tap send.

## User Flow

1. Eugene presses the Action button; a Shortcut dictates on-device and decides it's a task.
2. The Shortcut opens `lfg://new?prompt=<percent-encoded>&dir=<project name or absolute path>`.
3. lfg launches (or comes forward) on the New Session screen: composer holds the prompt, the
   directory chip shows the resolved project (Inbox when `dir` is absent or unknown), keyboard up.
4. Eugene checks it and taps send — the normal create flow runs. Nothing starts without that tap.

## Link Contract

- `lfg://new` — open New Session (blank).
- `prompt=<text>` — prefill the composer. Blank → treated as absent.
- `dir=<hint>` — preselect a directory. Absolute path (`/…`) or `~/…` is used as-is; otherwise
  matched against the picker's list (Inbox, Root, host repos, directories with sessions) by name,
  ignoring case, spaces and punctuation (`"dictate keyboard"` → `dictate-keyboard`). Unknown → Inbox.
- `host=<hint>` — preselect the host. Matched against the configured hosts' display name, machine
  name, URL authority or URL, ignoring case/spaces/punctuation. Unknown or absent → the normal
  default (live default host, then marked default, then first).
- `agent=<claude|codex>` (alias `provider=`, also accepting `anthropic`/`openai`) — preselect the
  provider. Absent/unknown → normal default.
- `model=<hint>` — preselect the model from the chosen host's live catalog (loaded for the link),
  falling back to the bundled catalog. Match order: exact (case-insensitive), then
  punctuation-insensitive (`GPT 5.5` → `gpt-5.5`), then the first catalog model containing the hint
  (`opus` → `claude-opus-5-5`). Without `agent`, the model's own provider is used. A model that
  matches nothing is ignored (agent's default model if `agent` was given). A linked model counts as
  picked by hand, so the directory's inferred model does not override it.
- The link replaces the WHOLE draft: every absent/unknown field falls back to what a freshly opened
  New Session shows (blank prompt, Inbox, default host, remembered/inferred model).
- Unknown query items are ignored (lenient, like the rest of the client). Standard
  percent-encoding; `+` is a literal plus.
- Existing `lfg://session/<id>` is unchanged.

## Success Criteria

- [x] SC1: `lfg://new?prompt=…&dir=…` parses to a new-session link carrying the exact prompt
  (newlines, unicode, `&`, `=`, `+`, `#`) and dir; `lfg://new` alone parses with both nil; blank
  values become nil — **Verify by:** `LFGDeepLinkTests` (LFGCore, `swift test`)
- [x] SC2: `lfg://session/<id>` parses exactly as before (percent-decoded id, one path component,
  case-insensitive scheme/host) and malformed links (other hosts, extra path, empty id) are rejected
  — **Verify by:** `LFGDeepLinkTests`
- [x] SC3: Directory hints resolve: absolute and `~` paths pass through; `inbox`/`root` and repo
  names match case/punctuation-insensitively; the first listed entry wins a tie; unknown → nil —
  **Verify by:** `NewSessionDirectoryHintTests`
- [x] SC4: On the simulator, opening the link with the app running AND from cold launch shows the
  New Session screen with the exact prompt in `newSession.input` and the resolved directory on
  `newSession.chip.directory`; no session is created until send is tapped — **Verify by:** FlowDeck
  `open-url` + tree/screenshot (auditor)
- [x] SC5: Opening a second link while New Session is already showing replaces the prompt/dir, and
  opening "+" afterwards starts blank (the prefill is consumed once) — **Verify by:** simulator
- [x] SC6: `RootView`'s existing `lfg://session/<id>` handling still opens the session (now routed
  through `LFGDeepLink`) — **Verify by:** unit test + simulator open-url of a real session id

### Phase 2 — host / agent / model params (requested 2026-09-29)

- [x] SC7: `host`, `agent`/`provider`, `model` parse (first value wins, blanks → nil) and round-trip
  through `NewSessionLink.url` — **Verify by:** `LFGDeepLinkTests`
- [x] SC8: Host hints match display name / machine name / authority / URL loosely; unknown → nil —
  **Verify by:** `NewSessionLinkHintsTests.testHostHints…`
- [x] SC9: Agent/model hints resolve per the Link Contract against a catalog (exact, normalized,
  contains; model implies provider; unknown model with agent → agent default; nothing → nil) —
  **Verify by:** `NewSessionLinkHintsTests.testModel…`
- [x] SC10: On the simulator, a link with `host`, `agent`, `model` shows those on the host and model
  chips (warm and cold), and a later link WITHOUT them resets host and model to the defaults a fresh
  screen shows, including clearing a previously linked model — **Verify by:** open-url + chip labels
  (auditor)

## Platform & Stack

- **Platform:** iOS 18+ (lfg iOS client)
- **Language:** Swift 6 (strict concurrency)
- **Key frameworks:** SwiftUI, LFGCore (Swift package, Swift Testing / XCTest per existing suite)

## Design

- `LFGCore/DeepLink.swift` (new): `LFGDeepLink.parse(_:)` → `.session(id:)` | `.newSession(NewSessionLink)`,
  plus `NewSessionDirectoryHint.resolve(_:in:)` over `(name, path)` candidates. Pure, tested.
- `RootView.onOpenURL` switches on `LFGDeepLink`. For `.newSession` it stores a one-shot
  `NewSessionPrefill` (link + fresh id), sets autofocus and presents the cover — one main-actor hop
  later, per the cold-launch trap in `ios/CLAUDE.md`.
- `newSessionPresentation(...)` gains a `prefill` binding, handed to `NewSessionView`, which applies
  it after its create metadata loads (so repo names can resolve) and on change (link arrives while
  the screen is open), then clears it.

## Steps to Verify

1. `cd ios/LFGCore && swift test --filter "LFGDeepLinkTests|NewSessionDirectoryHintTests"`, then full `swift test`.
2. `flowdeck build` / `run` the LFG scheme on the session simulator.
3. `flowdeck ui simulator open-url "lfg://new?prompt=…&dir=lfg"` warm and cold; read tree + screenshot.

## Decision Log

- **Prefill, don't auto-send.** Any app (or a web page, after a prompt) can open a URL scheme. A
  link that starts a Claude/Codex session on the host with no confirmation is remote code
  execution for anyone who can get a link opened on the phone. The one tap also lets Eugene fix a
  mis-transcribed prompt or a wrong project guess from the on-device model. Token-gated auto-send
  can be added later if the tap proves annoying.
- **`dir` resolves against the picker's own list** instead of a new server lookup, so a spoken
  project name matches exactly what the directory sheet would show.
- **Unknown query items ignored**, matching the client's lenient-decoding convention and letting
  Shortcuts add params later without breaking older builds.

## Verification Evidence

Self-verification, 2026-09-29, sim `cc-0b4fd8c7` (iPhone 17 Pro, iOS 26.3), app launched with
`--launch-options='-lfg.baseURL http://127.0.0.1:8766'` (Eugene's live local host — send was never tapped).

| SC | Run | Observed |
|----|-----|----------|
| SC1–SC3 | `cd ios/LFGCore && swift test --filter "LFGDeepLinkTests\|NewSessionDirectoryHintTests"` | 12/12 pass |
| regressions | `cd ios/LFGCore && swift test` | 614 executed, 0 failures, 1 skipped (pre-existing) |
| SC4 warm | list showing → `open-url "lfg://new?prompt=Fix%20the%20login%20bug%20on%20iPad%0Aand%20add%20a%20test%20%26%201%2B1%3D2&dir=dictate%20keyboard"` | New session cover; composer `Fix the login bug on iPad⏎and add a test & 1+1=2`; directory chip `dictate-keyboard`; keyboard focused |
| SC4 cold | `flowdeck stop` → `open-url "lfg://new?prompt=Cold%20launch%20task%20for%20Noto&dir=Noto"` | App launches straight into New session, composer `Cold launch task for Noto`, chip `Noto` |
| SC4 from detail | session detail pushed → `open-url "lfg://new?prompt=From%20inside%20a%20session&dir=lfg"` | Cover presents over the detail with prompt + chip `lfg`; ✕ returns to the same detail intact |
| SC4 no auto-send | `curl 127.0.0.1:8766/api/sessions \| grep -c <test prompts>` | 0 — no session created by any link |
| SC5 | cover open (prompt 1) → `open-url "lfg://new?prompt=Second%20task%20replaces%20the%20first&dir=noto"`; then ✕ → "+" | Composer + chip replaced (`Second task…`, `Noto`); "+" afterwards opens blank on `Inbox` |
| SC6 | `open-url "lfg://session/0b4fd8c7-9756-4216-bb18-903ee9b87726"` | Opens that session's detail |

Independent audit #1 (ios_visual_evidence_auditor, `ios/.codex/evidence/20260929-161424-ios-visual-audit/evidence.md`):
**PARTIAL** — SC4/SC5/SC6 flows pass, but a link arriving while New Session is open kept the previous
link's directory when its own `dir` was missing/unknown, and a bare `lfg://new` kept the old draft
(screens `09-…`, `10-…`, `11-…`). See Bugs → B1.

Fix re-verification (self, after B1 fix, rebuilt app F244329A):

| Case | Observed |
|------|----------|
| link `dir=noto` → link `dir=nonexistent project` (screen open) | chip `Inbox`, prompt replaced |
| link `dir=noto` (chip `Noto`) → link with no `dir` | chip `Inbox` |
| link `dir=lfg` → bare `lfg://new` | composer blank ("Describe the task…"), chip `Inbox` |
| `swift test --filter NewSessionDirectoryHintTests` (+ new `testLinkedDirectoryFallsBackToInbox`) | 13/13 deep-link tests pass |
| full `swift test` | 615 executed, 0 failures, 1 skipped |

Independent audit #2 (after B1 fix): **PASS** — `ios/.codex/evidence/20260929-163511-ios-visual-audit/evidence.md`.
All SC4/SC5/SC6 flows re-run warm and cold, the three B1 cases now reset to Inbox / blank, plus a
hand-picked directory reset by a no-dir link. No sessions created (7 before/after, per-row JSON check).
Recordings: `rec-A-warm-chain-of-links-then-dismiss-plus.mov`, `rec-B-session-link-new-link-over-detail-dismiss.mov`,
`rec-C-cold-link-then-second-link-dismiss-plus.mov`.

### Phase 2 self-verification (host / agent / model), 2026-09-29

Sim launched with two hosts via `--launch-options="-lfg.hosts <hex JSON>"`: `Eugenes-MacBook-Pro`
(127.0.0.1:8766, live, default) and `Mac Studio` (127.0.0.1:9, deliberately unreachable → bundled
catalog). Chip labels read from the FlowDeck tree (`newSession.chip.*`).

| Case | Link params | Chips (dir / host / model) |
|------|-------------|----------------------------|
| warm | `dir=noto&host=mac studio&model=sonnet` | Noto / Mac Studio / sonnet (bundled catalog) |
| second link | `dir=lfg&host=macbook pro&model=GPT 5.5` | lfg / Eugenes-MacBook-Pro / `opus` → `gpt-5.5` ~3s later once the live catalog loaded |
| no host/model | prompt only | Inbox / Eugenes-MacBook-Pro / opus (linked gpt-5.5 cleared) |
| provider only | `host=Mac Studio&provider=openai` | Inbox / Mac Studio / gpt-5.6-sol (codex default, bundled) |
| no host after studio | prompt only | Inbox / Eugenes-MacBook-Pro / opus |
| cold, unreachable host | `dir=noto&host=mac studio&agent=claude&model=haiku` | Noto / Mac Studio / haiku |
| cold, live catalog | `host=Eugenes-MacBook-Pro&model=astra&dir=noto` | Noto / Eugenes-MacBook-Pro / gpt-6-astra |
| "+" afterwards | — | Inbox / Eugenes-MacBook-Pro / opus |
| unit | `swift test` (LFGCore) | 625 executed, 0 failures, 1 skipped; deep-link suites 23/23 |
| no auto-send | per-row JSON search of `/api/sessions` | 7 sessions, 0 matching any test prompt |

Independent audit #3 (phase 2): **PASS** — `ios/.codex/evidence/20260929-165635-ios-visual-audit/evidence.md`.
Each field alone and combined, warm and cold; provider-only; loose host/model names (`MACSTUDIO`,
`Eugene's MacBook Pro`, `127.0.0.1:9`, `Opus 5.5`, `HAIKU`); unknown values fall back; a later link
resets hand-picked host/model from the sheets; linked model beats directory inference; back-to-back
links keep the newer one; no regressions (prompt/dir, bare link, "+", `lfg://session/<id>`, link over a
detail). No sessions created (7 before/after, per-row check). Chip settle times in `timings.tsv`:
warm 0.6–1.1s; cold live-only model shows the fallback `opus` ~0.4s before `gpt-5.5` (~3s incl. launch).
Six recordings (`rec-W1…W4`, `rec-C1…C2`).

## Residual Risks

- A `dir` name only resolves against directories known when the screen applies the link. On a cold
  launch where the host is unreachable, repo names can't load and the chip stays on Inbox (the
  prompt still arrives). Paths always resolve.
- iPad layout of the cover is unchanged code, not re-checked for this feature.
- The "Directory" fallback (Inbox not yet known) is unit-tested only; whether the host expands `~/`
  paths needs a real send.
- Unrelated, pre-existing: audit #1 saw the directory picker sheet render washed out (light grey on
  near-white, `20260929-161424…/08-absolute-path-directory-sheet.png`). Not touched by this feature.
- Not yet verified on a physical phone from the Shortcuts app.
- A model name that only the host's live catalog knows (`gpt-5.5`, `astra`) shows the default model
  for the ~1–3s the catalog takes to load. Sending inside that window would start the default model.
  The chip is on screen, which is the point of the review tap.
- `host` only matches hosts already configured in the app; a link can't add one.
- Two configured hosts can share a label (e.g. a relay and the local URL both named
  `Eugenes-MacBook-Pro`); a name hint then picks the first, and the chip can't show which. Give hosts
  distinct display names, or pass the URL authority.
- Spoken number words don't match (`gpt six astra` → ignored); the Shortcut must send digits.
- Picking a model in the sheet updates the remembered model immediately (pre-existing), so that is
  what a link's reset falls back to.

## Bugs

### B1 — second link inherits the previous link's directory (found by audit #1) — FIXED

- **Symptom:** with New Session open, a link with no `dir` or an unknown `dir` replaced the prompt but
  left the prior link's project selected (e.g. `ios`); bare `lfg://new` left the whole old draft.
  One tap on send would start the dictated task in the wrong repo.
- **Cause:** `applyPrefill()` only changed the directory on a successful match and the draft only
  when a prompt was present — it treated the link as a patch, not as the draft.
- **Fix:** the link now replaces the whole draft: `draft = prompt ?? ""`, directory =
  `NewSessionDirectoryHint.directory(for:in:inbox:)` (match, else Inbox). Pure fallback covered by
  `testLinkedDirectoryFallsBackToInbox`.
