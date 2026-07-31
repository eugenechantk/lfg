# lfg iOS client — design baseline

**Goal:** capture every core state of the lfg iOS client as it exists today, and recreate it
in Claude Design as the "what it looks like now" baseline to redesign against.

**Captured:** 2026-07-31, iPhone 16e simulator (390 × 844 pt), **dark mode**, driven against a
live `lfg serve` host with 15 real sessions. Screenshots: `.claude/feature/baseline-ios-states/`.

**Claude Design project:** "LFG iOS SwiftUI Client" → page *LFG iOS Baseline*
https://claude.ai/design/p/3e135dff-613d-4bd6-914d-c2a3f617ad5c

Design system was deliberately set to **None** (not "Apple Design Guidelines") so the model
replicates the app rather than restyling it toward HIG.

---

## 1. Captured states

| # | File | What it shows |
|---|------|---------------|
| 01 | `01-connect-empty.png` | First-run `ConnectView`, empty URL field, both buttons disabled |
| 02 | `02-connect-probe-ok.png` | URL filled, green "Reachable" probe row, buttons enabled |
| 03 | `03-push-permission-prompt.png` | System push-permission alert over the session list |
| 04 | `04-list-status-grouping.png` | Session list, Status grouping — WORKING + UNREAD, "Connected · 1 running" |
| 05 | `05-list-status-scrolled.png` | Bottom of the CLOSED section with the "Load more" row |
| 06 | `06-list-directory-collapsed.png` | Directory grouping, all collapsed, running/idle count badges |
| 07 | `07-list-directory-expanded.png` | Directory grouping with LFG expanded |
| 08 | `08-list-search-active.png` | Search "codex" — WORKING / UNREAD / CLOSED headers all visible |
| 09 | `09-detail-running-toollines.png` | Detail: assistant prose w/ inline code, tool_use + tool_result lines, composer, "Running" |
| 10 | `10-detail-user-bubble-attachments.png` | Detail: user bubble + two attachment file cards + assistant prose |
| 11 | `11-detail-action-menu.png` | ⋯ menu — Stop / Switch model / Assign to / Rename / Mark as unread / Debug / End session |
| 12 | `12-new-session-sheet.png` | New session sheet: empty state + config pill bar + composer |
| 13 | `13-new-session-model-picker.png` | Model picker menu open over the new session sheet |
| 14 | `14-settings.png` | Settings, single host, push registered |
| 15 | `15-host-edit.png` | Edit host form (default host, remove host) |
| 16a | `16-host-add-empty.png` | Add host form, empty |
| 16b | `16-host-add-unreachable.png` | Add host with orange "Unreachable" probe row |
| 17 | `17-settings-multihost.png` | Settings with two hosts — one green, one orange |
| 18 | `18-list-multihost-offline.png` | List in multi-host mode: per-host top-bar chips, host pill on every row |

**How states 16b/17/18 were produced:** a bogus second host (`Air` → `http://127.0.0.1:9999`)
was added through the real Settings UI on the throwaway session simulator. That is the only
deterministic way to reach the multi-host and offline-chip rendering without downing a real host.

---

## 2. Not captured — gaps in the baseline

These components exist in the code but were unreachable by driving the live app, because each
needs a condition that can't be forced without disrupting a real running agent or host:

| Component | Needs | Source |
|---|---|---|
| `PromptPanelView` | an agent mid-`AskUserQuestion` | `Components.swift:196` |
| `PausedBannerView` | `statusReason == out_of_credits` / `model_unavailable` | `Components.swift:279` |
| `PendingStripView`, `OptimisticUserBubble` | a send in flight / queued offline / failed | `Components.swift:327,375` |
| `ThinkingView` | a transcript containing a `thinking` message | `Components.swift:133` |
| `EmptyListState`, `ConnectionBanner` | zero sessions / all hosts down | `SessionListView.swift:623`, `RootView.swift:145` |
| `OfflineComposerNotice` | open session on an unreachable host | `SessionDetailView.swift:529` |

To close these, either stand up a stub server that returns the required shapes, or accept them
as spec-derived and build them from the Swift source.

---

## 3. Design tokens (extracted from `Theme.swift` + iOS dark semantics)

| Token | Value | Used for |
|---|---|---|
| bg | `#000000` | screen + grouped-list background |
| bg-secondary | `#1C1C1E` | list rows, cards, form cells |
| bg-tertiary | `#2C2C2E` | menus, popovers, raised surfaces |
| label | `#FFFFFF` | primary text |
| label-secondary | `rgba(235,235,245,0.60)` | subtitles, captions |
| label-tertiary | `rgba(235,235,245,0.30)` | counts, timestamps, chevrons |
| separator | `rgba(84,84,88,0.65)` | row hairlines |
| fill-tertiary | `rgba(118,118,128,0.24)` | agent badge tile, host pill |
| fill-quaternary | `rgba(116,116,128,0.18)` | model badge, search field, tool line |
| blue | `#0A84FF` | accent, user bubble, links, prompt panel |
| green | `#30D158` | working, reachable, push registered |
| orange | `#FF9F0A` | offline, paused, unreachable, **claude agent tint** |
| red | `#FF453A` | destructive, failed |
| purple | `#BF5AF0` | unread status dot |
| indigo | `#5E5CE6` | **codex agent tint** |
| teal | `#40C8E0` | **opencode agent tint** |

Status dot mapping (`Theme.statusColor`): needsInput → blue, blocked → orange, working → green,
unread → purple, idle → secondary gray, closed → secondary @ 45%.

Type: SF Pro. headline 17/600 · body 17 · subheadline 15 (row titles 15/500) · caption 12 ·
caption2 11 (section headers 11/600 uppercased). Monospace for tool lines, paths, ids.

Geometry: list card 10pt radius · user bubble 14pt (12/8 padding, 36pt min leading gutter) ·
tool line 8pt (10/6 padding, 3-line clamp) · prompt panel 14pt (blue 8% fill, blue 25% stroke) ·
composer 24pt glass panel · agent badge 28×28 @ 7pt · status dot 8pt · host-chip dot 7pt ·
directory count dot 6pt.

---

## 4. Method notes (for repeating this)

- Per-session simulator `lfg-53b306d3` / `921AB295-4797-4CC5-8BE8-DE535EC00542`, dark mode set
  via `flowdeck ui simulator set-appearance dark`.
- `flowdeck ui simulator scroll` silently no-ops; use `swipe --from x,y --to x,y --duration 0.15`.
- Nav-bar toolbar buttons and segmented-control segments ignore `tap "<label>"` — use
  `tap --point x,y` with coordinates read off the screenshot.
- Claude Design accepts **10 attachments per message**; excess is silently dropped with a
  "Keeping the first 10 files" toast. Batch accordingly.
- The Claude Design project chat has no scriptable `<input type=file>` (native picker), so
  follow-up states had to be specified in text rather than uploaded.
