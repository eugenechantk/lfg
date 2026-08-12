# Improvement Log — Session 405f48f7-6e70-4f8e-97ea-ec618cba5d81

## Tracker

- [ ] 2026-08-09 — Ran the session-start checklist *after* the first substantive tool calls, not before

## Log

### 2026-08-09 — Session-start checklist ran late

**What happened:** Eugene's first message was a question about `<synthetic>` sessions. I went straight to grepping the codebase and only ran `git pull` + created this improvement log several tool calls in.
**Why this was wrong:** The global CLAUDE.md checklist is explicitly "on the very first message of every session, before addressing the user's request." A read-only question doesn't exempt it — the whole point is that the log exists from turn one so observations aren't lost.
**What better looks like:** First action of any top-level session, regardless of how trivial the request looks: `git pull origin`, create `improvement-log/improvement-log-$CLAUDE_SESSION_ID.md`, then answer.
