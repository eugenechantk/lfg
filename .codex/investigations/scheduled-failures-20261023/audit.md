# Why scheduled tasks remain incomplete

Audit snapshot: 2026-10-23T23:58:31+08:00. All times use Hong Kong time unless stated otherwise.

**Fix execution gaps first.** Five of the seven tasks whose latest run is unsuccessful lost work to long execution gaps.
One other task needs a policy review. The remaining task last failed at the provider usage limit.

## Scope and counts

The live LFG API contains 30 tasks and 90 attempts from 9–22 October.
Their recorded statuses are 48 succeeded, 27 failed and 15 incomplete.
These are scheduler records, not a fresh verification of all 48 successes.
All 42 unsuccessful attempts were inspected through available transcripts, outcomes and canonical reports.
The audit retrieved 44 transcripts covering unsuccessful attempts and recent successes. One launch failure has no session.
Canonical report paths were found for 33 of those 45 selected attempts. Provider-limit and launch failures often have no report.

Seven tasks have unsuccessful latest attempts: six incomplete and one failed.
Seventeen tasks have succeeded latest attempts; six have no recorded attempt.
All 30 schedules are disabled. There are no active runs or pending retries in this snapshot.
A disabled or never-run task does not prove its underlying work succeeded or failed.

## The seven unresolved tasks

| Task | Latest attempt | Evidence and cause | Recommendation |
|---|---|---|---|
| Toni Instagram AM | 22 Oct 13:35; incomplete | 26 likes, 3 saves; both samples. Gaps shortened query 4 and prevented final cleanup. Old quota rules also influenced the verdict. | Review substantial engagement separately from cleanup. Fix the gaps before any fresh booking. |
| Marisol Instagram AM | 22 Oct 14:50; incomplete | 2 likes, 1 save; final sample 3/20. Long gaps consumed most of the session and cleanup. | Keep incomplete. Repeat only after gap repair and a new authorized booking. |
| Jess Instagram AM | 22 Oct 16:05; incomplete | 7 likes, 2 saves; initial sample absent and queries 1–4 missed. Large gaps. Cleanup succeeded. | Keep incomplete. Fix the gaps before retrying. |
| Toni Instagram PM | 22 Oct 17:20; incomplete | 7 likes, 1 save; initial 2/10, final 10/20. Gaps displaced core work. Cleanup succeeded. | Keep incomplete. Fix the gaps before retrying. |
| Roxie TikTok @roxie_bennett | 22 Oct 12:15; incomplete | 46 likes, 6 saves; all queries, both samples and cleanup. Failed on two similar watch pairs and uncertain feedback receipts. | Strong candidate for completion under the revised policy. Preserve feedback as unverified and retain incidents. |
| Roxie TikTok @roxiebennettfitness | 22 Oct 14:55; incomplete | 5 likes; initial 6/10, final 0/20. Gaps removed most Search work. Cleanup succeeded. | Keep incomplete. Fix the gaps before retrying. |
| Roxie Instagram @roxiebennettfitness | 20 Oct 07:45; failed | Provider usage exhaustion. This saved prompt lacks the newer completion-policy prefix. | Verify current provider capacity and refresh the task instructions before a new booking. |

The Roxie policy-review recommendation is this audit's judgment, not a saved verdict change.
Toni AM has substantial activity, but missing cleanup and reduced work require a separate assessment.
None of these recommendations authorizes editing history, re-arming schedules or extending phone time.

## Failure modes across all 42 unsuccessful attempts

Each attempt receives one primary category for counting. Secondary causes overlap.
The table is descriptive; it does not establish the internal cause of every delay or app loading failure.

| Primary category | Attempts | What failed | Fix |
|---|---:|---|---|
| Provider usage exhaustion | 13 | The agent hit an account limit, sometimes after partial work. | Check capacity before reserving a phone. Defer to a known reset or use an already authorized alternative. |
| App loading or VPN connectivity | 10 | Instagram Home/Search stayed blank, TikTok could not connect, or Surfshark stayed Connecting. | Run one bounded health check inside the booking. Require visible app loading and VPN Connected before content work. |
| Execution gaps | 8 | Delayed results or continuation gaps consumed fixed phase and cleanup appointments. | Trace the delivery path. Prove the repair with repeated image/status probes before another phone session. |
| Checklist or cap verdict | 5 | Useful sessions failed on quotas, samples, pacing or the old like cap. | Apply one authoritative completion policy. Keep mechanical shortfalls as findings. |
| Timing helper refusal | 3 | Boot-identity checks stopped commands or cleanup. | Use stable boot identity; verify existing source fix before fresh runs. Never reuse a refused booking. |
| Device ownership conflict | 1 | Another run still owned Hi Hi after the bounded wait. | Reserve the physical UDID atomically before launch. Release stale ownership only after checking the owner. |
| Unexpected foreground screen | 1 | Shared with You appeared and ownership or state became uncertain. | Re-check ownership and inspect a fresh screen. Recover only when the screen is understood and permitted. |
| Launch payload failure | 1 | An early run failed with command too long before creating a session. | Verify the current submission path handles the actual long prompt through a file or buffer. |

Provider limits dominate the older attempts. In the latest unresolved set, execution gaps dominate.
On 22 October, LFG recorded 18 attempts: 3 succeeded, 6 failed and 9 incomplete.
Marisol PM later completed with 34 likes and 6 saves, so its earlier failures are historical rather than unresolved latest outcomes.

## Priority 1 — repair execution gaps

Existing raw-trace analysis places the delay outside ordinary phone execution.
One local operation took about 1.3 seconds; its enclosing result arrived after about 900 seconds.
A later probe reproduced completed local work followed by roughly 60 seconds of delayed delivery.
Another probe had a long continuation gap with no outstanding phone command.
These are two observable boundaries. Their exact internal cause remains unknown.

The previous 60-second transport experiment recovered one stall but failed another live probe.
It was withdrawn. Current configuration has no candidate provider, and the launcher has no candidate routing import.
Do not repeat that experiment as an established fix.

Proposed repair work:

1. Record dispatch, local finish, outer result delivery and next command timestamps under one correlation ID.
2. Separate slow phone work, delayed delivery and delayed continuation in the resulting timeline.
3. Inspect existing diagnostic files for the affected sessions. A database read needs separate approval under the standing rules.
4. Fix the confirmed boundary, then repeat the previously failing image/status probes in both phone workspaces.
5. Add an elapsed-time monitor that reports lost time and remaining appointments without sending phone input.
6. Validate one newly booked session before broader recovery. Keep uncertain inputs unreplayed and deadlines fixed.

Acceptance: repeated probes finish without the earlier minute-scale gaps; local and outer timings explain each wait.
A fresh authorized session must preserve useful engagement and time for cleanup.
A passing unit test or one fast probe alone does not close this issue.

## Priority 2 — remove contradictory completion rules

Thirteen saved prompts contain the revised policy prefix.
Nine of those still contain an explicit all-items completion rule lower in the prompt.
Some also say 30 likes are mandatory or any timing shortfall requires failure.
The prefix says it overrides those rules, but the duplicated instructions still create avoidable ambiguity.
The unresolved Roxie Instagram fitness task has no revised prefix at all.

Recommendation: rewrite each saved execution prompt once around a single policy reference.
Keep identity, ownership, allowed actions and hard deadlines as firm boundaries.
Keep query counts, samples and like counts as work targets.
Have the helper return measurements and mechanical findings; have the agent state the canonical policy judgment.
Record the policy version with that judgment.

Review the Roxie 46-like TikTok run first. Its core work and cleanup are documented.
Retain two feedback actions as unverified. Do not repeat them to repair the historical evidence.
Review Toni AM separately because its cleanup failed.
Also inspect historical productive attempts with 30, 31, 38 or 44 likes under the new policy.
Those are review candidates, not automatic successes based on a like count.

Acceptance: no saved prompt says both quotas are optional and quotas determine completion.
A productive session can complete with documented minor incidents.
A session with only a handful of actions and major lost work remains incomplete.

## Priority 3 — check readiness before consuming the booking

Combine provider capacity, physical-phone reservation and app health into a small preflight.
Use the existing account-usage view and usage-limit notices where available.
A meter is a readiness signal, not a guarantee that the run has enough remaining capacity.
If a reset time is known, propose a compatible future slot rather than repeatedly launching against the same limit.

Reserve by physical UDID, since different account tasks share one phone.
Check the exact account and visibly loaded content after waking the phone.
Use only the existing authorized recovery for VPN or app loading failures.
If it fails, stop promptly and report the blocker.
A loading screen alone does not prove the VPN caused the failure.

Classify the blocker so retries can target its cause.
Keep the logical scheduled occurrence across retries using LFG's existing retry model.
Do not enable disabled schedules, change provider permissions or create phone bookings during this audit.
Acceptance: a blocked preflight sends no content actions and preserves the occurrence for an authorized recovery.

## Priority 4 — finish helper and cleanup verification

Several historical issues already have source changes:

- timing.py now uses kern.bootsessionuuid instead of an adjustable boot timestamp. A regression checks the stable identifier.
- The helper has separate TikTok phase boundaries and a regression for them.
- Current warm-up instructions make end locking optional. Missing power-lock confirmation alone no longer fails a run.
- Guidance already protects final-sample and cleanup appointments and requires fresh state after long gaps.

These source checks do not prove a future live run works.
Verify the stable boot guard across fresh processes and wall-clock changes; keep real reboot refusal intact.
Verify actual helper boundaries match the selected routine before dispatch.
Keep final Profile restoration and preview shutdown observable.
Do not add a fallback that operates after deadline or after ownership expires.
A cleanup monitor must obey those same boundaries.

Layout movement caused navigation mistakes and occasional accidental social actions.
Keep settle, identify, act and verify behavior, with fresh state after overlays or delays.
Separate uncertain actions from confirmed actions. Do not blindly repeat a tap.
Treat minor incidents under the current policy while retaining their evidence.

Acceptance: a valid fresh booking survives clock adjustment, a real new boot is refused, and cleanup occurs within ownership and time.

## Existing LFG features and their limits

LFG already has interval retry support and post-session outcome reconciliation.
A retry can preserve a logical occurrence; it does not fix provider capacity, phone connectivity or execution gaps.
The post-session hook synchronizes the exact run's final structured verdict.
It does not independently re-grade old evidence when the completion policy changes.
No matching local review receipt was found for these unsuccessful attempts.
That absence alone does not prove the hook failed; several attempts predate its installation.

Task completion and feed quality also need separate reporting.
A completed warm-up can still have a poorly tuned feed.
Marisol's latest completed run had 10% strict relevance in its final sample.
Broad fitness relevance should not be reported as proof that an over-50 audience feed is tuned.

## Recommended order and decision

Start with the execution-gap repair and the prompt cleanup.
Review clearly productive historical attempts separately so stale checklist verdicts do not trigger unnecessary phone work.
Then add capacity and phone-readiness checks, using the existing retry model.
Verify the helper fixes rather than implementing them again.
Do not mass-retry the backlog before this sequence passes.

This proposal changes no source, schedules, bookings, verdicts, phone state, provider configuration or database contents.

## Evidence and limits

Local evidence in this folder:

- tasks.json: live task snapshot, including exact saved instructions and latest outcomes.
- runs.json: all 90 live run records from per-task history APIs.
- classified-runs.json: the 42 unsuccessful attempts with one primary category each.
- transcripts/: 44 normalized full transcript snapshots.
- reports/: canonical report files and helper result files found for selected attempts.
- evidence-index.json: original report paths keyed by exact run ID.
- summary.json: reproducible counts and audit timestamp.

The audit read reports and receipts. It did not independently inspect every screenshot or replay phone actions.
Missing playback proof remains unknown. Partial samples remain partial.
The taxonomy summarizes recorded evidence, rather than proving a provider-internal root cause.

Existing project evidence:

- .codex/feature/iphone-execution-gaps.md and its independent-audit.md: unresolved delay analysis and rejected transport experiment.
- src/task-post-review.ts and src/scheduled-tasks.ts: outcome synchronization and logical-occurrence retry behavior.
- /Users/eugenechan/inbox/roxie-search-engage-2026-10-19/COMPLETION-POLICY.md: current social completion policy.
- Shared warm-up timing.py and test_helpers.py: stable boot identity and separate phase plans.

## Attempt index

This table assigns one primary category. Full evidence text remains in the snapshot files.

| Started HKT | Task | Status | Primary category | Run ID |
|---|---|---|---|---|
| 15 Oct 01:00 | FiftyStrong TikTok — @roxie_bennett (3 daily sessions) | failed | Launch payload failure | cbfa015a-f79c-4a3e-8626-f02de257bd7a |
| 18 Oct 04:00 | FiftyStrong search loops — @roxiebennettfitness 16:00 Eastern (2 days) | failed | Provider usage exhaustion | ba820437-2b04-4536-b3c5-649e6e10dd7d |
| 19 Oct 22:45 | Roxie search+engage — @roxiebennettfitness Instagram (US day + night, 19 Oct) | incomplete | Checklist or cap verdict | 66741360-a60f-4ec4-9cab-ae913d2e359b |
| 20 Oct 00:00 | Roxie search+engage — @roxie_bennett TikTok (US day + night, 19 Oct) | failed | Provider usage exhaustion | 01e1861c-3572-4614-a04f-de14d8919b90 |
| 20 Oct 00:30 | Instagram Hi Hi — @toniwhitfieldfitness — AM Pacific (3 days) | failed | Provider usage exhaustion | ed7af2d1-2df1-4279-b5dd-43becb1d27d1 |
| 20 Oct 01:15 | Roxie search+engage — @roxie_bennett_ Instagram (US day + night, 19 Oct) | failed | Provider usage exhaustion | 02563401-0516-478a-8053-1671bb91efce |
| 20 Oct 01:45 | Instagram Hi Hi — @marisolortegafitness — AM Pacific (3 days) | failed | Provider usage exhaustion | 7992d0c5-cf05-4c1a-a729-9b6cd9961727 |
| 20 Oct 02:30 | Roxie search+engage — @roxiebennettfitness TikTok (US day + night, 19 Oct) | failed | Provider usage exhaustion | 21583464-6170-4e8b-858a-904653b76225 |
| 20 Oct 03:00 | Instagram Hi Hi — @jesscallahanfitness — AM Pacific (3 days) | failed | Provider usage exhaustion | b3bf88a0-eccc-440a-a43d-466caeddce9a |
| 20 Oct 07:45 | Roxie search+engage — @roxiebennettfitness Instagram (US day + night, 19 Oct) | failed | Provider usage exhaustion | 110abce0-28c0-448c-af6e-07a76c4205e0 |
| 20 Oct 09:00 | Roxie search+engage — @roxie_bennett TikTok (US day + night, 19 Oct) | failed | Provider usage exhaustion | 4285c5e5-518f-4295-999e-9e2e711f05a9 |
| 20 Oct 10:00 | Instagram Hi Hi — @toniwhitfieldfitness — PM Pacific (3 days) | failed | Provider usage exhaustion | 25895f88-6093-4eff-b459-4d5e430c213a |
| 20 Oct 10:15 | Roxie search+engage — @roxie_bennett_ Instagram (US day + night, 19 Oct) | failed | Provider usage exhaustion | 8e17e677-fb6d-49a1-9853-fd04708112f6 |
| 20 Oct 11:15 | Instagram Hi Hi — @marisolortegafitness — PM Pacific (3 days) | failed | Provider usage exhaustion | bf36bfd1-5272-484a-a6bd-fcdbed5910ba |
| 20 Oct 11:30 | Roxie search+engage — @roxiebennettfitness TikTok (US day + night, 19 Oct) | failed | Provider usage exhaustion | 718a7164-716a-4246-adff-7e57119a00ca |
| 20 Oct 11:40 | Roxie search+engage — @roxiebennettfitness TikTok (US day + night, 19 Oct) | incomplete | Execution gaps | 779866c1-613e-4e8c-a5c9-3179fbbbf214 |
| 20 Oct 12:30 | Instagram Hi Hi — @jesscallahanfitness — PM Pacific (3 days) | incomplete | Unexpected foreground screen | 0bebb80f-9910-4d73-9cde-d322f6712708 |
| 20 Oct 13:41 | Roxie search+engage — @roxie_bennett_ Instagram (US day + night, 19 Oct) | incomplete | Checklist or cap verdict | aa9c4af7-4a2c-43d1-878f-d151aa6350e2 |
| 20 Oct 14:41 | Instagram Hi Hi — @toniwhitfieldfitness — PM Pacific (3 days) | incomplete | Execution gaps | 49b00e02-9853-45c2-9387-d992c54eba93 |
| 20 Oct 15:42 | Instagram Hi Hi — @marisolortegafitness — PM Pacific (3 days) | incomplete | Device ownership conflict | fa6b765e-75d4-435a-8c1b-245bbb9b3de6 |
| 21 Oct 00:00 | Roxie search+engage — @roxie_bennett TikTok (US day + night, 19 Oct) | failed | App loading or VPN connectivity | e5f4d696-4375-4aba-bc32-018c9af4acc2 |
| 21 Oct 00:30 | Instagram Hi Hi — @toniwhitfieldfitness — AM Pacific (3 days) | failed | App loading or VPN connectivity | ecfc1441-b0a4-4d2d-8273-6ba0dd70c14f |
| 21 Oct 01:45 | Instagram Hi Hi — @marisolortegafitness — AM Pacific (3 days) | failed | App loading or VPN connectivity | 2e97e505-68a0-4544-a312-bd1c0834e258 |
| 21 Oct 03:00 | Instagram Hi Hi — @jesscallahanfitness — AM Pacific (3 days) | failed | App loading or VPN connectivity | a453507b-91eb-4f19-b8b8-4c572a488d96 |
| 21 Oct 10:00 | Instagram Hi Hi — @toniwhitfieldfitness — PM Pacific (3 days) | failed | App loading or VPN connectivity | 6a5c8f3a-1597-4c08-ba35-78fb43eb294c |
| 21 Oct 11:15 | Instagram Hi Hi — @marisolortegafitness — PM Pacific (3 days) | failed | App loading or VPN connectivity | eaf34d09-317a-4d95-8f71-6c87bdbf62a0 |
| 21 Oct 12:30 | Instagram Hi Hi — @jesscallahanfitness — PM Pacific (3 days) | failed | App loading or VPN connectivity | f39efc7a-c3b5-4895-a229-2a52f63733fc |
| 22 Oct 00:30 | Instagram Hi Hi — @toniwhitfieldfitness — AM Pacific (3 days) | failed | Timing helper refusal | b2fd2ffc-7ffd-41fc-9d75-7d8620915cf1 |
| 22 Oct 01:45 | Instagram Hi Hi — @marisolortegafitness — AM Pacific (3 days) | failed | Timing helper refusal | 7c7ba80b-a6d1-47d3-b217-c812851f775b |
| 22 Oct 03:00 | Instagram Hi Hi — @jesscallahanfitness — AM Pacific (3 days) | incomplete | Checklist or cap verdict | b292f2ab-07b4-4706-b292-c1a9f0c88220 |
| 22 Oct 04:30 | Roxie search+engage — @roxie_bennett TikTok (US day + night, 19 Oct) | failed | App loading or VPN connectivity | 1d3dbde1-a912-420a-ac94-1b073ec36ac5 |
| 22 Oct 06:00 | Roxie search+engage — @roxie_bennett_ Instagram (US day + night, 19 Oct) | failed | App loading or VPN connectivity | 15480b6c-f30b-490d-a21e-032f6e61565f |
| 22 Oct 07:30 | Roxie search+engage — @roxiebennettfitness TikTok (US day + night, 19 Oct) | incomplete | Execution gaps | 49b4a98d-28c5-4ce8-987c-15a99b5bac5e |
| 22 Oct 10:00 | Instagram Hi Hi — @toniwhitfieldfitness — PM Pacific (3 days) | incomplete | Checklist or cap verdict | 44ac5fc0-575c-49e4-82ee-e9cce0045441 |
| 22 Oct 11:15 | Instagram Hi Hi — @marisolortegafitness — PM Pacific (3 days) | failed | Timing helper refusal | b3721fb5-df97-4d37-b4a1-2f0402b109e4 |
| 22 Oct 12:15 | Roxie search+engage — @roxie_bennett TikTok (US day + night, 19 Oct) | incomplete | Checklist or cap verdict | ed4f1ecd-b7fd-42e0-87dd-4ddefcf3a69a |
| 22 Oct 13:35 | Instagram Hi Hi — @toniwhitfieldfitness — AM Pacific (3 days) | incomplete | Execution gaps | ce474d85-3431-4028-b7f2-fbc8c2eb349a |
| 22 Oct 14:50 | Instagram Hi Hi — @marisolortegafitness — AM Pacific (3 days) | incomplete | Execution gaps | 5d191f26-268e-41de-ab47-0d9e2a490d37 |
| 22 Oct 14:55 | Roxie search+engage — @roxiebennettfitness TikTok (US day + night, 19 Oct) | incomplete | Execution gaps | 3aec75ac-7b8b-4c9d-8af8-6a38e5173ea2 |
| 22 Oct 16:05 | Instagram Hi Hi — @jesscallahanfitness — AM Pacific (3 days) | incomplete | Execution gaps | 141eb8ca-bd86-45b3-b61b-8e5e91f7c38a |
| 22 Oct 17:20 | Instagram Hi Hi — @toniwhitfieldfitness — PM Pacific (3 days) | incomplete | Execution gaps | 83fe9c8a-8e1f-449d-af1b-c05d85bbf7a5 |
| 22 Oct 18:35 | Instagram Hi Hi — @marisolortegafitness — PM Pacific (3 days) | failed | App loading or VPN connectivity | 1c9f0f12-5ec2-4d3d-9eb2-1582beb0720f |
