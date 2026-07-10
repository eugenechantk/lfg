# Delegation Brief: phase2d1 — Live Activities server groundwork (APNs liveactivity)

**Goal:** everything the lfg server needs to drive iOS Live Activities — token registration
endpoints + storage, pure APNs `liveactivity` payload builders, and watcher hooks that
start/update/end one activity per running session — all DORMANT behind an env flag until the
client half (widget extension) lands.

**Repo:** you are in a git worktree of `lfg` (Bun + TypeScript; run everything with `bun`).
Do NOT touch `ios/`, `/api/events*`, `src/journal*`. The iOS client half does not exist yet —
nothing here can be verified against a real device; verification is unit tests + curl.

## Context (read first)

- `src/push/apns.ts` — JWT + `sendApns` + `apnsBody`. Note `ApnsConfig.topic` is the app bundle
  id used for the `apns-topic` header.
- `src/push/store.ts` — device-token persistence (follow its storage style exactly).
- `src/push/watcher.ts` — `runPushTick` + `TickDeps` injection pattern; `reduceTransition`
  computes busy/prompt transitions per session per tick.
- `src/commands/serve.ts` — find the existing `POST /api/push/register` handler for house style.

## Pinned protocol facts (do not re-derive; flag disagreement in your report instead)

- Live Activity pushes use headers: `apns-push-type: liveactivity`,
  `apns-topic: <bundleid>.push-type.liveactivity`, `apns-priority: 10`.
- Payload shape:
  `{"aps": {"timestamp": <unix seconds>, "event": "start"|"update"|"end",
    "content-state": {...}, ...}}` where:
  - `event: "start"` additionally requires `"attributes-type": "<SwiftAttributesTypeName>"`,
    `"attributes": {...}`, and an `"alert"` object; it targets the device's **push-to-start
    token**.
  - `update`/`end` target the **per-activity update token**; `end` may carry
    `"dismissal-date": <unix seconds>`.
- Two token kinds therefore exist: `pushToStart` (one per device) and `activityUpdate` (one per
  live activity instance, keyed by sessionId).

## Spec

1. **Token store** (`src/push/liveactivity-store.ts`): persist
   `{token, kind: "pushToStart"|"activityUpdate", sessionId?, env, updatedAt}` following
   `store.ts`'s conventions. Upsert by (token) — re-registration refreshes. Expose list/lookup/
   remove. Unit tests.
2. **Endpoints** (serve.ts, additive):
   - `POST /api/push/live-activity/start-token {token, env}` — register/refresh push-to-start.
   - `POST /api/push/live-activity/update-token {token, env, sessionId}` — register the update
     token the client receives when an activity starts.
3. **Payload builders** (`src/push/liveactivity.ts`, PURE, unit-tested):
   `buildStart(session, attributesType)`, `buildUpdate(contentState)`, `buildEnd(contentState?,
   dismissalDate?)` producing `{headers, body}` per the pinned shapes. Content state (must match
   the future Swift `ContentState` field-for-field — keep flat and lenient):
   `{title: string, state: "working"|"blocked"|"idle", sid: string, since: number}`.
   Attributes for start: `{sid: string, hostName: string}`; `attributes-type: "LFGSessionAttributes"`.
4. **Sender** (`src/push/liveactivity.ts`): thin wrapper over the existing HTTP/2 send machinery
   in `apns.ts` that applies the liveactivity headers/topic. Reuse the JWT + transport — extend
   `sendApns`'s signature or factor a shared low-level send; do NOT duplicate the JWT code.
5. **Watcher hooks** (`watcher.ts`): entirely behind `LFG_LIVE_ACTIVITIES=1` (absent → zero new
   behavior). Per tick, from the existing transitions: session becomes busy and no activity is
   tracked → send `start` to every push-to-start token; busy→prompt-blocked or content change →
   `update` via the session's update token (if registered); idle for ≥2 consecutive ticks →
   `end`. Track in-memory `active: Map<sessionId, {startedAt}>`. Keep the pure decision logic
   ("what to send given transitions + tracked state") in an exported, unit-tested function.

## Verification (run yourself; paste output)
1. `bun test` fully green (new tests for store, builders, decision logic).
2. If your sandbox permits binding: boot `LFG_DATA=/tmp/codex-p2d LFG_PORT=8797 bun run
   src/cli.ts serve`, curl both endpoints with sample bodies, confirm 200 + persistence, and
   confirm with the flag UNSET the watcher sends nothing. If binding is blocked (known sandbox
   limitation), say so — the delegator runs these.

## Definition of done
- [ ] Both endpoints registered + persisted per store conventions.
- [ ] Builders produce exactly the pinned header/body shapes (tests assert them literally).
- [ ] Watcher inert without `LFG_LIVE_ACTIVITIES=1`; decision logic unit-tested.
- [ ] No JWT/transport duplication; no changes outside `src/push/` + `src/commands/serve.ts`.

**Report back:** files changed, test summary, curl outputs (or the sandbox limitation), and any
place you had to deviate from the pinned shapes.
