# Feature: media-fast-path

Companion to `.claude/diagnosis-media-slow-tunnel-in-vpn-20260917.md`. The transport fix (Surfshark
bypass) is Eugene's; this is the part that makes media usable at any RTT.

## User Story

As Eugene reading a session on the phone, I want screenshots to appear in a second or two and
videos to start playing within seconds, so that reviewing agent evidence on the phone is
practical over the Cloudflare path.

## User Flow

1. A transcript message references `/Users/…/shot.png` → an inline image or file card renders.
2. The image bytes that cross the wire are a downscaled JPEG rendition, not the original PNG.
3. Tapping an image opens the full-screen viewer with a sharper (2400 px) rendition.
4. Tapping a video opens the player; playback starts while the rest of the file streams.
5. Scrolling away and back does not refetch an image already shown.

## Success Criteria

- [x] SC1: `GET /api/file?path=<png>&w=1200` returns `image/jpeg`, at most 1200 px wide, with
  `ETag` and `Cache-Control: private, max-age=86400`; a second request hits the cache file —
  **Verify by:** `src/file-thumbs.test.ts` (rendition width, cache hit, key rotates with mtime,
  non-image → null) + live `curl` against the running server.
- [x] SC2: `If-None-Match` with the rendition's ETag returns 304 with no body — **Verify by:** live `curl`.
- [x] SC3: Non-image files, and images when `sips` fails, still serve the original bytes unchanged
  (no regression of the existing endpoint, incl. Range/206) — **Verify by:** live `curl` for a
  `.mov` range and a `.md` file; unit test for the fallback.
- [x] SC4 (viewer path; inline URL by unit test only): Inline transcript images request `w=1200`; the full-screen image viewer requests
  `w=2400` — **Verify by:** `HostFilesTests` (URL composition) + server-side request log during
  the sim run.
- [x] SC5: A host video plays in the viewer without a full download: the "Preparing video…"
  phase is gone and the first frame is on screen within a few seconds against a 200 MB+ file,
  with byte-range requests carrying the Access headers — **Verify by:** sim run against a stub
  host that 403s any request lacking `CF-Access-Client-Id` (exercises the real seam), server log
  of 206 responses, screenshot of playback with a non-zero position.
- [x] SC6: Range header composition for the resource loader is correct for
  offset/length and offset-to-end requests — **Verify by:** `StreamingRangeTests` in LFGCore.
- [x] SC7: Existing tests stay green — **Verify by:** `bun test` (server), `swift test` in
  `ios/LFGCore`, FlowDeck build of the app.

## Platform & Stack

- **Platform:** Bun server (`src/`) + iOS client (`ios/`)
- **Language:** TypeScript, Swift
- **Key frameworks:** Bun.serve, macOS `sips`, SwiftUI, AVFoundation (`AVAssetResourceLoaderDelegate`), MarkdownUI

## Steps to Verify

1. Server: `bun test src/file-thumbs.test.ts`, then restart `serve` and curl the endpoint.
2. Client: `swift test` in `ios/LFGCore`; FlowDeck build + run on iPhone 17 Pro sim.
3. Sim run: point the app at a stub host on a spare port that requires the Access headers and
   proxies `/api/file` to a local file with Range support; open a session containing a big
   `.mov` and a `.png`; observe playback and image load; capture screenshots.

## Implementation Phases

### Phase 1: Server renditions
- Scope: `src/file-thumbs.ts` (sips rendition + on-disk cache under `~/.lfg/cache/thumbs`,
  in-flight dedupe, concurrency cap), `w` param + ETag/304 in the `/api/file` handler.
- Success criteria covered: SC1, SC2, SC3
- Verification gate: unit tests + live curl.

### Phase 2: Client image path
- Scope: `HostFiles.fileURL(forPath:maxWidth:)`, inline provider → 1200, viewer → 2400,
  in-memory image cache, larger `URLCache`.
- Success criteria covered: SC4
- Verification gate: LFGCore tests + sim screenshot.

### Phase 3: Streaming video
- Scope: `StreamingResourceLoader` (app target) + `StreamingRange` helper (LFGCore),
  `FileViewerSheet` video phase → stream instead of download; plain URL when the host needs no
  credential.
- Success criteria covered: SC5, SC6
- Verification gate: LFGCore tests + sim run against the header-requiring stub.

## Decision Log

- **Renditions are JPEG q80 via `sips`, bucketed widths {480, 1200, 2400}.** sips is built into
  macOS, async via `Bun.spawn`, 26–100 ms per file; JPEG because every consumer decodes it and
  the p90 PNG shrinks 5.6×. Widths are bucketed so the cache stays bounded. Alternative (HEIC)
  is smaller but not worth a second code path. Non-darwin hosts return the original.
- **Cache key = sha1(realpath | mtime | size | width)**, stored as files, never pruned by the
  server (agent screenshots are small once downscaled; a `find -mtime +30 -delete` is a one-liner
  if it ever matters). Logged here so it isn't a surprise.
- **Viewer uses 2400, not the original.** 2400 px covers a 3× phone at 2× pinch. The original
  is one tap away only if someone asks; the point of the viewer is reading a screenshot.
- **Video streams through an `AVAssetResourceLoaderDelegate`, not a cookie.** Access refuses the
  `CF_Authorization` cookie without the service-token headers (403 verified with a cookie jar),
  and `AVURLAssetHTTPHeaderFieldsKey` is private API. The delegate forwards each byte-range
  request through `LFGClient.resourceRequest(for:)`. Hosts without a credential get the plain
  URL (the server already answers 206).
- **No server-side transcoding of video.** 200–400 MB sim recordings are H.264/HEVC already;
  streaming fixes the wait, transport fixes the rate.

## Verification Evidence

All runs 2026-09-17 00:55–01:25 HKT on the Pro; server restarted by port at 01:02 (pid 70657)
so the live curls hit the new code. Evidence files under `.claude/feature/evidence/media-fast-path/`.

| SC | Method | Observed |
|---|---|---|
| SC1 | `bun test src/file-thumbs.test.ts` | 12 pass, 0 fail (bucketing, candidates, key rotation, JPEG ≤ bucket width, cache hit with `sips=/usr/bin/false`, **no upscale** of a 300 px source, failure leaves no `.tmp.jpg`, 4 concurrent keys → 4 sips runs, duplicates shared) |
| SC1 | live `curl` `/api/file?path=<9.3 MB PNG 1536×2752>&w=1200` | `200`, `image/jpeg`, `227864` bytes (41× smaller), `ETag "76e9…"`, `Cache-Control: private, max-age=86400`, 0.10 s cold; second hit 0.0013 s from `~/.lfg/cache/thumbs/` |
| SC1 | live `curl` `&w=2400` | `image/jpeg` 744768 bytes (12.5× smaller) |
| SC2 | live `curl` with `If-None-Match: "76e9…"` | `304 Not Modified`, 0 bytes, ETag echoed |
| SC3 | live `curl` `.mov` `-r 0-99` with `&w=1200` | `206`, `video/quicktime`, `Content-Range: bytes 0-99/235826042`, `max-age=60` — unchanged |
| SC3 | live `curl` `.md` with `&w=1200`; `.png` without `w` | `text/markdown` unchanged; `image/png` 9301287 bytes (original) |
| SC4 | `swift test --filter MediaFastPathTests` | 6 pass (`hostFileURL` path+`w`, non-positive width ignored, origin check) |
| SC4 | sim, Files & Links → "gift shop" card, through the Access-gate stub | `stub.log`: `…/shots/30-gift.png&w=2400` → `200 image/jpeg ETag "a1bf…" max-age=86400`; `sc4-image-viewer.jpg` shows the screenshot rendered. First attempt (before the `viewerURL(for:)` helper) fetched the original PNG via `AttachmentsSheet` — bug found and fixed, see Bugs |
| SC4 (inline) | — | Not reachable from a transcript: `![]()` in prose is extracted into a card by `MediaScanner`, so `HostImageProvider` only serves markdown-file renders. URL composition covered by the unit test; the `w=1200` request itself is unverified live |
| SC5 | sim, "Download app on iPhone" → `04-chat-baize-small.mp4` card, through the stub (403 without headers) | `stub.log`: `206 bytes=0-1`, `206 bytes=0-`, `206 bytes=1900544-`, `206 bytes=1966080-`, `206 bytes=1916695-1966079`, `206 bytes=146988-1900543` — AVPlayer's range pattern, every request carried the Access headers (no 403). `sc5-video-streaming-frame.jpg` and `sc5-video-controls.jpg` are two different frames of the recording = playback progressing; no "Preparing video…" phase |
| SC6 | `swift test --filter MediaFastPathTests` | range header bounded/open/negative offset, `Content-Range` total incl. `*/N`, UTI from MIME then extension |
| SC7 | `bun test` / `swift test` / `flowdeck build` | 848 pass across 76 files; 531 pass, 1 skipped; BUILD succeeded (Debug, iPhone 17 Pro) |
| Audit | `ios_visual_evidence_auditor` (independent, did not rebuild) | **PASS** on SC5 / SC4 / SC3-regression — `evidence/media-fast-path/audit/evidence.md`: four 206 range responses for `05-gifts-tasks-small.mp4` with zero 403s, frames advancing over ~7 s and the in-video clock ticking; `35-task-center-2.png&w=2400` → `image/jpeg` + ETag + `max-age=86400` (a not-yet-cached image, chosen deliberately); `WALKTHROUGH.md` served as `text/markdown` unchanged. Caveat it raised: the run used a 1.7 MB video, so the "first frame within seconds on 200 MB+" timing is only argued from the range pattern, not timed |

Discriminating case for SC5: the old build issued ONE unranged GET and showed "Preparing video…" until the whole file landed; the new build's first byte-range request is 2 bytes and playback starts before the open-ended request finishes.

## Bugs

- **Fixed — second viewer entry point missed the width.** `AttachmentsSheet` (Files & Links) built
  its own viewer URL, so the first live tap fetched the original 9 MB PNG. Replaced both call sites
  with `HostFiles.viewerURL(for:)` so the rule lives at the boundary. Caught by the sim run, not by
  tests (the app target has no unit tests).
- **Fixed — `sips -Z` upscales.** A 300 px source came back 1200 px wide (bigger than the PNG).
  Now probes the source size first and clamps. Covered by the "never upscales" test.
- **Fixed (test only) — PNG fixture used raw DEFLATE.** `Bun.deflateSync` is raw DEFLATE; PNG
  needs a zlib stream. sips silently produced a 156-byte JPEG with no pixels. Fixture now uses
  `node:zlib`.

## Observations outside this feature (not fixed here)

- Two of this session's prose turns — the ones that consisted of a sentence plus two bare absolute
  file paths — never appeared in the transcript JSONL at all (`grep` finds them only inside later
  tool inputs), while every other prose turn did. The lfg server and client faithfully show what's
  on disk. Worth a separate look at what Claude Code does with such turns before relying on
  "mention the path in prose to get a card".
- `flowdeck run` reinstalls the app and re-seeds the bundled Cloudflare hosts while keeping a
  user-added host, so a sim configured against a stub ends up with three hosts after every
  rebuild. Remove the two bundled ones again before relying on routing.
