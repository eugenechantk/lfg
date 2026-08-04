#!/usr/bin/env python3
"""Install lfg's turn-state hook into Claude Code and codex.

Idempotent and ADDITIVE: both config files already carry hooks the user depends on
(notify.sh, atuin, the flowdeck guard), and `Stop` in particular is an array that
already has an entry. Appending to those arrays is the only safe edit; replacing an
event's list would silently disable someone else's tooling.

The hook itself is copied to ~/.lfg/bin so the installed config does not depend on
the lfg checkout staying at one path.

Run with --check to print what is installed without writing anything.
"""
import json
import os
import shutil
import sys

HOME = os.path.expanduser("~")
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lfg-agent-hook.py")
DEST = os.path.join(HOME, ".lfg", "bin", "lfg-agent-hook.py")
COMMAND = f"/usr/bin/python3 {DEST}"
EVENTS = ["UserPromptSubmit", "Stop", "SessionEnd"]

CLAUDE_SETTINGS = os.path.join(HOME, ".claude", "settings.json")
CODEX_HOOKS = os.path.join(HOME, ".codex", "hooks.json")


def already_present(groups):
    return any(
        DEST in (entry.get("command") or "")
        for group in groups
        for entry in group.get("hooks", [])
    )


def install_into(path, create_if_missing):
    if not os.path.exists(path):
        if not create_if_missing:
            return f"skipped (no {path})"
        cfg = {}
    else:
        with open(path) as fh:
            try:
                cfg = json.load(fh)
            except Exception as exc:
                return f"FAILED to parse {path}: {exc}"

    hooks = cfg.setdefault("hooks", {})
    added = []
    for event in EVENTS:
        groups = hooks.setdefault(event, [])
        if already_present(groups):
            continue
        # No matcher: turn-lifecycle events are not tool-scoped, and an absent
        # matcher means "all" in both harnesses.
        groups.append({"hooks": [{"type": "command", "command": COMMAND}]})
        added.append(event)

    if not added:
        return "already installed"

    backup = path + ".lfg-backup"
    if os.path.exists(path) and not os.path.exists(backup):
        shutil.copy2(path, backup)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    return "added " + ", ".join(added) + f" (backup: {os.path.basename(backup)})"


def main():
    check = "--check" in sys.argv
    os.makedirs(os.path.dirname(DEST), exist_ok=True)
    if not check:
        shutil.copy2(SRC, DEST)
        os.chmod(DEST, 0o755)
    print(f"hook script: {DEST} {'(would copy)' if check else '(copied)'}")

    if check:
        for label, path in (("claude", CLAUDE_SETTINGS), ("codex", CODEX_HOOKS)):
            present = False
            if os.path.exists(path):
                try:
                    cfg = json.load(open(path))
                    present = any(
                        already_present(cfg.get("hooks", {}).get(e, [])) for e in EVENTS
                    )
                except Exception:
                    pass
            print(f"{label:8} {path}: {'installed' if present else 'NOT installed'}")
        return 0

    print(f"claude   {install_into(CLAUDE_SETTINGS, create_if_missing=True)}")
    print(f"codex    {install_into(CODEX_HOOKS, create_if_missing=True)}")
    print()
    print("NOTE (codex only): codex pins a trusted_hash per hook entry in config.toml.")
    print("A newly added entry does not run until it is trusted — accept the prompt on")
    print("the next interactive codex start, or pass --dangerously-bypass-hook-trust.")
    print("Claude Code has no equivalent gate; its hooks are live for NEW sessions now.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
