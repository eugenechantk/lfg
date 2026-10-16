# Transcript file cards without duplicate links

Product UI fix. The iPhone transcript should show one file card for each attachment, without a second hyperlink above it.

## Success criteria

- [x] HTML, video, document, and image handoffs render their existing cards without duplicate file links or standalone paths. Verify with Swift tests and an iPhone simulator screenshot matching the supplied example.
- [x] Surrounding prose, ordinary web links, file order, labels, and follow-up actions remain usable. Verify deterministic row-text tests.
- [x] Code examples keep their literal file paths. The stored transcript text remains unchanged. Verify row-text regressions.
- [x] Cards still open previews and expose file actions. Verify a real simulator tap and independent UI audit.

## Decision log

Assistant row text currently removes image markdown only. Every scanned file still gets a card, so ordinary markdown file links render twice. Change the shared presentation derivation used by the main and subagent transcripts. Keep the scanner, card identities, file viewers, and raw messages unchanged. Protect code examples while removing file handoffs from prose. Preserve all concurrent edits and earlier desktop/mobile work.

## Verification evidence

- The new regressions failed before implementation: 14 expected assertion failures across file-link cases (`tests-before.log`).
- All 448 LFGCore tests in 65 suites pass after the nested-list correction (`.codex/evidence/transcript-file-cards-only/core-tests-final-audit.log`). Coverage includes HTML, video, PDFs, images, duplicate references, labels/order, spaced paths, titled links, ordinary web links, filename prefixes, empty file-only lists, code fences, indented code, and inline commands.
- Final FlowDeck simulator build passed (`build-final-audit.jsonl`). Parent native inspection confirms three cards without duplicate file links, while the docs link and inline command remain visible (`parent-transcript.jpg`). Independent final visual verification passed on the frozen build: `.codex/evidence/20261017-000825-ios-visual-audit/evidence.md`.

The DEBUG session fixture now accepts optional Pro/Air URL overrides. Defaults remain unchanged; separate ports avoid interfering with another session's fixture. This task uses 18911/18912, with an isolated settings suite and in-memory test store. Production hosts and data are not involved.


## Verification notes

A nested-list regression exposed that four spaces can mean list content rather than code. The presentation now tracks the list content column before protecting indented code. The new regression failed with four assertions before correction and passes with the full suite (`nested-before.log`, `core-tests-final-audit.log`).

The final simulator app is frozen under the evidence directory's `verified-build` root to avoid concurrent builds replacing the audited candidate. The manifest covers every bundle file, including the Swift debug dylib, plus source hashes.

## Final UI evidence

The independent iPhone 17 Pro audit passed in light and dark appearance for the standard transcript and nested-list session. Screenshots show one HTML/video/image card each, no duplicate file hyperlinks, and preserved ordinary web links and code examples. A recording proves a direct card tap opens the final build's HTML preview. Video and image previews load, and the HTML share sheet presents the correct filename and type. It was dismissed without saving or sharing.

The final bundle manifest was rechecked after the audit and matches exactly. The simulator was restored to light appearance. Captures and disposable fixtures stopped; the session simulator returned to its original shutdown state. Other sessions' fixtures and all production hosts remained untouched.

## Residual risks

Verification covers the iPhone simulator and deterministic PDF/document cases. Physical devices, older OS versions, and a new TestFlight release were not part of this request. The raw transcript and card/file identities remain unchanged.
