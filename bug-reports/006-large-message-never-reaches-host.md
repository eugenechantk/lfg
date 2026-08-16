# Bug 006: Large iOS message never reaches an LFG host

## Status: INVESTIGATING

## Description

A roughly 1,000-line message submitted from LFG iOS appears never to run. LFG
has previously delivered a 213,910-byte multiline payload end to end, so this
incident must distinguish an app/outbox failure from an HTTP upload failure,
host routing, and agent-composer delivery.

The supplied connection timeline shows both configured hosts repeatedly
stalling or timing out during the incident window. The phone moved between Wi-Fi
and cellular, briefly reported no internet, and the primary host alternated
between live and unreachable. No send/outbox events are present in the exported
connection timeline.

## Steps to Reproduce

1. Launch LFG iOS 1.2.0 (202608152131) with both configured hosts enabled.
2. Open a closed/resumable Claude session.
3. Paste roughly 1,000 lines into the composer.
4. Tap Send while a host is reachable.
5. Observe that the message never becomes an agent user turn.

## Root Cause

The affected session (`bc4a7d48-ac5d-4524-9bf4-83a8d467aaef`) is a closed
Claude transcript. Sending to a closed session does not use LFG's confirmed
paste queue. The server calls `resumeClosedSession(prompt: text)`, and
`spawnManagedSession` places the entire message in the argv for:

`tmux new-session … claude --resume <id> … -- <message>`

tmux rejects a roughly 100 KB / 1,001-line reproduction with `command too
long`. Because resume fails before `recordImmediateMessage`, no server queue row
is created. Live-session messages avoid this failure because they are inserted
through `tmux load-buffer` / bracketed paste.

## Success Criteria

_TBD — defined after root cause is understood. Each criterion will include a
unit test and simulator verification steps._

## Investigation Log

### Attempt 1

**Hypothesis:** The payload was not rejected for length; it either never entered
the durable iOS outbox or its background upload could not complete during the
observed host/network instability.

**Changes:** None.

**Result:** Historical verification proves a 213,910-byte message delivered
exactly once. The supplied phone log shows repeated `timedOut`,
`networkConnectionLost`, `cannotConnectToHost`, and one
`notConnectedToInternet` interval, but it contains no send/outbox lifecycle
events from which to establish whether the large payload was persisted or
posted.

### Attempt 2

**Hypothesis:** Line count is not causal; the original message targeted a
session whose owning host was unreachable.

**Changes:** None.

**Result:** The user's follow-up carrying the connection log itself traversed
the same LFG iOS send path as a 60,526-byte, 732-line message. The MacBook Pro
server enqueued it 112 ms after receipt and marked it delivered after 1,283 ms
in one attempt. The Pro's queue contains no earlier large message from the
incident window. Tailscale identifies `100.120.101.14` as the MacBook Pro and
`100.75.162.40` as the MacBook Air; the Air's last-seen time was 11:10 HKT and
it remains offline. The original target session is required to determine
whether its durable phone outbox is waiting for the Air or whether a Pro-bound
row failed to replay.

### Interim diagnosis after Attempt 2

- Not a 1,000-line or HTTP body-size limit.
- Confirmed severe phone-to-host path instability during the reported window.
- Confirmed MacBook Air outage beginning around 11:10 HKT.
- Original payload did not reach the MacBook Pro send queue.
- The exported connection log lacks outbox/send lifecycle events, so it cannot
  prove whether the phone persisted the original payload. Adding those events
  is a diagnostic improvement, but no product change is authorized in this
  investigation yet.

### Attempt 3

**Hypothesis:** The affected closed session takes a different delivery path
whose process-command argv cannot hold a 1,000-line prompt.

**Changes:** None.

**Result:** Confirmed. The target is a closed Claude transcript. A disposable
Claude session was created, allowed to reach `READY`, closed, and then sent a
synthetic 100,028-byte / 1,001-line follow-up through the same `/send` endpoint.
The endpoint failed in under one second with `command too long`; it created no
resumed session or queue row. The disposable live pane was closed and no scratch
session remains running.

**Recommended fix:** Resume closed sessions without an argv prompt, wait for the
new live session id/pane, then submit the preserved text and `clientId` through
the same confirmed tmux paste/send queue used by live sessions. This removes the
argv ceiling and unifies delivery/retry semantics.

### Current diagnosis

- Confirmed deterministic closed-session argv-size bug; network instability is
  incidental to this reproduction.
- Live-session long messages work because they use the paste queue.
- Closed-session long messages fail before a queue row exists, so queue/history
  inspection alone misleadingly looks as if the phone never posted them.
