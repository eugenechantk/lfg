# Improvement Log — Session 20260710-status-detection

## Tracker

- [ ] 2026-07-10 — Background watcher script died on zsh read-only variable `status`

## Log

### 2026-07-10 — Background watcher script died on zsh read-only variable `status`

**What happened:** A background polling loop used `status=$(...)` as a variable name; zsh reserves `status` as a read-only alias for `$?`, so the script exited immediately with "read-only variable: status" and the supervision gap went unnoticed until the failure notification.
**Why this was wrong:** Wasted a round-trip relaunching the watcher. This shell is zsh (stated in the environment info), and `status`/`path`/`argv` are classic zsh reserved variables.
**What better looks like:** In zsh shell snippets, never use `status`, `path`, `argv`, or `options` as variable names — prefix locals (e.g. `jstatus`).
