# Improvement Log — Session 0c5762d2

## Tracker

- [ ] 2026-08-13 — Added a sidebar toggle without first checking what SwiftUI already renders; shipped a duplicate button into the simulator
- [ ] 2026-08-13 — No iPad simulator existed and the FlowDeck guard only ever provisions `iPhone 17 Pro`, so iPad-only work has no sanctioned device
- [ ] 2026-08-13 — Headless simulators cannot be rotated; landscape-specific iPad behaviour is unverifiable with the current toolchain
- [ ] 2026-08-13 — Verified a gesture by performing it ONCE; the second attempt was broken and I nearly shipped it
- [ ] 2026-08-13 — A selection-dependent `listRowBackground` silently broke List selection; caught only by A/B-ing against a stashed baseline

## Log

### 2026-08-13 — Built a toggle before checking what the system already draws

**What happened:** Eugene asked for a collapsible sidebar on iPad. I read `RootView`, saw `columnVisibility` bound with no control driving it, and immediately added a `topBarLeading` toggle. The first simulator screenshot showed **two** identical `sidebar.leading` buttons side by side — SwiftUI renders its own toggle whenever the sidebar is hidden, and mine sat next to it.

**Why this was wrong:** The premise ("there is no control") was half true and I never tested which half. The accessibility dump settled it in one call: system `Show Sidebar` at x=14, mine `toggleSidebar` at x=71 — and in the sidebar-*visible* state the system button vanished entirely. That is the actual gap: SwiftUI gives you "bring it back" and never "put it away". Knowing that changed the fix from "add a button" to "remove the system's half-toggle (`.toolbar(removing: .sidebarToggle)`) and own both directions".

**What better looks like:** For any "there's no control for X" request on an Apple platform, capture the current screen + accessibility tree **before** writing the control. The system may already render part of it, and which part it renders determines the design. One `flowdeck ui simulator screen --json` up front would have skipped a whole build-and-verify round trip.

### 2026-08-13 — No sanctioned iPad simulator for iPad-only work

**What happened:** `flowdeck simulator list` had eleven simulators, none an iPad. The guard's `PREFERRED_DEVICE` is hardcoded to `iPhone 17 Pro`, so its auto-provisioned session sim was also an iPhone — useless for a split-view feature. I created `cc-0c5762d2-ipad` (iPad Pro 11-inch M4) inside the session namespace, which the guard accepted because it only gates `run`/`test`/`ui simulator` by name prefix.

**Why this matters:** The house rule "always verify on iPhone 17 Pro" is about screenshot comparability, but it silently blocks any iPad-only surface (split view, multitasking widths, pointer/keyboard). The escape hatch — create inside `cc-<sid8>-*` and pass the UDID explicitly — works but is undocumented, and finding the device-type *identifier* (`--device-type` rejects display names; it needs `com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB`) cost two failed attempts.

**What better looks like:** Note in the iOS instructions that iPad-only work provisions `cc-<sid8>-ipad` in-namespace, and that `simulator create --device-type` takes the identifier from `simulator device-types --json`, not the display name. Shut the sim down when done.

### 2026-08-13 — Landscape on a headless simulator is unreachable

**What happened:** The interesting iPad case is landscape (both columns pinned open). FlowDeck exposes no orientation command (`ui simulator rotate` is a two-finger *gesture*), `simctl` is guarded, and driving Simulator.app via AppleScript was impossible — a throwaway `screencapture` came back 100% black, so the display was asleep.

**Why this matters:** I verified both split states (`doubleColumn` and `detailOnly`) in portrait, which is what the code branches on — but "verified in landscape" would have been a claim I could not back. The black-frame check took one command and correctly stopped me from burning time on GUI automation dead ends.

**What better looks like:** Treat orientation as untestable headless: exercise the *state* the code keys off, say plainly which axis was not covered, and reach for a device build if the orientation itself is load-bearing.

### 2026-08-13 — Verified a gesture once, and once passed while twice failed

**What happened:** I added swipe-to-dismiss to the iPad sidebar, drove the swipe in the simulator, saw the sidebar collapse, and moved on. Only when capturing a final screenshot — which happened to be the *second* dismissal in that app run — did the sidebar stay put with a row's swipe action hanging open instead. The gesture worked exactly once per launch.

**Root cause:** the standard "already fired" latch. `@State var fired` set in `onChanged`, cleared in `onEnded` — except the action *hides the sidebar*, which tears down the view the gesture is attached to, so `onEnded` never arrives. The flag stayed true for the life of the app and every later swipe was silently ignored. Fixed by deleting the latch and making the action idempotent (`setSidebar` early-returns when already in the target state).

**Why this was wrong:** a one-shot verification cannot distinguish "works" from "works once". That failure mode is *specific to gestures whose action destroys their own view*, which is most sidebar/sheet/dismiss gestures — exactly the code where a latch is most tempting.

**What better looks like:** for any gesture or transient control, drive it **three times in a row** and assert the state after each. It cost one loop to catch this; without it the bug ships and reads as "the swipe is flaky". Same rule for anything with a `@State` flag cleared in a completion callback: ask what happens if the callback never fires, because view teardown means it often doesn't.

### 2026-08-13 — Colliding gestures separated by measurement, not by guessing

**What happened:** the sidebar's rows already own trailing `swipeActions` (hide-directory), so "swipe left to dismiss the sidebar" and "swipe left to reveal a row action" are the same gesture. My first attempt fired on `onEnded` at 80pt and left the row sitting open behind the dismissed sidebar — one stray tap from muting a directory.

**What fixed it:** measuring the actual thresholds in the simulator rather than reasoning about them — a row reveals at ~55pt, so firing at 60pt **from `onChanged`** cancels the row's half-finished reveal mid-drag. Short flick = row action (feature preserved), decisive swipe = dismiss, no leftover state. Verified by binary-searching the swipe distance (45 / 55 / 70pt) against the accessibility tree.

**What better looks like:** when a new gesture shares a direction with an existing one, measure where each engages and place the new threshold past it, then assert the *other* gesture still works afterwards. Both halves need a test — it is very easy to "fix" a collision by quietly destroying the older feature.

### 2026-08-13 — A cosmetic row background broke List selection, and only an A/B caught it

**What happened:** adding a selected-state tint via `.listRowBackground(...)` computed from `selection` made tapping an unread row open it and then *immediately deselect it* — the detail column emptied. Nothing about the change suggested it could touch behaviour; it was a colour.

**Why it happened:** an unread row re-sections the instant you open it (it becomes read and leaves the Unread group). A `listRowBackground` that varies with selection rebuilds the cell's background configuration in that same update, the row loses its tag mid-diff, and the List clears `selection`. Moving the pill to a `background` on the row's *content* — leaving `listRowBackground` a constant — fixed it.

**How it was caught, and the mistake inside the catch:** I first "confirmed" it was pre-existing with ONE trial on a stashed baseline. That is the same single-trial error logged above, made twice in one session. The list churns constantly (live sessions re-sort), so a single trial is noise. The real answer came from `git stash` + 6 trials per build: baseline 6/6 kept the session open, the `listRowBackground` variant failed twice in a row, the fixed variant 6/6.

**What better looks like:** (1) a visual-only change to a `List` row is NOT behaviour-free — anything that varies with `selection` participates in cell diffing, so exercise selection after making one; (2) when deciding "is this pre-existing?", stash the change and run the SAME harness N times on both builds. One trial each is a coin flip presented as evidence.
