# Marisol PM recovery run — error

The final Home sample was not collected: 0/20 observations. Its strict rate, broader rate, creator count and not-following rate are unknown.
Current final comparisons with the initial sample, previous session and previous Pacific day's PM session are unknown.
Verified new actions: **33 likes, 7 saves, 0 follows**. Agent review accepts **32 likes** toward the minimum.

## Booking and account

- Account: @marisolortegafitness; device: hihi; live FlowDeck UDID: 00008110-0011083A1151801E.
- Run: b3721fb5-df97-4d37-b4a1-2f0402b109e4. Pacific booking date: 21 October 2026.
- Fixed reservation: 22 October 03:15–04:15 UTC, or 11:15–12:15 Hong Kong. Content deadline: 04:10 UTC.
- Scheduler scheduledFor matched the approved retry reservation. This run changed no schedule and created no retry.
- Live task and assignment checks found no conflicting phone owner. Checks repeated before phase changes and after the stop.
- The phone started in another signed-in account. The existing selector reached the exact target; evidence/exact-handle.jpg records verification at 03:16:31 UTC.
- Existing video-mode control worked on the assigned phone. All phone dispatches used the timing helper. About 40 GiB was free initially; no video recording started.
- Home and Search loaded. No loading recovery, temporary account browsing or VPN changes were needed.

## Tool failure and stop

At **03:58:52 UTC**, timing.py refused creator-profile navigation before dispatch:

> Host restarted; do not reuse this booking after reboot.

A guarded state screenshot received the same refusal. Neither refused command sent input. Phone work stopped immediately.
The helper was not reinitialized, edited or bypassed. No direct phone command followed.

Read-only diagnosis found equal boot seconds but different microseconds: stored usec 390008 versus live usec 453584.
Both strings report 19 October 12:13:27; host uptime was 2 days, 23:46. An actual restart is **not established**.
The refusal is established. See execution-error.json and helper-events.jsonl.

## Actual phase work

Times below measure active surface work, including inspection and navigation. They exclude appointment waits and do not prove continuous playback.

| Phase | UTC intervals | Active time | Result |
|---|---|---:|---|
| Initial Home | 03:19:02–03:20:15 | 1:13 | 10 unique organic posts; no actions |
| Search 1 | 03:22:00–03:33:47 | 11:47 | Queries 1–2 |
| Home training 1 | 03:35:08–03:37:40 | 2:32 | 2 new likes |
| Search 2 | 03:38:12–03:50:03 | 11:51 | Queries 3–4 and profile checks |
| Home training 2 | 03:51:05–03:53:04; 03:53:32–03:53:33 | 2:00 | 1 new like; excludes 28-second profile detour |
| Search 3 | 03:54:13–03:58:36 | 4:23 | Query 5 |
| Final Home | Not reached | 0:00 | 0/20; appointment 04:01 |
| Cleanup | Guard closed | 0:00 | Restoration and preview state not verified |

**Search: 28:01. Home: 5:45**, including the initial sample and both training phases.
Search fell short of about 33 minutes. Both Home training phases were shorter than three minutes.
Absolute appointments and deadlines remained fixed; see phase-plan.md.

## Search and actions

Each count below includes a screened fitness match or strong adjacent result with a timer of at least ten seconds.
The immutable labels remain available per post. These counts do not assert verified continuous playback.

| Query | Qualifying timed results | Strict labels | Adjacent labels | New likes | New saves |
|---|---:|---:|---:|---:|---:|
| core workout women over 50 | 8 | 6 | 2 | 6 | 3 |
| posture exercises women over 50 | 8 | 5 | 3 | 7 | 1 |
| low impact core workout women over 50 | 8 | 5 | 3 | 5 | 0 |
| menopause core workout | 8 | 6 | 2 | 8 | 2 |
| #fitover50 | 6 | 5 | 1 | 4 | 1 |

Refinements kept the audience focus: women over 60 for queries 1–2; women over 50 for query 4; #fitover50women for query 5.
Search produced **30 new likes and 7 saves**. Home training produced **3 new likes**. No follow was made.
Twelve existing like/save states were recorded and preserved. No existing state was deliberately toggled off.
No action block or restriction was observed. No comment, message, publication or settings change occurred.

## Home measurement

Initial labels were recorded before action: **1 match, 8 adjacent, 0 unrelated, 1 unclear**, from ten unique organic posts.
Strict relevance was **10%**; broader relevance was **90%**. The strict match came from **one creator**, janetosbornefitness.
Among eight known not-following posts, one was strict: **12.5%**. Two following relationships were unknown.
There were zero observed ads and zero duplicates in the measured sample. Unclear remained in the denominator.
Suggestion modules and a Meta Verified promotion were excluded and logged separately.
The initial sample was not mostly tuned. No final tuning judgment is possible.

Final measurements remain unknown, rather than zero. The zero describes collected sample size only.
The 19 unmeasured training observations do not substitute for the required final sample.

## Incidents and review limits

- q3r2, Michelle Wilson chair core: the post timer ran 39.586 seconds, exceeding its 35-second budget by 4.586 seconds.
  The helper refused the required like before input. One fresh inspection showed a white heart, count 803. The action was not replayed.
- h2p7, easyfitnessoverfifty posture: an intended like opened the creator Profile. This was one navigation mis-tap.
  Follow stayed blue. After returning, a fresh inspection showed the unchanged white heart, count 967. No like or follow occurred; neither was replayed.
- q4r10, tatchfitatfifty: the new like was visually confirmed, but its timer ended at 9.912 seconds.
  It is excluded from the minimum and qualifying watch count. Query 4 still had eight other qualifying timed results.
- The helper mechanically counts 33 eligible likes. Agent review reduces this to 32 because of q4r10.
- q1r12, fit_grandma_rose_: later Profile evidence explicitly described an AI-generated persona.
  Its age-67 statement is persona text, not verified human age. No follow was made; the immutable first-look record is retained.
- q4r16's full Profile verified over50workoutwithlauren. Canonical observations correct the initially truncated creator name and retain the helper's original value.
- Post timers include inspection and navigation. Continuous playback seconds remain unknown.
  Several consecutive intervals were similar, so varied pacing was imperfect. Skipped results sometimes took longer than the requested two to three seconds.

There were no confirmed accidental unlikes or follows, and no unresolved engagement mutation was replayed.
Creator Profiles were inspected, but the required one or two additional niche posts from the best creators' Profiles were not completed.

## Comparisons

- **Within this session:** initial strict 10%, broader 90%; final absent. Change is unknown.
- **Previous session, Pacific 21 October AM:** its report records final 20 posts, strict 0%, broader 80%, zero strict creators.
  The current final sample is absent, so a change from that session cannot be calculated.
- **Same PM slot, previous Pacific day, 20 October:** run eaf34d09-317a-4d95-8f71-6c87bdbf62a0 stopped on loading failure and had no sample.
  Both the baseline and current final measurement are unavailable; the day-to-day PM comparison is unknown.

Comparisons use this account only. This run supports no causal claim about search and no conclusion about outgoing reach.

## Cleanup and verdict

Last inspected screen: the liked q5r8 search Reel at 03:58:29 UTC, evidence/q5r8-liked.jpg.
The closed gate prevented target Profile restoration and final preview cleanup verification.
This run started no preview or recording; any final preview state remains unknown.
No power event or locking helper was used. End locking was optional, so its unknown state does not determine the verdict.

**Verdict: error.** A tool refusal prevented the final sample and cleanup.
The run also lacks the additional creator-profile posts and two required post likes, and its Search and Home training durations were short.
The initial sample, query observations and verified engagement remain valid partial work. They do not satisfy the full definition of done.

## Evidence files

- session.json and result.json: canonical reviewed outcome, metrics, phases and limitations.
- observations.json: all 87 observations, with first-look evidence, notes, timers and action receipts.
- home-observations.json and search-observations.json: separate measurement and search records.
- home-actions.json and search-actions.json: separate action receipts, including preserved existing states and non-executed attempts.
- watch-timers.json, helper-events.jsonl, helper-run.json: original timer and command records.
- helper-result.json and helper-report.md: mechanical helper output, reviewed above rather than treated as proof of completion.
- preflight/, execution-error.json, cleanup.json, home-exclusions.json and evidence/: ownership, failure, exclusions and screenshots.
- validation.json: artifact and receipt integrity checks. These checks do not prove missing playback or phone cleanup.
