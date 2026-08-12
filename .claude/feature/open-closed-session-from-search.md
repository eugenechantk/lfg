# Opening a closed session gets stuck on "Opening session…"

**Reported:** 2026-08-12 — "In the iOS client I can't open sessions that are already
closed, like the 50 Strong (fiftyworkout) ones." Symptom, from Eugene: *"shows opening
sessions indefinitely."*

## Ground truth (server is innocent)

Probed the Pro's live server directly:

| Check | Result |
| --- | --- |
| fiftyworkout transcripts on disk | 23 |
| `GET /api/sessions/resumable?q=fiftyworkout` | 19 closed rows |
| `GET /api/sessions/<id>/messages` for `dfe2b671…`, `5f2c4999…`, `03533b45…` | 200, real content |

So every FiftyStrong conversation is present, closed, searchable, and its transcript
fetches fine. The break is entirely client-side.

## Why FiftyStrong specifically

The **newest 100 resumable rows are all gbrain-autopilot temp-cwd sessions** (67
`gbrain-claude-cli-cwd-*` project dirs on this host — see memory
`gbrain-autopilot-temp-cwds`). FiftyStrong's newest closed transcript is far below that
flood, so in practice the only way Eugene reaches one is **search** — which is exactly
the path that is broken. That is why this reads as "closed sessions don't open" rather
than "one session doesn't open".

## Root cause A — a search result is not a session the detail view can resolve

`RootView`'s detail column binds through `store.session(selection)`; when that returns
nil it renders `DetailLoading()` — the literal "Opening session…" spinner, with no
timeout and nothing that ever retries. It is a *fallback*, not a load state.

`SessionStore.session(_:)` (`ios/LFG/SessionStore.swift:2402`) resolves an id from four
places:

1. `sessions` (live + the closed pages actually paged in)
2. `remappedIds` (placeholder → real id)
3. `focusedSnapshot` (session reaped while focused)
4. `deepLinkSession` (closed session a *notification* deep-linked to)

`searchResults` is **not** one of them. But `SessionListView.matchingSessions`
deliberately renders a UNION of `store.filteredSessions` and `store.searchResults`
(`SessionListView.swift:92-101`) — closed matches come from the host's whole-corpus
index, not from `sessions`. So a search-only row is tappable, sets `selection`, and then
resolves to nothing. Stuck spinner, forever.

The notification path got an explicit escape hatch for exactly this problem
(`deepLinkSession`). The search path, added later, did not.

## Root cause B — the notification escape hatch can't reach an old session either

`resolveDeepLink` (`SessionStore.swift:454`) resolves a closed deep-link by scanning
`client.resumable(limit: 80)` for the sid. Verified against the live host: the newest 80
rows do **not** contain `5f2c4999…`. Every FiftyStrong session is out of reach, so a
tapped push for one lands on the same stuck spinner.

Two further defects in the same function:

- It uses `client` (the host-agnostic default) rather than every configured host, so a
  session whose transcript is only newest on a peer is missed in a multi-host setup.
- A miss leaves `deepLinkSession` nil with no user-visible signal.

The server already supports the exact query needed: `sessionId` is part of the search
haystack (`entryHaystack`, `src/session-index.ts:137`), so
`?q=<sessionId>` is a one-request exact lookup. Verified: returns exactly 1 hit.

## Success criteria

- **SC1** Typing a query that only matches a closed session, then tapping the result,
  opens its detail view with the transcript — no "Opening session…".
- **SC2** The opened session survives the search being cleared or edited while its
  detail view is on screen (it must not blank back to the spinner).
- **SC3** A deep link (notification tap) to a closed session older than the newest 80
  resumable rows opens it.
- **SC4** SC3 works when the transcript's newest copy is on a non-default host.
- **SC5** No duplicate/ghost rows in the list, and a session that is live still resolves
  to its live copy, not a closed stand-in.

## Approach

1. `session(_:)` gains `searchResults` as a fifth fallback — **last**, so a live copy
   always wins (SC5).
2. Latch on focus: when the detail view calls `focus(id)` and the id resolves only via
   `searchResults`, copy it into the held-closed-session slot so clearing the search
   can't blank the open detail (SC2). Reuses the existing `deepLinkSession` slot, whose
   meaning widens from "notification deep-link" to "closed session held open".
3. `resolveDeepLink` looks the sid up by `?q=<sessionId>` across **all reachable hosts**
   instead of scanning the default host's newest 80 (SC3, SC4).

Edits are confined to `ios/LFG/SessionStore.swift`, which is clean at HEAD —
`RootView.swift` and `SessionListView.swift` are dirty with other agents' in-flight work
(3+ concurrent lfg sessions), so nothing is touched there.

## Verification

Live on iPhone 17 Pro (sim `cc-ba11a488` / `4CDA1D87…`), real onboarding, real search
field, real taps — per `verify-ui-by-tapping`, a unit test is not evidence here.
Evidence: `.claude/evidence/20260812-open-closed-session/`.

| SC | Result | Evidence |
| --- | --- | --- |
| SC1 search-result tap opens | **PASS** | `03-search-results.png` → `04-opened-fixed.png` — typed "up until now", got 3 closed matches, tapped the fiftyworkout one, transcript + composer render |
| SC2 survives search clear/edit | **By construction, not gestured** | Latch fires in `focus(_:)`; on iPhone the list is covered by the pushed detail so the query can't be edited while it's on screen. Untested on regular width (iPad). |
| SC3 deep link to an old closed session | **PASS** | `05-deeplink-old-closed.png` — `lfg://session/5f2c4999…`, a session proven absent from the newest 80, opens |
| SC4 deep link resolves on a non-default host | **Not tested** | Single host configured on the test sim. Code asks every reachable host in turn. |
| SC5 live session still resolves live | **PASS** | `06-live-session-still-live.png` — live fiftyworkout session opens streaming, with an enabled composer, not a closed stand-in |

### That the fix is what made SC1 pass

The tapped row had to come from `searchResults` and nowhere else, which is what makes
the `session(_:)` change causal rather than incidental:

- The client's first closed page is `resumable(limit: 60)` (`SessionStore.swift:1555`).
- That page contains **59/60 gbrain-autopilot temp cwds** and does **not** contain
  `dfe2b671…`, the row that was tapped (verified by direct API call).
- So the row existed only in `searchResults`, and at HEAD `session(_:)` had four
  lookups, none of them `searchResults` → nil → `DetailLoading` — Eugene's exact
  reported symptom, "shows opening sessions indefinitely".

**Not captured:** a screenshot of the pre-fix stuck spinner. Reproducing it would have
meant reverting `SessionStore.swift` in a tree that 3+ concurrent lfg agents are working
in. The chain above plus the original report is the evidence instead.

## Not fixed here — and muting alone does NOT cover it

The gbrain-autopilot flood is what makes the closed list unusable and forces search in
the first place. The directory-filter feature (another session's work, complete and
uncommitted in the tree) mutes it — verified live: entering the pattern
`*/gbrain-claude-cli-cwd-*` saves and the list stops showing those rows
(`11-hidden-list.png`).

**But muting does not make FiftyStrong browsable, because the mute is applied
client-side, after paging.** The server pages 60 raw rows and the client hides what
matches. Measured against the live corpus, walking the closed list with the mute on:

| Load-more taps | Rows fetched | Closed rows actually visible |
| --- | --- | --- |
| 1 | 60 | 1 |
| 2 | 120 | 2 |
| 3 | 180 | 3 |
| 4 | 240 | 7 |
| 5–8 | 480 | 7 (pages 5–8 are 100% gbrain) |

Eight pages in, FiftyStrong is still not reached. The UI confirms it: with the mute on,
the closed section reads **"Closed, 1"** (`12-closed-list-clean.png`).

So **search is the only working route to these conversations**, which is exactly why the
fix in this document is load-bearing rather than a nicety.

The structural fix — pass the mute list to the server so it pages *visible* rows — is not
attempted here; it belongs with the directory-filter feature and its own session.
