# Media files 404 in the iOS client when the path contains a space

**Date:** 2026-09-22
**Reported as:** "Can't load some of the image and video files from the most recent
ai girl game sessions — 404 errors."
**Status:** fixed, verified live in the simulator.

## The report, narrowed

Three recent sessions ran with cwd `/Users/eugenechan/dev/inbox/AI girl game`.
Auditing every `SendUserFile` call in their transcripts:

| session | files handed over | path contains a space |
| --- | --- | --- |
| `0f7b518d` | 47 | 47 |
| `79b6a3bd` | 72 | 72 |
| `41497ff4` | 57 | 5 |

108 of 158 media files. **All 163 unique paths exist on disk**, and the server
serves them correctly — `GET /api/file?path=<percent-encoded spaced path>`
returns `200` with the right byte count. So this was never a server or a
missing-file problem.

## Root cause — the client's media scanner cannot parse a destination with a space

`MediaScanner` (`ios/LFGCore/Sources/LFGCore/MediaRefs.swift`) had:

```
imageMarkdown  !\[([^\]]*)\]\(([^)\s]+)\)
bareRef        …(?<![\w.~/-])(?:/[^\s)]+|[\w.~-]+(?:/[\w.~-]+)+)\.([A-Za-z0-9]{1,5})
```

The destination `([^)\s]+)` stops at the first space. Run against a real line:

```
![storyboard-v3.png](/Users/eugenechan/dev/inbox/AI girl game/creative/…/storyboard-v3.png)
  image matches: 0
  bare match   : game/creative/…/storyboard-v3.png
```

Two failures compound:

1. The markdown image/link **matches nothing**, so no labelled card is produced.
2. The bare-path pass then matches the **tail after the space**,
   `game/creative/…`, which has no leading `/` and is therefore treated as
   relative and joined to the session cwd →
   `/Users/…/AI girl game/game/creative/…` — a path that cannot exist. That is
   the 404 Eugene saw.

A second, smaller source of the same symptom: a `~/…` path (agents write these
constantly in their "Files:" handoff lines) was also "not absolute", so it too
was joined to the cwd.

## Fix

**Client — `MediaRefs.swift`**
- Markdown destinations accept spaces, and CommonMark's angle form
  `(<path with spaces.png>)`, which additionally tolerates `)` in the path.
  A trailing link title (`"…"` / `'…'`) is stripped.
- Markdown match ranges are now *claimed*: the bare pass skips anything inside
  them, so the tail-after-the-space phantom can no longer be produced.
- A spaced destination must still look like a path (contain `/`), so
  `[ref](Smith et al. 2020)` does not become a `.2020` card.

**Client — `TranscriptRowText.swift`**
- The prose-stripping regex mirrors the new destination grammar (angle wrapper,
  optional title), or the raw `![…](…)` would stay in the prose under the card.

**Client — `RichContent.swift`**
- `~`-rooted paths pass through untouched instead of being joined to the cwd.

**Server — `src/commands/serve.ts`**
- `/api/file` expands a leading `~` (`expandUserPath`). Only the host knows its
  own home directory. This also helps builds that predate the client fix.

**Server — `src/sessions.ts`**
- `sendUserFileText` wraps a destination containing a space or a paren in angle
  brackets, so spec-following markdown renderers see a destination too. Ordinary
  paths keep the bare form older clients already parse — no regression for them.

## Verification

- `swift test` in `ios/LFGCore` — 170 tests pass, including a new
  "Paths containing spaces" suite.
- `bun test` — 956 tests pass, including four new `sendUserFileText` cases.
- Live on `iPhone 17 Pro` (sim `cc-3e41c545`), against the real host and the real
  transcripts:
  - "Files & Links" now lists the spaced entries at their **full absolute path**
    (previously the relative `game/creative/…` phantom).
  - Tapping `draft-s25-v3.14-30s-0-sheet.jpg` (spaced path) renders the contact
    sheet; `draft-s25-v3.14-30s-0.mp4` (spaced path) plays.
  - An **inline** transcript card, `sheet-v6-zh.jpg` under
    `/Users/eugenechan/dev/inbox/AI girl game/creative/rps-strip/character/`,
    opens in the viewer.
  - Re-ran after the final guard: `booth-full-v6-0.mp4` still opens — no
    regression for ordinary paths.

## What is still needed

The parse happens on device, so the shipped TestFlight build keeps 404ing until
a new build goes out. The server changes need an `lfg serve` restart, which is
deliberately deferred (it drops in-memory session tracking).

## Latent, not fixed

`URLComponents` leaves `+` unescaped in a query value, and Bun's
`URLSearchParams.get` decodes `+` as a space — so a path containing a literal `+`
would still 404. No such path exists in these sessions.
