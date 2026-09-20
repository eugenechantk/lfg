# Diagnosis — transfer off an offline host fails with "Server error 530: <!doctype html>…" (2026-09-20)

Eugene moved a session from the offline Pro to the online Air and got a toast:
`Transfer: closing on Pro failed: Server error 530: <!doctype html> <!--[if lt IE 7]> …`

**Cause: the client mistakes Cloudflare's answer for the Pro's.** Every client request
goes through the Cloudflare tunnel. When the Pro (or its `cloudflared`) is down, the
request does not fail at the transport layer — the edge answers **HTTP 530** with an
HTML error page. `LFGClient` surfaces that as `LFGError.http(status: 530, body: html)`,
and everything downstream reads `.http` as "the lfg server answered".

## The path that failed

`SessionTransfer.perform` (`ios/LFGCore/Sources/LFGCore/SessionTransfer.swift`):

1. `plan(sourceKnownDown:)` — the Pro was not yet *known* down (host state inside its
   grace window, or still `connecting`), so the plan was `.normal`: close the source
   first.
2. `source.close(id)` → Cloudflare 530.
3. The escalation written for exactly this moment —
   `catch where closeFailureIsUnreachable(error) { plan = .sourceUnreachable }` — only
   recognises `.notReachable`, `.transport`, `.streamStalled`. `.http` is classified as
   "host refused", so the transfer throws `Failure.sourceClose` and aborts.

Since client access is Cloudflare-only, a dead host **never** produces a transport
error here. The escalation branch has effectively never fired in production; the
transfer only works once the host state has already reached `offline` and the plan
starts as `.sourceUnreachable`. The unit test pins the gap:
`SessionTransferTests` asserts `http(500)` → not unreachable, and has no case for an
edge status.

## Same root, other consumers (read, not yet reproduced)

- `SendTerminality.classify`: `.http(status)` → `.serverAnswered(status)`. A 530 marks
  a send as answered by a server that never saw it.
- The toast prints raw Cloudflare HTML because `LFGError.http`'s description is
  `"Server error \(s): \(b)"`.
- Host probes do the right thing by accident: any failed fetch is `.probeFailed`.

## Proposed fix — at the boundary, once

In `LFGClient`, where a non-2xx becomes `LFGError.http`: if the status is an
edge/origin-down status (**502, 503, 504, 520–527, 530**) **and the body is not lfg's
JSON** (Cloudflare's page starts `<!doctype html`; lfg always answers JSON — and lfg
itself deliberately returns a JSON 502 for codex resume errors, which must stay
`.http`), throw `.notReachable(underlying: "Pro is unreachable through Cloudflare
(530)")` instead. Then, with no further changes:

- the transfer's escalation fires and the move proceeds as `.sourceUnreachable`
  (force-resume on the target, deferred source close) — the behaviour already built
  and tested for transport failures;
- sends classify as `transportFailed`, which is the truth;
- the user sees a sentence, not an HTML dump.

Tests: `SessionTransferTests` gains 530/502-HTML → unreachable and 502-JSON → refused;
an `LFGClient` test feeds a stubbed 530 HTML response and expects `.notReachable`;
`SendTerminality` gains a 530 case.

## Status

Not applied. This session is on the Air, where `git` and `swift` are both blocked by
the un-accepted Xcode licence (`sudo xcodebuild -license accept`), and the Pro is
unreachable (its ssh tunnel answers "websocket: bad handshake"), so nothing can be
tested or committed right now. Another session has uncommitted edits in
`SessionTransfer.swift`, `MultiHost.swift` and `SessionStore.swift` on the Pro; the
proposed change lives in `LFGClient.swift` plus tests and does not need to touch
those files.
