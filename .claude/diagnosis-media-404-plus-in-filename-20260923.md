# Media files 404 when the filename contains `+`

**Date:** 2026-09-23
**Reported as:** "I can't see any of the images in the files and link list for this
session: lfg-52b00a"
**Sequel to:** `.claude/diagnosis-media-404-spaces-in-path-20260922.md` — same
symptom, different character, and this one was written down as "latent, not fixed"
in that note the day before.

## The session

`lfg-52b00a` = `56c91326-2c9e-4ac5-8610-8f371398e6b6`, cwd
`/Users/eugenechan/dev/personal/Noto`. It handed over **9 image files** across four
`SendUserFile` turns. Probing each one through the exact URL the client builds:

| file | result | why |
| --- | --- | --- |
| `04-share-sheet-noto2-row.png` | 200 | fine |
| `09-digest-tab.png` | 200 | fine |
| `05d-session-t+0.1s-pill.jpg` | **404** | `+` in the filename |
| `08-after-add-notes-kotlin-t+3.5s.jpg` | **404** | `+` in the filename |
| `25-after-add-notes-perl-cold-t+3.5s.jpg` | **404** | `+` in the filename |
| `u2-captured.jpg`, `v3-after-add.jpg`, `y4-editor.jpg`, `y5-digest.jpg` | **404** | file no longer on disk |

So 7 of 9 failed, from **two unrelated causes**.

## Cause 1 — `+` means "space" to the server, and nobody escaped it

`+` is legal in a URL query component, so Foundation's `URLComponents` passes it
through unescaped:

```
URLQueryItem(name: "path", value: "/e/shot-t+3.5s.jpg")
  → path=/e/shot-t+3.5s.jpg
```

The server reads it with `url.searchParams.get("path")`. `URLSearchParams` applies
`application/x-www-form-urlencoded` decoding, where a bare `+` **is** a space:

```
searchParams.get("path") → "/e/shot-t 3.5s.jpg"   ← a path that does not exist
```

A filesystem path is not form data. Both sides were individually defensible and
the composition was wrong.

Only `+` has this problem. Checked every character `URLComponents` leaves raw in a
query value: `&`, `=`, `#`, `%` and space are all escaped correctly; `?` and `;`
pass through but survive parsing intact.

## Cause 2 — the file is gone

The other four were written to the session's own scratchpad under
`/private/tmp/claude-501/<project>/<session>/scratchpad/` and later removed. The
card is correct, the path is correct, the bytes are gone. Nothing to fix in code —
the viewer already says `Can't load file — Server error 404`. The lesson belongs
upstream: **a file handed to the user with `SendUserFile` must not live in the
session scratchpad**, which is explicitly ephemeral. Deliverables belong in the
working directory.

## Fix

**Client — `LFGClient.hostFileURL`** builds the query with `percentEncodedQuery`
and a new `escapedForQueryValue`, whose allowed set removes `+?;&=#`. `+` now goes
out as `%2B`.

This is the half that matters: **it works against the currently running,
unmodified server**, because `%2B` form-decodes back to `+`. All five previously
failing-or-fragile paths return 200 against the live server with no restart.

**Server — `/api/file`** no longer trusts a single reading of `?path=`.
`filePathCandidates` also decodes the raw query value with `decodeURIComponent`
(which leaves `+` alone) and offers that reading first, keeping the form reading as
a fallback so a client that really did mean a space still resolves. Each candidate
is re-checked for root containment before it can be served, so the fallback cannot
widen what is reachable. This covers any other client — the desktop app, curl, and
every build that predates the client fix.

## Verification

- `swift test` in `ios/LFGCore` — 177 pass, including three new escaping tests
  that assert `+` survives the round trip and that spaces, `&`, `=`, `?`, `;`, `#`
  and `%` still do.
- `bun test` — the new `src/api-file-path-param.test.ts` passes (7 cases). Two
  pre-existing failures in `sessions-resumable-closed.test.ts` are unrelated:
  they fail identically on a stashed (clean) tree.
- Against the **live unmodified server**, all three `+` paths went 404 → 200.
- Live on `iPhone 17 Pro`: Files & Links for `lfg-52b00a` lists all nine images,
  and `05d-session-t+0.1s-pill.jpg` now opens and renders. `y4-editor.jpg` still
  shows `Can't load file — 404`, correctly, because the file is gone.

## Note on the list itself

The Files & Links list was never the problem — it reads `store.transcripts[sid]`,
the full merged transcript, and the backward history walk does reach all 1,429
messages of this session (simulated page by page against the live server). All
nine images were listed the whole time; they just would not open.
