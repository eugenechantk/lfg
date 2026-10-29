#!/usr/bin/env python3
"""Build every `cua-*` artboard and the canvas index entries for the page
"Chat & Cua Spaces (Oct 21)".

Run:  python3 build.py
Out:  project/cua-*.dc.html  and  canvas-entries.json
"""

import json
import pathlib

import gen_spaces
import gen_chat
import gen_control
import gen_platforms

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "project"
PAGE = {"id": "cua-spaces", "name": "Chat & Cua Spaces (Oct 21)"}

ALL = {}
for mod in (gen_spaces, gen_chat, gen_control, gen_platforms):
    ALL.update(mod.BOARDS)

ORDER = [
    "cua-list.dc.html", "cua-empty.dc.html", "cua-new.dc.html", "cua-host.dc.html",
    "cua-sheet.dc.html", "cua-starting.dc.html",
    "cua-chat.dc.html", "cua-tools.dc.html", "cua-queued.dc.html", "cua-confirm.dc.html",
    "cua-signin.dc.html",
    "cua-watch.dc.html", "cua-handoff.dc.html", "cua-stopped.dc.html",
    "cua-control.dc.html", "cua-control-zoom.dc.html", "cua-control-land.dc.html",
    "cua-control-keyboard.dc.html",
    "cua-mac.dc.html", "cua-mac-wide.dc.html", "cua-ipad.dc.html",
]

NOTES = {
    "cuaTitle": {"x": 0, "y": -300, "kind": "title1", "maxW": 2740, "page": PAGE["id"],
                 "text": "Chat & Cua Spaces (Oct 21): delegate to Codex in a Linux desktop, "
                         "then take the screen yourself"},
    "cuaTitleChat": {"x": 0, "y": 964, "kind": "title1", "maxW": 2270, "page": PAGE["id"],
                     "text": "Chat"},
    "cuaTitleWatch": {"x": 0, "y": 2228, "kind": "title1", "maxW": 1330, "page": PAGE["id"],
                      "text": "Watch, hand over, recover"},
    "cuaTitleControl": {"x": 0, "y": 3492, "kind": "title1", "maxW": 2708, "page": PAGE["id"],
                        "text": "Manual control"},
    "cuaTitlePlatforms": {"x": 0, "y": 4756, "kind": "title1", "maxW": 2950, "page": PAGE["id"],
                          "text": "Mac and iPad"},

    "cuaFlow": {"x": 3120, "y": 0, "w": 460, "fill": "blue", "page": PAGE["id"], "text": (
        "The flow\n\n"
        "Message → pick or create a Space → chat → the desktop strip above the composer "
        "→ Watch → Take control → full screen → Done → back to watching.\n\n"
        "A Space is a Linux desktop. Codex works inside it. The chat is the main surface; "
        "the desktop is evidence, not a second app.\n\n"
        "TAKING CONTROL PAUSES THE AGENT, NOT THE SPACE. The desktop, its apps and its "
        "downloads keep running the whole time.\n\n"
        "Sending another chat message hands control back to Codex. That is the only way "
        "it resumes, and the handoff board says so on screen.\n\n"
        "Done exits control, returns to watching and puts the phone back in portrait."
    )},
    "cuaReused": {"x": 3120, "y": 1120, "w": 460, "fill": "gray", "page": PAGE["id"], "text": (
        "Reused, not reinvented\n\n"
        "• List rows, status dots and the three-line row: s2-list. No buttons in rows.\n"
        "• Host dots, the glass Search/••• capsule and the floating dock: s2-list. "
        "Message is a third tab.\n"
        "• Offline host = the hollow amber ring from dA2-sessions, row at 50%.\n"
        "• Top bar, centred title and status line, glass back and tools: s2-view.\n"
        "• User bubble #355C8F on #F2F2F7: bub-soft, the picked option.\n"
        "• Composer, model chip, Stop that becomes Send on typing: s2-view.\n"
        "• Queued and not-sent as a soft strip above the composer, with the row menu: "
        "s2-queued and s2-queued-failed.\n"
        "• Tool steps grouped and expanded inline over a 1.5pt rule: s2-view.\n"
        "• Bottom panel with eyebrow, title, card and no Dismiss: s2-signin-prompt.\n"
        "• Sheet scaffold, drag indicator, 34pt corners: NewSessionSheets.\n"
        "• Mac titlebar, tab strip, host strip and time-column rows: dA2-sessions.\n"
        "• iPad 320pt sidebar card and the #182B3E selected row: ip-session.\n\n"
        "New only where nothing existed: the desktop stage, and the manual-control chrome."
    )},
    "cuaDecisions": {"x": 3120, "y": 2360, "w": 460, "fill": "orange", "page": PAGE["id"], "text": (
        "Decisions worth arguing with\n\n"
        "1. THE STAGE, NOT A TAB. A Chat/Desktop tab pair would hide one to show the other. "
        "The desktop instead lives in the slot S2 gives its pill row: a 44pt live strip at rest, "
        "a 229pt player when you tap Watch. The chat never leaves the screen and the transcript "
        "only gives up 185pt.\n\n"
        "2. CONTROLLING IS A MODE, NOT A STATUS. It gets no sixth dot colour. It gets a 3pt "
        "accent ring around the whole screen and a blue “You have control” chip, next to an "
        "amber “Agent paused” chip. Watching has neither, so the two read apart in a thumbnail.\n\n"
        "3. SPACE POWER LIVES IN THE SPACE SHEET. “Stop this Space” is one sheet away, under its "
        "own Space heading, never beside the composer’s Stop. Stop-the-turn stops the agent; "
        "Stop-the-Space closes the desktop. Two words that far apart cannot be fat-fingered.\n\n"
        "4. NOTHING IS SENT UNTIL IT IS CONFIRMED. The agent writes a draft in Gmail and says so. "
        "The ask panel shows the real recipient, subject and body, and the footnote reads "
        "“Nothing has been sent.” The second button is Keep it as a draft, not Cancel.\n\n"
        "5. NO JARGON FOR PERMISSION. “Let this Space read a folder?” with the folder name, the "
        "host and “read-only”. No mounts, no bind paths, no container words anywhere.\n\n"
        "6. DARK ONLY, like every S2 and iPad board on this canvas. A light pass belongs with the "
        "Sessions light pass, not alone here."
    )},
    "cuaGestures": {"x": 3120, "y": 3700, "w": 460, "fill": "green", "page": PAGE["id"], "text": (
        "Manual control: the gesture map\n\n"
        "• One finger, tap or drag — the guest cursor. Tap, drag, select.\n"
        "• Two-finger tap — right-click.\n"
        "• Two fingers, drag — pan the local viewport. Never reaches the desktop.\n"
        "• Pinch — zoom, 1× to 4×. The factor shows beside Fit once past 1×.\n"
        "• Fit — back to the whole desktop, centred, at 1×.\n\n"
        "One finger is the guest and two fingers are the local view: that split is the whole "
        "model, and the hint strip states it in four pairs rather than an onboarding sheet.\n\n"
        "Chrome stays to Done, Fit and Keyboard. Portrait fits the desktop to width (390×244) "
        "and says to turn the phone; landscape fits to height (624×390). Landscape-right is "
        "landscape-left mirrored — the chrome insets on whichever side the sensor housing is.\n\n"
        "The keyboard row carries what a Linux desktop needs and iOS will not send: "
        "esc, tab, ctrl, alt, arrows, return."
    )},
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = {}
    for name in ORDER:
        build, x, y, w, h, title = ALL[name]
        (OUT / name).write_text(build(), encoding="utf-8")
        entries[name] = {"x": x, "y": y, "w": w, "h": h, "title": title,
                         "page": PAGE["id"], "is_interactive": True}
    assert len(entries) == len(ALL), (len(entries), len(ALL))
    (HERE / "canvas-entries.json").write_text(json.dumps({
        "canvas": "https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD",
        "page": PAGE,
        "order": ORDER,
        "boards": entries,
        "notes": NOTES,
    }, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(entries)} boards to {OUT}")


if __name__ == "__main__":
    main()
