# Feature: iPad layout pass

Tier: product (lfg ships to TestFlight with `TARGETED_DEVICE_FAMILY = "1,2"`).

## Audit (2026-10-17, build of the current tree on iPad Pro 11" sim, iOS 26.3, dark)

Screenshots: `.claude/ipad-audit/shots/` (portrait 834×1210, landscape 1210×834).

What already works and stays:
- Two columns (list sidebar + session or task) in both orientations.
- The session sheet, Files & links and Settings open as centered form sheets.
- Search opens at the bottom of the sidebar; the list ••• menu is a popover.
- Task detail reads well in portrait.

Problems, iPad only:
1. **Cold launch in portrait shows an empty screen.** The split view starts at `.automatic`, which hides the sidebar in portrait. The first screen is "No session selected" and one small button (`01-launch-portrait.png`).
2. **Lines are far too long in landscape.** The transcript and composer fill the detail column: ~840pt (≈115 characters a line) with the list, ~1180pt (≈150) without it (`12-…`, `13-…`). Task detail stretches the same way: Run now and Pause become 400–560pt wide (`14-…`, `15-…`).
3. **Two buttons do one job in the session top bar.** The pill holds "show/hide list" and a back chevron. In two columns the chevron only clears the selection and shows the list, which the list button already does (`03-…`, `12-…`).
4. **New session is a full-screen page with a composer 810–1190pt wide** and a mostly empty screen (`08-…`).
5. **The Sessions and Tasks sidebars do not match.** Tasks: square, edge-to-edge selection fill and row chevrons. Sessions: inset rounded selection, no chevrons. The task view's list button is a lone circle; the session view's is a pill (`06-…`, `15-…`).

Noted, not changed in this pass (see Decision Log): hiding the list also hides the Sessions/Tasks switcher; the hidden state is shared by both tabs; only one hardware-keyboard shortcut exists (⌃⌘S).

## User Story

As Eugene on an iPad, I want lfg to use the big screen like an iPad app — list beside the work, text at a comfortable line length, no duplicate controls — so reading and steering sessions is easier than on the phone, not harder.

## User Flow

1. Open lfg on the iPad in portrait or landscape → the session list is showing beside the detail.
2. Tap a session → the transcript and composer sit in a centered reading column; the list stays.
3. Tap the list button → the list hides; the column stays centered at the same width. Tap again → the list returns.
4. Tap + → New session opens with the composer in the same centered column.
5. Switch to Tasks → the sidebar rows and selection look like the Sessions sidebar; the task detail uses the same centered column.

## Success Criteria

- [x] SC1: On an iPad in portrait and landscape, a cold launch shows the session list beside the detail. — **Verify by:** cold launch on the iPad sim in both orientations, screenshot.
- [x] SC2: In regular width, transcript rows, the pending strip, pills, needs-input panel and composer sit in one centered column no wider than the board's column width; the phone layout is unchanged. — **Verify by:** landscape screenshots with and without the list, measured against the canvas board; iPhone 17 Pro screenshot vs. before.
- [x] SC3: In two columns, the session top bar has the list button only (no back chevron); the phone keeps its back button. — **Verify by:** iPad + iPhone screenshots.
- [x] SC4: New session in regular width keeps the composer and empty state inside the centered column. — **Verify by:** iPad landscape screenshot vs. board.
- [x] SC5: Task detail content in regular width sits in the centered column. — **Verify by:** iPad landscape screenshot vs. board.
- [x] SC6: Tasks sidebar on iPad uses the Sessions sidebar selection style (inset rounded fill) and drops row chevrons; phone and Mac task lists are unchanged. — **Verify by:** iPad screenshot vs. board; iPhone screenshot; desktop target still builds.
- [x] SC7: The layout rule (which width gets the column, how wide) is unit-tested in LFGCore. — **Verify by:** `swift test --filter ReadableColumn`.

## Platform & Stack

- iOS 26 SwiftUI app (`ios/LFG`), shared task views (`shared/`), LFGCore package tests.

## Steps to Verify

1. `flowdeck run -S <iPad udid>`; rotate with Simulator.app (Device › Rotate Left) after `lfg-unlock unlock`.
2. Capture each state; compare with the canvas boards served locally (see memory `render-canvas-boards-locally`).
3. `cd ios/LFGCore && swift test`.
4. iPhone 17 Pro run for the no-regression check.

## Implementation Phases

### Phase 1: Launch + session view
- Scope: default split visibility; readable column for transcript and bottom chrome; drop the back chevron in two columns; wider user bubble cap in the column.
- Covers SC1, SC2, SC3, SC7.

### Phase 2: New session + tasks
- Scope: new session column; task detail column; tasks sidebar selection style and chevrons on iPad.
- Covers SC4, SC5, SC6.

## Design

Canvas "LFG UI Map", page **iPad (Oct 17)** (https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD): row 1 `ip-today-*` (audit screenshots with numbered pins), row 2 `ip-launch`, `ip-session-portrait`, `ip-session`, `ip-session-full`, `ip-new`, `ip-task`; stickies `ipAudit`, `ipLater`, `ipChanges`, `ipKeeps`. Generator: session scratchpad `canvas-ipad/gen.py`. Boards were redrawn once after measuring the app (detail column starts at x=330, not 340).

## Implementation

- `LFGCore/ReadableColumn.swift` (+ `ReadableColumnTests`): column cap 720 (16pt padding inside), centered; user-bubble text cap 480 in a column ≥ 600, else 290. Keys off the offered width only, so a phone (402) is unchanged.
- `SessionDetailView`: transcript `LazyVStack` and the bottom chrome (pills, pending strip, sign-in rows, needs-input panel, composer) framed to the column; publishes `transcriptColumnWidth` to the rows.
- `Components.TextBubble`: `CappedWidth(ReadableColumn.userBubbleTextCap(…))`.
- `RootView`: iPad starts `.detailOnly` and the post-render `.task` animates to `.doubleColumn`; the size-class fallback restores `.doubleColumn`; the two-column back chevron (`session_back_to_list`) is gone.
- `NewSessionView`: composer framed to the column; the empty-state hint is a `ViewThatFits` (74pt top, 16pt top, none) so the composer stays above the landscape keyboard.
- `shared/ScheduledTasksView`: iOS task detail content and Ask bar framed to the column; iPad sidebar list painted `systemBackground` (#1C1C1E), selection is an inset rounded `accentColor 0.14` wash with no bottom hairline, rows without chevrons (`TaskRowView.showsChevron`).

## Decision Log

- Removed the back chevron in two columns rather than keeping it beside the list button: it only cleared the selection and showed the list, which the list button already does. No rationale for it was recorded in `.codex/feature/ipad-sidebar-navigation.md` or the commit that added it (0e9cea0).
- iPad launches `.detailOnly` and slides the list in after the first render. Measured: any launch whose first frame shows the sidebar (`.doubleColumn` at init, or `.automatic` in landscape — the latter is the OLD behavior too) lays both columns out 55pt low, with the tab container at y=32, until the next hide/show. Hidden → shown is the only path that laid out right every time. Trade-off: a 0.22s slide-in at launch.
- The column is width-based, not idiom-based, so iPad Split View / Stage Manager windows get it whenever the detail is wider than 720.
- User bubbles: 480pt of text in a ≥600pt column (75% of the phone's ratio would be ~515; 480 keeps a clear left margin for the assistant's text column). Optimistic bubbles keep their uncapped phone style; they are transient.
- Tasks sidebar background matched to Sessions (#1C1C1E): it was the darker default glass, a second visible mismatch under finding 5.
- New-session keyboard overlap (found while building, pre-existing): fixed with `ViewThatFits` instead of a keyboard-height read, so no new keyboard state is introduced.

- Keep New session a full-screen cover and constrain its content, instead of switching to a form sheet. Lower risk (the cover owns keyboard and focus handling that took several sessions to get right) and it matches the session view it turns into.
- Leave "hiding the list hides the tab switcher" alone. One tap brings the list back, and moving the switcher into the detail toolbar would duplicate it on screen whenever the list shows.
- Hardware-keyboard shortcuts and the iPadOS menu bar are out of scope for this pass; listed as an open item on the canvas.

## Verification Evidence

Self-check (implementer's measurements, iPad Pro 11" sim A00EE23C, iOS 26.3, dark; raw captures measured at 1.451 px/pt). Not the independent verdict — see the verifier row.

| SC | What ran | Result | Artifact |
| --- | --- | --- | --- |
| SC1 | Cold launch, portrait and landscape; sidebar card top measured | List shows; card top 42 (portrait), 43 (landscape). Old `.automatic` landscape launch measured 96.5 as the control | `.claude/ipad-audit/shots/p1-launch-portrait-final.png`, `p-raw-oldpath-landscape.png` |
| SC2 | Landscape with list: composer edges, text left edge | Composer 422.75–1117.25 (column 410–1130), text from 427; list hidden: composer 257.5–951.75, text from 262; bubble 607–1113 (≈480pt text) | `p1-session-landscape.png`, `p1-session-landscape-full.png`, `p1-bubble-landscape.png` |
| SC3 | Two columns: top-left controls | One list button at 350–394 (10–54 when hidden); iPhone keeps its back button | `p1-session-portrait.png`, `iphone-03-session.png` |
| SC4 | New session landscape | Composer 256.75–952.5, bottom 21; with keyboard, all composer controls above it | `p2-new-landscape4.png`, `p2-new-landscape3.png` |
| SC5 | Task view landscape | Next-run card 429.75–1109; Ask bar 425.5–1113.75 | `p2-task-landscape.png` |
| SC6 | Tasks sidebar | Fill #1C1C1E (was #0F–#17); selection 17.75–321.25 × 137–219.5, #172B3D; no chevrons; Mac sources typecheck (`swiftc -typecheck`, exit 0) | `p2-raw-task2.png` |
| SC7 | `swift test --filter ReadableColumn`; full `swift test` | 6/6; 454 tests in 66 suites passed | terminal |

Independent verifier, round 1 (claude-design-verifier, full boards): **FAIL** overall, `.claude/ipad-audit/verifier-r1/evidence.md`. Every component this pass changed passed within ~1pt (column 421.8–1117.2 vs 422–1118; list hidden 257.1–953.1 vs 257–953; bubble 606.5–1113.7 vs 606–1114; one list button 350–394; cold launch panel top 42 in both orientations; keyboard-up New session fully visible). The 18 findings split as:
- Fixed after round 1: F1 header dot on the card edge (Sessions and Tasks; the sidebar column reports a COMPACT size class, so the flag is now passed in as `inSidebarCard`), F14 Tasks header glyphs differ from Sessions (now the same `BoardGlyph`s and label tint), F15 Tasks selection 5pt short (vertical inset removed).
- Board errors, corrected on the canvas: F5 placeholder position/size, F4 dock height.
- Pre-existing, out of scope, listed on the canvas (`ipFound`) and in the reply: F2 unread rows lack "New reply", F6 text readable behind the top bar, F7 system keyboard-focus ring (`.focusEffectDisabled()` on the List and on rows did not remove it; not forced off, to keep arrow-key navigation), F12 send arrow looks enabled when empty.
- Pre-existing styling drawn approximately on my boards (out of scope; `ipHowTo` sticky): F3, F8, F9, F10, F11, F12 fills, F16, F17, F18.

Independent verifier, round 2 (scoped to the changed components), `.claude/ipad-audit/verifier-r2/evidence.md`: A cold launch both orientations PASS; B landscape column PASS; C list hidden PASS; D portrait PASS; H phone PASS (one sub-point PARTIAL: back button 45 vs 46 wide, unchanged). Sessions and Tasks headers pixel-identical in the app. FAIL items were all board-vs-unchanged-component: header search/more glyphs 5pt/2pt off the board, Ask bar 52 vs 50 tall, New-session composer 196 vs 194 tall (boards corrected to the app, canvas v77; not re-verified), and the header host dot (61,222,102) vs the board's #30D158 (pre-existing `Color(.systemGreen)` in the elevated sidebar; not changed). Still visible and out of scope: the system focus ring on the selected Sessions row with a hardware keyboard.

## Bugs

_None yet._
