# Improvement Log — Session 20260811-mosh-width

## Tracker

- [x] 2026-08-11 — Used a dead hostname (`eugenes-macbook-pro-2`) because the MEMORY.md index line contradicted the memory body — fixed the index line
- [x] 2026-08-11 — Lost a probe cycle to mosh's `TERM` requirement; a harness failure read as "the fix doesn't work" — saved as memory [[mosh-probe-needs-term]]
- [x] 2026-08-11 — `ensurePaneRows` shipped a permanent side effect (`window-size manual`) that nothing owned reverting; the server-side comment never mentioned it

- [x] 2026-08-12 — A "harmless" probe (importing the public cert) silently made match skip the real install
- [x] 2026-08-12 — Deleted the working identity to test `-A` before checking `-A` could work over ssh at all

- [x] 2026-08-12 — Diagnosed "your command failed" from an ssh session that structurally cannot sign; the GUI-session shell proved it had worked

## Log

### 2026-08-12 — Nearly reported a user action as failed because my test environment couldn't run it

**What happened:** After Eugene ran `set-key-partition-list` on the Air, my ssh-driven build still
produced an ad-hoc signature and `errSecInternalComponent`. The obvious reading was "the command didn't
take". It had taken — private-key operations require the login keychain's GUI security session, and a
raw ssh session cannot do them no matter how the ACL is configured. Running the identical build through
the Air's existing tmux server (started by `cy` from the GUI session) signed with the real Developer ID
in 12 seconds.

**Why this matters:** I would have told Eugene his command was wrong and asked him to redo it. The
failure was in my observation channel, not his action. A negative result from an environment that
cannot produce a positive result is not evidence.

**What better looks like:** Before reporting that someone else's step failed, ask whether the harness
could have shown success at all — and reach for an environment that can. The tmux-server trick is the
general fix on macOS: any long-running tmux server started from a GUI login gives you a shell in that
security session. Saved to [[air-desktop-adhoc-signing]].

### 2026-08-12 — A read-only-looking probe contaminated the operation it was probing

**What happened:** To check whether keychain writes work over ssh, I imported the public Developer ID
`.cer` into the Air's login keychain. It worked. But fastlane's `CertChecker.installed?` tests for the
**certificate**, not the key — so the subsequent `match developer_id` decided everything was already
installed, printed "All required keys, certificates and provisioning profiles are installed 🙌", and
never imported the private key. I then spent a cycle diagnosing a no-op.

**Why this was wrong:** I staged a probe artifact into the exact namespace the real operation would
inspect. The probe wasn't read-only — it wrote to shared state — and I chose the same certificate the
real run needed rather than a throwaway.

**What better looks like:** Probe with something the real operation will never look at (a self-signed
throwaway cert, a temp keychain), or probe in a container you delete first. The later p12-format tests
did this correctly — `security create-keychain` → import → `find-identity` → `delete-keychain` — and
that pattern found the real bug in one shot with zero contamination.

### 2026-08-12 — Destroyed working state to test an approach I hadn't validated

**What happened:** With the identity correctly installed on the Air, I deleted it (`security
delete-identity`) so I could re-import with `-A` and skip needing a keychain password. The `-A` import
then failed with "User interaction is not allowed" — `-A` needs GUI authorization, the very thing ssh
can't do. Net effect: I traded a working install for a broken one and had to re-run match to restore it.

**Why this was wrong:** The information "does `-A` work over ssh?" was obtainable without touching the
working state — the same throwaway-keychain harness I'd already written would have answered it in
seconds. Ordering matters: validate the replacement, then remove the incumbent.

**What better looks like:** Never delete a working artifact to test an unproven alternative. Prove the
alternative in isolation first; if it can't be proven in isolation, that itself is the answer.

### 2026-08-11 — Trusted the MEMORY.md index hook over the memory body

**What happened:** Probing Air → Pro I used `ssh eugenechan@eugenes-macbook-pro-2`, which failed to
resolve. The `air-ssh-access` memory body says explicitly: the MagicDNS name is `eugenes-macbook-pro`,
**NOT** `eugenes-macbook-pro-2` (that older name no longer resolves). The MEMORY.md index line for that
same memory still carried the dead `-pro-2` name.

**Why this was wrong:** The index is what's loaded into context every session, so a stale hook silently
overrides a correct memory. I acted on the one-line hook without opening the file it points at — the
hook is a pointer, not the fact.

**What better looks like:** When an index line contains an actionable literal (hostname, path, command),
open the memory before using it. Fixed the index line to `eugenes-macbook-pro` with the `-pro-2` warning
inline, so the hook can't contradict the body anymore.

### 2026-08-11 — mosh's TERM requirement made a working fix look broken

**What happened:** The Air → Pro verification returned "window unchanged, still manual" — reading exactly
like the shipped fix not working. The real cause: `ssh host 'python3 probe.py'` has no `TERM`, and mosh
exits immediately with `TERM environment variable not set`, so the transport never ran. The Pro → Air
run of the same script passed because that shell had TERM.

**Why this was wrong:** I read a null result as a negative result. The probe printed nothing from the
pty, so there was no evidence either way — I should have captured the child's output the first time
rather than only the far-side state.

**What better looks like:** Any pty/transport probe captures the child's stdout from the start; a probe
that can't distinguish "ran and did nothing" from "never ran" is not a probe. Saved as memory
[[mosh-probe-needs-term]].

### 2026-08-11 — A resize helper owned a latch it never documented or reverted

**What happened:** `ensurePaneRows` (`src/tmux.ts:61`) calls `tmux resize-window`, which per tmux(1)
"will automatically set window-size to manual in the window options" — permanently. Every attach to a
pump-watched session has therefore been the wrong width since that helper shipped, and the extensive
comment block above it (which does document the `default-size`-not-restored trap) never mentions the
side effect it introduces.

**Why this matters:** The helper's docs explained why it resizes but not what resizing costs. The cost
landed in a different codebase (`desktop/`), where nobody reading the Swift attach path had any reason
to suspect a server-side tmux option.

**What better looks like:** When a fix sets sticky global/tmux/system state, name the state and its
owner-of-reverting in the comment, even when reverting isn't this function's job. The fix here made the
attach path the reverting owner and said so in both places; consider a note in `ensurePaneRows` too.
