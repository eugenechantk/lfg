#!/usr/bin/env python3
"""Row 4 — full-screen manual control.

Controlling is a MODE, not a status, so it is marked structurally: an accent
ring around the whole screen plus a blue "You have control" chip. Watching has
neither. That reads instantly even in a thumbnail.
"""

from parts import (head, script, svg, dot, desk, I,
                   BLACK, RAISED, CARD, CONTROL, EDGE, GLASS, GLASS_EDGE,
                   INK, SOFT, SECOND, GREY, META, DIM, ACCENT, ACCENT_INK,
                   LIVE, AMBER, AMBER_INK, RED, CONTROL_RING, FONT)

RING = 3


def screen(w, h, content):
    return (f'<div style="width: {w}px; height: {h}px; position: relative; overflow: hidden; background: {BLACK}; '
            f'color: {INK}; font-family: {FONT}; -webkit-font-smoothing: antialiased;">\n{content}\n</div>')


def ring():
    """The one marker that separates controlling from watching."""
    return (f'<div aria-hidden="true" style="position: absolute; inset: 0; border: {RING}px solid {CONTROL_RING}; '
            f'border-radius: 2px; pointer-events: none; z-index: 5;"></div>')


def glass_pill(inner, extra=""):
    return (f'<div style="height: 44px; border-radius: 22px; background: {GLASS}; '
            f'box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid {GLASS_EDGE}; '
            f'display: flex; align-items: center; padding: 0 4px; {extra}">{inner}</div>')


def done_btn(href="cua-watch.dc.html"):
    return (f'<a href="{href}" style="height: 44px; padding: 0 18px; border-radius: 22px; background: {GLASS}; '
            f'box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid {GLASS_EDGE}; '
            f'display: flex; align-items: center; font-size: 17px; font-weight: 600; color: {INK};">Done</a>')


def tool_pill(zoom=None, fit_on=False):
    z = ''
    if zoom:
        z = (f'<span style="height: 30px; padding: 0 10px; margin-left: 2px; border-radius: 15px; '
             f'background: rgba(255,255,255,0.14); font-size: 13px; font-weight: 600; '
             f'font-variant-numeric: tabular-nums; color: {SOFT}; display: flex; align-items: center;">{zoom}</span>')
    fit_bg = f'background: rgba(255,255,255,0.16); ' if fit_on else ''
    inner = (f'{z}'
             f'<button type="button" aria-label="Fit the whole desktop on screen" style="width: 40px; height: 36px; '
             f'margin: 0 1px; border: 0; border-radius: 18px; {fit_bg}display: flex; align-items: center; '
             f'justify-content: center; padding: 0; cursor: pointer; color: {INK};">{svg("fit", 19, "currentColor", 2)}</button>'
             f'<button type="button" aria-label="Show the keyboard" style="width: 40px; height: 36px; border: 0; '
             f'border-radius: 18px; display: flex; align-items: center; justify-content: center; padding: 0; '
             f'cursor: pointer; color: {INK};">{svg("kbd", 19, "currentColor", 1.8)}</button>')
    return glass_pill(inner)


def mode_chips(centred_top=None, left=None, right=None):
    pos = (f'left: 0; right: 0; justify-content: center; top: {centred_top}px;' if centred_top is not None
           else f'left: {left}px; top: {right}px;')
    return f"""
  <div style="position: absolute; {pos} display: flex; align-items: center; gap: 6px; z-index: 4;">
    <span style="height: 28px; padding: 0 11px; border-radius: 14px; background: {CONTROL_RING}; display: flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: #FFFFFF;">
      {svg('hand', 13, '#FFFFFF', 2)}You have control</span>
    <span style="height: 28px; padding: 0 11px; border-radius: 14px; background: rgba(255,159,10,0.18); border: 0.5px solid rgba(255,159,10,0.42); display: flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: {AMBER_INK};">
      {dot(AMBER, size=6)}Agent paused</span>
  </div>"""


GESTURES = [
    ("1 finger", "tap and drag"),
    ("2 fingers", "pan the view"),
    ("pinch", "zoom to 4×"),
    ("2-finger tap", "right-click"),
]


def gesture_strip(bottom, width=366, left=12, one_line=False):
    """The gesture hint. It fades a few seconds after you enter control; the
    boards draw it visible so the mapping is reviewable."""
    size = 11 if one_line else 12
    cells = "".join(
        f'<span style="display: flex; align-items: baseline; gap: 4px; white-space: nowrap;">'
        f'<span style="font-size: {size}px; font-weight: 600; color: {SECOND};">{a}</span>'
        f'<span style="font-size: {size}px; color: {META};">{b}</span></span>'
        for a, b in GESTURES)
    wrap = "nowrap" if one_line else "wrap"
    bg = "rgba(12,12,14,0.86)" if one_line else "rgba(28,28,30,0.72)"
    pad = "7px 14px" if one_line else "9px 12px"
    return (f'<div style="position: absolute; left: {left}px; width: {width}px; bottom: {bottom}px; '
            f'display: flex; flex-wrap: {wrap}; justify-content: center; gap: 6px 13px; '
            f'padding: {pad}; box-sizing: border-box; border-radius: 16px; background: {bg}; '
            f'backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px); z-index: 4;">{cells}</div>')


def home_bar(bottom=8, w=140, horizontal=True):
    if horizontal:
        return (f'<span aria-hidden="true" style="position: absolute; left: 50%; transform: translateX(-50%); '
                f'bottom: {bottom}px; width: {w}px; height: 5px; border-radius: 3px; '
                f'background: rgba(255,255,255,0.30); z-index: 6;"></span>')
    return (f'<span aria-hidden="true" style="position: absolute; top: 50%; transform: translateY(-50%); '
            f'right: {bottom}px; height: {w}px; width: 5px; border-radius: 3px; '
            f'background: rgba(255,255,255,0.30); z-index: 6;"></span>')


# ----------------------------------------------------------- 14. portrait --

def board_control():
    dh = round(390 * 10 / 16)          # 244 — the whole desktop, fitted to width
    top = (844 - dh) // 2
    body = f"""
  <div style="position: absolute; left: 0; top: {top}px; width: 390px; height: {dh}px; overflow: hidden;">
    {desk(390, dh, 'compose')}
  </div>
  <span aria-hidden="true" style="position: absolute; left: 196px; top: {top + 120}px; width: 15px; height: 21px; z-index: 3;">
    <svg width="15" height="21" viewBox="0 0 15 21" fill="#FFFFFF" stroke="#000000" stroke-width="1.1" aria-hidden="true"><path d="M1.2 1.1l12 8.4-5.3.7 3.1 6.2-2.6 1.3-3.1-6.2-3.6 3.9z"></path></svg>
  </span>

  <div style="position: absolute; top: 54px; left: 16px; right: 16px; display: flex; align-items: center; gap: 10px; z-index: 4;">
    {done_btn()}
    <span style="flex: 1 1 auto;"></span>
    {tool_pill()}
  </div>
{mode_chips(centred_top=110)}
{gesture_strip(bottom=96)}
  <span style="position: absolute; left: 0; right: 0; bottom: 60px; text-align: center; font-size: 12px; color: {DIM}; z-index: 4;">Turn the phone sideways for a bigger view</span>
{home_bar()}
{ring()}"""
    return head("Cua · Manual control, portrait") + screen(390, 844, body) + script(
        {"$preview": {"width": 390, "height": 844}}, "  renderVals() { return {}; }")


# ------------------------------------------------------------- 15. zoomed --

def board_control_zoom():
    z = 2.4
    w, h = round(390 * z), round(244 * z)   # 936 x 586
    body = f"""
  <div style="position: absolute; left: -268px; top: 118px; width: {w}px; height: {h}px; overflow: hidden;">
    {desk(w, h, 'compose')}
  </div>
  <span aria-hidden="true" style="position: absolute; left: 238px; top: 470px; width: 17px; height: 24px; z-index: 3;">
    <svg width="17" height="24" viewBox="0 0 15 21" fill="#FFFFFF" stroke="#000000" stroke-width="1.1" aria-hidden="true"><path d="M1.2 1.1l12 8.4-5.3.7 3.1 6.2-2.6 1.3-3.1-6.2-3.6 3.9z"></path></svg>
  </span>

  <div style="position: absolute; top: 54px; left: 16px; right: 16px; display: flex; align-items: center; gap: 10px; z-index: 4;">
    {done_btn()}
    <span style="flex: 1 1 auto;"></span>
    {tool_pill(zoom='2.4×', fit_on=True)}
  </div>
{mode_chips(centred_top=110)}
  <div style="position: absolute; left: 12px; right: 12px; bottom: 96px; display: flex; justify-content: center; z-index: 4;">
    <span style="display: flex; align-items: center; gap: 8px; padding: 9px 14px; border-radius: 16px; background: rgba(28,28,30,0.72); backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px); font-size: 12px; color: {SECOND};">
      {svg('fit', 14, ACCENT_INK, 2)}<span><span style="color: {ACCENT_INK}; font-weight: 600;">Fit</span> puts the whole desktop back on screen</span>
    </span>
  </div>
{home_bar()}
{ring()}"""
    return head("Cua · Manual control, zoomed and panned") + screen(390, 844, body) + script(
        {"$preview": {"width": 390, "height": 844}}, "  renderVals() { return {}; }")


# ---------------------------------------------------------- 16. landscape --

def board_control_land():
    dh = 390 - 0
    dw = round(dh * 16 / 10)     # 624
    left = (844 - dw) // 2       # 110
    body = f"""
  <div style="position: absolute; left: {left}px; top: 0; width: {dw}px; height: {dh}px; overflow: hidden;">
    {desk(dw, dh, 'compose')}
  </div>
  <span aria-hidden="true" style="position: absolute; left: {left + 330}px; top: 196px; width: 15px; height: 21px; z-index: 3;">
    <svg width="15" height="21" viewBox="0 0 15 21" fill="#FFFFFF" stroke="#000000" stroke-width="1.1" aria-hidden="true"><path d="M1.2 1.1l12 8.4-5.3.7 3.1 6.2-2.6 1.3-3.1-6.2-3.6 3.9z"></path></svg>
  </span>

  <div style="position: absolute; top: 14px; left: {{{{padL}}}}px; right: {{{{padR}}}}px; display: flex; align-items: center; gap: 10px; z-index: 4;">
    {done_btn()}
    <span style="display: flex; align-items: center; gap: 6px;">
      <span style="height: 28px; padding: 0 11px; border-radius: 14px; background: {CONTROL_RING}; display: flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: #FFFFFF;">
        {svg('hand', 13, '#FFFFFF', 2)}You have control</span>
      <span style="height: 28px; padding: 0 11px; border-radius: 14px; background: rgba(255,159,10,0.18); border: 0.5px solid rgba(255,159,10,0.42); display: flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: {AMBER_INK};">
        {dot(AMBER, size=6)}Agent paused</span>
    </span>
    <span style="flex: 1 1 auto;"></span>
    {tool_pill()}
  </div>
{gesture_strip(bottom=20, width=560, left=142, one_line=True)}
  <span aria-hidden="true" style="position: absolute; left: 50%; transform: translateX(-50%); bottom: 5px; width: 180px; height: 5px; border-radius: 3px; background: rgba(255,255,255,0.30); z-index: 6;"></span>
  <span aria-hidden="true" style="position: absolute; top: 0; bottom: 0; {{{{notchSide}}}}: 0; width: 34px; background: linear-gradient({{{{notchDir}}}}, rgba(0,0,0,0.55), rgba(0,0,0,0)); z-index: 2;"></span>
{ring()}"""
    logic = """
  renderVals() {
    const o = this.props.orientation || 'left';
    // Landscape-left puts the sensor housing on the left, so the chrome insets
    // on that side. Landscape-right is the mirror image.
    return o === 'left'
      ? { padL: '48', padR: '16', notchSide: 'left', notchDir: 'to right' }
      : { padL: '16', padR: '48', notchSide: 'right', notchDir: 'to left' };
  }"""
    props = {"orientation": {"editor": "enum", "options": ["left", "right"], "default": "left"},
             "$preview": {"width": 844, "height": 390}}
    return head("Cua · Manual control, landscape") + screen(844, 390, body) + script(props, logic)


# ----------------------------------------------------- 17. keyboard open --

def board_control_keyboard():
    kb_h, acc_h = 150, 42
    area = 390 - kb_h - acc_h          # 198
    dh = area - 10
    dw = round(dh * 16 / 10)
    left = (844 - dw) // 2
    keys = ["esc", "tab", "ctrl", "alt", "←", "↑", "↓", "→", "return"]
    acc = "".join(
        f'<button type="button" style="height: 28px; padding: 0 {14 if len(k) > 2 else 10}px; border: 0; '
        f'border-radius: 7px; background: rgba(255,255,255,0.14); color: {SOFT}; font-size: 13px; '
        f'font-weight: 500; cursor: pointer;">{k}</button>' for k in keys)
    rows = [
        "q w e r t y u i o p",
        "a s d f g h j k l",
        "z x c v b n m",
    ]
    kb = ""
    for i, r in enumerate(rows):
        ks = "".join(
            f'<span style="width: 58px; height: 34px; border-radius: 5px; background: #6B6B70; '
            f'box-shadow: 0 1px 0 rgba(0,0,0,0.45); display: flex; align-items: center; justify-content: center; '
            f'font-size: 15px; color: #FFFFFF;">{c}</span>' for c in r.split())
        pad = [0, 30, 60][i]
        kb += (f'<div style="display: flex; gap: 8px; justify-content: center; padding: 0 {pad}px;">{ks}</div>')
    body = f"""
  <div style="position: absolute; left: {left}px; top: 6px; width: {dw}px; height: {dh}px; overflow: hidden;">
    {desk(dw, dh, 'compose')}
  </div>

  <div style="position: absolute; top: 12px; left: 48px; display: flex; align-items: center; gap: 8px; z-index: 4;">
    <a href="cua-watch.dc.html" style="height: 36px; padding: 0 15px; border-radius: 18px; background: {GLASS}; border: 0.5px solid {GLASS_EDGE}; display: flex; align-items: center; font-size: 15px; font-weight: 600; color: {INK};">Done</a>
    <span style="height: 26px; padding: 0 10px; border-radius: 13px; background: {CONTROL_RING}; display: flex; align-items: center; gap: 5px; font-size: 12px; font-weight: 600; color: #FFFFFF;">
      {svg('hand', 12, '#FFFFFF', 2)}You have control</span>
  </div>
  <div style="position: absolute; top: 12px; right: 16px; display: flex; align-items: center; gap: 6px; z-index: 4;">
    <span style="height: 36px; border-radius: 18px; background: {GLASS}; border: 0.5px solid {GLASS_EDGE}; display: flex; align-items: center; padding: 0 4px;">
      <button type="button" aria-label="Fit the whole desktop on screen" style="width: 34px; height: 30px; border: 0; border-radius: 15px; background: transparent; display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer; color: {INK};">{svg('fit', 17, 'currentColor', 2)}</button>
      <button type="button" aria-label="Hide the keyboard" style="width: 34px; height: 30px; border: 0; border-radius: 15px; background: rgba(255,255,255,0.18); display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer; color: {INK};">{svg('kbd', 17, 'currentColor', 1.8)}</button>
    </span>
  </div>

  <div role="toolbar" aria-label="Keys the desktop needs" style="position: absolute; left: 0; right: 0; bottom: {kb_h}px; height: {acc_h}px; background: rgba(40,40,42,0.96); border-top: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center; gap: 7px; z-index: 5;">
    {acc}
  </div>
  <div aria-hidden="true" style="position: absolute; left: 0; right: 0; bottom: 0; height: {kb_h}px; background: #2C2C2E; display: flex; flex-direction: column; justify-content: center; gap: 8px; padding-bottom: 14px; z-index: 5;">
    {kb}
    <span style="position: absolute; left: 50%; transform: translateX(-50%); bottom: 4px; width: 180px; height: 5px; border-radius: 3px; background: rgba(255,255,255,0.30);"></span>
  </div>
{ring()}"""
    return head("Cua · Manual control, keyboard open") + screen(844, 390, body) + script(
        {"$preview": {"width": 844, "height": 390}}, "  renderVals() { return {}; }")


BOARDS = {
    "cua-control.dc.html": (board_control, 0, 3792, 390, 844, "Phone · full-screen control, portrait"),
    "cua-control-zoom.dc.html": (board_control_zoom, 470, 3792, 390, 844, "Phone · zoomed 2.4× and panned, Fit resets"),
    "cua-control-land.dc.html": (board_control_land, 940, 3792, 844, 390, "Phone · control in landscape, both orientations"),
    "cua-control-keyboard.dc.html": (board_control_keyboard, 1864, 3792, 844, 390, "Phone · landscape with the keyboard and Tab/Esc/Enter"),
}
