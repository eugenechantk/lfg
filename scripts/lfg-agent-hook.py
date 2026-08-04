#!/usr/bin/env python3
"""Record an agent's own turn transitions for lfg.

Installed as a Claude Code / codex hook. Both harnesses pass the same JSON on
stdin — `session_id`, `hook_event_name`, `transcript_path` — so ONE script serves
both; `turn_id` is codex-only and simply absent for Claude Code.

Writes `~/.lfg/agent-state/<session_id>.json`. A file, not an HTTP POST: a hook
fires in a short-lived process that must not depend on `lfg serve` being up, and
the server is restarted often enough that coupling the two would drop events.

Never fails loudly. A hook that exits non-zero on Claude Code's `UserPromptSubmit`
BLOCKS the prompt (exit 2) — so every error path here is swallowed and exits 0.
Losing a state update costs accuracy for one tick; blocking a turn costs the user
their prompt.
"""
import json
import os
import sys
import tempfile
import time

# Claude Code fires Stop only on a clean turn end — an ESC interrupt fires
# nothing at all, leaving "running" behind. That stale value is expected and is
# resolved upstream by the transcript layer, which records the interrupt; see
# `sessionTurnState` in src/session-state.ts. Do not try to fix it here.
EVENT_STATE = {
    "UserPromptSubmit": "running",
    "Stop": "idle",
    "StopFailure": "idle",
    "SessionEnd": "ended",
}


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0

    sid = payload.get("session_id")
    event = payload.get("hook_event_name")
    state = EVENT_STATE.get(event)
    # Unknown or non-turn events (PreToolUse, PreCompact…) are not state changes.
    if not sid or not state or not isinstance(sid, str):
        return 0
    # `session_id` becomes a filename — refuse anything that could escape the dir.
    if "/" in sid or "\\" in sid or sid.startswith("."):
        return 0

    record = {
        "sessionId": sid,
        "state": state,
        "event": event,
        "at": int(time.time() * 1000),
        "transcript": payload.get("transcript_path") or None,
        "turnId": payload.get("turn_id") or None,
        "cwd": payload.get("cwd") or None,
        # SessionEnd only. Distinguishes a session that genuinely went away
        # ("prompt_input_exit", "logout", "other") from one whose id simply
        # rolled over inside a still-running process ("clear", "resume"). lfg's
        # `closed` is otherwise inferred from ABSENCE — see
        # .claude/feature/closed-state-derivation.md — and absence cannot tell
        # those apart, nor tell either from a host that just went offline.
        "reason": payload.get("reason") or None,
    }

    # Preferred target: the LEASE, next to the transcript. `transcript_path` is
    # in our payload, and the lease path is a pure function of it — so we can
    # write the session's state with no server, no config, and no lookup. That
    # matters twice over: hooks fire while `lfg serve` is restarting, and the
    # lease lives in the SYNCED tree, so this state reaches the other host too.
    #
    # We own `state`/`stateAt`/`stateEvent`/`endReason` and must leave lfg's
    # liveness fields (hostId/pid/acquiredAt/heartbeatAt) untouched — see
    # LeaseRecord in src/leases.ts. lfg's `renewLease` does the same in reverse.
    transcript = payload.get("transcript_path")
    target = None
    if isinstance(transcript, str) and transcript:
        target = os.path.join(os.path.dirname(transcript), sid + ".lease.json")

    if target is None:
        # No transcript in the payload — fall back to the host-local store so a
        # state update is still recorded rather than dropped.
        root = os.environ.get("LFG_AGENT_STATE_DIR") or os.path.join(
            os.path.expanduser("~"), ".lfg", "agent-state"
        )
        target = os.path.join(root, sid + ".json")
        merged = record
    else:
        existing = {}
        try:
            with open(target) as fh:
                loaded = json.load(fh)
            if isinstance(loaded, dict):
                existing = loaded
        except Exception:
            existing = {}
        merged = dict(existing)
        merged["state"] = state
        merged["stateAt"] = record["at"]
        merged["stateEvent"] = event
        if record.get("reason"):
            merged["endReason"] = record["reason"]

    # A session that genuinely ENDED releases its lease instead of annotating it.
    # `closed` has exactly one definition — "no fresh lease" — so releasing is how
    # the hook makes that resolve NOW rather than after the 90s heartbeat window,
    # without introducing a second thing for readers to check.
    #
    # `clear` and `resume` are excluded on purpose: those roll the session id over
    # inside a process that is still very much alive. Releasing there would report
    # a running agent as closed — the dangerous direction.
    ROLLOVER = ("clear", "resume")
    if (
        state == "ended"
        and target.endswith(".lease.json")
        and record.get("reason") not in ROLLOVER
    ):
        try:
            os.unlink(target)
        except Exception:
            pass
        return 0

    tmp = None
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        # Atomic replace: lfg may read this at any moment, and a torn write would
        # parse as garbage — which for the lease means losing LIVENESS, not just
        # turn state.
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=".tmp-")
        with os.fdopen(fd, "w") as fh:
            json.dump(merged, fh)
        os.replace(tmp, target)
    except Exception:
        if tmp:
            try:
                os.unlink(tmp)
            except Exception:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
