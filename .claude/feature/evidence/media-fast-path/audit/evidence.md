# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-17 01:27–01:30 local (2026-09-16T17:27Z–17:30Z; stub.log ids 422–442)
Repository: /Users/eugenechan/dev/personal/lfg
Simulator: iPhone 17 Pro, iOS 26.3, UDID E0DC8228-3248-4630-8929-FBC5DFC6AE6D
App: com.eugenechan.lfg (pid 98289, already installed — NOT rebuilt or reinstalled)
Host under test: stub Access gate at http://127.0.0.1:8797 (bun pid 79684) forwarding to lfg serve on :8766; 403s any request without the CF-Access headers

## Change Audited

media-fast-path (`.claude/feature/media-fast-path.md`): server `w=` JPEG renditions with ETag +
`Cache-Control: private, max-age=86400`; full-screen image viewer requests `w=2400`; host videos
stream through an `AVAssetResourceLoaderDelegate` (`StreamingResourceLoader`, `ios/LFG/RichContent.swift`)
that forwards byte-range requests with the Access credential, replacing the download-first
"Preparing video…" phase.

Path driven: session list → row `sessionRow-cb8d34c6-…` ("Download app on iPhone") → transcript file
cards → video card → Done → image card → Done → markdown card → Done.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC5 — video streams instead of downloading first (no "Preparing video…" phase; playing frames; 206 byte-range requests carrying Access headers; no 403) | PASS | `05-video-frame-t0.jpg` (first frame captured after the tap: viewer open, decoded video visible, no spinner), `05-video-frame-t1.jpg` / `05-video-frame-t3.jpg` / `05-video-frame-t7.jpg` (different content; in-video clock advances 12:05→12:06 in `06-video-controls.jpg`); `stub-log-excerpt.jsonl` ids 422–425: four `206` responses for `05-gifts-tasks-small.mp4` with `Range: bytes=0-1`, `bytes=0-`, `bytes=1671168-`, `bytes=16366-1671167`, type `video/mp4`; zero 403 lines in the window (the stub 403s any request without the headers, so a 206 proves the headers were present) |
| SC4 — image viewer requests a `w=2400` rendition | PASS | `07-image-viewer-tasks.jpg` (image rendered in viewer titled "tasks"); `stub-log-excerpt.jsonl` id 438: `…/shots/35-task-center-2.png&w=2400` → `200`, `image/jpeg`, ETag `"796ca3ad…"`, `Cache-Control: private, max-age=86400` |
| SC3 regression — markdown card still opens and renders; served as text/markdown with no `w=` | PASS | `08-markdown-viewer.jpg` (rendered "Lovin — App Walkthrough" headings/paragraphs), `08-markdown-viewer-tree.json` (StaticText headings 1–7 in the accessibility tree); `stub-log-excerpt.jsonl` id 442: `…/WALKTHROUGH.md` → `200`, `text/markdown`, no `w=` param, `private, max-age=60` |

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/feature/evidence/media-fast-path/audit/`:

- `01-launch.jpg` — state on attach (implementer had left the "gift shop" viewer open)
- `02-after-close-viewer.jpg` — transcript file cards after closing that viewer
- `03-session-list.jpg` — session list; "Download app on iPhone" row under Idle
- `04-session-open.jpg` — session reopened by row id; image/video/markdown cards
- `05-video-frame-t0.jpg`, `05-video-frame-t1.jpg`, `05-video-frame-t3.jpg`, `05-video-frame-t7.jpg` — session frames (500 ms capture) after tapping the .mp4 card
- `06-video-controls.jpg` — later frame of playback (in-video clock 12:06)
- `07-image-viewer-tasks.jpg` — image viewer for "tasks"
- `08-markdown-viewer.jpg`, `08-markdown-viewer-tree.json` — markdown viewer + accessibility tree
- `09-final-state.jpg` — back on the transcript after closing the markdown viewer
- `stub-log-excerpt.jsonl` — the `/api/file` lines from stub.log for the audit window (ids 422–442)

## Commands

Run from `/Users/eugenechan/dev/personal/lfg/ios` with `FLOWDECK_UI_SKIP_LOCK_CHECK=1`:

- `flowdeck config get --json` (scheme LFG, iPhone 17 Pro E0DC8228…)
- `flowdeck apps --json` (com.eugenechan.lfg running on iPhone 17 Pro, pid 98289)
- `flowdeck ui simulator session start -S E0DC8228-3248-4630-8929-FBC5DFC6AE6D --json` (session 2AB9409E)
- `flowdeck ui simulator touch down 350,100` / `touch up 350,100` — Done button (x4)
- `flowdeck ui simulator touch down 38,84` / `touch up 38,84` — back chevron
- `flowdeck ui simulator tap --by-id sessionRow-cb8d34c6-37c2-4ba7-b5be-716575fe7219`
- `flowdeck ui simulator tap "05-gifts-tasks-small.mp4"`, `tap "tasks"`, `tap --point 200,582` (WALKTHROUGH.md — two cards share the label, so tapped the visible one by point)
- `flowdeck ui simulator tap --point 200,500` (attempt to reveal AVKit controls; no overlay appeared)

## Notes

- No source, project, config, or build changes were made. The app was not rebuilt or reinstalled.
- The video used was `05-gifts-tasks-small.mp4` (1,717,584 bytes) as instructed by the caller — not the
  200 MB+ file the feature doc's SC5 wording mentions. The seam under test (byte-range requests via the
  resource loader, with the Access credential, no pre-download) is exercised identically; the "first
  frame within seconds against 200 MB+" timing claim is NOT covered by this run.
- Synthetic tap on the video did not surface AVKit's transport controls (accessibility tree shows only
  a `Video` element), so a scrubber screenshot with a numeric position was not obtainable. Playback
  progress is proven instead by differing frames across ~7 s and the in-video status-bar clock
  advancing 12:05 → 12:06.
- Frame filenames in the FlowDeck session are capture-start timestamps at 500 ms granularity; the
  claim is "the first frame captured after the tap already showed decoded video with no spinner",
  not a sub-second latency figure.
- SC4 was checked on "tasks" rather than "gift shop" deliberately: "gift shop" (30-gift.png) had already
  been fetched at w=2400 during the implementer's run and would have been served from the in-memory
  image cache, so it would not have produced a discriminating stub.log line.
- Only one 403 exists in the whole stub.log (id 1, `/api/sessions`, before the credential was configured).
- Transcript live-update over SSE is not relayed by the stub (caller-stated artifact); the session was
  reopened from the list to load over REST, which is the path this audit used.
