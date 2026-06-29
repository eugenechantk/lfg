# Improvement Log — Session 20260629-qa-fidelity

## Tracker

- [ ] 2026-06-29 — Asked a clarifying symptom question that went unanswered, then proceeded; could have led with the safe additive fix first

## Log

### 2026-06-29 — Clarifying question went unanswered before proceeding

**What happened:** For the iOS Q&A panel request ("see full question/option/description/display text"), I traced the data path, found the iOS model dropped `header`/`multiSelect`, then asked the user to confirm the exact on-screen symptom. The user didn't answer, so I proceeded with the unambiguous additive fix anyway.
**Why this was mildly inefficient:** The header/multiSelect/no-clip fix is correct regardless of which symptom they have — it drops no data and adds the missing "display text" (header). I could have implemented it first and asked only if a deeper pane-fallback bug remained.
**What better looks like:** When investigation reveals a clearly-correct, risk-free additive fix that covers all candidate symptoms, ship it first and reserve the clarifying question for the part that genuinely forks (here: whether descriptions are missing due to the pane-scrape fallback winning over the transcript source).
