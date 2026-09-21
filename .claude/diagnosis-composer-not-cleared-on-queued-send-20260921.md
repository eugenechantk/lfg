# Composer keeps its text after a queued send — diagnosis (open)

**Report (Eugene, 2026-09-21):** often, when a message is submitted and queued, the input field is not cleared.

## Established

- Nothing in the app restores a draft. `draft` (`SessionDetailView.swift:42`) is written in three places: the debug
  fixture seed, `editQueued` (an explicit tap on a queued item), and `MessageComposer.submit()`, which sets
  `text = ""` BEFORE calling `onSend` (fix `40a6050`, 2026-08-24, in every build since).
- So a stuck field means the UITextView behind `TextField(axis: .vertical)` is showing text the binding no longer
  holds, or is writing text back into the binding after the clear.
- What a queued send does that an immediate one does not: it appends a `PendingSend` with `queuedBehindTurn`, which
  inserts `PendingStripView` above the composer and grows the bottom chrome in the same transaction as the clear.

## Repro attempt 1 — queued send, hardware-keyboard input: DOES NOT reproduce

Added `LFG_SEND_FOLLOW_FIXTURE_QUEUED=1` (DEBUG only, `SessionStore.dispatchSendFollowFixture`): the fixture send goes
to the pending strip for 4 s instead of becoming a bubble. iPhone 17 Pro / iOS 26.5 sim `cc-31267937`, typed through
FlowDeck HID, tapped `composer.send`. Result: strip appears, field value reads back as the placeholder.
Evidence: `.claude/evidence/composer-not-cleared-20260921/02-after-queued-send.png`.

**What this rules out:** the pending-strip layout pass alone is not sufficient.
**What it does not cover:** the software keyboard was never up (no Simulator.app on the Air; the Pro was offline), so
autocorrect, inline prediction, swipe typing and dictation — everything that leaves provisional/marked text in the
UITextView at the moment Send is tapped — were not exercised. That is the leading hypothesis and it is UNTESTED.

## Instrumentation + narrow repair (2026-09-21, uncommitted)

Eugene could not say whether the send arrow is active when the field sticks, nor which input method is involved, so
the app now records it. `ComposerClearProbe` (`MessageComposer.swift`) runs 350 ms after every send and, only if the
binding or the first-responder UITextView still holds exactly the sent message, writes one line to the connection log
(Settings > connection log, category SND) and clears whichever side is stale:

    SND composer not cleared: sent=<n> binding=<n> view=<n|none> marked=<bool>

Reading it: `binding=0 view=n` = the text view never repainted; `binding=n` = something wrote the text back;
`marked=true` = provisional text (swipe, dictation, IME) was live at send. Lengths only, never message text.

Verified in the sim with `LFG_COMPOSER_FORCE_WRITEBACK=1` (DEBUG; re-inserts the sent text 100 ms after the clear):
log line `18:55:33.582 SND composer not cleared: sent=22 binding=22 view=22 marked=false`, field read back as the
placeholder afterwards (`03-forced-writeback-healed.png`). This proves the probe's detection and the binding-side
repair. NOT proven: that the device failure is one of these two shapes, or that the view-side repair
(`unmarkText()` + `text = ""`) beats whatever the keyboard does next. The repair is a guard, not a root-cause fix.

## Next

1. Two facts from the device: when the field is stuck, is the send arrow active or greyed? (greyed = binding is empty,
   only the text view is stale; active = something wrote the text back). And the input method used (tap typing,
   swipe, dictation).
2. Repro with the real keyboard on a host that has Simulator.app, using the queued fixture.
