# Feature: iOS file attachments (photos/videos + arbitrary files)

## User Story

As someone driving Claude Code sessions from my phone, I want to attach **any**
file — not just photos — to a message I send into a session, so the agent can
read the PDF, log, CSV, or screen recording I'm looking at without me having to
get to a laptop and copy it onto the host myself.

## User Flow

1. Open a session (or the new-session draft screen).
2. Tap the paperclip in the composer.
3. A menu appears with two choices: **Photos & Videos** and **Files**.
4. Pick either:
   - *Photos & Videos* → system photo picker, multi-select images **and** videos.
   - *Files* → system document picker (`fileImporter`), multi-select any type.
5. Picked items appear as chips above the input: images/videos as thumbnails,
   other files as an icon + filename + size chip. Each has an ✕ to remove.
6. Type a message (optional) and tap send.
7. Bytes upload to the host, which persists them under `$TMPDIR/lfg-uploads/`
   **keeping the original filename**, and the absolute paths are appended to the
   message text so the agent can read them.
8. The sent bubble renders the attachment as a tappable card / inline image.

## Success Criteria

- [x] SC1: The composer's paperclip opens a menu with exactly two options —
  "Photos & Videos" and "Files" — instead of going straight to the photo picker.
  **Verify by:** simulator screenshot of the open menu (FlowDeck UI automation).
- [x] SC2: Selecting *Photos & Videos* allows picking **videos** as well as
  images (the current picker is `matching: .images` only).
  **Verify by:** simulator — open picker, confirm videos are selectable, pick one,
  confirm a video chip appears in the composer. Screenshot.
- [x] SC3: Selecting *Files* opens the document picker and a non-image file
  (e.g. `.pdf`, `.txt`) attaches, shown as a named chip (not a blank thumbnail).
  **Verify by:** simulator — seed a file into the sim's Files provider, attach it,
  screenshot the chip showing the real filename.
- [x] SC4: The host stores an uploaded file under its **original filename** and
  returns a path that `/api/file` will serve.
  **Verify by:** `curl` POST of a `.pdf` to `/api/sessions/<id>/upload` with the
  filename header → response path ends in the original name; `curl /api/file?path=…`
  returns 200 with matching bytes.
- [x] SC5: Filename sanitization is safe — path traversal (`../`), separators,
  spaces, control chars, and absurd lengths cannot escape the upload dir or
  produce a path that breaks the appended-path message text.
  **Verify by:** LFGCore unit tests over the pure sanitizer + a server-side
  `curl` with `X-LFG-Filename: ../../etc/passwd` → stored inside the upload dir.
- [x] SC6: Content type is preserved end to end — a JPEG uploads as JPEG (not
  re-encoded to PNG), a PDF as `application/pdf`.
  **Verify by:** LFGCore unit tests on the extension→content-type mapping, plus
  the SC4 curl round-trip asserting `Content-Type` from `/api/file`.
- [x] SC7: An attachment queued while **offline** replays after reconnect with
  its filename and content type intact (not flattened to `image/png`).
  **Verify by:** LFGCore unit tests on the outbox sidecar name codec
  (`<index>__<filename>` round-trip incl. the legacy `<index>.png` form).
- [x] SC8: A message sent with an attachment renders in the transcript as an
  attachment card / inline image, and the file opens when tapped.
  **Verify by:** simulator end-to-end against a real host — attach, send, screenshot
  the transcript bubble, tap the card, screenshot the viewer.
- [x] SC9: Nothing regresses for the existing image-attach path (pick photo →
  send → renders inline).
  **Verify by:** `swift test` green + simulator run of the original flow.

## Platform & Stack

- **Platform:** iOS 17+ client (SwiftUI) + Bun/TypeScript host server
- **Language:** Swift 6 (strict concurrency), TypeScript
- **Key frameworks:** SwiftUI, PhotosUI, UniformTypeIdentifiers, Bun.serve
- **Tests:** `swift test` in `ios/LFGCore`, `bun test` in repo root

## Steps to Verify

1. `cd ios/LFGCore && swift test` — LFGCore unit tests.
2. `bun test src/upload*.test.ts` — server upload naming tests.
3. `flowdeck simulator boot "iPhone 17 Pro"` then build/install via FlowDeck.
4. Tap paperclip → verify menu (SC1); pick a video (SC2); pick a file (SC3).
5. `curl` the upload endpoint directly for SC4/SC5/SC6.
6. Send with attachment → verify transcript card + tap-to-open (SC8).

## Implementation Phases

### Phase 1: Core model + naming (LFGCore, pure, tested)

- Scope: `Attachments.swift` in LFGCore — `AttachmentKind`, `AttachmentMeta`,
  filename sanitizer, extension↔content-type mapping, outbox sidecar name codec.
  Unit tests for all of it.
- Success criteria covered: SC5, SC6, SC7 (unit half)
- Verification gate: `swift test` green.

### Phase 2: Server upload endpoint

- Scope: `/api/sessions/:id/upload` accepts `X-LFG-Filename`, stores under a
  per-upload subdirectory preserving the original name, widens the content-type
  map, sanitizes defensively.
- Success criteria covered: SC4, SC5 (server half), SC6 (server half)
- Verification gate: `bun test` + live `curl` round-trip through `/api/file`.

### Phase 3: iOS transport + store

- Scope: `LFGClient.upload` filename param; `SessionStore` send + outbox
  persistence/replay carry filename and content type.
- Success criteria covered: SC6, SC7
- Verification gate: `swift test` green; existing send path unbroken.

### Phase 4: Composer UI

- Scope: paperclip → menu; photos picker widened to images+videos; `fileImporter`;
  generalized `ComposerAttachment` + chip rendering for non-visual files.
- Success criteria covered: SC1, SC2, SC3, SC9
- Verification gate: simulator screenshots of each surface.

### Phase 5: End-to-end verification

- Success criteria covered: SC8 + re-verify all
- Verification gate: `ios_visual_evidence_auditor` PASS.

## Decision Log

_Decisions made autonomously during this task._

- **Store uploads in a per-upload subdirectory** (`lfg-uploads/<sid>-<ts>-<rand>/<original-name>`)
  rather than mangling the filename into a flat name. Alternative was
  `<sid>-<ts>-<rand>-<name>.<ext>`, which is collision-free but shows the user a
  card labeled `a1b2…-report.pdf`. `MediaRef.filename` is the last path
  component, so the subdirectory gives a clean card label for free, and
  `/api/file`'s containment check is prefix-based against `tmpdir()`, so nesting
  is already allowed.
- **Sanitized filenames replace whitespace with `_`.** The upload path is appended
  to the message text as a bare token; both `MediaScanner`'s bare-ref regex and
  the shell-ish way the agent consumes the path break on spaces. Losing the space
  is a much smaller cost than an unreadable path.
- **Images pass through in their original encoding** (png/jpeg/gif/webp) instead
  of the current unconditional `img.pngData()`. HEIC — the iPhone default — is
  transcoded to JPEG because the Anthropic API does not accept HEIC image input.
  This also stops a 3 MB HEIC becoming a 15 MB PNG on every photo send.
- **Photos-picker items get generated filenames** (`IMG_<short>.<ext>` /
  `VID_<short>.<ext>`). PhotosUI exposes no reliable original filename without a
  custom `FileRepresentation` round-trip through disk; the document picker path
  (where names actually matter) does have real names via `url.lastPathComponent`.
- **Outbox sidecars are named `<index>__<filename>`** rather than gaining a
  separate `manifest.json`. Self-describing, atomic (no file/manifest skew), and
  the legacy `<index>.png` form stays readable so already-queued offline messages
  still replay after the upgrade.
- **Client-side size cap** on attachments so a 4 GB screen recording can't OOM
  the app or wedge the single-process host; over the cap surfaces a visible error.

## Verification Evidence

Evidence directory: `.claude/evidence/20260816-ios-file-attachments/`

Verification ran against a **scratch server on port 8793** (new code) rather than
the live host on 8766, so nothing Eugene had running was disturbed. Test session
`eeefae45-…` was created in `~/dev/inbox` for the end-to-end run and closed
afterwards; the scratch server was stopped and port 8766 (pid 6774) was confirmed
untouched throughout.

| SC | Method run | Result | Artifact |
| --- | --- | --- | --- |
| SC1 | Tapped paperclip in BOTH composers | Menu shows exactly "Photos & Videos" + "Files" | `07-SC1-attach-menu.png` (new-session), `23-SC1-session-menu.png` (session) |
| SC2 | Opened picker with a 2s mp4 in the sim library | Video tile offered with `0:02` badge — impossible under the old `matching: .images`; attached as `VID_037398.mp4` | `08-SC2-photo-picker.png`, `09-SC2-video-chip.png` |
| SC3 | Seeded `Q3 Sales Report.pdf` + `metrics.csv` into "On My iPhone", attached both | Named chips with real filenames, sizes and per-type icons; space sanitized to `Q3_Sales_Report.pdf` | `14-SC3-file-chips.png`, `15-SC3-chips-scrolled.png` |
| SC4 | `curl` POST pdf + `X-LFG-Filename`, then GET `/api/file` | Stored as `…/lfg-uploads/<sid>-<ts>-<rand>/Q3_Sales_Report.pdf`; `/api/file` → `HTTP 200`, bytes `cmp`-identical | command output below |
| SC5 | 17 `bun test` cases + live `curl` with `../../etc/passwd`, `/etc/shadow`, `..`, `....//....//x.png` | Every payload contained inside the upload dir; `/etc/passwd` untouched | `bun test src/upload-names.test.ts` (17 pass) |
| SC6 | Unit tests + `/api/file` response header | `Content-Type: application/pdf`; mp4 stored at 11402 B = byte-identical to source (no PNG re-encode) | server file listing below |
| SC7 | 6 `swift test` cases on the sidecar codec | `<index>__<filename>` round-trips; legacy `<index>.png` still parses; ordering numeric not lexicographic | `swift test` (84 pass) |
| SC8 | Attached `metrics.csv` + text in the **session composer**, sent | Card rendered in transcript; agent ran `Read {"file_path": "/var/folders/…/lfg-upl…"}` and answered with the file's real contents (`date, region, revenue`) | `26-session-composed.png`, `27-SC8-session-sent.png`; PDF viewer opens with correct title in `22-SC8-pdf-open.png` |
| SC9 | Full suites + photo attach/send | `swift test` 84 pass, `bun test` 646 pass; photo still attaches as an inline thumbnail and sends | `21-SC8-csv-card.png` |

Host-side result of the end-to-end send (all four byte-exact, original names):

```
VID_037398.mp4       11402
IMG_7D4730.png        7875
Q3_Sales_Report.pdf      69
metrics.csv              59
```

## Bugs

### Fixed: non-media attachments rendered as a raw path, not a card

**Found by** the SC8 end-to-end run: `metrics.csv` came back in the transcript as
a wall of raw `/var/folders/…` path text while the mp4, png and pdf all rendered
as cards.

**Cause:** `MediaScanner.scan` only claims a *bare* path when its extension maps
to a known `MediaKind` (`allowAny: false`), deliberately, so that prose merely
mentioning a file doesn't become a card. That restriction was invisible while
attachments could only ever be images; allowing arbitrary files exposed it.

**Fix:** a bare path inside `/lfg-uploads/` is by construction something a user
attached, so it now claims any extension (`MediaScanner.isUploadedAttachment`).
Prose mentioning `/Users/e/out/data.csv` still does not become a card — covered
by a regression test.

**Verified:** `21-SC8-csv-card.png` shows `metrics.csv` as a card; 4 new tests in
`UploadedAttachmentScanTests`.

## Follow-ups (not in scope, flagged for Eugene)

1. **The live host must be restarted to get the server half.** Port 8766 (pid
   6774) started `Sun Aug 16 16:48`, before `src/commands/serve.ts` was changed at
   `21:20`. Until it restarts, a phone pointed at the real host uploads through
   the OLD endpoint, which ignores `X-LFG-Filename` and names every non-image
   `.jpg`. Not restarted here on purpose: it drops in-memory session tracking for
   live sessions, and other agents are running.
2. **New-session sends attachments as a SECOND message.** `attemptCreate` posts
   the kickoff text, then `sendWithAttachments(realId, text: "", …)`. The agent
   therefore answers the text before the files arrive — visible in the run as
   "No files were attached to that message". Pre-existing (it behaved this way
   with photos), so left alone, but it reads oddly now that attaching files is a
   headline feature.
