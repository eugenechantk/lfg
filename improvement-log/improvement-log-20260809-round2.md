# Improvement Log — Session 20260809 (question preamble, round 2)

## Tracker

- [x] 2026-08-09 — Shipped a fix verified against a session shape the user never uses. Third report of the same bug.
- [x] 2026-08-09 — Treated "the mechanism works" as "the bug is fixed" without enumerating the real live sessions.
- [ ] 2026-08-09 — I twice patched a parser when the *source* was inadequate. No step in my process asks "is this source sufficient even when it works?"

## Log

### 2026-08-09 — Verified against the wrong session shape, twice

**What happened:** On 2026-08-07 I fixed the missing question preamble by (a) spawning lfg's tmux
sessions at 120x200 and (b) adding a reconciler to keep them there. I verified it by creating a
session through `POST /api/sessions/new` and watching it work. Eugene reported the bug again two
days later. His sessions come from `cy()` in `~/.zshrc`, which runs `tmux new-session` with no `-d`
and no `-x/-y` — attached, sized by the iTerm window (78x60). `paneSizeArgs()` never ran for it, and
`ensurePaneRows` skips attached panes *on purpose*. Neither half of the fix could ever have applied
to a single session he actually uses.

**Why this was wrong:** I verified the mechanism, not the situation. One `tmux ls` with
`#{window_width} #{window_height} #{session_attached}` across the real sessions would have shown, on
2026-08-07, that the panes I cared about were 78-80 columns and attached — the earlier data was even
in my own scrollback (`cy-132805-95065 w=79 h=79 attached=1`) and I read past it because the session
I had just created looked right.

**What better looks like:** for any fix that depends on the state of existing resources (panes,
processes, files, installed builds), enumerate the *real* population and check the property holds
across it — before and after. "I made a new one and it works" is a test of the constructor, not of
the fix. Added to the repo CLAUDE.md as a hard rule for pane fixes.

### 2026-08-09 — Patched the parser twice when the source was inadequate

**What happened:** Round 1 widened the pane and raised a scan cap; round 2's first instinct was
again to find the branch in `contextAbovePrompt` that returned undefined. Only after measuring did I
establish that the best possible single-capture scrape still yields 1,664 of 4,447 chars, starting
mid-sentence. No parser change could have fixed that.

**Why this was wrong:** I anchored on "the parser returns the wrong thing" because that's where the
symptom surfaces. I never asked whether the input was sufficient in principle. The measurement that
settled it (ground truth vs best-case capture) took two minutes and should have been the first thing
I did in round 1.

**What better looks like:** when a transform produces bad output, measure the *input's* information
content against the desired output before touching the transform. If the input can't contain the
answer, stop parsing and go change the source. Here that reframing produced a different and correct
solution — reconstruct the scrollback from the captures the pump already takes.

### 2026-08-09 — What actually worked, for next time

Sampling the pane during a streaming turn and checking whether the head was ever visible (frame 5:
yes; final frame: no) was the decisive experiment, and it was cheap. When information seems
unrecoverable, check whether it was observable *earlier* rather than concluding it is gone.
