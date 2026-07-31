# Delegation Brief: fix measured design deltas in the session list

An independent design-verification agent compared the running app against the Claude Design
artboards component-by-component and measured concrete deltas. Fix them.

## Where to work

**Work in the git worktree, NOT the main repo:**
`/Users/eugenechan/dev/personal/lfg/.worktrees/session-list`

The main tree currently does not build (other agents' in-flight work). The worktree builds clean and
contains only this task's changes. Edit only:
- `ios/LFG/SessionListView.swift`
- `ios/LFG/Theme.swift`

Full evidence, including paired design-vs-app crops:
`/Users/eugenechan/dev/personal/lfg/.worktrees/session-list/.codex/evidence/session-list-verify-v2/evidence.md`
Spec (geometry + tokens): `/Users/eugenechan/dev/personal/lfg/.claude/feature/session-list-restyle.md`

## The core problem to fix first — the colour token layer is wrong

`SessionListView.swift` currently maps every design colour onto a UIKit semantic colour, with a
comment claiming each design value *is* that semantic colour's dark variant. **That claim is only
partly true and the comment is now wrong — correct it.**

Verified exact: `#000000` = `systemBackground`, `#1C1C1E` = `secondarySystemBackground`,
`rgba(235,235,245,0.60)` = `secondaryLabel`, `0.30` = `tertiaryLabel`.

Verified WRONG — these have **no** semantic equivalent and were silently rounded to the nearest one:

| Token | Design | Currently rendering |
|---|---|---|
| row separator | `rgba(255,255,255,0.07)` → `(18,18,18)` on black | `Color(.separator)` → `(42,42,44)`, blue-tinted |
| row meta text | `rgba(235,235,245,0.50)` → `(118,118,123)` | `.secondaryLabel` `0.60` → `(141,141,147)` |
| group chevron / host ink | `rgba(235,235,245,0.40)` → `(94,94,98)` | `.tertiaryLabel` `0.30` → `(70,70,73)` |
| composer placeholder | `rgba(235,235,245,0.45)` → `(121,121,127)` | `.placeholderText` `0.30` → `(90,90,94)` |
| unread status dot | `#BF5AF0` → `(191,90,240)` | `Color.purple` → `(219,52,242)` |

Two fixes:

1. **`Color.purple` is not `systemPurple`.** In `Theme.swift`, the status dots must use the
   `UIColor` system palette (`Color(.systemPurple)` etc.), not SwiftUI's `Color.purple`. Check
   **every** status colour this way, not just unread — only Unread was on screen when measured, so
   `needsInput` / `idle` / `blocked` / `closed` are unconfirmed and may have the same defect.
   `Color.green` was confirmed to read back exactly `#30D158`, so some are already right.

2. **For the four values with no semantic equivalent, define explicit adaptive colours** — e.g. a
   small helper building `Color(UIColor { traits in ... })` that returns the design's exact dark
   value in `.dark` and a sensible mirrored light value in `.light`. Do NOT hard-code a single
   value (the list must keep following system appearance, which is a deliberate requirement) and do
   NOT keep substituting a semantic colour that measurably differs. Keep the token names.

Whatever you do here, make the code comment honest about which values are semantic and which are
explicit, and why.

## Remaining measured deltas

| # | Component | Design | App now | Fix |
|---|---|---|---|---|
| D1 | row separator | **1 pt** | ⅓ pt (`1/UIScreen.main.scale`) | use 1 pt. Inset 39 is already correct — keep it |
| D2 | row rhythm | title→meta gap **4**, row pitch **78** | gap **7**, pitch **80.33** | the gap is `VStack(spacing: 3)` stacked on a `.padding(.top, 4)`; make it 4 total, and bring pitch to 78 |
| D4 | row meta copy | `lfg · opus · 47s` | `lfg · opus · 18s ago` | drop the trailing " ago" — compact relative style |
| D5 | group header leading | chevron ink `x=22`, name `x=42` | chevron `x=36.7`, name `x=59.3` | the `Section` header never gets the `.listRowInsets(EdgeInsets())` the rows do |
| D6 | group header vertical | list-top→header **26**, header→first row **8** | **52**, **17.7** | |
| D10 | composer bottom | **26 from the frame bottom** | 60 (26 above a 34 pt safe area) | the design floats it 26 from the very bottom of the screen — it clears the home indicator, which sits lower |
| D11 | glyph sizes (rendered box, not font size) | search `15×15`, filter `13×9`, gear `17×17`, plus `15×15`, mic `10.8×15` | `18.3×18.7`, `19×11.3`, `20×20`, `19×19`, `14×21` | every glyph is oversized; SF Symbols render smaller than their point size, so scale the font sizes down until the rendered boxes match. Approximate starting points: search ≈15.5, filter ≈13, gear ≈16, plus ≈19, mic ≈14 — **treat these as starting guesses, not answers** |

**D12 is NOT a defect — do not "fix" it.** The header title is deliberately the host status line
(status dot + `Connected · N running`) rather than the design's literal "All sessions" string. Leave
that behaviour alone.

## Do not regress

- The list must still follow system appearance (light **and** dark both correct).
- Everything in spec §2 (agent nesting, load-more, connection banner, empty state, offline dimming,
  pull-to-refresh, mark-all-read) must keep working.
- All accessibility identifiers must stay. In particular the group-header button must remain
  tappable across its **full width** — its `Spacer` is inside the button's label on purpose; if you
  restructure that header for D5/D6, keep the full-width hit area or collapse silently breaks.
- If a shared helper is used elsewhere (e.g. the relative-time formatter in `Theme.swift` is used by
  other views), add a compact variant for the list rather than changing the shared one.

## Verification

```bash
cd /Users/eugenechan/dev/personal/lfg/.worktrees/session-list/ios/LFGCore && swift test   # must stay green
```

Do **not** attempt a simulator build or visual check — Claude owns that and will build, drive the
app, and re-run independent design verification.

## Report back

Files changed; `swift test` output; each delta with what you set it to; anything you could not
match or deliberately deviated from, stated explicitly.
