# Feature: model-catalog-sync

## User Story

As Eugene, I want the iOS app's model list to be the list my computer has,
and to stay that way as Claude Code and codex update, so that the app never
offers or falls back to models the computer moved past (gpt-5.6-sol when the
computer runs gpt-6.1-sol).

## Background (state before this change)

- The host already serves its live list at `GET /api/models` (discovered from
  the installed claude/codex CLIs, 15 s server cache).
- The app fetched it only when a picker or a session opened, and kept it in
  memory (`SessionStore.modelCatalogByHost`). Every cold launch started from the
  list compiled into the app, which stops at gpt-5.6.
- When the server's discovery failed (codex app-server timeout), the server
  answered with ITS compiled list, so a client could receive a stale list even
  from a current host.

## User Flow

1. Eugene opens the app (cold launch or back from background).
2. Without opening any picker, the app asks each configured computer for its
   model list and saves it on the phone.
3. Any model picker, default or fallback reads that saved list. After a
   relaunch it is there at once, even before the computer answers.
4. Claude Code or codex updates on the computer. The next launch/foreground or
   picker open brings the new list to the phone.

## Success Criteria

- [x] SC1: The app saves each host's catalog on the phone and restores it at
  launch. — **Verify by:** LFGCore unit tests for the cache (round-trip,
  per-host, corrupt data ignored, removed hosts pruned); live: the sim's
  preferences plist holds the Pro's catalog (incl. gpt-6.1-sol) after launch.
- [x] SC2: The app refreshes every configured host's catalog on launch and on
  foreground, without a picker being opened. — **Verify by:** live in the
  simulator: fresh launch, no picker opened → plist holds the catalog;
  background + foreground → the entry's `fetchedAt` advances.
- [x] SC3: The server answers with the last successfully discovered list for an
  agent when discovery fails, not its compiled list. — **Verify by:** bun unit
  tests for the resolver; integration probe: `currentModelCatalog()` in a bun
  script with `LFG_CODEX_BIN=/usr/bin/false` and a seeded last-good file →
  codex list equals the seeded list.
- [x] SC4: Agent defaults come from the host's catalog, not the compiled list:
  a codex directory whose newest session has no readable model opens on the
  host's default (gpt-6.1-sol), not gpt-5.6-sol. — **Verify by:** LFGCore unit
  test on `AgentModelSelection.inferred(..., catalog:)`.
- [x] SC5: No regressions. — **Verify by:** `swift test` (LFGCore), `bun test
  src/model-catalog.test.ts`, FlowDeck build, the new-session picker shows the
  host's list live.

## Platform & Stack

- **Platform:** iOS client (SwiftUI) + Bun server
- **Language:** Swift 6, TypeScript
- **Key frameworks:** SwiftUI, Observation, UserDefaults; Bun

## Steps to Verify

1. `cd ios/LFGCore && swift test`
2. `bun test src/model-catalog.test.ts`
3. `flowdeck run -S <session sim>`; read the app's preferences plist in the sim
   data container for the catalog key.
4. Background/foreground via FlowDeck (`button home`, relaunch) → `fetchedAt` advances.
5. Bun probe for SC3 (temp `LFG_DATA`, failing codex bin).

## Implementation Phases

### Phase 1: Server keeps last-good discovery
- Scope: `src/model-catalog.ts` — pure resolver + `~/.lfg/model-catalog.json`.
- SC: SC3.
- Gate: bun tests + probe.

### Phase 2: iOS persists and refreshes
- Scope: `LFGCore` cache type + tests; `SessionStore` load/save/refresh;
  Siri intent fallback; `inferred` takes the host catalog for agent defaults.
- SC: SC1, SC2, SC4.
- Gate: swift test, build, live plist checks.

## Decision Log

- **Runtime sync, not a build-time script.** A script that rewrites the compiled
  list at deploy time still goes stale between deploys and needs a deploy for
  every CLI update. Saving the host's own answer on the phone keeps the list as
  fresh as the last contact with no deploys.
- **Refresh on launch + foreground only** (plus the existing picker/detail
  opens). No periodic timer: a CLI update matters only when Eugene next picks a
  model, and every picker already refreshes on open.
- **The compiled lists are NOT rewritten** (changed from the first plan). They
  are compatibility floors for hosts that predate `GET /api/models`, whose
  servers allowlisted exactly gpt-5.6-* and the Claude aliases. With the host's
  list saved on the phone, the compiled list is only seen before the app's first
  contact with a host, so rewriting it buys nothing and breaks the old-host case.
  What did matter: places that read the compiled list's *default* even when a
  host catalog was available (`inferred` tier 2). Those now take the catalog.
- **Server persistence is the single choke point** for "never regress to the
  compiled list": every client (iOS, intents, MCP) gets it for free.
- **Restore is logged to the connection log** ("restored saved model catalogs: …").
  It is once per launch, and it is the only way to prove the restore happened:
  the launch refresh overwrites the entry within a second.
- The server restart needed to deploy Phase 1 is NOT done in this task:
  restarts drop in-memory session tracking. Phase 1 takes effect on the next
  restart.

## Verification Evidence

Self-verification, 2026-10-08 (independent audit result appended below when it lands).

| SC | Action | Observed | Artifact |
| --- | --- | --- | --- |
| SC1 save | `flowdeck run` on sim cc-37ccd237, no picker opened, read prefs plist key `lfg.modelCatalogCache.v1` | `https://lfg-pro.eugenechantk.me fetchedAt 10:45:53 · codex gpt-6.1-sol [gpt-6.1-sol, gpt-6-astra, gpt-6-sol, gpt-6-luna, gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna] · claude [claude-opus-5-5, claude-fable-5-1, claude-sonnet-5-5, claude-haiku-5-5]` | plist probe output (scratch `catalog_plist.py`) |
| SC1 restore | Reinstall + relaunch; read `Diagnostics/connection-log.txt` | `18:51:56.156 APP restored saved model catalogs: https://lfg-pro.eugenechantk.me` — written in `SessionStore.init`, before any network | connection log in sim container |
| SC1 unit | `swift test --filter ModelCatalogCacheTests` | 4/4 pass (round-trip, replace, corrupt → empty, prune) | — |
| SC2 launch | as SC1 save: entry written on the session list with no picker opened | fetchedAt 10:45:53 | — |
| SC2 foreground | `button home`, tap the lfg icon, re-read plist | fetchedAt 10:45:53 → 10:46:29 (foregrounded 10:46:28) | `.claude/evidence/model-sync-after-foreground.png` |
| SC3 unit | `bun test src/model-catalog.test.ts` | 9/9 pass (5 new) | — |
| SC3 probe | `currentModelCatalog(true)`, `LFG_CODEX_BIN=/usr/bin/false`, temp `LFG_DATA` seeded with a gpt-6.1 list | codex `[gpt-6.1-sol, gpt-6-astra, gpt-5.6-sol]`, default gpt-6.1-sol. Same probe, no seed: `[gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna]` (the old behaviour). Real codex, empty dir: file written with the 7-model list | probe output |
| SC4 | `swift test --filter NewSessionModelDefaultsTests` | new `testAgentOnlyDirectoryUsesTheHostsDefault` and `testUnsafeModelDegradesToTheHostsDefault` pass (gpt-6.1-sol) | — |
| SC5 | full `swift test`; FlowDeck build; New Session → model chip | 637 tests, 0 failures; BUILD succeeded; picker lists the host's 4 Claude + 7 codex models | `.claude/evidence/model-sync-picker.png` |

**Independent audit (ios_visual_evidence_auditor): PASS on SC1–SC5.** Report:
`.claude/evidence/model-catalog-sync-audit/evidence.md`. It also reported the
refresh-waits-for-every-host flaw below, and noted that only the Pro could be
proven (the Air answered HTTP 530 throughout).

**Re-verification after the fix (per-host refresh), 2026-10-08:**
- `swift test`: 637 XCTest, 0 failures. `bun test src/model-catalog.test.ts`: 9/9.
- FlowDeck build succeeded. Relaunch → connection log `19:03:21.218 APP restored
  saved model catalogs: https://lfg-pro.eugenechantk.me`; plist fetchedAt
  10:59:50 → 11:03:22 on launch.
- Home, then the lfg icon → `19:03:46.270 APP foreground after 6s backgrounded`;
  fetchedAt 11:03:22 → 11:03:46. (The plist on disk lags the write by a few
  seconds; the first read 6 s after the tap still showed the old time.)

Not deployed: the server change needs an lfg restart; the app change needs a TestFlight build.

## Bugs

- **Fixed — refresh held every host's result until the slowest host answered.**
  The first version gathered all hosts in one task group and saved after the
  group finished, and one in-flight refresh absorbed the next. A hanging host
  (up to the 15 s timeout) delayed the Pro's save and could swallow a foreground
  refresh. Now one task per host, saved as each lands, de-duplicated per host
  (`modelCatalogRefreshing`). Found in self-review and by the auditor.
