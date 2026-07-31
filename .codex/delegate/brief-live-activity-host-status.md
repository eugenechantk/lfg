# Delegation Brief: Live Activity — host connection status + per-row host pills, drop timer

## Goal
Evolve the fleet Live Activity per new design direction:
1. **Remove the elapsed timer** from session rows entirely.
2. **Header line 2** = host connection status, mirroring the app's list subtitle wording.
3. **Each session row** shows a **host pill** matching the app's `SessionListView` chip
   (goes orange + ⚠︎ when that host is offline).
Idle behavior is unchanged (activity still ends when nothing is active — do NOT add a
resting card). Prior design context: `.claude/brainstorm/live-activity-redesign.md`.

## Context / files
- iOS widget: `ios/LFGWidgets/LFGSessionActivityWidget.swift` (current fleet widget).
- Shared attributes: `ios/Shared/LFGFleetAttributes.swift`.
- iOS manager (mock + tokens): `ios/LFG/LiveActivityManager.swift`.
- Server: `src/push/liveactivity.ts` (payload/content-state types + builders),
  `src/push/watcher.ts` (`reduceFleetLiveActivity`, `orderFleetRows`), tests
  `src/push/liveactivity.test.ts` + `watcher.test.ts`.
- **Match the app's host chip exactly** — see `ios/LFG/SessionListView.swift` around
  lines 532–554 (the `hostLabel` capsule) and the connection subtitle
  `statusSubtitle` around lines 457–471. Reproduce that styling/wording in the widget.

Conventions: Bun/TS server (`bun test`), LFGCore swift tests, lenient Codable decoding
(every field optional-with-default + custom `init(from:)`), Swift 6 Sendable. Don't
reformat unrelated code. Do NOT build the iOS app or run a simulator — Claude builds via
FlowDeck and does the visual verification + host-pill tuning.

## Data model change (Swift ⇄ TS must match)
Add host connection status to the content-state. In `LFGFleetAttributes.ContentState`
(Swift) and `LiveActivityContentState` (TS) add:
```
hosts: [HostStatus]          // connection status per host, e.g. [{name:"pro", online:true}, {name:"air", online:false}]
```
```
HostStatus: { name: String, online: Bool }   // lenient: name default "", online default true
```
Rows already carry `host: String`. Keep the existing `working`/`needsInput`/`rows`
counts. You MAY drop `updatedAt` if now unused (the header no longer shows "updated"),
or leave it — your call, but remove any now-dead references.

## Widget UI (`LFGSessionActivityWidget.swift`)
- **Remove** `ElapsedTimeText` usage from rows (and the struct if now unused).
- **Header line 1** unchanged: `{working+needsInput} agents · {needsInput} need you`
  (amber accent when needsInput>0 else blue) with the app-icon `LFGMark`.
- **Header line 2** = connection status string built like the app's `statusSubtitle`:
  - multi-host: online hosts `", "`-joined + `" online"`, then offline hosts + `" offline"`,
    joined with `" · "` → e.g. `pro online · air offline` or `pro, air online`.
  - single host: `Connected` (online) / `Offline`.
  Derive purely from `ContentState.hosts`. Color offline host names orange if easy;
  otherwise plain secondary text is fine (the row pills carry the strong offline signal).
- **Session rows**: leading state dot + title + **host pill**, NO timer. The host pill
  mirrors the app chip: `Text(host)` in a `Capsule`, `.font(.caption2)`,
  `.padding(.horizontal,5).padding(.vertical,1)`; background `Color(.tertiarySystemFill)`
  normally, `Color.orange.opacity(0.15)` when that host is offline; foreground
  `.secondary` normally, `.orange` when offline; when offline prepend an
  `Image(systemName:"exclamationmark.triangle.fill")` (~8pt). Determine offline by
  looking up the row's `host` in `ContentState.hosts` (missing/`online:false` → offline).
  The row's trailing "needs input" amber pill (blocked state) stays as-is; a working row
  now shows just the host pill (no timer).
- **Overflow** "+N more" and the 2-row lock-screen cap stay as-is.
- **Dynamic Island** expanded rows: same treatment (host pill, no timer). Keep the
  compact/minimal dot + count as-is.
- Keep the lock-screen padding as currently set (16–20pt) — don't tighten it.

## Server (`liveactivity.ts` + `watcher.ts`)
- Add `hosts` to the content-state type + `buildStart`/`buildUpdate` passthrough, and to
  `sameFleetContentState` equality (so a host going offline/online triggers an update).
- In `reduceFleetLiveActivity`: populate `hosts`. For v1 the pushing server knows its own
  host is online — set `hosts` to `[{ name: hostName, online: true }]` (a single entry for
  the pushing host). Leave a `// TODO` noting the phone app / multi-host will enrich this.
  Order rows / counts logic unchanged.
- Update `orderFleetRows`/reducer tests + `liveactivity.test.ts` for the new field
  (start/update fire correctly; host status carried; equality accounts for `hosts`).

## iOS mock (`LiveActivityManager.swift`)
Extend BOTH mock variants so I can visually verify online + offline:
- `LFG_LA_MOCK=1` (needs-input): `hosts: [{pro, online:true},{air, online:true}]`.
- `LFG_LA_MOCK=working`: make ONE host offline, e.g. `[{pro, online:true},{air, online:false}]`,
  and ensure a row's host is "air" so its pill renders offline (orange + ⚠︎).
Keep the DEBUG guard and the existing token-registration code intact.

## Verification (you run; report exact output)
1. `cd /Users/eugenechan/dev/personal/lfg && bun test src/push/` — all green.
2. `cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test` — all green.
   (If SwiftPM sandbox blocks caches, use the `--disable-sandbox` +
   `CLANG_MODULE_CACHE_PATH` workaround; note it if so.)
Do not build the app target.

## Definition of done
- [ ] `hosts` added to content-state (Swift + TS), lenient/Sendable, equality updated.
- [ ] Timer removed from rows; header line 2 shows app-style connection status.
- [ ] Row host pill matches the app chip incl. offline orange + ⚠︎.
- [ ] Server populates `hosts` (own host online, TODO noted); reducer/tests updated.
- [ ] Both mock variants populate `hosts` (one offline in the `working` variant).
- [ ] `bun test src/push/` + LFGCore `swift test` both green.

## Report back
Files changed, exact test output, and any interface you shaped differently from this brief.
