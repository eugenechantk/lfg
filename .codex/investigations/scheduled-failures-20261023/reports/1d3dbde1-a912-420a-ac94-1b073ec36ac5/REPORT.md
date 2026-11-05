Final feed: not collected; direct rate, broader rate, and distinct matching creators are unknown.
Change from initial and prior final: unknown. Latest collected prior final was 2/20 direct (10%) from two creators.
Engagement: zero new verified likes, saves, follows, and Not interested actions.

# Roxie TikTok recovery run — 22 October 2026

Verdict: **error**. TikTok connectivity prevented target-account verification. The approved Surfshark recovery did not confirm reconnection. The required 60-minute session did not run.

## Identity and reservation

Task: c127b235-8d75-4a7c-8df2-4a1b13f5fefd.
Run: 1d3dbde1-a912-420a-ac94-1b073ec36ac5.
Reservation: 22 October, 04:30 HKT. Host start: 04:30:22.592. Hard deadline: 05:35 HKT.
The live scheduledFor was 1792614600000, matching this recovery reservation. The disabled finite task and empty nextRunAt were expected.
Preflight, recovery, and final scheduler snapshots showed only this active run. No schedule changes occurred.
The existing phone_assignment helper reports hihi only. Full scheduler snapshots independently established dumb dumb ownership; see ownership-verification.json.

FlowDeck discovered dumb dumb over USB, UDID 00008140-00124C2A26E3001C. The existing named session was ready in video mode.
Wake succeeded, and the fresh screenshot showed Settings without an authentication prompt. Disk had 44 GiB available.
All phone commands passed through timing.py. No driver changes, new sessions, WDA restart, accessibility-tree query, or blind gesture replay occurred.

The helper was initialized with this Run ID, live UDID, exact account, Roxie profile, and 04:30 reservation.
phase-appointments.md records every absolute TikTok appointment. The helper has Instagram-like intermediate phase boundaries; it was not modified.
Final sample remained appointed for 05:18, cleanup for 05:27, and hard stop for 05:35. The error stop ended content work earlier.

## Failure and bounded recovery

| HKT | Observed step | Evidence |
|---|---|---|
| 04:31:20 | Fresh wake screen showed Settings. | evidence/001-awake.jpg |
| 04:31:39 | Profile showed @roxiebennettfitness and No internet connection. | evidence/004-profile.jpg |
| 04:31:44 | Signed-in selector included roxie_bennett. | evidence/005-selector.jpg |
| 04:31:49 | Selected target once; Loading appeared on the starting Profile. | evidence/006-target-switch.jpg |
| 04:32:17 | Loading ended; original handle and connection error remained. | evidence/008-switch-state.jpg |
| 04:32:24 | One visible retry produced Couldn't connect to the internet toast. | evidence/009-retry.jpg |
| 04:32:39 | Surfshark showed Connected to United States, dedicated IP 172.216.113.196. | evidence/011-vpn.jpg |
| 04:32:45 | Disconnect confirmation offered a separate Disconnect action; selected it once. | evidence/012-vpn-disconnected.jpg |
| 04:33:01 | Not connected was visible; location/server remained unchanged. | evidence/014-vpn-disconnect-state.jpg |
| 04:33:06 | Selected Connect once. Surfshark began Connecting to the same dedicated IP. | evidence/015-vpn-reconnecting.jpg |
| 04:34:36 | Last inspection still showed Connecting. Connected was never verified. | evidence/020-vpn-final.jpg |
| 04:34:43 | Preview stop returned running=false. | preview-stop.json |

The recovery window ran from 04:31:39 to the final recovery inspection at 04:34:36, within three minutes.
The app's own connection-attempt indicator changed during the single reconnect request. No further connect request or server change was sent.
No social browsing, engagement, or sampling occurred while the VPN was disconnected or reconnecting.
The target switch remained stuck, so no additional temporary-account cycle ran. The actual starting handle was inspected before VPN fallback.
The target handle was never verified. Its current liked, saved, and followed post states could not be inspected.
Prior reports were read, including the 20 October incomplete run and 21 October connectivity error. No historical gesture was replayed.
No unintended engagement, action block, sign-in, CAPTCHA, or sharing screen was observed.

## Required work and measurements

The initial ten-post sample, all five US-day queries with six to eight fitting watched results each, both training phases, and final twenty-post sample remain unperformed.
There are no watch timers, post observations, or engagement receipts because target verification never passed.
Thirty required new verified likes remain missing. Saves and follows have no required minimum.
Direct and broader rates and matching-creator counts are null, not zero. Empty collected sample sizes are zero.
Verified playback duration is unknown. Opening TikTok before account verification did not count as assigned-account viewing.

Latest collected same-account final: 2/20 direct (10%), 13/20 broader (65%), two matching creators, from run 01e1861c-3572-4614-a04f-de14d8919b90.
The 21 October failed run collected no final. The older 19 October final was 2/20 direct (10%) and 5/20 broader (25%).
No current comparison or tuning verdict is possible. Small samples do not establish cause.

Checks and recovery occupied about 4.3 minutes after the reservation. Content-phase time was zero.
No required phase was claimed from elapsed time or helper output. The helper reports missing mechanical checks; the agent assigns error because app/VPN failure prevented work.

## Cleanup and evidence

Preview stop reported no active preview. The reusable session stayed alive. No power event was sent; end locking is optional.
Target Profile restoration failed because target switching and VPN restoration remained unresolved.
The phone was left on Surfshark's reconnect screen, preserving its selected server and connection attempt. Final VPN restoration remains unverified.
No further content work or recovery attempt was made.

result.json holds null sample rates, zero verified actions, every unperformed query, incidents, comparison, and cleanup state.
helper-run.json and helper-events.jsonl preserve immutable identity, dispatch, capture, and timing evidence.
helper-result.json and helper-report.md list missing checks. Twenty screenshot sets preserve the observed screens.
