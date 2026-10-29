#!/usr/bin/env python3
"""Shared components for the "Chat & Cua Spaces (Oct 21)" artboards.

Every token and every component here is lifted from the existing LFG canvas:
S2 Sessions (`s2-list`, `s2-view`, `s2-queued`, `s2-signin-prompt`), Desktop A2
(`dA2-sessions`) and iPad (`ip-session`). Nothing new is invented except the
desktop stage and the manual-control chrome, which had no precedent.
"""

# ---------------------------------------------------------------- tokens --
# Straight from s2-view.dc.html / s2-list.dc.html / dA2-sessions.dc.html.
BLACK = "#000000"
RAISED = "#1C1C1E"
CARD = "#2C2C2E"
CONTROL = "#3A3A3C"
HAIR = "#2C2C2E"
EDGE = "#38383A"
GLASS = "rgba(44,44,46,0.92)"
GLASS_EDGE = "rgba(255,255,255,0.10)"

INK = "#FFFFFF"
SOFT = "#F2F2F7"
SECOND = "#D1D1D6"
GREY = "#A1A1A6"
META = "#8E8E93"
DIM = "#636366"

ACCENT = "#0A6EE0"          # filled buttons / Send
ACCENT_INK = "#409CFF"      # accent text
LIVE = "#30D158"            # working
AMBER = "#FF9F0A"           # needs input / paused
AMBER_INK = "#FFB340"
RED = "#FF453A"
IDLE = "#0A84FF"            # Space ready, agent idle
STOPPED = "#636366"
BUBBLE = "#355C8F"          # the picked soft blue (bub-soft)
BUBBLE_INK = "#F2F2F7"
IPAD_SEL = "#182B3E"

# Manual control is a MODE, not a status, so it gets a structural marker (an
# accent ring) rather than a sixth status colour.
CONTROL_RING = "#0A84FF"

FONT = "-apple-system, 'SF Pro Text', system-ui, sans-serif"
MAC_FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"


def head(title):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
a{{color:inherit;text-decoration:none}}a:hover{{color:inherit}}
button,textarea,input{{font:inherit;color:inherit}}
button{{background:transparent;border:0}}
textarea::placeholder{{color:#8E8E93}}
</style>
</helmet>"""


def script(props, body):
    import json
    pj = json.dumps(props, ensure_ascii=False).replace("'", "\\u0027")
    return f"""</x-dc>
<script type="text/x-dc" data-dc-script data-props='{pj}'>
class Component extends DCLogic {{
{body}
}}
</script>
</body>
</html>
"""


def phone(content, w=390, h=844, bg=BLACK):
    return (f'<div style="width: {w}px; height: {h}px; position: relative; overflow: hidden; '
            f'background: {bg}; color: {INK}; font-family: {FONT}; '
            f'-webkit-font-smoothing: antialiased;">\n{content}\n</div>')


# ------------------------------------------------------------------ icons --
# 24-box stroke paths, the same set the S2 boards draw.
I = {
    "back": '<path d="M15 5l-7 7 7 7"></path>',
    "search": '<circle cx="11" cy="11" r="6.5"></circle><path d="M16 16l4.5 4.5"></path>',
    "dots": None,  # filled, see dots()
    "tools": '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"></path><circle cx="15" cy="7" r="2.2"></circle><circle cx="9" cy="17" r="2.2"></circle>',
    "plus": '<path d="M12 5v14M5 12h14"></path>',
    "chev_r": '<path d="M9 6l6 6-6 6"></path>',
    "chev_d": '<path d="M6 9l6 6 6-6"></path>',
    "chev_u": '<path d="M18 15l-6-6-6 6"></path>',
    "send": '<path d="M12 19V5M5 12l7-7 7 7"></path>',
    "mail": '<path d="M3 5.5h18v13H3z"></path><path d="M3 6l9 7 9-7"></path>',
    "browser": '<path d="M3 4h18v14H3zM3 8h18"></path>',
    "edit": '<path d="M4 20h4L19 9l-4-4L4 16z"></path><path d="M13.5 6.5l4 4"></path>',
    "file": '<path d="M6 2.5h8l4.5 4.5v14.5H6zM14 2.5V7h4.5"></path>',
    "folder": '<path d="M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2.5h8.5A1.5 1.5 0 0 1 21 9v9.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z"></path>',
    "key": '<circle cx="8" cy="15" r="4"></circle><path d="M11 12l9-9M16 7l3 3"></path>',
    "ask": '<path d="M4 5h16v11H9l-5 4z"></path><path d="M10 9a2 2 0 1 1 3 1.7c-.6.4-1 .8-1 1.5"></path>',
    "host": '<rect x="3" y="4" width="18" height="12" rx="1.5"></rect><path d="M9 20h6M12 16v4"></path>',
    "check": '<path d="M4.5 12.5l5 5 10-11"></path>',
    "desktop": '<rect x="2.5" y="4" width="19" height="13" rx="2"></rect><path d="M8 21h8M12 17v4"></path>',
    "hand": '<path d="M8.5 11V5.2a1.7 1.7 0 0 1 3.4 0V10"></path><path d="M11.9 10V4.2a1.7 1.7 0 0 1 3.4 0V10"></path><path d="M15.3 10.4V6.6a1.6 1.6 0 0 1 3.2 0v7.6a7 7 0 0 1-7 7h-.6a6 6 0 0 1-5.3-3.2l-2-3.7a1.7 1.7 0 0 1 2.8-1.9l1.7 2.2"></path>',
    "fit": '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"></path>',
    "kbd": '<rect x="2.5" y="6" width="19" height="12" rx="2"></rect><path d="M6 10h.01M9.5 10h.01M13 10h.01M16.5 10h.01M8 14h8"></path>',
    "power": '<path d="M12 3v9"></path><path d="M6.8 6.8a8 8 0 1 0 10.4 0"></path>',
    "refresh": '<path d="M20.5 11A8.5 8.5 0 1 0 19 16.4"></path><path d="M20.5 5.5V11H15"></path>',
    "warn": '<path d="M12 4.5l9 15.5H3z"></path><path d="M12 10v4"></path><circle cx="12" cy="17" r="0.6" fill="currentColor" stroke="none"></circle>',
    "eye": '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"></path><circle cx="12" cy="12" r="3"></circle>',
}


def svg(name, size=17, color="currentColor", sw=1.9, fill="none"):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="{fill}" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
            f'{I[name]}</svg>')


def dots(size=20, color=INK):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="{color}" aria-hidden="true">'
            f'<circle cx="5" cy="12" r="1.9"></circle><circle cx="12" cy="12" r="1.9"></circle>'
            f'<circle cx="19" cy="12" r="1.9"></circle></svg>')


def dot(color, halo=False, size=8):
    sh = f' box-shadow: 0 0 0 3px {color}40;' if halo else ''
    return (f'<span style="width: {size}px; height: {size}px; flex: 0 0 {size}px; border-radius: 50%; '
            f'background: {color};{sh}"></span>')


def ring_dot(color, size=8):
    """Offline host marker — the hollow ring dA2-sessions uses."""
    return (f'<span style="width: {size}px; height: {size}px; flex: 0 0 {size}px; border-radius: 50%; '
            f'border: 1.5px solid {color}; box-sizing: border-box;"></span>')


# ------------------------------------------------------------- phone bars --

def glass_btn(icon_html, label, href=None, size=44):
    tag = "a" if href else "button"
    extra = f' href="{href}"' if href else ' type="button"'
    return (f'<{tag}{extra} aria-label="{label}" style="width: {size}px; height: {size}px; flex: 0 0 {size}px; '
            f'border-radius: {size // 2}px; background: {GLASS}; box-shadow: 0 2px 12px rgba(0,0,0,0.5); '
            f'border: 0.5px solid {GLASS_EDGE}; display: flex; align-items: center; justify-content: center; '
            f'padding: 0; cursor: pointer;">{icon_html}</{tag}>')


def status_dyn():
    """A status line whose parts come from renderVals as plain values.

    `{{x}}` interpolates TEXT, not markup, so anything variable has to be a
    token inside real markup rather than an HTML string built in JS.
    """
    return ('<span style="width: 7px; height: 7px; flex: 0 0 7px; border-radius: 50%; '
            'background: {{dotColor}}; box-shadow: {{dotHalo}};"></span>'
            '<span style="color: {{statusColor}}; font-weight: 600;">{{statusLabel}}</span>'
            '<span>{{statusTail}}</span>')


def top_bar(title, status_html, back="cua-list.dc.html", menu="cua-sheet.dc.html"):
    """The S2 session top bar: glass back, centred title + status line, glass tools."""
    return f"""
  <div style="position: absolute; top: 0; left: 0; right: 0; height: 124px; background: linear-gradient({BLACK} 72%, rgba(0,0,0,0)); pointer-events: none;"></div>
  <div style="position: absolute; top: 54px; left: 16px; right: 16px; height: 56px; display: flex; align-items: center; gap: 10px;">
    {glass_btn(svg('back', 20, INK, 2.4), 'Back to Spaces', back)}
    <a href="{menu}" style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 3px;">
      <span style="font-size: 17px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%;">{title}</span>
      <span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: {GREY}; white-space: nowrap;">{status_html}</span>
    </a>
    {glass_btn(svg('tools', 20, INK), 'Space tools and options', menu)}
  </div>"""


def status_line(color, label, tail):
    return (f'{dot(color, halo=(color == LIVE), size=7)}'
            f'<span style="color: {color}; font-weight: 600;">{label}</span>'
            f'<span>{tail}</span>')


def composer(placeholder="Message the agent…", bottom=28, model="Codex gpt-6.1 · High",
             stop_default=True, left=12, right=12):
    """The S2 composer. Stop while working; typing turns it into Send."""
    return f"""
  <div style="position: absolute; left: {left}px; right: {right}px; bottom: {bottom}px; height: 96px; border-radius: 24px; background: {RAISED}; border: 0.5px solid {EDGE}; box-sizing: border-box; padding: 11px 10px 10px 16px; display: flex; flex-direction: column; justify-content: space-between;">
    <textarea aria-label="Message" rows="1" placeholder="{placeholder}" value="{{{{draft}}}}" onInput="{{{{onType}}}}" style="border: 0; outline: none; resize: none; padding: 0; background: transparent; font: inherit; font-size: 17px; line-height: 22px; color: {INK};"></textarea>
    <span style="display: flex; align-items: center; gap: 8px;">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="{GREY}" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"><path d="M20.5 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1l8.6-8.6a3.4 3.4 0 0 1 4.8 4.8l-8.6 8.6a1.7 1.7 0 0 1-2.4-2.4l7.9-7.9"></path></svg>
      <span style="height: 28px; padding: 0 10px; border-radius: 14px; background: {CARD}; display: flex; align-items: center; gap: 5px; font-size: 13px; font-weight: 500; color: {SECOND};">{model}
        <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"></path></svg></span>
      <span style="flex: 1 1 auto;"></span>
      <sc-if value="{{{{showStop}}}}" hint-placeholder-val="{{{{{str(stop_default).lower()}}}}}">
        <button aria-label="Stop the agent" style="width: 34px; height: 34px; border: 0; border-radius: 17px; background: {SOFT}; display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer;">
          <span style="width: 11px; height: 11px; border-radius: 3px; background: {BLACK};"></span>
        </button>
      </sc-if>
      <sc-if value="{{{{showSend}}}}" hint-placeholder-val="{{{{{str(not stop_default).lower()}}}}}">
        <button onClick="{{{{send}}}}" aria-label="Send" style="width: 34px; height: 34px; border: 0; border-radius: 17px; background: {ACCENT}; display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer;">
          {svg('send', 16, INK, 3)}
        </button>
      </sc-if>
    </span>
  </div>"""


def bottom_fade(h=196, start=22):
    return (f'<div style="position: absolute; left: 0; right: 0; bottom: 0; height: {h}px; '
            f'background: linear-gradient(rgba(0,0,0,0), {BLACK} {start}%); pointer-events: none;"></div>')


# ------------------------------------------------------ transcript pieces --

def bubble(text, note=None):
    n = (f'<span style="font-size: 12px; color: {GREY};">{note}</span>') if note else ''
    wrap_s = 'display: flex; flex-direction: column; align-items: flex-end; gap: 4px;' if note else ''
    inner = (f'<div style="background: {BUBBLE}; color: {BUBBLE_INK}; border-radius: 20px; padding: 9px 14px; '
             f'font-size: 17px; line-height: 22px;">{text}</div>')
    if note:
        return f'<div style="align-self: flex-end; max-width: 290px; {wrap_s}">{inner}{n}</div>'
    return (f'<div style="align-self: flex-end; max-width: 290px; background: {BUBBLE}; color: {BUBBLE_INK}; '
            f'border-radius: 20px; padding: 9px 14px; font-size: 17px; line-height: 22px;">{text}</div>')


def prose(text):
    return f'<div style="font-size: 17px; line-height: 24px; color: {SOFT};">{text}</div>'


def tool_row(icon, text, chevron=True, color=GREY):
    ch = (f'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="{DIM}" stroke-width="2.8" '
          f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I["chev_r"]}</svg>') if chevron else ''
    return (f'<div style="display: flex; align-items: center; gap: 8px; padding: 2px 0; color: {color};">'
            f'{svg(icon, 17, "currentColor")}'
            f'<span style="flex: 1 1 auto; font-size: 15px;">{text}</span>{ch}</div>')


def tool_group(icon, text, lines, open_key="toolOpen", chev_key="toolChevron", toggle="toggleTool"):
    """A grouped tool step that expands inline — exactly s2-view's pattern."""
    body = "".join(f'<span>{l}</span>' for l in lines)
    return f"""
    <div style="display: flex; flex-direction: column;">
      <button onClick="{{{{{toggle}}}}}" style="border: 0; background: transparent; padding: 2px 0; font: inherit; display: flex; align-items: center; gap: 8px; text-align: left; cursor: pointer; color: {GREY};">
        {svg(icon, 17, 'currentColor')}
        <span style="flex: 1 1 auto; font-size: 15px;">{text}</span>
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="{DIM}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{{chev_key}}}}}"></path></svg>
      </button>
      <sc-if value="{{{{{open_key}}}}}" hint-placeholder-val="{{{{false}}}}">
        <div style="margin: 4px 0 0 8px; padding-left: 16px; border-left: 1.5px solid {EDGE}; display: flex; flex-direction: column; gap: 6px; font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 12.5px; line-height: 17px; color: {GREY};">{body}</div>
      </sc-if>
    </div>"""


def fact_row(icon, title, sub, tint=None, ink=SECOND, icon_color=None):
    """A plain row for a connected account / shared folder. No previews, no buttons."""
    bg = f'background: {tint}; ' if tint else f'background: {RAISED}; '
    return (f'<div style="{bg}border-radius: 14px; padding: 10px 13px; display: flex; align-items: center; gap: 11px;">'
            f'{svg(icon, 17, icon_color or GREY)}'
            f'<span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">'
            f'<span style="font-size: 15px; font-weight: 500; color: {ink};">{title}</span>'
            f'<span style="font-size: 13px; color: {META};">{sub}</span></span></div>')


def transcript(items, bottom, top=112, pad="0 16px 8px"):
    body = "\n    ".join(items)
    return (f'<div style="position: absolute; top: {top}px; left: 0; right: 0; bottom: {bottom}px; '
            f'overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; gap: 14px; '
            f'padding: {pad}; box-sizing: border-box;">\n    {body}\n  </div>')


# ------------------------------------------------------------ the desktop --

def desk(w, h, variant="inbox", radius=0):
    """A Linux desktop with Chrome open on Gmail.

    Laid out from w/h so one component serves the 366pt stage, the full-screen
    canvas and the Mac/iPad panes. Sample content only — no real address is
    shown anywhere.
    """
    s = h / 229.0          # scale against the phone stage, the reference size
    f = lambda v: round(v * s, 1)
    panel = f(13)
    win_x, win_y = f(14), f(26)
    win_w, win_h = w - f(28), h - f(40)
    tab_h, bar_h = f(22), f(20)

    rows = [
        ("Design review — round 3", "Thanks — two notes on the spacing before we…", "9:12", True),
        ("Re: launch checklist", "I’ve ticked everything except the store copy…", "8:47", False),
        ("Weekly digest", "12 new items in your reading queue", "8:02", False),
        ("Re: contractor invoice", "Attaching the signed copy for your records", "7:31", False),
        ("Build 205 is ready to test", "TestFlight processed your build", "6:58", False),
    ]
    list_html = ""
    for title, snip, when, hot in rows[: (3 if h < 200 else 5)]:
        bg = "rgba(255,255,255,0.07)" if hot else "transparent"
        wt = "600" if hot else "400"
        list_html += (
            f'<div style="height: {f(21)}px; background: {bg}; border-radius: {f(3)}px; display: flex; '
            f'align-items: center; gap: {f(7)}px; padding: 0 {f(7)}px; box-sizing: border-box;">'
            f'<span style="width: {f(6)}px; height: {f(6)}px; border-radius: 50%; background: {"#8AB4F8" if hot else "rgba(255,255,255,0.18)"}; flex: 0 0 auto;"></span>'
            f'<span style="flex: 0 0 {f(62)}px; font-size: {f(8.5)}px; font-weight: {wt}; color: #E8EAED; '
            f'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{title}</span>'
            f'<span style="flex: 1 1 auto; min-width: 0; font-size: {f(8.5)}px; color: #9AA0A6; '
            f'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{snip}</span>'
            f'<span style="flex: 0 0 auto; font-size: {f(8)}px; color: #9AA0A6;">{when}</span></div>')

    compose = ""
    if variant == "compose":
        cw, ch = f(126), f(86)
        compose = (
            f'<div style="position: absolute; right: {f(8)}px; bottom: 0; width: {cw}px; height: {ch}px; '
            f'background: #292A2D; border-radius: {f(6)}px {f(6)}px 0 0; box-shadow: 0 {f(4)}px {f(16)}px rgba(0,0,0,0.5); '
            f'overflow: hidden; display: flex; flex-direction: column;">'
            f'<div style="height: {f(15)}px; background: #3C4043; display: flex; align-items: center; padding: 0 {f(7)}px; '
            f'font-size: {f(8)}px; color: #E8EAED;">New message</div>'
            f'<div style="padding: {f(5)}px {f(7)}px; display: flex; flex-direction: column; gap: {f(4)}px;">'
            f'<span style="font-size: {f(8)}px; color: #9AA0A6; border-bottom: 1px solid rgba(255,255,255,0.10); padding-bottom: {f(3)}px;">To: design review thread</span>'
            f'<span style="font-size: {f(8)}px; color: #9AA0A6; border-bottom: 1px solid rgba(255,255,255,0.10); padding-bottom: {f(3)}px;">Re: Design review — round 3</span>'
            f'<span style="font-size: {f(8)}px; line-height: {f(11)}px; color: #E8EAED;">Thanks both — I’ll tighten the row spacing to 8pt and re-post…</span>'
            f'</div>'
            f'<span style="position: absolute; left: {f(7)}px; bottom: {f(5)}px; height: {f(13)}px; padding: 0 {f(9)}px; '
            f'border-radius: {f(7)}px; background: #8AB4F8; color: #202124; font-size: {f(8)}px; font-weight: 600; '
            f'display: flex; align-items: center;">Send</span>'
            f'<span style="position: absolute; right: {f(7)}px; bottom: {f(6)}px; font-size: {f(7.5)}px; color: #9AA0A6;">Draft saved</span>'
            f'</div>')

    return f"""<div style="position: absolute; inset: 0; border-radius: {radius}px; overflow: hidden; background: linear-gradient(150deg, #332A4A 0%, #241F39 55%, #1A172B 100%);">
  <div style="position: absolute; top: 0; left: 0; right: 0; height: {panel}px; background: rgba(0,0,0,0.42); display: flex; align-items: center; padding: 0 {f(9)}px; font-size: {f(8)}px; color: rgba(255,255,255,0.72);">
    <span>Activities</span><span style="flex: 1 1 auto;"></span><span>14:32</span>
  </div>
  <div style="position: absolute; left: {win_x}px; top: {win_y}px; width: {win_w}px; height: {win_h}px; border-radius: {f(6)}px; overflow: hidden; background: #202124; border: 1px solid rgba(255,255,255,0.08); box-shadow: 0 {f(8)}px {f(26)}px rgba(0,0,0,0.5);">
    <div style="height: {tab_h}px; background: #35363A; display: flex; align-items: flex-end; gap: {f(3)}px; padding: 0 {f(6)}px;">
      <span style="display: flex; gap: {f(4)}px; align-self: center; margin-right: {f(4)}px;"><span style="width: {f(6)}px; height: {f(6)}px; border-radius: 50%; background: #FF5F57;"></span><span style="width: {f(6)}px; height: {f(6)}px; border-radius: 50%; background: #FEBC2E;"></span><span style="width: {f(6)}px; height: {f(6)}px; border-radius: 50%; background: #28C840;"></span></span>
      <span style="height: {f(16)}px; padding: 0 {f(9)}px; border-radius: {f(5)}px {f(5)}px 0 0; background: #202124; color: #E8EAED; font-size: {f(8)}px; display: flex; align-items: center;">Inbox (12)</span>
      <span style="height: {f(14)}px; padding: 0 {f(9)}px; border-radius: {f(5)}px {f(5)}px 0 0; background: rgba(255,255,255,0.05); color: #9AA0A6; font-size: {f(8)}px; display: flex; align-items: center;">Calendar</span>
    </div>
    <div style="height: {bar_h}px; display: flex; align-items: center; gap: {f(6)}px; padding: 0 {f(8)}px; background: #202124;">
      <span style="width: {f(10)}px; height: {f(10)}px; border-radius: 50%; border: {max(1, f(1.2))}px solid #5F6368;"></span>
      <span style="flex: 1 1 auto; height: {f(13)}px; border-radius: {f(7)}px; background: #2F3134; display: flex; align-items: center; padding: 0 {f(8)}px; font-size: {f(8)}px; color: #BDC1C6;">mail.google.com</span>
    </div>
    <div style="position: absolute; left: 0; right: 0; top: {tab_h + bar_h}px; bottom: 0; display: flex;">
      <div style="flex: 0 0 {f(44)}px; padding: {f(7)}px {f(6)}px; display: flex; flex-direction: column; gap: {f(5)}px; border-right: 1px solid rgba(255,255,255,0.06);">
        <span style="height: {f(16)}px; border-radius: {f(8)}px; background: #8AB4F8; color: #202124; font-size: {f(8)}px; font-weight: 600; display: flex; align-items: center; justify-content: center;">Compose</span>
        <span style="font-size: {f(8)}px; color: #E8EAED;">Inbox</span>
        <span style="font-size: {f(8)}px; color: #9AA0A6;">Starred</span>
        <span style="font-size: {f(8)}px; color: #9AA0A6;">Drafts</span>
      </div>
      <div style="flex: 1 1 auto; min-width: 0; padding: {f(5)}px {f(6)}px; display: flex; flex-direction: column; gap: {f(2)}px; position: relative;">
        {list_html}
        {compose}
      </div>
    </div>
  </div>
</div>"""


# ===========================================================================
# Revision, Oct 21 — agent threads with a shared desktop pool.
# Agents are the identity and the navigation. Desktops are a pooled resource
# that an agent borrows and gives back, so nothing below names a Space as a
# place you go to.
# ===========================================================================

# Agent monograms. Desaturated on purpose: the status dot has to stay the
# loudest thing in the row. Each tint also differs in lightness, not only hue.
AGENT_TINT = {
    "Mail": "#3A5A8C",
    "Scout": "#3F6B52",
    "Patch": "#5E4A7D",
    "Ledger": "#7A5A38",
    "Archivist": "#3F5F6B",
    "Booker": "#6B4448",
}


def monogram(name, size=38, status=None, halo=False, radius=None):
    """Agent identity in a list row or a header.

    The only change to the S2 row: its 20pt dot gutter becomes a 38pt monogram
    with the same dot as a corner badge, because a messaging list is read by
    who is talking first and what state they are in second.
    """
    tint = AGENT_TINT.get(name, "#4A4A52")
    r = radius if radius is not None else round(size * 0.30)
    initial = name[0].upper()
    badge = ""
    if status:
        d = max(10, round(size * 0.30))
        sh = f' box-shadow: 0 0 0 2px {status}44;' if halo else ''
        badge = (f'<span style="position: absolute; right: -1px; bottom: -1px; width: {d}px; height: {d}px; '
                 f'border-radius: 50%; background: {status}; border: 2.5px solid {BLACK}; box-sizing: content-box;'
                 f'{sh}"></span>')
    return (f'<span style="position: relative; width: {size}px; height: {size}px; flex: 0 0 {size}px; '
            f'border-radius: {r}px; background: {tint}; display: flex; align-items: center; justify-content: center; '
            f'font-size: {round(size * 0.42)}px; font-weight: 600; color: {SOFT};">{initial}{badge}</span>')


def eyebrow(color, text, right=None, right_color=None):
    r = (f'<span style="font-size: 12px; font-weight: 600; color: {right_color or META};">{right}</span>'
         if right else '')
    return (f'<div style="display: flex; align-items: center; gap: 7px;">{dot(color, halo=True, size=7)}'
            f'<span style="flex: 1 1 auto; font-size: 12px; font-weight: 700; letter-spacing: 0.4px; '
            f'text-transform: uppercase; color: {color};">{text}</span>{r}</div>')


def inline_card(body, border=EDGE, fill=RAISED):
    """A card that lives IN the transcript.

    It scrolls with the conversation, never covers it, and never blocks the
    composer — so the one action that needs you can wait while the agent gets
    on with everything else.
    """
    return (f'<div style="border-radius: 18px; background: {fill}; border: 1px solid {border}; '
            f'padding: 13px 14px 14px; display: flex; flex-direction: column; gap: 10px;">{body}</div>')


def card_btn(label, kind="primary", icon=None, href=None):
    bg = {"primary": ACCENT, "secondary": CARD, "quiet": "transparent"}[kind]
    fg = {"primary": INK, "secondary": SOFT, "quiet": ACCENT_INK}[kind]
    ic = f'{svg(icon, 15, "currentColor", 2.1)}' if icon else ''
    tag, extra = ("a", f' href="{href}"') if href else ("button", ' type="button"')
    return (f'<{tag}{extra} style="min-height: 44px; padding: 0 15px; border: 0; border-radius: 22px; '
            f'background: {bg}; color: {fg}; font-size: 15px; font-weight: 600; display: flex; '
            f'align-items: center; justify-content: center; gap: 7px; cursor: pointer;">{ic}{label}</{tag}>')


def note_row(icon, text, color=None):
    """A quiet one-line fact in the transcript — a desktop taken, a desktop
    given back. Same weight as a tool step, because that is what it is."""
    c = color or META
    return (f'<div style="display: flex; align-items: center; gap: 8px; padding: 1px 0; color: {c};">'
            f'{svg(icon, 15, "currentColor", 1.9)}'
            f'<span style="flex: 1 1 auto; font-size: 14px; line-height: 19px;">{text}</span></div>')


def desk_chip(text, color=None, href=None):
    """The subtle contextual desktop affordance. It appears only while the
    thread actually holds a desktop."""
    c = color or SECOND
    tag, extra = ("a", f' href="{href}"') if href else ("span", "")
    return (f'<{tag}{extra} style="height: 24px; padding: 0 9px; border-radius: 7px; background: {CARD}; '
            f'display: inline-flex; align-items: center; gap: 5px; font-size: 12px; color: {c};">'
            f'{svg("desktop", 13, "currentColor", 1.8)}{text}</{tag}>')
