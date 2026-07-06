# Improvement Log — Session 20260702-testflight

## Tracker

- [ ] 2026-07-02 — First `bundle exec fastlane` attempt failed: non-interactive Bash shell used system Ruby 2.6, not rbenv 3.2.7

## Log

### 2026-07-02 — Non-interactive shell defaults to system Ruby, breaking bundler

**What happened:** Ran `bundle exec fastlane ios deploy_testflight` and got `Could not find 'bundler' (2.4.19)` — the Bash tool's non-interactive shell resolved `ruby` to `/usr/bin/ruby` (system 2.6) instead of rbenv's 3.2.7. Had to prepend `PATH="$HOME/.rbenv/shims:$PATH"`.
**Why this was slow:** One wasted deploy attempt + version discovery round-trip before the real run.
**What better looks like:** For any Ruby/fastlane command in this repo, prepend `export PATH="$HOME/.rbenv/shims:$PATH"` up front. Candidate for a project CLAUDE.md note or testflight-deploy skill gotcha.

