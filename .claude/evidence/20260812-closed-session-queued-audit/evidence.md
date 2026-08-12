# iOS Visual Evidence Audit

Verdict: **PASS**

Timestamp: 2026-08-12 19:16 (local, Eugenes-MacBook-Pro)
Repository: /Users/eugenechan/dev/personal/lfg
Simulator: `cc-0899b223-a18b5fd5` — iPhone 17 Pro, iOS 26.3, UDID `6A6ADA9C-CB83-45D5-874B-A3953C55A063`
App: `com.eugenechan.lfg`, scheme `LFG`, project `/Users/eugenechan/dev/personal/lfg/ios/LFG.xcodeproj`, built from the dirty working tree (3 modified + 4 new files)
Host under test: `http://127.0.0.1:8766` (live `lfg serve` on this Mac)

## Change Audited

Sending to a **closed** session used to render an immediate muted gray transcript bubble
("Waking session…") that turned accent-blue the moment the send POST returned. It should now
render as a **queued row in the pending strip** above the composer (spinner + text + "Queued"
+ ellipsis) and become a blue user bubble only once the reopened session's transcript actually
carries the user turn.

Audited independently — implementation notes and the implementation agent's own evidence
directory (`.claude/evidence/20260812-closed-session-queued/`) were treated as claims, not
proof. All artifacts below were produced by this audit.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| **SC1** Send to a closed session produces a pending-strip row, not a transcript bubble of any colour | **PASS** | `10-run1-t0.0-queued-row-on-send.jpg` (row present at t+0.0s, transcript untouched), `30-run2-t1.8-queued-while-header-running.jpg`, `60-a11y-tree-queued-resume-row.json` (row nodes at y≈719, i.e. above the composer at y≈768; transcript region has no matching bubble) |
| **SC2** Row shows "Queued" + ellipsis affordance; the three row types stay distinguishable | **PASS (2 of 3 captured live)** | Resume row = spinner + "Queued" + ellipsis: `10-…`, `30-…`, `60-a11y-tree-queued-resume-row.json` (`id: pendingStripRowResuming`, labels "Queued" and "More"). Busy row = spinner + ellipsis, **no** "Queued": `20-sc5-live-send-plain-row-no-queued-label.jpg`. Offline row (clock + "Queued") **not captured live** — see Notes. |
| **SC3** Row does not turn blue when the send POST returns; still "Queued" while the nav header reads "Running" | **PASS** | `11-run1-t1.5-queued-while-header-running.jpg` and `30-run2-t1.8-queued-while-header-running.jpg` — nav subtitle reads **"Running"** (host accepted, pane live) while the strip row still reads **"Queued"**. Held for a further ~1–3s: `12-run1-t2.5-still-queued.jpg`, `31-run2-t4.4-still-queued.jpg` |
| **SC4** Row is replaced by a blue bubble with the same text (no duplicate) and the agent replies in the same conversation | **PASS** | Replacement: `13-run1-t3.4-blue-bubble-row-gone.jpg`, `32-run2-t5.3-blue-bubble-row-gone.jpg` — blue bubble present, strip row gone in the same frame. No frame in any of the three runs (0.8s cadence) shows both. Agent reply: `33-run2-t7.7-agent-reply-live.jpg` (reply rendered live 2.4s after the bubble), `61-run3-final-blue-bubble-and-reply.png` (reply "40"). Video: `sc1-sc4-closed-send-queued-to-blue.mov` |
| **SC5** No regression on a live session: plain strip row (no "Queued") → blue bubble + reply | **PASS** | Busy live session: `20-sc5-live-send-plain-row-no-queued-label.jpg` → `21-sc5-live-send-blue-bubble.jpg`. Idle live session: `40-sc5-idle-send-instant-blue-no-queued.jpg` (instant blue bubble, no strip row — the documented idle path) → `41-sc5-idle-send-agent-reply-live.jpg` (reply "24" live). Video: `sc5-live-send.mov` |

### Runs performed

| Run | Session (closed) | Message | Queued row observed | Blue bubble | Agent reply |
|---|---|---|---|---|---|
| 1 | `a370bf44` "What is 2+2?" | INDIA4242 | 19:56:08.2 → 19:56:11.0 | 19:56:12.0 | delivered late (stalled stream, see Notes) |
| 2 | `a8700a04` "…HOTELAUDIT…" | NOVEMBER6060 | 19:08:30.3 → 19:08:32.9 | 19:08:33.8 | 19:08:36.2 live |
| 3 | `20fd1857` "…CHARLIE…" | What is 20+20? | 19:15:49 (a11y tree) | ~19:15:51 | "40" live |

All three target sessions live in `/Users/eugenechan/lfg-verify-0899b223` (throwaway). No real
session was resumed, messaged, or modified.

## Artifacts

Directory: `/Users/eugenechan/dev/personal/lfg/.claude/evidence/20260812-closed-session-queued-audit/`

- `10-run1-t0.0-queued-row-on-send.jpg` … `13-run1-t3.4-blue-bubble-row-gone.jpg` — run 1 time series
- `20-…`, `21-…` — SC5 busy-session send (plain row, no "Queued")
- `30-…` … `33-run2-t7.7-agent-reply-live.jpg` — run 2 time series, incl. live agent reply
- `40-…`, `41-…` — SC5 idle-session send (instant blue, live reply)
- `50-offline-gate-blocks-offline-row-capture.png` — why the offline row could not be captured
- `60-a11y-tree-queued-resume-row.json` — accessibility-tree proof of `pendingStripRowResuming` + "Queued"
- `61-run3-final-blue-bubble-and-reply.png` — run 3 resolved state
- `sc1-sc4-closed-send-queued-to-blue.mov`, `sc5-live-send.mov` — screen recordings

Time-series stills are FlowDeck UI-session frames (~0.8s cadence) captured live and copied out
before the session's 60s retention pruned them; each filename carries its offset from the send tap.

## Commands

```
flowdeck config get --json
flowdeck run --scheme LFG                       # guard returned the dedicated UDID
flowdeck run --scheme LFG -S "6A6ADA9C-CB83-45D5-874B-A3953C55A063"
flowdeck ui simulator session start -S "6A6ADA9C-…" --json
flowdeck ui simulator tap  -S "6A6ADA9C-…" -p <x>,<y> | "<label>"
flowdeck ui simulator type -S "6A6ADA9C-…" "<text>"
flowdeck ui simulator erase / hide-keyboard -S "6A6ADA9C-…"
flowdeck ui simulator screen -S "6A6ADA9C-…" --output <file>.png
flowdeck ui simulator record -S "6A6ADA9C-…" -o <file>.mov -t <n> --codec h264
flowdeck run --scheme LFG --no-build -S "6A6ADA9C-…"   # relaunch after stalled stream
flowdeck apps
```

Server-side ground truth was read with plain `curl` against `http://127.0.0.1:8766`
(`/api/sessions`, `/api/sessions/:id/messages`, `/api/sessions/resumable`, `/api/events`).

## Notes

### Confounder found and cleared: a stalled live event stream (not caused by this change)

Run 1's blue bubble was correct, but the agent's `INDIA4242` reply never rendered — it sat on the
host for 3.5 minutes while the client showed a two-message transcript, and only appeared after
backing out and re-entering the detail view (which forces `loadHistory`).

Before attributing that to the change, it was disconfirmed three ways:

1. Reproduced on a **freshly created, never-closed** session (`3aaeb59d`) — its reply `KILO9911`
   also never rendered live. So the failure is not the resume path.
2. `GET /api/events` showed the server **did** journal both `msg` deltas (user turn and assistant
   reply) for that session — so the server side was healthy.
3. Relaunching the app (`flowdeck run --no-build`) fixed it immediately: an API-side send landed
   `MIKE3030` in the open detail view within seconds, and runs 2 and 3 both rendered their replies
   live within ~2.5s.

The first app instance's live event stream was dead for its whole lifetime while still displaying
"Connected". The diff under audit does not touch the `msg`-delta application path
(`git diff` covers `PendingSend`, `applyQueueAck`, `applyAcceptance`, `watchForResumeLanding`,
`sendWithAttachments`, and the two views). **Not attributable to this change, but a separate
latent issue worth its own investigation** — a client that shows "Connected" while its event
stream is dead is indistinguishable from a quiet host.

### SC2's third row type not captured live

The offline-queued row (clock icon + "Queued") could not be reproduced in this app instance:
with a single configured host, making it unreachable drops the whole UI to the "Host unreachable /
Not connected" gate (`50-offline-gate-blocks-offline-row-capture.png`), so there is no detail view
to send from. Verified instead by reading `PendingStripView` (`ios/LFG/Components.swift:343-378`):
the offline branch renders `clock.arrow.circlepath` where the other two render `ProgressView`, and
the resume branch is the only other one that also emits the "Queued" label. The three are therefore
distinguishable — but the resume and offline rows differ **only by the leading glyph** (spinner vs
clock); label and affordance are identical. That is the design decision recorded in the feature
doc, not a defect, but it is a thin distinction.

### Incidental observation (artificial condition, out of scope)

While forcing the offline state by editing the host address to a dead port and back, a message
typed during the offline window (`Offline row check OSCAR1234`) did not appear on the host after
the address was restored, and no pending row survived. A host-URL edit is not the same event as a
genuine network drop, so this is **not** reported as an offline-queue regression — but it is worth
a dedicated check against a real transport failure.

### Other limitations

- Codex sessions, a 409 "live on another host" resume, and multi-line / attachment sends down the
  resume path were not exercised.
- Cold-launch-mid-resume (the residual risk the feature doc records: a restored outbox row comes
  back as a bubble, not a queued row) was not exercised.
- All coordinate taps were used where label matching was ambiguous (composer, send arrow, search
  field, settings rows); label taps were used where available and are noted in the command list.
