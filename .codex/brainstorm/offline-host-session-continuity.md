# Offline-host session continuity

Status: product/architecture exploration

## Recommendation

Ship this as **Continue on another host**, not “move a running process.” LFG
should show the offline host's last-known sessions, serve their replicated
transcripts through an online peer, and reconstruct a selected session on an
online host only after the existing cross-host lease permits takeover.

Most of the foundation already exists. The smallest useful release is an iOS
transfer-path change plus focused tests; it does not require a new server
endpoint. A later mirrored-session endpoint is only needed if the list must be
complete on a device that never saw the source host while it was online.

## What works today

The current implementation is much closer than the older brainstorms imply:

- The client persists each host's last successful live-session snapshot in its
  local store. When a host goes offline, those rows stay in the unified list and
  retain their owner.
- Offline rows are dimmed and their host chip turns orange. Stale `busy` and
  prompt claims are retracted, so an offline host no longer leaves sessions
  falsely marked Working.
- Transcript reads already use `MultiHost.readRouteHost`: when the owner is
  down, `ensureHistory` and paged reads use a reachable peer. This works because
  Claude and Codex transcripts are replicated between hosts.
- Every locally enumerated live session is now covered by `ensureLease`, not
  just sessions created by LFG. The resume endpoint rejects a fresh foreign
  lease with HTTP 409, which is the split-brain guard needed for takeover.
- A general Move to host action already exists for live sessions.

The remaining blocking bug is narrow: `SessionStore.transfer` always closes the
source first and aborts if that request fails. Therefore Move is guaranteed to
fail when the source host is offline—the exact case this feature needs to
support. The menu also offers offline destinations instead of limiting the
choice to hosts that can accept the session.

## Product contract

“Offline” means **unreachable from this phone**, not “proven powered off.” The
feature can promise:

- the latest transcript that has replicated to an online host;
- clear attribution to the last-known owner;
- a safe attempt to continue on an online host;
- refusal when another host still holds a fresh lease.

It cannot promise:

- preservation of a process's in-memory state;
- recovery of output that never reached the transcript or never replicated;
- proof that the source is dead when both direct connectivity and replication
  are unavailable.

This is why “Continue on Pro” is more accurate than “Move to Pro” for an offline
source. A normal online-to-online transfer can retain the Move wording because
it performs a clean source close first.

## Recommended experience

### Session list

Keep the existing last-known rows. They already answer the primary discovery
job without introducing a second session type.

- Preserve the orange offline host chip and dimmed row.
- Do not put an offline session in Working or Needs you; those are live claims
  the client can no longer verify.
- **Primary action:** swiping an offline session row to the left reveals a blue
  `Continue on Pro` trailing action alongside the existing directory-hide
  actions. Do not require opening the session first.
- With exactly one reachable destination, the swipe action names and targets it
  directly. With multiple reachable destinations, label it `Continue…` and open
  a host picker; never choose a destination silently.
- Disable full-swipe execution. Continuing reconstructs a live process and can
  be lease-blocked, so it should require an intentional button tap.
- Host grouping remains the clearest way to inspect everything last seen on one
  machine. A new global Offline section is not necessary for v1.

### Session detail

When the owning host is offline:

- Show a compact notice: `Air is offline. Showing the latest copy available on
  Pro.`
- Keep the composer disabled until takeover succeeds.
- Retain `Continue on Pro` in the detail menu as a secondary path, with one
  action per reachable peer.
- On success, navigate to the reconstructed live session and update its owner.
- If the target returns a fresh-lease conflict, say: `Air still appears to be
  running this session. Try again after it reconnects or stops.`
- If the transcript has not replicated, say: `This session is not available on
  Pro yet.`

No force-takeover button in v1. It would turn an ambiguous network failure into
silent split brain, which is worse than asking the user to wait or recover the
source host.

## Transfer algorithm

```text
continue(session, target):
  require target is reachable
  require target is not current owner

  if source is confirmed online:
    close session on source
    wait until source no longer reports it live
    resume transcript on target
  else if source is confirmed offline:
    skip source close and source polling
    ask target to resume the replicated transcript
  else:
    stop; source state is still reconnecting or unknown

  if target reports a fresh foreign lease:
    stop; source may still be running it
  if target cannot resolve the transcript:
    stop; replication has not delivered it
  if original working directory is unavailable on target:
    stop; never resume silently in a fallback directory

  remap the session id if the agent minted a new one
  set target as owner
  refresh and select the continued session
```

The target server remains the authority on takeover readiness. The client
should not implement its own 90-second timer. It may enter the takeover branch
only for the store's known-down state (`isOffline`), never merely because the
host is not currently `isLive`; connecting, degraded, and unknown states are
still ambiguous. Only the target can inspect the lease and transcript it will
actually use.

## Safety invariants

1. **One live writer per conversation.** A fresh foreign lease always blocks
   resume on the target.
2. **Reads and writes route differently.** Reads may use any online replica;
   sends remain pinned to the live owner until takeover succeeds.
3. **The destination must be online.** Do not present unreachable hosts as
   transfer targets.
4. **The original cwd must exist.** The current server falls back to the LFG repo
   when it cannot derive a transcript cwd. Takeover must fail loudly instead;
   reconstructing the right conversation in the wrong repo is unsafe.
5. **Staleness is visible.** The transcript shown while offline is a replicated
   snapshot, not a live stream from the owner.
6. **No forced bypass in v1.** A coordinator-less, sync-backed lease narrows the
   race substantially but cannot prove death during a replication outage.

## Completeness gap

The v1 list is complete only for sessions the phone previously learned from the
source host, plus conversations that later surface as resumable through an
online peer. Two cases lose attribution:

- the phone never fetched the source host's live session before it went down;
- the app's local store was cleared or this is a fresh installation.

After the foreign lease becomes stale, an online host can eventually return the
transcript as closed/resumable, but the row no longer says which host last ran
it. While the lease is still fresh, the resumable endpoint correctly hides it,
so it may be absent from a fresh client's list altogether.

If this matters in practice, add phase 2:

`GET /api/sessions/mirrored` on every online host returns replicated transcripts
with foreign lease metadata:

```text
sessionId
agent
title / cwd / project / lastUserText
ownerHostId
leaseHeartbeatAt
leaseState: fresh | stale
transcriptUpdatedAt
```

The client merges these with its last-good snapshots by session ID. Mirrored
rows remain attributed to the owner and read-only until the lease permits
takeover. Keep this separate from `/api/sessions/resumable`: “visible through a
replica” and “safe to resume here” are different facts.

## Options considered

| Option | Result | Recommendation |
| --- | --- | --- |
| Keep requiring source close | Strongest safety, but feature never works when source is offline | Reject |
| Lease-gated continuation from an online replica | Small change, uses current architecture, blocks an apparently live source | **Ship first** |
| Add mirrored-session inventory immediately | Complete cross-host visibility and attribution, but adds server/client state before usage proves it necessary | Phase 2 |
| Central coordinator or cloud lock | Stronger ownership guarantees during sync failure | Overkill for the current personal two-host fleet |
| Proxy the offline host through an online host | Cannot work; the source is not answering | Reject |

## Implementation scope

### Phase 1 — useful continuation

- `SessionStore.transfer`: branch on confirmed source state. Keep the current
  clean close/wait/resume path for an online source; skip source operations only
  for a known-offline source and call target resume directly; refuse while the
  source is merely reconnecting/unknown.
- `SessionDetailView`: filter targets to reachable peers and use Continue wording
  for an offline owner.
- `SessionListView`: add the trailing swipe action to offline rows. Reuse the
  same continuation method as the detail menu; one reachable target executes
  directly, while multiple targets present a picker. Set `allowsFullSwipe` to
  `false`.
- `LFGClient`/error handling: recognize the resume 409 well enough to show the
  lease-conflict message rather than raw JSON.
- Server resume path: reject a missing/unavailable cwd for takeover rather than
  falling back to `SELF_REPO`. This can be a takeover-only request flag if the
  legacy fallback must remain for ordinary resume.
- Tests: extract the transfer decision into a pure policy in `LFGCore`, then test
  online source, offline source, offline target, fresh-lease conflict, transcript
  missing, cwd missing, Claude ID remap, and Codex ID stability.

### Phase 2 — complete mirrored inventory

- Add the mirrored endpoint and lease/transcript enrichment.
- Merge mirror rows into the client without treating them as closed.
- Show last-owner and last-replicated timestamps.
- Add cold-launch/fresh-install coverage where the source is offline from the
  beginning.

## Acceptance scenarios

1. Air offline, Pro online, cached Air session: row remains visible; opening it
   loads transcript pages from Pro.
2. Air offline, Pro online: swiping the Air row left exposes Continue on Pro
   without opening the session.
3. Air offline with stale lease: Continue on Pro succeeds, owner changes to Pro,
   and the new/live ID is selected.
4. Air unreachable from phone but still alive and heartbeating: Pro returns 409;
   no second process starts.
5. Air and Pro both online: Move performs the existing clean close then resume.
6. Destination offline: it is absent or disabled in the swipe action and target
   menu.
7. Transcript not yet replicated: continuation fails clearly and the source row
   remains intact.
8. Working directory missing on Pro: continuation refuses to start in another
   directory.
9. Cold app launch with Air offline: its persisted sessions and recent messages
   are visible; live claims are shown as unavailable, not Working.
10. Multiple online targets: the swipe action opens a picker instead of choosing
    a host implicitly.
11. Phase 2 only: a fresh install can discover an Air-owned mirrored session via
   Pro even though it never received an Air snapshot.

## Decision

Implement Phase 1 first. It closes the real usability gap with the machinery
already in the tree. Treat Phase 2 as evidence-driven: build it only if fresh
install/cache-loss completeness or owner attribution for never-seen sessions is
actually needed.
