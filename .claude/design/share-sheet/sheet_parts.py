#!/usr/bin/env python3
"""Components for the "Share sheet (Oct 23)" page of the LFG UI Map canvas.

Tokens and the shared components (svg, dot, head/script/phone, card buttons)
come from the Chat & Cua generator's parts.py, which lifted them from S2.
Only the share-specific pieces live here: the dimmed host app, the share
sheet scaffold, the To strip, the context cards, the keyboard and the
iOS system share sheet.

Templates use [[NAME]] for Python values so `{{hole}}` stays literal for the
canvas runtime without f-string brace escaping.
"""

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "chat-cua-spaces"))

import parts  # noqa: E402
from parts import (head, script, phone, svg, dot, ring_dot, I,  # noqa: E402,F401
                   BLACK, RAISED, CARD, CONTROL, HAIR, EDGE, GLASS, GLASS_EDGE,
                   INK, SOFT, SECOND, GREY, META, DIM, ACCENT, ACCENT_INK,
                   LIVE, AMBER, AMBER_INK, RED, IDLE, STOPPED, BUBBLE, BUBBLE_INK)

UNREAD = "#BF5AF0"
SHEET_LINE = "#38383A"      # hairline on the raised sheet
KEY = "#5A5A5E"
KEY_FN = "#3A3A3D"
KBD_BG = "#252527"
PIN = "#FF375F"             # numbered pins, as on the build-plan pages

I.update({
    "x": '<path d="M6 6l12 12M18 6L6 18"></path>',
    "globe": '<circle cx="12" cy="12" r="9"></circle><path d="M3 12h18M12 3c2.8 3 2.8 15 0 18M12 3c-2.8 3-2.8 15 0 18"></path>',
    "quote": '<path d="M5 17c2.6-.8 4-2.6 4-5.4V7H5v5h4M15 17c2.6-.8 4-2.6 4-5.4V7h-4v5h4"></path>',
    "photo": '<rect x="3" y="5" width="18" height="14" rx="2"></rect><circle cx="8.5" cy="10" r="1.6"></circle><path d="M21 16l-5-5-8 8"></path>',
    "list": '<path d="M9 6h11M9 12h11M9 18h11"></path><path d="M4.5 6h.01M4.5 12h.01M4.5 18h.01"></path>',
    "clock": '<circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path>',
    "mic": '<rect x="9" y="3" width="6" height="11" rx="3"></rect><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"></path>',
    "copy": '<rect x="8" y="8" width="12" height="12" rx="2"></rect><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"></path>',
    "book": '<path d="M4 5.5A1.5 1.5 0 0 1 5.5 4H11v16H5.5A1.5 1.5 0 0 1 4 18.5zM20 5.5A1.5 1.5 0 0 0 18.5 4H13v16h5.5a1.5 1.5 0 0 0 1.5-1.5z"></path>',
    "bookmark": '<path d="M6 3h12v18l-6-4-6 4z"></path>',
    "open": '<path d="M14 4h6v6M20 4l-9 9M18 14v6H4V6h6"></path>',
    "shift": '<path d="M12 4l8 8h-4.5v7h-7v-7H4z"></path>',
    "del": '<path d="M8.5 5H21v14H8.5L2.5 12z"></path><path d="M11.5 9.5l5 5M16.5 9.5l-5 5"></path>',
    "airdrop": '<circle cx="12" cy="12" r="1.6"></circle><path d="M8.3 15.7a5.2 5.2 0 1 1 7.4 0M5.6 18.4a9 9 0 1 1 12.8 0"></path>',
    "bubble": '<path d="M12 4c4.7 0 8.5 3 8.5 6.8s-3.8 6.8-8.5 6.8c-.9 0-1.8-.1-2.6-.3L5 19.5l1-3.4C4.4 14.9 3.5 13 3.5 10.8 3.5 7 7.3 4 12 4z"></path>',
    "notes": '<rect x="5" y="3.5" width="14" height="17" rx="2"></rect><path d="M8.5 8.5h7M8.5 12h7M8.5 15.5h4"></path>',
})


def T(s, **kw):
    """Fill [[NAME]] slots with Python values; `{{hole}}` passes through."""
    for k, v in kw.items():
        s = s.replace(f"[[{k}]]", str(v))
    if "[[" in s:
        i = s.index("[[")
        raise ValueError("unfilled slot: " + s[i:i + 40])
    return s


def js(value):
    """A Python value as a JS literal inside the logic script."""
    return json.dumps(value, ensure_ascii=False).replace("</", "<\\/")


# ------------------------------------------------------------- identity --

LFG_BLADES = [
    "452,182 572,182 572,360 512,466 452,360",
    "452,842 572,842 572,662 512,557 452,662",
    "256,295 412,384 472,489 352,489 196,398",
    "768,295 612,384 552,489 672,489 828,398",
    "196,625 352,535 472,535 412,638 256,728",
    "828,625 672,535 552,535 612,638 768,728",
]


def lfg_icon(size, radius=None):
    """The LFG app icon (cream asterisk on near-black), drawn from AppIcon-1024."""
    r = radius if radius is not None else round(size * 0.225)
    polys = "".join(f'<polygon points="{p}"></polygon>' for p in LFG_BLADES)
    return (f'<span style="width: {size}px; height: {size}px; flex: 0 0 {size}px; border-radius: {r}px; '
            f'background: #0B0B0B; border: 0.5px solid rgba(255,255,255,0.16); box-sizing: border-box; '
            f'display: flex; align-items: center; justify-content: center; overflow: hidden;">'
            f'<svg width="{size}" height="{size}" viewBox="0 0 1024 1024" fill="#F5F7EC" aria-hidden="true">'
            f'{polys}</svg></span>')


def pin(n, top, left):
    return (f'<span aria-hidden="true" style="position: absolute; top: {top}px; left: {left}px; width: 24px; height: 24px; '
            f'border-radius: 12px; background: {PIN}; color: #FFFFFF; font-size: 13px; font-weight: 700; '
            f'display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 8px rgba(0,0,0,0.5); '
            f'z-index: 5;">{n}</span>')


# -------------------------------------------------------- the host app --

def backdrop(title="Sheets", url="developer.apple.com"):
    """The app you shared from, pushed back and dimmed by the page sheet."""
    return T("""
  <div aria-hidden="true" style="position: absolute; top: 14px; left: 10px; right: 10px; height: 160px; border-radius: 18px; background: #F2F2F7; overflow: hidden; color: #1C1C1E;">
    <div style="padding: 18px 20px 0; display: flex; flex-direction: column; gap: 10px;">
      <span style="font-size: 12px; color: #6E6E73;">[[URL]]</span>
      <span style="font-size: 26px; font-weight: 700;">[[TITLE]]</span>
    </div>
  </div>
  <div aria-hidden="true" style="position: absolute; inset: 0; background: rgba(0,0,0,0.62);"></div>""",
             TITLE=title, URL=url)


def safari_page():
    """A full Safari page for the system share sheet board (light page, dark UI)."""
    lines = "".join(
        f'<span style="display: block; height: 11px; width: {w}%; border-radius: 5px; background: #D8D8DE;"></span>'
        for w in (92, 86, 95, 64, 0, 90, 88, 72))
    return T("""
  <div aria-hidden="true" style="position: absolute; inset: 0; background: #F2F2F7; color: #1C1C1E;">
    <div style="padding: 70px 22px 0; display: flex; flex-direction: column; gap: 12px;">
      <span style="font-size: 13px; color: #6E6E73;">Human Interface Guidelines · Components</span>
      <span style="font-size: 34px; line-height: 40px; font-weight: 700;">Sheets</span>
      <span style="font-size: 17px; line-height: 24px; color: #3A3A3C;">A sheet helps people do one scoped task that stays close to what they were doing.</span>
      <div style="display: flex; flex-direction: column; gap: 9px; margin-top: 6px;">[[LINES]]</div>
    </div>
  </div>
  <div aria-hidden="true" style="position: absolute; inset: 0; background: rgba(0,0,0,0.45);"></div>""", LINES=lines)


# ------------------------------------------------------------ the sheet --

def circle_btn(icon_html, label, href, bg=CONTROL):
    return (f'<a href="{href}" aria-label="{label}" style="width: 44px; height: 44px; flex: 0 0 44px; '
            f'border-radius: 22px; background: {bg}; display: flex; align-items: center; justify-content: center;">'
            f'{icon_html}</a>')


def send_btn(href="{{sendHref}}", bg="{{sendBg}}", ink="{{sendInk}}", label="Send"):
    """The S2 send button, at sheet-header size."""
    return (f'<a href="{href}" aria-label="{label}" style="width: 44px; height: 44px; flex: 0 0 44px; '
            f'border-radius: 22px; background: {bg}; display: flex; align-items: center; justify-content: center;">'
            f'<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="{ink}" stroke-width="3" '
            f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I["send"]}</svg></a>')


def sheet(title, inner, lead="close", lead_href="sh-system.dc.html", action="", top=58, radius=38, bg="#1C1C1E"):
    if lead == "close":
        lead_html = circle_btn(svg("x", 15, SECOND, 2.8), "Cancel", lead_href)
    elif lead == "back":
        lead_html = circle_btn(svg("back", 18, SECOND, 2.6), "Back", lead_href)
    else:
        lead_html = '<span style="width: 44px; flex: 0 0 44px;"></span>'
    action = action or '<span style="width: 44px; flex: 0 0 44px;"></span>'
    return T("""
  <section role="dialog" aria-label="[[TITLE]]" style="position: absolute; left: 0; right: 0; top: [[TOP]]px; bottom: 0; background: [[BG]]; border-radius: [[R]]px [[R]]px 0 0; overflow: hidden;">
    <div aria-hidden="true" style="position: absolute; top: 6px; left: 50%; width: 36px; height: 5px; margin-left: -18px; border-radius: 3px; background: #48484A;"></div>
    <div style="position: absolute; top: 14px; left: 14px; right: 14px; height: 44px; display: flex; align-items: center; gap: 10px;">
      [[LEAD]]
      <h1 style="flex: 1 1 auto; min-width: 0; margin: 0; text-align: center; font-size: 17px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">[[TITLE]]</h1>
      [[ACTION]]
    </div>
    [[INNER]]
  </section>""", TITLE=title, TOP=top, R=radius, LEAD=lead_html, ACTION=action, INNER=inner, BG=bg)


def eyebrow(text, color=META):
    return (f'<span style="font-size: 12px; font-weight: 600; letter-spacing: 0.05em; text-transform: uppercase; '
            f'color: {color};">{text}</span>')


def to_strip():
    """Send to: chips for the likely sessions, plus a grouped pill for All / New.

    The selected chip always sits first. The pill never scrolls away.
    """
    return T("""
      <div style="padding: 0 20px 7px;">[[EYEBROW]]</div>
      <div style="display: flex; align-items: center; gap: 8px; padding-right: 16px;">
        <div style="flex: 1 1 auto; min-width: 0; display: flex; gap: 8px; overflow-x: auto; scrollbar-width: none; padding-left: 16px;">
          <sc-for list="{{chips}}" as="c" hint-placeholder-count="3">
            <button type="button" onClick="{{c.pick}}" aria-pressed="{{c.pressed}}" style="flex: 0 0 auto; max-width: 200px; height: 36px; padding: 0 13px 0 11px; border-radius: 18px; background: {{c.bg}}; border: 0.5px solid {{c.border}}; color: {{c.fg}}; box-sizing: border-box; font: inherit; font-size: 15px; font-weight: 500; display: flex; align-items: center; gap: 7px; cursor: pointer;">
              <sc-if value="{{c.isNew}}" hint-placeholder-val="{{false}}">
                <svg style="flex: 0 0 14px;" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"></path></svg>
              </sc-if>
              <sc-if value="{{c.hasDot}}" hint-placeholder-val="{{true}}">
                <span style="width: 8px; height: 8px; flex: 0 0 8px; border-radius: 50%; background: {{c.dotBg}}; border: {{c.dotBorder}}; box-shadow: {{c.dotRing}}; box-sizing: border-box;"></span>
              </sc-if>
              <span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{c.label}}</span>
            </button>
          </sc-for>
        </div>
        <div style="flex: 0 0 auto; height: 36px; border-radius: 18px; background: #2C2C2E; display: flex; align-items: center; padding: 0 2px;">
          <a href="sh-pick.dc.html" aria-label="All sessions" style="width: 40px; height: 36px; display: flex; align-items: center; justify-content: center; color: #F2F2F7;">[[LIST]]</a>
          <span style="width: 0.5px; height: 18px; background: #48484A;"></span>
          <button type="button" onClick="{{pickNew}}" aria-label="New session" style="width: 40px; height: 36px; border: 0; background: transparent; display: flex; align-items: center; justify-content: center; color: #F2F2F7; padding: 0; cursor: pointer;">[[PLUS]]</button>
        </div>
      </div>""", EYEBROW=eyebrow("Send to"), LIST=svg("list", 18, "currentColor", 2),
             PLUS=svg("plus", 18, "currentColor", 2.2))


def status_hint():
    """What Send will do, for the chosen session. Hidden while New session is chosen."""
    return """
      <sc-if value="{{showHint}}" hint-placeholder-val="{{true}}">
        <div style="padding: 10px 20px 0; display: flex; flex-direction: column; gap: 2px; font-size: 13px; line-height: 18px;">
          <span style="display: flex; align-items: center; gap: 6px; color: #A1A1A6; white-space: nowrap; overflow: hidden;">
            <span style="width: 7px; height: 7px; flex: 0 0 7px; border-radius: 50%; background: {{hintDotBg}}; border: {{hintDotBorder}}; box-shadow: {{hintHalo}}; box-sizing: border-box;"></span>
            <span style="color: {{hintColor}}; font-weight: 600;">{{hintLabel}}</span>
            <span style="overflow: hidden; text-overflow: ellipsis;">{{hintTail}}</span>
          </span>
          <span style="color: #8E8E93;">{{hintNote}}</span>
        </div>
      </sc-if>"""


def new_session_fields():
    """New session chosen: Host / Folder / Agent replace the status line."""
    def row(icon, label, value, last=False):
        b = "" if last else f" border-bottom: 0.5px solid {SHEET_LINE};"
        return (f'<div style="min-height: 44px; padding: 0 12px 0 13px; display: flex; align-items: center; gap: 10px;{b}">'
                f'{svg(icon, 16, GREY)}'
                f'<span style="flex: 1 1 auto; font-size: 15px;">{label}</span>'
                f'<span style="font-size: 15px; color: {GREY}; white-space: nowrap;">{value}</span>'
                f'{svg("chev_r", 12, DIM, 2.8)}</div>')
    return T("""
      <sc-if value="{{isNew}}" hint-placeholder-val="{{false}}">
        <div style="margin: 12px 16px 0; border-radius: 14px; background: #2C2C2E; overflow: hidden;">
          [[ROWS]]
        </div>
        <div style="padding: 7px 20px 0; font-size: 13px; line-height: 18px; color: #8E8E93;">Your message and the link become its first prompt.</div>
      </sc-if>""", ROWS=row("host", "Host", "Pro") + row("folder", "Folder", "lfg") +
             row("ask", "Agent", "Claude · Opus 5.5", last=True))


def message_field(placeholder="Add a message…", rows=3):
    return T("""
      <div style="height: 0.5px; background: #38383A; margin: 14px 20px 0;"></div>
      <textarea aria-label="Message" rows="[[ROWS]]" placeholder="[[PH]]" value="{{draft}}" onInput="{{onType}}" style="display: block; margin: 12px 20px 0; border: 0; outline: none; resize: none; padding: 0; background: transparent; font: inherit; font-size: 17px; line-height: 22px; color: #FFFFFF;"></textarea>""",
             ROWS=rows, PH=placeholder)


# ------------------------------------------------------- context cards --

def card_link(title, domain, compact=False):
    pad = "9px 12px 9px 9px" if compact else "10px 14px 10px 10px"
    th = 40 if compact else 52
    return T("""
      <div style="margin: [[M]]; border-radius: 16px; background: #2C2C2E; padding: [[PAD]]; display: flex; align-items: center; gap: 12px;">
        <span style="width: [[TH]]px; height: [[TH]]px; flex: 0 0 [[TH]]px; border-radius: 10px; background: #3A3A3C; display: flex; align-items: center; justify-content: center; color: #A1A1A6;">[[GLOBE]]</span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 15px; line-height: 20px; font-weight: 600; color: #F2F2F7; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;">[[TITLE]]</span>
          <span style="font-size: 13px; color: #8E8E93; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">[[DOMAIN]]</span>
        </span>
      </div>""", M="0 16px" if compact else "10px 16px 0", PAD=pad, TH=th,
             GLOBE=svg("globe", 22 if not compact else 18, "currentColor", 1.6), TITLE=title, DOMAIN=domain)


def card_quote(text, source):
    return T("""
      <div style="margin: 10px 16px 0; border-radius: 16px; background: #2C2C2E; padding: 12px 14px 12px 12px; display: flex; gap: 10px;">
        <span style="flex: 0 0 18px; color: #8E8E93; padding-top: 1px;">[[Q]]</span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 8px;">
          <span style="font-size: 16px; line-height: 22px; color: #F2F2F7;">[[TEXT]]</span>
          <span style="display: flex; align-items: center; gap: 6px; font-size: 13px; color: #8E8E93; white-space: nowrap; overflow: hidden;">[[G]]<span style="overflow: hidden; text-overflow: ellipsis;">[[SRC]]</span></span>
        </span>
      </div>""", Q=svg("quote", 18, "currentColor", 1.8), TEXT=text, SRC=source,
             G=svg("globe", 13, "currentColor", 1.8))


def shot_thumb(w, h, variant=0):
    """A tiny dark-mode phone screenshot: transcript lines over a composer."""
    bub = (f'<span style="align-self: flex-end; width: 56%; height: {round(h*0.07)}px; border-radius: 6px; background: {BUBBLE};"></span>')
    lines = "".join(f'<span style="width: {w_}%; height: {round(h*0.028)}px; border-radius: 3px; background: #48484A;"></span>'
                    for w_ in ((84, 70, 92) if variant == 0 else (76, 88, 60)))
    overlap = (f'<span style="position: absolute; left: 8%; right: 8%; bottom: {round(h*0.05)}px; height: {round(h*0.09)}px; '
               f'border-radius: {round(h*0.045)}px; background: rgba(60,60,64,0.95); border: 1px solid #FF9F0A;"></span>')
    comp = (f'<span style="position: absolute; left: 6%; right: 6%; bottom: {round(h*0.09)}px; height: {round(h*0.08)}px; '
            f'border-radius: {round(h*0.04)}px; background: #2C2C2E;"></span>')
    return (f'<span style="position: relative; width: {w}px; height: {h}px; flex: 0 0 {w}px; border-radius: 10px; '
            f'background: #000000; border: 0.5px solid #48484A; overflow: hidden; display: flex; flex-direction: column; '
            f'gap: {round(h*0.03)}px; padding: {round(h*0.12)}px 8px 0; box-sizing: border-box;">{bub}{lines}{comp}{overlap}</span>')


def card_images(n_label, size_label):
    return T("""
      <div style="margin: 10px 16px 0; display: flex; flex-direction: column; gap: 8px;">
        <div style="display: flex; gap: 8px;">[[A]][[B]]</div>
        <span style="display: flex; align-items: center; gap: 6px; font-size: 13px; color: #8E8E93;">[[P]][[N]] · [[S]]</span>
      </div>""", A=shot_thumb(118, 212, 0), B=shot_thumb(118, 212, 1),
             P=svg("photo", 14, "currentColor", 1.8), N=n_label, S=size_label)


def card_file(name, kind_size):
    return T("""
      <div style="margin: 10px 16px 0; border-radius: 16px; background: #2C2C2E; padding: 10px 14px 10px 10px; display: flex; align-items: center; gap: 12px;">
        <span style="position: relative; width: 44px; height: 54px; flex: 0 0 44px; border-radius: 6px; background: #F2F2F7; display: flex; align-items: flex-end; justify-content: center; padding-bottom: 7px; box-sizing: border-box;">
          <span style="font-size: 10px; font-weight: 800; letter-spacing: 0.04em; color: #FF453A;">PDF</span>
        </span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 15px; font-weight: 600; color: #F2F2F7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">[[NAME]]</span>
          <span style="font-size: 13px; color: #8E8E93;">[[KS]]</span>
        </span>
      </div>""", NAME=name, KS=kind_size)


def footnote(text="{{receives}}"):
    return (f'<div style="padding: 10px 20px 0; font-size: 13px; line-height: 18px; color: {META};">{text}</div>')


# ------------------------------------------------------------- keyboard --

def keyboard(suggest=("the", "pattern", "sheet")):
    """A dark iOS keyboard, so the board shows the space the sheet really has."""
    def key(ch, w=33):
        return (f'<span style="width: {w}px; height: 42px; flex: 0 0 {w}px; border-radius: 8px; background: {KEY}; '
                f'display: flex; align-items: center; justify-content: center; font-size: 22px; color: #FFFFFF; '
                f'box-shadow: 0 1px 0 rgba(0,0,0,0.4);">{ch}</span>')

    def fn(html, w, bg=KEY_FN, fs=16):
        return (f'<span style="width: {w}px; height: 42px; flex: 0 0 {w}px; border-radius: 8px; background: {bg}; '
                f'display: flex; align-items: center; justify-content: center; font-size: {fs}px; color: #FFFFFF; '
                f'box-shadow: 0 1px 0 rgba(0,0,0,0.4);">{html}</span>')

    r1 = "".join(key(c) for c in "qwertyuiop")
    r2 = "".join(key(c) for c in "asdfghjkl")
    r3 = (fn(svg("shift", 19, "#FFFFFF", 1.8), 42) + '<span style="width: 6px;"></span>' +
          "".join(key(c) for c in "zxcvbnm") + '<span style="width: 6px;"></span>' +
          fn(svg("del", 20, "#FFFFFF", 1.8), 42))
    r4 = (fn("123", 46) + f'<span style="flex: 1 1 auto; height: 42px; border-radius: 8px; background: {KEY}; '
          f'display: flex; align-items: center; justify-content: center; font-size: 16px; color: #FFFFFF; '
          f'box-shadow: 0 1px 0 rgba(0,0,0,0.4);">space</span>' + fn("return", 92))
    sug = ('<span style="width: 0.5px; height: 22px; background: #48484A;"></span>').join(
        f'<span style="flex: 1 1 0; text-align: center; font-size: 16px; color: #E5E5EA;">{s}</span>' for s in suggest)
    return T("""
  <div aria-hidden="true" style="position: absolute; left: 0; right: 0; bottom: 0; height: 336px; background: [[BG]]; border-top: 0.5px solid #3A3A3C;">
    <div style="height: 44px; display: flex; align-items: center; padding: 0 8px;">[[SUG]]</div>
    <div style="display: flex; flex-direction: column; gap: 11px; padding: 6px 3px 0;">
      <div style="display: flex; justify-content: center; gap: 6px;">[[R1]]</div>
      <div style="display: flex; justify-content: center; gap: 6px;">[[R2]]</div>
      <div style="display: flex; justify-content: center; gap: 6px;">[[R3]]</div>
      <div style="display: flex; gap: 6px; padding: 0 3px;">[[R4]]</div>
    </div>
    <div style="position: absolute; left: 26px; right: 26px; bottom: 30px; display: flex; justify-content: space-between; color: #A1A1A6;">[[GLOBE]][[MIC]]</div>
    <span style="position: absolute; left: 50%; bottom: 8px; width: 134px; height: 5px; margin-left: -67px; border-radius: 3px; background: #FFFFFF;"></span>
  </div>""", BG=KBD_BG, SUG=sug, R1=r1, R2=r2, R3=r3, R4=r4,
             GLOBE=svg("globe", 24, "currentColor", 1.6), MIC=svg("mic", 24, "currentColor", 1.6))


# ----------------------------------------------------- session sample data --
# The S2 list's sample sessions, ordered by last activity (newest first): the
# order the strip and the guess use. Readwise import fix moved to Pro so the
# closed example and the offline example don't share a host.

SESSIONS = [
    {"id": "fork", "title": "Fork session feature", "kind": "working", "host": "Pro",
     "project": "lfg", "model": "Opus 5.5", "age": "now"},
    {"id": "ship", "title": "Ship lfg 1.3.1 to TestFlight", "kind": "needs", "host": "Pro",
     "project": "lfg", "model": "Opus 5.5", "age": "2m", "ask": "upload build 205 now?"},
    {"id": "glass", "title": "Liquid Glass tab bar", "kind": "unread", "host": "Pro",
     "project": "lfg", "model": "GPT-5.6 Sol", "age": "12m"},
    {"id": "audit", "title": "Search Console audit", "kind": "offline", "host": "Air",
     "project": "inbox", "model": "GPT-6 Astra", "age": "14m"},
    {"id": "shinkai", "title": "Shinkai room decorator", "kind": "idle", "host": "Pro",
     "project": "SleepingBeauty", "model": "Opus 5.5", "age": "1d"},
    {"id": "readwise", "title": "Readwise import fix", "kind": "closed", "host": "Pro",
     "project": "readwise-sync", "model": "Codex", "age": "1d"},
]

# What Send does for each kind of session. `done` is the confirmation board
# Send leads to; `say` is the line under the session in that confirmation.
KINDS = {
    "working": {"dot": LIVE, "ring": False, "halo": True, "label": "Working",
                "note": "Your message joins its current turn.", "done": "sh-joined.dc.html"},
    "needs": {"dot": AMBER, "ring": False, "halo": False, "label": "Needs input",
              "note": "It asks: {ask} Your message runs after you answer.", "done": "sh-waits.dc.html"},
    "unread": {"dot": UNREAD, "ring": False, "halo": False, "label": "New reply",
               "note": "Your message starts its next turn now.", "done": "sh-sent.dc.html"},
    "idle": {"dot": IDLE, "ring": False, "halo": False, "label": "Idle",
             "note": "Your message starts its next turn now.", "done": "sh-sent.dc.html"},
    "closed": {"dot": STOPPED, "ring": False, "halo": False, "label": "Ended yesterday",
               "note": "Your message resumes it.", "done": "sh-resumed.dc.html"},
    "offline": {"dot": AMBER, "ring": True, "halo": False, "label": "Air is offline",
                "note": "LFG queues it and sends it when Air is back.", "done": "sh-queued.dc.html"},
}


def compose_logic(initial="fork", draft="", receives_tail="your message, then the page title and link.",
                  order=None, new_target="sh-started.dc.html"):
    """Logic for every compose board: chip selection, status line, Send target."""
    order = order or [s["id"] for s in SESSIONS]
    return T("""
  constructor(props) { super(props); this.state = { sel: [[INIT]], draft: [[DRAFT]] }; }
  renderVals() {
    const S = [[SESSIONS]], K = [[KINDS]], ORDER = [[ORDER]];
    const s = this.state, byId = {};
    S.forEach((x) => { byId[x.id] = x; });
    const isNew = s.sel === 'new';
    const ids = isNew ? ['new'].concat(ORDER) : [s.sel].concat(ORDER.filter((id) => id !== s.sel));
    const chips = ids.map((id) => {
      const on = id === s.sel;
      if (id === 'new') {
        return { label: 'New session', isNew: true, hasDot: false, dotBg: 'transparent', dotBorder: '0', dotRing: 'none',
                 bg: on ? '#0A6EE0' : '#2C2C2E', border: on ? '#0A6EE0' : '#38383A', fg: '#FFFFFF',
                 pressed: on ? 'true' : 'false', pick: () => this.setState({ sel: 'new' }) };
      }
      const x = byId[id], k = K[x.kind];
      return {
        label: x.title, isNew: false, hasDot: true,
        dotBg: k.ring ? 'transparent' : k.dot,
        dotBorder: k.ring ? ('1.5px solid ' + k.dot) : (on ? '1.5px solid #FFFFFF' : '0'),
        dotRing: 'none',
        bg: on ? '#0A6EE0' : '#2C2C2E', border: on ? '#0A6EE0' : '#38383A',
        fg: on ? '#FFFFFF' : '#F2F2F7', pressed: on ? 'true' : 'false',
        pick: () => this.setState({ sel: id })
      };
    });
    const cur = isNew ? null : byId[s.sel];
    const k = cur ? K[cur.kind] : null;
    const label = cur ? (cur.kind === 'offline' ? 'Air is offline' : k.label) : '';
    const tail = cur ? (cur.kind === 'offline' ? ' · last seen 14m ago' : ' · ' + cur.host + ' · ' + cur.project) : '';
    const note = cur ? k.note.replace('{ask}', '\\u201c' + (cur.ask || '') + '\\u201d') : '';
    const who = isNew ? 'The new session gets ' : (cur.title + ' gets ');
    return {
      chips, isNew, showHint: !isNew,
      pickNew: () => this.setState({ sel: 'new' }),
      hintDotBg: k ? (k.ring ? 'transparent' : k.dot) : 'transparent',
      hintDotBorder: k && k.ring ? '1.5px solid ' + k.dot : '0',
      hintHalo: k && k.halo ? '0 0 0 3px rgba(48,209,88,0.25)' : 'none',
      hintColor: k ? (cur.kind === 'offline' ? '#FFB340' : k.dot === '#636366' ? '#A1A1A6' : k.dot) : '#A1A1A6',
      hintLabel: label, hintTail: tail, hintNote: note,
      receives: who + [[TAIL]],
      draft: s.draft, onType: (e) => this.setState({ draft: e.target.value }),
      sendHref: isNew ? [[NEWT]] : k.done, sendBg: '#0A6EE0', sendInk: '#FFFFFF'
    };
  }""", INIT=js(initial), DRAFT=js(draft), SESSIONS=js(SESSIONS), KINDS=js(KINDS), ORDER=js(order),
             TAIL=js(receives_tail), NEWT=js(new_target))


# ------------------------------------------------------- session rows --

def session_rows(href="sh-compose.dc.html", checked="fork", bg=RAISED):
    """The S2 list rows, grouped, on the sheet's raised background."""
    return T("""
    <sc-for list="{{sections}}" as="sec" hint-placeholder-count="4">
      <button type="button" onClick="{{sec.toggle}}" aria-expanded="{{sec.expanded}}" style="width: 100%; border: 0; background: transparent; font: inherit; display: flex; align-items: center; gap: 8px; padding: 14px 16px 6px 20px; font-size: 15px; color: #A1A1A6; text-align: left; cursor: pointer;">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{sec.chevron}}"></path></svg>
        <span style="font-weight: 600; color: {{sec.color}};">{{sec.label}}</span>
        <span style="color: #8E8E93;">{{sec.count}}</span>
      </button>
      <sc-for list="{{sec.rows}}" as="r" hint-placeholder-count="2">
        <a href="[[HREF]]" style="display: flex; align-items: flex-start; padding-left: 20px; opacity: {{r.opacity}};">
          <span style="width: 20px; flex: 0 0 20px; padding-top: 18px;"><span style="display: block; width: 8px; height: 8px; border-radius: 50%; background: {{r.dotBg}}; border: {{r.dotBorder}}; box-sizing: border-box;"></span></span>
          <span style="flex: 1 1 auto; min-width: 0; padding: 11px 16px 12px 0; border-bottom: 0.5px solid #38383A; display: flex; align-items: center; gap: 10px;">
            <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
              <span style="font-size: 17px; line-height: 22px; font-weight: {{r.weight}}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{r.title}}</span>
              <span style="display: flex; align-items: center; gap: 5px; font-size: 15px; line-height: 20px; color: {{r.lineColor}}; min-width: 0;">
                <sc-if value="{{r.live}}" hint-placeholder-val="{{false}}">
                  <span style="width: 7px; height: 7px; flex: 0 0 7px; border-radius: 50%; background: #30D158; box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span>
                </sc-if>
                <span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{r.line}}</span>
              </span>
              <span style="display: flex; align-items: center; gap: 5px; font-size: 13px; line-height: 18px; color: #8E8E93; white-space: nowrap; overflow: hidden;">
                <span style="overflow: hidden; text-overflow: ellipsis;">{{r.meta}}</span>
                <svg style="flex: 0 0 13px;" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><rect x="3" y="4" width="18" height="12" rx="1.5"></rect><path d="M9 20h6M12 16v4"></path></svg>
                <span>{{r.host}}</span>
              </span>
            </span>
            <sc-if value="{{r.checked}}" hint-placeholder-val="{{false}}">
              <svg style="flex: 0 0 20px;" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#409CFF" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-label="Chosen" role="img"><path d="M4.5 12.5l5 5 10-11"></path></svg>
            </sc-if>
          </span>
        </a>
      </sc-for>
    </sc-for>""", HREF=href)


def rows_logic(checked="fork", collapsed=None):
    collapsed = collapsed or {"needs": False, "working": False, "unread": False, "idle": True, "closed": True}
    return T("""
  constructor(props) { super(props); this.state = { collapsed: [[COLLAPSED]] }; }
  renderVals() {
    const c = this.state.collapsed, CHECK = [[CHECK]];
    const open = 'M6 9l6 6 6-6', shut = 'M9 6l6 6-6 6';
    const amber = '#FF9F0A', green = '#30D158', grey = '#A1A1A6', ink = '#D1D1D6';
    const row = (o) => Object.assign({ weight: '400', lineColor: grey, live: false, opacity: '1', dotBorder: '0' }, o, { checked: o.id === CHECK });
    const defs = [
      { id: 'needs', label: 'Needs input', color: amber, rows: [
        row({ id: 'ship', dotBg: amber, weight: '600', title: 'Ship lfg 1.3.1 to TestFlight', line: 'Asks: upload build 205 now?', lineColor: amber, meta: 'lfg \\u00b7 Opus 5.5 \\u00b7 2m \\u00b7', host: 'Pro' }),
        row({ id: 'audit', dotBg: 'transparent', dotBorder: '1.5px solid ' + amber, opacity: '0.5', title: 'Search Console audit', line: 'Air is offline \\u00b7 last seen 14m ago', lineColor: '#FFB340', meta: 'inbox \\u00b7 GPT-6 Astra \\u00b7 14m \\u00b7', host: 'Air' })
      ]},
      { id: 'working', label: 'Working', color: grey, rows: [
        row({ id: 'fork', dotBg: green, title: 'Fork session feature', live: true, line: 'Working \\u00b7 3m', lineColor: green, meta: 'lfg \\u00b7 Opus 5.5 \\u00b7 2 subagents \\u00b7', host: 'Pro' }),
        row({ id: 'readwise-sync', dotBg: green, title: 'Readwise sync check', live: true, line: 'Working \\u00b7 12m', lineColor: green, meta: 'readwise-sync \\u00b7 Codex \\u00b7', host: 'Pro' })
      ]},
      { id: 'unread', label: 'Unread', color: grey, rows: [
        row({ id: 'glass', dotBg: '#BF5AF0', weight: '600', title: 'Liquid Glass tab bar', line: 'New reply', lineColor: ink, meta: 'lfg \\u00b7 GPT-5.6 Sol \\u00b7 12m \\u00b7', host: 'Pro' }),
        row({ id: 'repo', dotBg: '#BF5AF0', weight: '600', title: 'Daily repo review', line: 'New reply', lineColor: ink, meta: 'lfg \\u00b7 Opus 5.5 \\u00b7 9:00 AM \\u00b7', host: 'Pro' })
      ]},
      { id: 'idle', label: 'Idle', color: grey, rows: [
        row({ id: 'shinkai', dotBg: '#0A84FF', title: 'Shinkai room decorator', line: 'Ready for your next message', meta: 'SleepingBeauty \\u00b7 Opus 5.5 \\u00b7 1d \\u00b7', host: 'Pro' })
      ]},
      { id: 'closed', label: 'Closed', color: grey, rows: [
        row({ id: 'readwise', dotBg: '#636366', title: 'Readwise import fix', line: 'Ended yesterday \\u00b7 send a message to resume', meta: 'readwise-sync \\u00b7 Codex \\u00b7 1d \\u00b7', host: 'Pro' })
      ]}
    ];
    const counts = { needs: '2', working: '2', unread: '15', idle: '17', closed: '40' };
    return {
      sections: defs.map((d) => ({
        label: d.label, color: d.color, count: counts[d.id],
        chevron: c[d.id] ? shut : open, expanded: c[d.id] ? 'false' : 'true',
        rows: c[d.id] ? [] : d.rows,
        toggle: () => { const n = Object.assign({}, c); n[d.id] = !c[d.id]; this.setState({ collapsed: n }); }
      }))
    };
  }""", COLLAPSED=js(collapsed), CHECK=js(checked))


def search_field(placeholder="Search sessions"):
    return T("""
      <div style="margin: 0 16px; height: 40px; border-radius: 12px; background: #2C2C2E; display: flex; align-items: center; gap: 8px; padding: 0 12px; color: #8E8E93;">
        [[ICON]]<span style="font-size: 17px;">[[PH]]</span>
      </div>""", ICON=svg("search", 17, "currentColor", 2), PH=placeholder)


# --------------------------------------------------------- confirmation --

def done_sheet(icon, icon_bg, icon_ink, title, dot_html, session, say, top=470, extra=""):
    """After Send: the sheet drops to a short detent and closes itself."""
    return T("""
  <section role="status" aria-label="[[TITLE]]" style="position: absolute; left: 0; right: 0; top: [[TOP]]px; bottom: 0; background: #1C1C1E; border-radius: 38px 38px 0 0; overflow: hidden; display: flex; flex-direction: column; align-items: center; padding: 34px 28px 0; box-sizing: border-box; text-align: center;">
    <div aria-hidden="true" style="position: absolute; top: 6px; left: 50%; width: 36px; height: 5px; margin-left: -18px; border-radius: 3px; background: #48484A;"></div>
    <span style="width: 60px; height: 60px; border-radius: 30px; background: [[IBG]]; display: flex; align-items: center; justify-content: center; color: [[IINK]];">[[ICON]]</span>
    <span style="margin-top: 14px; font-size: 22px; line-height: 28px; font-weight: 700;">[[TITLE]]</span>
    <span style="margin-top: 8px; max-width: 100%; display: flex; align-items: center; gap: 8px; font-size: 17px; font-weight: 600; color: #F2F2F7;">[[DOT]]<span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">[[SESSION]]</span></span>
    <span style="margin-top: 6px; font-size: 15px; line-height: 21px; color: #A1A1A6;">[[SAY]]</span>
    [[EXTRA]]
    <a href="s2-view.dc.html" style="margin-top: 20px; min-height: 44px; padding: 0 18px; border-radius: 22px; background: #2C2C2E; color: #F2F2F7; font-size: 15px; font-weight: 600; display: flex; align-items: center; gap: 7px;">[[OPEN]]Open in LFG</a>
    <span style="position: absolute; left: 50%; bottom: 8px; width: 134px; height: 5px; margin-left: -67px; border-radius: 3px; background: #FFFFFF;"></span>
  </section>""", TOP=top, IBG=icon_bg, IINK=icon_ink, ICON=icon, TITLE=title, DOT=dot_html,
             SESSION=session, SAY=say, EXTRA=extra, OPEN=svg("open", 15, "currentColor", 2.1))
