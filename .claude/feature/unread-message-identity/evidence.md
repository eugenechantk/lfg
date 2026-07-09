# Evidence — unread keyed on message identity, not mtime

**Change:** iOS read-state moves from `lastActivityAt` (transcript file mtime) to
`Session.last.id` (transcript line uuid).

## 1. The bug, reproduced against the live server

A `touch` is exactly what Syncthing does to these files: mtime moves, content doesn't.

```
transcript: ~/.claude/projects/-Users-eugenechan-dev-personal-lfg/7ad9e3b6-…jsonl
sha before: 3aa439730c19f406

=== BEFORE touch ===
  lastActivityAt = 1783588528810
  last.id        = 73283852-38cb-4778-bf90-668e65de0deb
  busy           = False

=== AFTER touch (content unchanged) ===
  lastActivityAt = 1783589433526.017      <- +904s  → old predicate: UNREAD
  last.id        = 73283852-38cb-4778-bf90-668e65de0deb   <- unchanged → new predicate: READ
  busy           = True                   <- 12s false "Working" flash

sha after:  3aa439730c19f406              <- byte-identical
```

`lastActivityAt` moved and `busy` flipped on a file whose bytes never changed.
`last.id` — the identity the new predicate keys on — did not move. That is the fix,
demonstrated on the real seam rather than a mock.

## 2. Root cause of the touches

`~/.claude` is a Syncthing folder (`.stfolder` present; `config.xml` lists it).
`.stignore` excludes only `/sessions`, so 347 transcripts / 794 MB sync between
machines. Snapshot → wait 180s → re-stat showed an idle transcript's mtime advance
by **exactly 3600.000 s**, preserving the `.481` ms fraction, with an unchanged
SHA-256: an mtime *rewrite* of `old + 1h`, not a write and not a `touch(now)`. Two
machines whose recorded mtimes differ by one hour ping-pong metadata forever.

## 3. Unit coverage

`swift test` (LFGCore): **82/82 pass**, including 14 in `ReadStateTests`:

- identity predicate: never-seen → unread; new id → unread; same id → read;
  no messages → never unread
- `testTouchedTranscriptWithNoNewMessageStaysRead` — the regression above
- `testIdentityIsImmuneToClockSkew` — no device-vs-host clock comparison
- migration predicate (message-ts based), 5 cases
- wire decoding: `last` decodes; absent `last` is nil; **malformed `last` does not
  fail the whole `Session` decode** (lenient-decoding convention)

Run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
(the machine's `xcode-select` points at CommandLineTools, which has no XCTest).

## 4. Migration

Old `lfg.lastOpenedAt` (epoch ms per session) is read once on first refresh and
converted into `lfg.lastSeenMessageID`. Read-ness is decided the way the old scheme
*meant* to — `Session.last.ts` (a message timestamp) vs the open time, **not** mtime
— so sessions that were genuinely unread stay unread, and sessions that only looked
unread because their file was touched become read. Guarded by
`lfg.readStateMigratedToMessageID`; never clobbers an existing seen-id.

## 5. Shipped

TestFlight build **202607091848** uploaded 2026-07-09 18:50 (secondary host:
Homebrew Ruby + `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

Archived from the **working tree**, at Eugene's explicit direction to "include
everything". So this build carries, in addition to the unread fix, ~1081 lines of
then-uncommitted multi-host / host-health work from a concurrent session
(`HostHealth.swift`, `MultiHost.swift`, `LFGClient`, `SettingsView`, `RootView`,
`SessionDetailView`, `SessionListView`, `LFGApp`, `PushManager`, `NewSessionView`,
and that session's half of `SessionStore.swift`).

Gate at time of upload: `swift test` 87/87 green, `flowdeck build` clean. The
multi-host work was **not** independently exercised by this session. The unread fix
shipped **without** live UI verification (see below) — unit-tested and reproduced
against the live server, but the real gesture was never driven.

## 6. Live UI verification

STATUS: **not done** — `flowdeck ui simulator session start` crashes
(`SimulatorControlCache.simulator(for:)` → uncaught NSException) because this machine's
`xcode-select` points at `/Library/Developer/CommandLineTools`. `DEVELOPER_DIR` does
not reach `idb` (see memory `flowdeck-ui-needs-real-xcode-select`). Needs:

```sh
sudo xcode-select -s /Applications/Xcode.app
```

App builds and launches fine on sim `ios-9d8366fa`
(`4A332768-4408-4680-9CE8-D10D854E4755`), host seeded to `http://127.0.0.1:8766`.

Planned tap-level check, per memory `verify-ui-by-tapping`:
1. Screenshot the list — a never-opened session sits under **Unread**.
2. Tap it, then back out — it moves to **Idle**.
3. `touch` its transcript, wait one 3s poll — it **stays** under Idle.
   (Before this change, step 3 moved it back to Unread.)
