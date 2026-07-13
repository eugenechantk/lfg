# Why the first directory toggle has more bottom spacing (desktop app)

**Verdict: macOS SwiftUI `List` framework behavior, not a bug in our code.**
Reproduced in a minimal app (4 empty `Section`s with plain `Text` headers,
`.listStyle(.inset)`) — nothing lfg-specific involved.

## Measurements (1x pixels = points)

Collapsed Directory mode, header-center to header-center:

| gap | size |
|---|---|
| personal/lfg → web | **58.5pt** |
| web → .claude | 47.5pt |
| .claude → track-b | 47.0pt |

Expanded variant: first header → its own first row = 36.5pt, other headers →
their first row = 25.75pt. So the extra ~11pt hangs **below the first
section header specifically**, regardless of collapsed/expanded, header
content (Button vs Text), or item counts.

## Mechanism

macOS `List` section headers are **sticky** (they pin to the top of the
scroll area while their section scrolls). The inset list style also has a
~10pt **top content inset**. At scroll offset 0 the first header renders in
its pinned position — flush against the top edge, *above* the content
inset — while the rest of the list lays out below the inset. The inset
therefore shows up as extra empty space *under* the first header instead of
above it. Every other header sits inline in the flow, so their spacing is
uniform.

Proof (screenshots alongside this file):

- `repro-collapsed.png` — minimal repro shows the same oversized first gap.
- `repro-scrolled-header-pinned.png` — after scrolling, the first header
  stays pinned and rows slide up underneath it with **normal** spacing; the
  extra gap closes. Only explainable by pinning + top inset.

Also verified: putting any plain (non-Section) row as the first `List`
element makes all header gaps identical (47.5pt) — the anomaly is tied to a
section header being the list's first element.

## Fix options (if we care)

1. **Live with it** (recommended) — it's the system's rest-state rendering
   of a pinned header; every stock macOS sectioned list shows it.
2. Make directory toggles regular rows instead of `Section` headers —
   uniform spacing, but loses sticky headers when sections are expanded and
   scrolled.
3. Hack: `.padding(.top, 10)` on non-first headers or a spacer first row —
   both verified to change the geometry, both fragile against OS changes.
