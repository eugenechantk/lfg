# Diagnosis — Live Activity only updates when the app is opened

Session `284eede0`, 2026-08-06. Related earlier report: session `dd496c44`
(2026-08-05) — "the running counter keeps increasing, even when sessions are
done". Same defect, seen from the other side.

**Symptom:** the fleet Live Activity is stale while the app is backgrounded.
Opening the app snaps it to the truth.

## Ruled out (with evidence)

| Suspect | Evidence | Verdict |
| --- | --- | --- |
| Feature disabled | `.env` has `LFG_LIVE_ACTIVITIES=1` | ruled out |
| Server never computes updates | `~/.lfg/fleet-activity-state.json` rewrites with fresh `updatedAt`; it is only written *after* a push is accepted | ruled out |
| APNs rejects the pushes | direct probe: all registered `activityUpdate` tokens → **HTTP 200** | ruled out |
| Wrong APNs topic | `cfg.topic` = `com.eugenechan.lfg` = `PRODUCT_BUNDLE_IDENTIFIER`; `withTopic` appends `.push-type.liveactivity` | ruled out |
| Missing frequent-updates key | `project.yml` sets `NSSupportsLiveActivities` **and** `NSSupportsLiveActivitiesFrequentUpdates` | ruled out |
| Push delivery is broken | Eugene observed a background `needsInput` transition land on the Lock Screen at 20:58 | **ruled out — delivery works** |

## Root cause: the server pushes to a card it can no longer address, and 200 hides it

Two defects compound.

### 1. The server and the app disagree about who is working

`~/.lfg/live-activity-tokens.json` holds **8 distinct `activityUpdate` tokens**
for one device. Meanwhile `startedAt` in `fleet-activity-state.json` has been
pinned at `1786019471` (20:11 HKT) for the whole observation window — the server
has neither ended nor re-started the card. So every one of those extra tokens was
minted on the device without the server's knowledge (a new activity from
`FleetActivityController.sync()`'s `Activity.request`, or an ActivityKit token
rotation). Either way the server's addressable token went stale.

The card ends on the device when the **app's** count reaches zero
(`sync()` → `activeTotal == 0` → `endCurrentActivity`). The **server's** count
does not reach zero at the same time, because the watcher re-derives `busy`
itself instead of reading the journal signal the app renders from. Measured
drift, 2026-08-06 20:59:45–20:59:56:

```
api_busy=3 [019fd27f,17005940,284eede0]   card: w=4 rows=019fd27f,019fd561,17005940
```

`019fd561` (a **codex** session) is counted working by the watcher while the
journal says idle — the count is inflated by one, and it took ~60s to correct
(card became `w=3` with matching rows at 21:00:03). The watcher's chain is
`transcriptTurnState(rollout) || isBusy(pane) || codexDelegationSessionIds()`;
the journal's is a different chain entirely. **Two owners of `busy`, as
`.claude/CLAUDE.md` already warns about** — this is that hazard, realised.

Consequence: app hits 0 → app ends the card → app starts a fresh one with a fresh
token. Server never hit 0, so it never sends `end` or `start`, and never learns
the new token. Its updates now go to a dead activity.

### 2. APNs 200 makes the orphaning invisible

- **A dead Live Activity token is not `410`.** APNs accepts and drops it. So
  `isDeadApnsToken()` (`410` / `BadDeviceToken` / `Unregistered`) never fires and
  `removeLiveActivityToken` never prunes. Confirmed by probe: all 8 tokens → 200.
- **`sendLiveActivityToTokens` counts any 200 as success**, and
  `applyLiveActivityDecision` advances `active.current` on `sent > 0`. One stale
  token is enough to convince the server the update landed.
- Because `active.current` stays non-null, the server never re-sends `start`, so
  it can never recover the addressable card on its own.

Opening the app repairs both halves at once: `LiveActivityManager.track()`
registers the live token, and `FleetActivityController.sync()` updates the card
**locally** (no push involved). Hence "it only updates when I open the app".

## Fix plan

1. **One owner for `busy`.** The push watcher must consume the same
   journal-derived state the clients do, not re-derive it from panes/transcripts.
   This alone removes the app/server empty-fleet disagreement — and fixes the
   `dd496c44` "counter keeps increasing" report as a side effect.
2. **Stop trusting 200 as proof of delivery.** Keep at most one
   `activityUpdate` token per device/env — replace on registration rather than
   append — and drop tokens that predate the current activity.
3. **Let the client tell the server the card is gone.** When
   `FleetActivityController` ends or recreates the activity, notify the server so
   it clears `active.current` and re-`start`s addressably instead of pushing into
   a dead token.
4. Consider priority 5 for routine count changes, reserving priority 10 for
   `needsInput`, so the update budget is spent where it matters.

## Secondary findings (real, unrelated)

- A second `lfg serve` (pid 73041, port **8767**) spawned at 20:40 by a codex
  agent runs its own push watcher against the same `~/.lfg` token store — it is
  pushing real Live Activity updates to the real device with an independent
  in-memory `active.current`. Scratch servers must not run the push watcher.
- `[push] … 400 DeviceTokenNotForTopic` repeats forever for four *alert* device
  tokens (`80eb8b76`, `9dcbd193`, `800c0950`, `8036135c`) left over from the old
  `dev.omg.lfg` bundle id. They are never pruned because 400 is not in
  `isDeadApnsToken`.

## Evidence artifacts

- `scratchpad/probe-la.ts` — every LA token vs real APNs (all 200)
- `scratchpad/probe-observe.ts` — decomposes the watcher's busy chain per session
- `scratchpad/watch-drift.sh` → `drift.log` — journal busy vs card state, 5s
- `scratchpad/watch-lifecycle.sh` → `lifecycle.log` — card `startedAt` vs token count
