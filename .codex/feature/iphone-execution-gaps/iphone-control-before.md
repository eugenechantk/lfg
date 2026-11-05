---
name: iphone-control
description: >-
  Drive Eugene's physical iPhone over USB from the CLI — unlock, launch any app (App Store apps included), read the screen as an accessibility tree, tap, type, swipe, screenshot, and screen-record — using Appium XCUITest + WebDriverAgent. Use for any task that needs the real phone: installing/testing App Store apps, walking an onboarding flow, reproducing a bug on device, capturing evidence. Prefer this over iPhone Mirroring (phone-harness) for driving; it does not depend on Wi-Fi or the Mac being unlocked.
---

# iphone-control

CLI control of the physical iPhone through Appium's XCUITest driver over USB. WebDriverAgent runs on the phone and exposes the accessibility tree, so every app is driven by its real labels and buttons, not pixels. Nothing here needs Wi-Fi, Bluetooth, iPhone Mirroring, or the Mac to be unlocked.

Scripts live in `~/.claude/skills/iphone-control/scripts/`. Runtime state (config, session id, Appium log) lives in `~/.iphone-control/`. Setup and failure modes are in `install.md`.

```bash
S=~/.claude/skills/iphone-control/scripts
$S/server.sh start            # Appium on :4723 with keep-alive + screen-record enabled
$S/phone.py ensure --wait 15  # returns ready=true, or the same background startup job to poll
$S/phone.py wake              # unlock + dismiss lock screen (passcode must be off)
$S/phone.py app com.apple.AppStore
$S/phone.py screen            # text + tappable choices with coordinates
```

## More than one phone

Unset, every command drives the default phone (`~/.iphone-control/config.json`, currently calmer). To drive another phone **side by side** on the same Appium server, prefix every command with `IPHONE_CONTROL_DEVICE=<device name>`:

```bash
export IPHONE_CONTROL_DEVICE=hihi
$S/phone.py setup     # matches the USB iPhone by name; allocates its own WDA local port (8101+)
$S/phone.py ensure    # own session file + own WDA build dir under ~/.iphone-control/devices/hihi/
```

Never re-run plain `phone.py setup --udid <other>` to switch phones: it overwrites the default config and orphans whatever session is driving it.

## When to use which tool

| Need | Use |
|---|---|
| Drive the phone: taps, typing, app launch, onboarding flows, App Store installs | **iphone-control** |
| Screenshot or screen recording from the device | **iphone-control** (`shot`, `rec`) |
| Read a secure screen (passcode entry, some payment sheets) or the phone has a passcode and is locked | `phone-harness` (iPhone Mirroring) — needs the Mac unlocked |
| Simulator, not device | `flowdeck ui simulator` |
| TikTok / Reels / Shorts or any app with a playing video | **iphone-control in `mode video`** (see Video apps); plain taps hang |

## Preconditions (say these to Eugene before a long step)

- Phone on USB, Developer Mode on, trusted.
- **Passcode off** for headless `wake`. With a passcode on, the phone must already be unlocked and Auto-Lock set to Never; XCUITest cannot see or type on the passcode screen.
- Face ID is off whenever the passcode is off, so Apple purchase sheets ask for the Apple Account password.

## Workflow

1. **Start**: `server.sh start`, `phone.py ensure --wait 15`. Continue only when `ready=true`. A pending startup returns a job and exit code 3; poll `ensure` to reuse it. `doctor` checks USB, signing, Appium, session, and lock state. First time: `setup`; with several phones, select by name or UDID. If locked, run `wake`. See `install.md` for pairing and signing.
2. **Look before acting**: `phone.py screen` is the primary sense. It prints the on-screen text and every visible tappable element with `@(x,y wxh)`. Use `phone.py shot out.png` and view it only when the tree is ambiguous (icons without labels, layout questions). `phone.py buttons` lists off-screen buttons too, useful when the continue button is below the fold.
3. **Scroll long views**: `phone.py swipe up` scrolls down one screen (`down` scrolls up), verified in Safari web pages and native lists. `phone.py scrollto "<text>" [up|down] [--n=12]` swipes until the text is on screen and reports how many swipes it took; use it to reach a section or a button below the fold. Do not use Appium's `mobile: scroll` with a predicate inside web views; it hits its max scroll count and hangs.
4. **Act by label**: `taptext "Continue"` tries exact matches, then substrings only when no exact match exists. Separate duplicate targets return candidates; select their reported `--index`. On UI errors, inspect the attached screenshot before retrying. Type with `typeid <id> <text>` or tap a field and use `type`. Both support `--file`, `--replace`, `--append`, and `--verify`. Use `hold x y [seconds]` for long presses.
5. **Observe at decision points**: use `--observe tree` or `--observe screenshot` on an action to receive the next screen in one call. Verify important text and final outcomes. Known short paths can use `batch`; stop at unknown pages or partial results. An accepted command does not prove task success.
6. **Launch apps by bundle id**: `phone.py app <bundleId>`. Unknown id: `phone.py bundle <display name>`. Useful ids: App Store `com.apple.AppStore`, Settings `com.apple.Preferences`, Safari `com.apple.mobilesafari`.
7. **Onboarding quizzes**: `auto.py --steps 12 --prefer "Not Now,Maybe later,Continue,3 days a week"` advances by preferred answers and stops at account/paywall/purchase screens, cycles, or when nothing preferred is visible. Read its stop reason, then take over manually. Keep the first run short (`--steps 3`) until you have seen it behave on that app.
8. **Evidence**: `rec start` before the flow, `rec stop out.mp4` after. Stop streams the native video through a temporary loopback receiver, avoiding a large base64 JSON response. Use a new output path. `rec status` checks whether recording is active. Verify the file with `ffprobe`; shrink for sharing with `ffmpeg -i in.mp4 -vf scale=604:-2 -crf 28 -an out.mp4` (width must be even). Give the full absolute output path.
9. **Finish**: stop the preview, then `phone.py lock`. It sends a power-button event only when unlocked and confirms the lock state within five seconds. Leave the Appium server and session alive for reuse.

## Settle, identify, act, verify — all apps

Use this directive when an app launches, a page changes, a menu opens, results load, or the layout moves.
An accepted command is not proof that the intended screen has appeared.

1. **Settle:** inspect a fresh screen after the transition. If loading or animation still moves controls, wait briefly and inspect again.
   For an unstable target, require two observations showing the same control and position before tapping.
   Compare the control area, not changing video frames. Keep waits short and within the task's deadline.
2. **Identify:** locate the intended control in the latest observation. Confirm its label or icon, surrounding context, and current bounds.
   Prefer a stable accessibility identifier in normal apps. In video mode, use the screenshot and its coordinate sidecar.
   Recompute coordinates after scrolling, menu changes, keyboard movement, account switches, or new results.
3. **Act:** send one input to the identified control. Do not reuse old coordinates across a transition or chain blind taps.
4. **Verify:** inspect the resulting screen or changed state before the next action.
   If it differs from the intended result, classify the actual state and choose the next action from a fresh observation.

After launching an app from a video app, confirm the new app's visible chrome before using normal-mode accessibility commands.
A launch can return while the old app is still visible. Do not query a playing video app's tree to check the launch.
If controls do not settle within a short bounded wait, use the task's loading-recovery rule instead of guessing a target.
A timed-out action may have executed: inspect once before deciding what remains, and never replay it blindly.
This is an agent directive using existing commands. It does not require a new controller or changes to the phone scripts.

## Video apps (TikTok, Instagram Reels, YouTube Shorts)

Some video players block accessibility queries. WDA commands that resolve the active application can hang for minutes: ordinary taps, swipes, trees, and session creation. Each hung command also blocks the queue. `waitForIdleTimeout: 0` does not solve this. The upgraded `ensure` and `status` use settings queries instead of active-app geometry probes.

```bash
$S/phone.py front com.apple.Preferences   # (only if no session yet) get the video app out of the way
$S/phone.py ensure
$S/phone.py mode video                    # WDA targets SpringBoard; never touches the app's AX tree
$S/phone.py front com.zhiliaoapp.musically
$S/phone.py shot /tmp/v.png --max 560     # sense with screenshots only; view /tmp/v.jpg
$S/phone.py wswipe up                     # next video, ~0.75 s
$S/phone.py wdtap 200 400                 # double-tap = like (never un-likes)
$S/phone.py wtap 371 582                  # any button, coordinates read off the screenshot
$S/phone.py type "text"; $S/phone.py enter  # keyboard works unchanged
$S/phone.py mode normal                   # back to label-based driving for normal apps
```

- **Coordinates come from the screenshot**: logical points = screenshot pixels ÷ 3 (or × 402/width of the downscaled JPEG on a 402-pt-wide phone).
- `shot` now returns an image sidecar with exact `pixel_to_point` values. Prefer those values over fixed device assumptions.
- Video mode rejects accessibility commands before sending them. Use `observe --mode screenshot`, `front`, and W3C gestures. Plain focused `type` remains available; field verification needs normal mode.
- `wdrag x1 y1 x2 y2 [seconds]` provides a video-safe drag for visible sheet handles and custom regions.
- **Unstick a hang without restarting WDA**: `front com.apple.Preferences`. With the video app in the background, the stuck command fails fast and the queue drains in seconds. Then `front <app>` resumes the same screen.
- **Never kill the WDA `xcodebuild` and never wrap `ensure` in `timeout`.** Orphaned session creations keep running server-side and kill each other's xcodebuild, so WDA never comes up (cost 40 min on 2026-10-03). If it happens, wait for every pending `POST /session` in `server.sh log` to fail out, then run one `ensure`.
- TikTok playbook with right-rail coordinates and the engagement routine: `~/dev/personal/AiTinder/.claude/tiktok-warmup/playbook.md`.

## Structured workflows and recovery

Read `references/workflows.md` for structured observations, targeting, text continuation, bounded waits, batches, list collection, and metrics.

Every device has a shared operation lock keyed by UDID. Startup runs in a detached worker. Another caller reuses its job rather than creating a second session.

Errors report `action_state`: `not_executed`, `executed_unverified`, or `uncertain`. A timeout does not cancel the server action. Read actual state before repeating a mutation. A batch reports `completed_steps` and `stopped_at`; never replay the whole batch.

`front` deliberately bypasses the WDA operation lock so it can release a hung video-app query. After an orphaned startup, `adopt` can reuse exactly one existing Appium session for that UDID. It never creates a session.

## Optional live preview

Preview is off by default. `phone.py preview start` returns a local browser URL. It uses an independent USB MJPEG stream at 3 fps and 50 percent scale.

Open the URL to view the phone. Hidden pages stop renewing a three-second capture lease. `preview pause` stops capture and clears pixels; `preview stop` also restores stream settings. Pause before authentication. See `references/preview.md` for details and performance measurement.

## App Store installs

Open `com.apple.AppStore`, `tapid AppStore.searchField`, `type <name>`, `enter`, then `screen`. Results carry `AppStore.offerButton[state=get|redownload|downloading|open]` buttons; tap the one on the organic result, not the `Advertisement` row. Redownloads of previously-owned free apps install with no prompt. A first-time free install or a paid one raises Apple's sheet — that tap and any password are Eugene's. Poll `screen` until the state is `open`.

## Hard stops (hand to Eugene, do not drive through)

- Account creation and sign-in of any kind, including Sign in with Apple and Google.
- Apple purchase and subscription confirmation sheets, and any password prompt.
- Anything outward-facing from his real phone: sending messages, posting, payments, changing settings that outlive the session.
Say what screen you stopped on and what tap is his, then resume when he says so.

## Gotchas

- **Chat-style onboarding echoes the previous answer as a button** near the top (y < 200). Tapping it goes back a step. `auto.py` filters these; do the same when tapping manually.
- **Lock screen swipe**: `mobile: swipe up` scrolls the notification list. Dismissing the lock screen is a quick edge drag from the phone's real bottom edge (hold ≤0.05 s; `wake` reads the screen height and does it for you). A 0.25 s hold unlocked hihi but left the display dark and the tree empty.
- **`wake` order**: home press to light the lock screen, then the edge swipe; WDA's `mobile: unlock` is only the fallback, because it times out on hihi (iOS 26). Verified twice on hihi from an Auto-Lock sleep, ~5 s each. The 17 Pro (calmer) is untested on the new order; if it misbehaves there, the fallback is the old path.
- **Secure screens go dark**: passcode entry and some StoreKit sheets return a black screenshot and an empty tree. That is Apple, not a bug. Do not blind-tap on them.
- **Session dies on reboot or passcode changes** with `socket hang up`. Use `doctor`; `ensure` creates a session only after confirmed absence. A transport failure remains uncertain. Turning the passcode off can reset lockdown pairing (`InvalidHostID`): re-pair per `install.md`.
- **Notification previews on the lock screen are readable** by `screen`. Don't print or keep them; `wake` first.
- **Don't grep for the device by list position**; match the UDID. The FlowDeck list is long and the iPhone is usually last.
- **Long steps**: the first WDA install can wait up to 30 minutes for an unlock. Run it in the background with a log, and tell Eugene what the phone needs before starting.
- **Safari's address bar** has label `Address` but no accessibility id: `taptext Address`, then `type <url>`, `enter`.
- Port 8766 is LFG's. The server refuses it.
- **Lock uses a power-button event**: legacy `mobile: lock` can time out on iOS 26 and 27. `phone.py lock` checks state, sends one 0.5-second IOHID Power press, then polls for confirmation. Repeated calls while locked do not press Power again. Failures never replay the press; inspect state before retrying. `locked` can disagree with the display right after a bad swipe. Use `wake` before reading the screen, so notification previews are not exposed.
- **SpringBoard tips (e.g. "Edit Home Screen") ignore `taptext`**: it prints `tapped` but the sheet stays. Use `tap x y` on the button centre from `screen`, then re-check.
- **The first `shot` after `wake` can be all black** while the display powers up. Take it again before concluding it's a secure screen.

## Debug mode

If the user includes `[DEBUG]` in the prompt:

1. Create `debug/iphone-control-<YYYYMMDD-HHMMSS>.md` in the cwd.
2. Header: `# Debug Log: iphone-control`, timestamp, the task, the phone UDID and iOS version from `phone.py status`.
3. After each major step (server/session start, wake, each app launch, each `auto.py` run, each manual tap sequence, recording start/stop) append:
   `## Step N: <name>` with **Reasoning**, **Command(s)**, **Screen before** (the `screen` output, trimmed), **Result**, **Decision**, **Next**.
4. Copy every screenshot taken during the run into `debug/` and reference it from the step.
5. On any error, append the `phone.py` error text and the last 30 lines of `server.sh log`.
6. End with `## Summary`: steps completed, where it stopped and why, what was handed to Eugene, key decisions.
7. Print the debug file path in the conversation.
