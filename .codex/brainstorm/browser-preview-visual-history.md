# Browser Preview Visual History

Status: product/architecture exploration

Related: [live-browser-preview.md](./live-browser-preview.md)

## Decision to revisit

The original Browser Preview deliberately kept only the latest frame in memory.
That minimized persistence and privacy risk, but it also removes most of the
feature's diagnostic value: once the next screenshot arrives, the evidence for
how the agent reached the current state is gone.

The useful product is not a video player or a pile of screenshots. It is a
**visual audit trail**: a bounded sequence of browser states, ordered in time and
connected to the agent steps that produced them.

## Product options

| Option | Experience | Cost | Recommendation |
| --- | --- | --- | --- |
| A. Ephemeral rewind | Keep the last 20–50 frames in memory; scrub only while the host process remains alive | Small | Too fragile for a feature whose purpose is backtracing |
| B. Visual audit trail | Persist a bounded host-local history; scrub frames, see time/action context, and jump to the corresponding transcript step | Moderate | **Recommended** |
| C. Full session replay | Combine screenshots, browser actions, transcript, prompts, and user steering into a playable/exportable replay | Large | Valuable later, after B proves the interaction |

Option B is the smallest version that solves the actual problem. A screenshot
timeline without an agent-step anchor answers “what did the page look like?” but
not “why did we get here?”

## Recommended experience

### Floating preview

The floating preview remains optimized for the latest state and keeps its
current drag, dock, close, and full-screen behavior.

- Add a history affordance and frame count, for example `clock.arrow.circlepath`
  plus `24`.
- Tapping the image still opens full screen, initially following the latest
  frame.
- Do not put a horizontal scrub gesture on the floating card; that conflicts
  with dragging the card.
- Closing the preview hides it but does not delete its history. “Show Browser
  Preview” restores it at the last viewed frame or latest frame; recommend
  latest for predictability.

### Full-screen visual timeline

Use a Photos-style viewer rather than native video playback. These are discrete,
action-synchronized frames with irregular timing and semantic anchors, not a
continuous media stream.

```text
┌──────────────────────────────────────┐
│  Close     Browser Preview    Latest │
│                                      │
│                                      │
│          selected screenshot         │
│                                      │
│                                      │
│  14:32:08 · Claude · Click           │
│  “Opened the LFG design project”      │
│                                      │
│  ◻︎  ◻︎  ◻︎  ▣  ◻︎  ◻︎  ◻︎           │
│  ─────────────●──────────────  18/31 │
│        Jump to agent step             │
└──────────────────────────────────────┘
```

- Swipe between frames or drag a bottom scrubber/filmstrip.
- Show absolute time and relative age, source, and a short action label when
  known.
- `Jump to agent step` closes full screen and scrolls the transcript to the
  nearest correlated tool call/result.
- While the user is on the latest frame, new frames advance automatically.
- Scrubbing backward disables auto-follow. New arrivals increment a `Latest +N`
  affordance without moving the selected frame.
- Tapping `Latest` returns to the newest frame and resumes auto-follow.
- Missing/expired images stay represented as gaps with timestamp/action context;
  never silently collapse the timeline and make ordering misleading.

### Viewer state

```text
                 new frame
      ┌────────────────────────────┐
      │                            ▼
  FOLLOWING_LATEST ── scrub back ──▶ REVIEWING_HISTORY
      ▲                                  │
      └──────────── tap Latest ──────────┘

  any state ── close full screen ──▶ FLOATING_PREVIEW
  any state ── close preview ──────▶ HIDDEN (history retained)
```

Selection is by stable `frameId`, not array index. Retention or pagination can
change indices while the viewer is open.

## Data model

Each frame needs metadata beyond the current latest-frame descriptor:

- `sessionId`, `frameId`, `capturedAt`, `contentType`, `source`
- monotonic host `sequence` for stable ordering and cursor pagination
- nullable `transcriptMessageId`
- nullable vendor `toolCallId`
- nullable action label (`Navigate`, `Click`, `Type`, `Submit`, `Wait`)
- optional safe page origin/title; do not persist full URL query/fragment by
  default
- byte size and image dimensions for layout, quotas, and diagnostics

Correlation rules:

1. Prefer the normalized transcript message ID from the same transcript line as
   the screenshot result.
2. Otherwise retain the vendor tool-call ID.
3. Otherwise jump to the transcript message nearest `capturedAt` and label the
   relationship as approximate.

The frame sequence should be independent from Swift array indices and can reuse
the journal event sequence if the write order is guaranteed.

## Host storage

Recommended layout:

```text
~/.lfg/
├── journal.db
│   └── browser_frames metadata table (no image blobs)
└── browser-frames/
    └── <safe-session-key>/
        └── <content-hash>.<ext>
```

Why:

- Keep image blobs out of the SSE journal and SQLite WAL.
- Preserve history across `lfg serve` restarts.
- Keep screenshots on the owning host; do not sync them between hosts or to a
  cloud service.
- Content hashes preserve deduplication and make frame URLs immutable.
- Metadata remains queryable without walking the filesystem.

Publish algorithm:

```text
validate type/size
  → hash bytes and suppress consecutive duplicate
  → atomically write image if absent
  → insert metadata with session/action correlation
  → append latest-frame SSE event
  → prune expired/over-quota frames
```

The SSE event must be emitted only after the bytes and metadata are readable, so
an iOS client never receives a frame it immediately cannot fetch.

## Retention recommendation

Use all three bounds; whichever is reached first wins:

- 14-day time-to-live, aligned with the existing event journal
- 200 frames per session
- 500 MB total browser-frame storage per host, oldest-frame-first pruning

These should be named constants and observable in diagnostics before becoming
user settings. A 200-frame session is enough to backtrace a substantial browser
flow while the global quota prevents abandoned sessions from consuming disk
without bound.

Persisting browser screenshots is a material privacy change. The UI should say
“Stored on this host for up to 14 days,” and Settings should provide `Clear
Browser Preview History`. Deleting a session need not silently delete history in
v1 unless session deletion already promises data erasure; explicit clearing is
safer than ambiguous lifecycle coupling.

## API shape

Keep the existing immutable frame fetch:

- `GET /api/browser/frame?sessionId=…&frameId=…`

Add cursor-paginated metadata:

- `GET /api/browser/frames?sessionId=…&beforeSequence=…&limit=30`
- Returns newest-first metadata, `nextBeforeSequence`, and whether more history
  exists.

Keep the existing latest metadata endpoint as a cheap cold-launch baseline, or
implement it internally as `frames(limit: 1)`.

Do not send frame bytes through SSE. SSE continues to announce only the newest
metadata; the timeline endpoint backfills history on demand.

## iOS loading model

`SessionStore` remains the source of truth for per-session metadata and viewer
selection. Full-size decoded images belong in a bounded `NSCache`, not observable
model state.

Loading strategy:

1. Open with the current latest frame already available.
2. Fetch the newest 30 metadata records.
3. Fetch only the selected image and prefetch its immediate neighbors.
4. Downsample decoded images to the presentation size.
5. Fetch the next metadata page when the scrubber approaches the oldest loaded
   frame.
6. Cancel obsolete image tasks during fast scrubbing.

A thumbnail filmstrip is desirable but should not force server-side image
processing in the first pass. Begin with a compact tick/thumbnail hybrid using
client-cached frames; add stored thumbnails only if measured bandwidth or decode
latency demands them.

## Failure behavior

| Failure | User-visible behavior |
| --- | --- |
| Host restarted | Persisted history reloads; latest resumes when new frames arrive |
| Owner host offline | Timeline shows cached metadata/current image if available plus “Host offline”; no false empty state |
| Frame pruned while viewing | Keep its timeline position and show “Screenshot expired” |
| Image fetch fails | Retry action on the frame; adjacent frames remain browsable |
| New frames arrive while reviewing | Selection stays fixed; `Latest +N` appears |
| Duplicate screenshot | No new timeline entry |
| Correlation unavailable | Show timestamp/source; `Jump to agent step` uses nearest timestamp and says “Approximate” |
| Storage quota reached | Prune oldest eligible frames and log counts/bytes; never stop capture silently |
| Corrupt metadata/file mismatch | Expose a gap, log frame/session IDs, and repair/delete the orphan during pruning |

## Delivery slices

### Slice 1 — dependable rewind

- Disk-backed bounded frame store and metadata table
- History list endpoint with cursor pagination
- Full-screen previous/next navigation and scrubber
- Auto-follow versus review state
- Restart, retention, isolation, and slow-scrub tests

### Slice 2 — causality

- Capture transcript/tool-call correlation and action labels
- Show context under the selected frame
- `Jump to agent step`
- Approximate timestamp fallback

### Slice 3 — polish based on measurements

- Filmstrip thumbnails if needed
- History storage diagnostics and clear-history control
- Optional play-through at action timing or fixed speed
- Export/share only after an explicit privacy review

Recommendation: design Slices 1 and 2 together so the schema carries anchors
from day one, then ship them as one user-facing feature if implementation remains
contained. Avoid building MP4/HLS playback; it discards action semantics and
makes sparse-frame retention, pagination, and deletion harder.

## Acceptance criteria

- A user can move backward through at least 200 action-synchronized frames in a
  long-running browser session.
- History survives a server restart and remains isolated to the owning host and
  session.
- Reviewing old frames is never interrupted by new arrivals.
- Returning to latest is one tap.
- A selected frame can navigate to the producing or nearest transcript step.
- Storage is bounded, observable, and explicitly clearable.
- No frame bytes enter SSE, journal payloads, logs, or cross-host sync.
- Fast scrubbing does not cause unbounded network requests, decoded-image memory,
  or SwiftUI updates.

## Decisions to confirm

1. Adopt the visual audit trail (Option B) rather than screenshot-only rewind.
2. Persist on the host across restarts and closed-session viewing.
3. Start with 14 days / 200 frames per session / 500 MB per host.
4. Make full-screen the history-browsing surface; keep the floating card focused
   on the latest frame.
5. Treat `Jump to agent step` as core value, not a later nice-to-have.
