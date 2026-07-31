# Improvement Log — Session 20260713-desktop-crash

## Tracker

- [ ] 2026-07-13 — axdriver `--contains "personal/lfg"` rejected with "unexpected argument"

## Log

### 2026-07-13 — axdriver `--contains` fails on values containing `/`

**What happened:** While verifying the desktop crash fix, `axdriver press --contains "personal/lfg"` errored with `unexpected argument: personal/lfg — Options must use --name value form`, even though the skill doc lists `--contains` as a shared matcher. Worked around it by matching untitled header buttons with `--index`.
**Why this matters:** The skill's documented matcher silently doesn't cover a common case (titles with slashes, or possibly `--contains` on `press` at all), costing a retry loop each time.
**What better looks like:** Reproduce minimally (`--contains` with and without `/`, on `find` vs `press`), fix axdriver's arg parsing or document the limitation + the `--index` fallback in the macos-test skill.
