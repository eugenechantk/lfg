# Diagnosis — long-idle sessions keep reappearing as "Unread" in the iOS client

**Date:** 2026-07-09
**Symptom:** Sessions that were read, and have had no new conversation activity for
days, resurface in the iOS list's **Unread** group.

## Verdict

The unread predicate is correct. Its **input** is wrong.

`ReadState.isUnread(lastActivityAt:lastOpenedAt:)` asks "did this session produce
activity more recently than I last opened it?" — but the server defines
`lastActivityAt` as the **transcript file's mtime**, not the timestamp of the last
message:

```ts
// src/sessions.ts:1078 (claude), :1169 (codex), :1241 (aisdk)
lastActivityAt = statSync(transcriptPath).mtimeMs;
```

Anything that touches the file — with or without adding a single message — moves
`lastActivityAt` forward, past `lastOpenedAt`, and the session pops back into
Unread. Marking it read only buys time until the next touch.

## What is touching the files

**Syncthing.** `~/.claude` is a synced folder (`~/.claude/.stfolder` exists;
`config.xml` lists `path="/Users/eugenechan/.claude"`). Its `.stignore` excludes
only `/sessions`, so all **347 transcripts / 794 MB** under `~/.claude/projects`
sync between machines.

Measured directly — snapshot `(size, sha256, mtime)`, wait 180s, re-stat:

```
8e9f76da  mtime 1783583752.5 -> 1783587352.5  (+3600.0s)  PURE TOUCH (content identical)
359f53d0  mtime ...           (+204.8s)  APPEND +157549b     <- genuinely active
f688108c  mtime ...           (+268.9s)  APPEND +200985b     <- genuinely active
9d8366fa  mtime ...           (+96.9s)   APPEND  +55126b     <- genuinely active
```

`8e9f76da`'s last real message is **2026-07-07T10:34:23Z** — two days old. Its
mtime advanced by **exactly 3600.000 s**, preserving the `.481` millisecond
fraction, while the file's SHA-256 was unchanged. That is not a write and not a
`touch` (which would stamp *now*); it is an mtime **rewrite of old + 1 h**,
repeating hourly. Two machines whose recorded mtimes differ by exactly one hour
will ping-pong metadata forever.

The same skew is visible statically across every idle transcript — mtime sits ~1 h
from wall clock while the last real message is days old:

```
8e9f76da  mtime=2026-07-09T07:55:52Z  lastMsgTs=2026-07-07T10:34:23Z
7ad9e3b6  mtime=2026-07-09T08:15:28Z  lastMsgTs=2026-07-07T17:46:35Z
b3b0ebfd  mtime=2026-07-09T08:12:46Z  lastMsgTs=2026-07-07T14:19:23Z
406f5481  mtime=2026-07-09T08:44:39Z  lastMsgTs=2026-07-07T10:44:41Z
```

Secondary effect from the same line: `busy` is computed as
`Date.now() - lastActivityAt < 12_000` (`REST_BUSY_WINDOW_MS`), so for **12 s after
every touch** an idle session also reports `busy: true` and can flash **"Working"**.

## Why this is a server fix, not a client fix

The client is doing the right thing with the data it's given, and the touch is
external — pinning read-state to message identity in the app would paper over a
`lastActivityAt` that is also wrong for sorting, for `busy`, and for push.

`previewLast(transcriptPath)` is already called on the line immediately after the
`statSync`, already returns a `SessionMsg` carrying `ts`, and already skips the
metadata lines Claude Code appends (`mode`, `permission-mode`, `bridge-session`,
`ai-title`, `last-prompt`) plus anything flagged `isMeta`. The correct value is
sitting right there, for free.

```ts
const mtimeMs = statSync(transcriptPath).mtimeMs;   // keep: cheap liveness signal
last = await previewLast(transcriptPath).catch(() => null);
lastActivityAt = last?.ts ?? mtimeMs;               // conversation activity
```

Three call sites, identical shape: `src/sessions.ts:1073-1108` (claude),
`:1165-1192` (codex), `:1237-1270` (aisdk).

### Open fork — what should `busy` read?

| | `busy` from mtime (today) | `busy` from `last.ts` |
|---|---|---|
| Idle session, Syncthing touch | false "Working" for 12 s | correct |
| Mid-turn, streaming messages | correct | correct (lines land every few s) |
| Mid-turn, long tool call (60 s build) | correct only if something writes | goes false |

During a long tool call nothing appends to the transcript, so **mtime doesn't bump
either** — the two signals are equivalent mid-turn, and `last.ts` is strictly
better when idle. REST `busy` is only a fallback for sessions outside the 24-id SSE
window (`SessionStore.refresh`), which carry accurate pane-scraped busy.

**Recommendation:** move both onto `last.ts`, keep `mtimeMs` as the fallback when
the transcript has no parseable message.

## Also worth fixing (environment, not code)

Syncing 794 MB of append-only, constantly-churning transcripts across machines is
the source of the mtime ping-pong, and of the `sync-conflict-*` files already
littering the repo. Add to `~/.claude/.stignore`:

```
/sessions
/projects
```

This is orthogonal to the code fix — the code fix makes lfg correct *even under* a
touching filesystem, which is the property we actually want.

## Evidence commands

```sh
# server's view
curl -s localhost:8766/api/sessions | python3 -m json.tool | grep -E 'sessionId|lastActivityAt'

# mtime vs last real message, per transcript
#   -> idle transcripts show mtime days newer than lastMsgTs

# pure-touch proof: snapshot (size, sha256, mtime), sleep, re-stat
#   -> content identical, mtime +3600.000s
```
