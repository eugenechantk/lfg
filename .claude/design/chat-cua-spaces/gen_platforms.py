#!/usr/bin/env python3
"""Row 5 — Mac (narrow first, then wide) and iPad."""

from parts import (head, script, svg, dot, ring_dot, desk, I,
                   BLACK, RAISED, CARD, CONTROL, HAIR, EDGE, GLASS, GLASS_EDGE,
                   INK, SOFT, SECOND, GREY, META, DIM, ACCENT, ACCENT_INK,
                   LIVE, AMBER, AMBER_INK, RED, IDLE, STOPPED, BUBBLE, BUBBLE_INK,
                   CONTROL_RING, IPAD_SEL, FONT, MAC_FONT)

# S2Desk tokens, from desktop/SessionsListS2.swift and dA2-sessions.
D_BG = "#1B1B1E"
D_TITLE = "#F4F4F6"
D_META = "#A8A8B0"
D_SECOND = "#8A8A93"
D_SEP = "rgba(255,255,255,0.06)"
D_CTRL = "rgba(255,255,255,0.07)"
D_SEL = "rgba(255,255,255,0.16)"
D_GREEN = "#32D74B"
D_GREENT = "#5BE37A"
D_AMBER = "#FFB340"
D_ACCENT = "#8FB8FF"
D_FILL = "#3B8EFF"


def mac_screen(w, h, content):
    return (f'<div style="width: {w}px; height: {h}px; box-sizing: border-box; display: flex; flex-direction: column; '
            f'background: {D_BG}; color: {D_TITLE}; font-family: {MAC_FONT}; font-size: 13px; line-height: 1.35;">'
            f'\n{content}\n</div>')


def traffic():
    return ('<div style="display: flex; gap: 8px; flex: none" aria-hidden="true">'
            '<span style="width: 12px; height: 12px; border-radius: 6px; background: #FF5F57"></span>'
            '<span style="width: 12px; height: 12px; border-radius: 6px; background: #FEBC2E"></span>'
            '<span style="width: 12px; height: 12px; border-radius: 6px; background: #28C840"></span></div>')


def mac_tabs(current="Spaces"):
    out = []
    for label, badge in [("Sessions", "2"), ("Tasks", "2"), ("Spaces", "1")]:
        on = label == current
        bg = f'background: {D_SEL}; ' if on else ''
        col = D_TITLE if on else "#C9CBD3"
        b = ('' if not badge else
             f'<span style="min-width: 16px; height: 16px; padding: 0 4px; box-sizing: border-box; border-radius: 8px; '
             f'background: {AMBER}; color: #1A1206; font-size: 10px; font-weight: 800; display: flex; '
             f'align-items: center; justify-content: center">{badge}</span>')
        out.append(f'<span role="tab" aria-selected="{str(on).lower()}" style="height: 26px; display: flex; '
                   f'align-items: center; gap: 6px; padding: 0 11px; border-radius: 13px; {bg}color: {col}; '
                   f'font-size: 12px; font-weight: 600">{label}{b}</span>')
    return (f'<div role="tablist" aria-label="View" style="display: flex; padding: 3px; border-radius: 16px; '
            f'background: {D_CTRL}">{"".join(out)}</div>')


def mac_titlebar(current="Spaces"):
    return f"""
  <div style="display: flex; align-items: center; gap: 8px; height: 52px; padding: 0 12px 0 14px; flex: none">
    {traffic()}
    <div style="flex: 1; display: flex; justify-content: center">{mac_tabs(current)}</div>
    <button aria-label="Search Spaces" style="flex: none; width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 15px; background: {D_CTRL}; color: #D6D7DD">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="7" cy="7" r="4.5"></circle><path d="M10.5 10.5 14 14"></path></svg>
    </button>
  </div>"""


def mac_hoststrip():
    return f"""
  <div style="display: flex; align-items: center; gap: 8px; padding: 0 16px 8px; font-size: 12px; color: {D_META}; flex: none">
    <span style="width: 7px; height: 7px; border-radius: 4px; background: {D_GREEN}"></span><span>Pro</span>
    <span style="width: 7px; height: 7px; border-radius: 4px; background: {D_GREEN}; margin-left: 4px"></span><span>Air</span>
    <span style="color: {D_SECOND}">· 2 desktops running</span>
    <span style="flex: 1"></span>
    <button style="height: 22px; display: flex; align-items: center; gap: 4px; padding: 0 8px; border: 0; border-radius: 11px; background: rgba(255,255,255,0.06); font-size: 11px; color: #C9CBD3">By status
      <svg width="9" height="9" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M4 6l4 4 4-4"></path></svg>
    </button>
  </div>"""


MAC_ROWS = [
    ("needs", "Needs input", D_AMBER, [
        ("1m", "ago", D_AMBER, "Inbox triage", "Codex gpt-6.1 · Ubuntu 24.04 · Pro",
         "Asks: send this reply?", D_AMBER, "ask", 1),
    ]),
    ("working", "Working", D_SECOND, [
        ("3m", "ago", D_GREENT, "Design review replies", "Codex gpt-6.1 · Ubuntu 24.04 · Pro",
         "Working · writing a draft", D_META, "live", 1),
        ("12m", "ago", D_GREENT, "Expense receipts", "Codex gpt-6.1 · Ubuntu 24.04 · Pro",
         "Working · downloading PDFs", D_META, "live", 1),
    ]),
    ("ready", "Ready", D_SECOND, [
        ("2h", "ago", D_TITLE, "Weekly reading", "Codex gpt-6.1 · Ubuntu 24.04 · Pro",
         "Ready · desktop is running", D_META, "idle", 1),
        ("4h", "ago", D_SECOND, "Travel bookings", "Codex gpt-6.1 · Ubuntu 24.04 · Air",
         "Air is offline", D_AMBER, "off", 0.5),
        ("1d", "ago", D_SECOND, "Vendor research", "Codex gpt-6.1 · Pro",
         "Stopped · send a message to start it", D_META, "stop", 1),
    ]),
]


def mac_list(selected="Design review replies"):
    out = []
    for _sid, label, color, rows in MAC_ROWS:
        out.append(
            f'<div style="display: flex; align-items: center; gap: 8px; width: 100%; padding: 14px 16px 6px 18px;">'
            f'<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="{D_SECOND}" stroke-width="2.4" aria-hidden="true"><path d="M4 6l4 4 4-4"></path></svg>'
            f'<span style="font-size: 13px; font-weight: 600; color: {color}">{label}</span>'
            f'<span style="font-size: 12px; color: {D_SECOND}">{len(rows)}</span></div>')
        for time, sub, tcol, title, meta, line, lcol, kind, op in rows:
            if kind == "ask":
                mark = (f'<svg style="flex: none" width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="{D_AMBER}" '
                        f'stroke-width="1.6" aria-hidden="true"><path d="M3 4.5A1.5 1.5 0 0 1 4.5 3h7A1.5 1.5 0 0 1 13 4.5v5a1.5 1.5 0 0 1-1.5 1.5H7l-3 2.5V11A1.5 1.5 0 0 1 3 9.5z"></path></svg>')
            elif kind == "live":
                mark = (f'<span style="flex: none; width: 7px; height: 7px; border-radius: 4px; background: {D_GREEN}; '
                        f'box-shadow: 0 0 0 3px rgba(50,215,75,0.22)"></span>')
            elif kind == "idle":
                mark = f'<span style="flex: none; width: 7px; height: 7px; border-radius: 4px; background: {IDLE}"></span>'
            elif kind == "off":
                mark = (f'<span style="flex: none; width: 7px; height: 7px; border-radius: 4px; '
                        f'border: 1.5px solid {AMBER}; box-sizing: border-box"></span>')
            else:
                mark = f'<span style="flex: none; width: 7px; height: 7px; border-radius: 4px; background: {STOPPED}"></span>'
            sel = title == selected
            selbg = f'background: {IPAD_SEL}; ' if sel else ''
            out.append(
                f'<a href="#" style="display: flex; align-items: stretch; padding-left: 16px; opacity: {op}; {selbg}">'
                f'<span style="flex: 0 0 46px; padding-top: 10px; display: flex; flex-direction: column">'
                f'<span style="font-size: 14px; line-height: 19px; font-weight: 650; font-variant-numeric: tabular-nums; color: {tcol}">{time}</span>'
                f'<span style="font-size: 11px; line-height: 15px; color: {D_SECOND}">{sub}</span></span>'
                f'<span style="flex: 1; min-width: 0; display: flex; align-items: center; gap: 10px; padding: 9px 14px 10px 0; '
                f'border-bottom: 1px solid {D_SEP}">'
                f'<span style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px">'
                f'<span style="font-size: 14px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{title}</span>'
                f'<span style="font-size: 12px; color: {D_META}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{meta}</span>'
                f'<span style="display: flex; align-items: center; gap: 5px; min-width: 0; font-size: 12px; color: {lcol}">'
                f'{mark}<span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{line}</span></span>'
                f'</span></span></a>')
    return "".join(out)


# --------------------------------------------------------- 18. Mac narrow --

def mac_chat_column(w, show_stage=True):
    """The narrow-window chat: identical anatomy to the phone, Mac metrics."""
    stage = ""
    if show_stage:
        stage = f"""
    <a href="#" style="margin: 0 12px 8px; height: 38px; border-radius: 19px; background: rgba(255,255,255,0.05); border: 1px solid {D_SEP}; display: flex; align-items: center; gap: 9px; padding: 0 11px 0 4px; flex: none;">
      <span style="display: block; width: 48px; height: 30px; border-radius: 6px; overflow: hidden; position: relative; background: linear-gradient(150deg, #332A4A, #1A172B);">
        <span style="position: absolute; left: 14%; top: 22%; right: 12%; bottom: 14%; border-radius: 2px; background: #202124; border: 0.5px solid rgba(255,255,255,0.12);"></span>
        <span style="position: absolute; left: 18%; top: 44%; width: 24%; height: 3px; border-radius: 2px; background: #8AB4F8;"></span>
      </span>
      <span style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 1px;">
        <span style="font-size: 12px; font-weight: 600; color: {D_TITLE};">Desktop</span>
        <span style="display: flex; align-items: center; gap: 5px; font-size: 11px; color: {D_GREENT};">
          <span style="width: 6px; height: 6px; border-radius: 3px; background: {D_GREEN};"></span>Working · composing a reply</span>
      </span>
      <span style="font-size: 12px; font-weight: 600; color: {D_ACCENT};">Watch</span>
    </a>"""
    return f"""
  <div style="flex: 1; min-height: 0; display: flex; flex-direction: column;">
    <div style="flex: 1; min-height: 0; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; gap: 11px; padding: 12px 14px;">
      <div style="align-self: flex-end; max-width: {w - 120}px; background: {BUBBLE}; color: {BUBBLE_INK}; border-radius: 15px; padding: 7px 11px; font-size: 13px; line-height: 18px;">go through this morning’s inbox and draft a reply to the design review thread</div>
      <div style="font-size: 13px; line-height: 19px; color: {D_TITLE};">I’ll open Gmail in the Space and read what came in this morning.</div>
      <div style="display: flex; align-items: center; gap: 7px; color: {D_META};">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['mail']}</svg>
        <span style="flex: 1; font-size: 12px;">Opened Gmail, read 12 messages</span>
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="{D_SECOND}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['chev_r']}</svg>
      </div>
      <div style="font-size: 13px; line-height: 19px; color: {D_TITLE};">Three need an answer. I’ve written one for the design review thread and left it as a draft — nothing has been sent.</div>
    </div>
{stage}
    <div style="margin: 0 12px 12px; min-height: 66px; border-radius: 16px; background: rgba(255,255,255,0.05); border: 1px solid {D_SEP}; padding: 9px 8px 8px 12px; display: flex; flex-direction: column; justify-content: space-between; flex: none;">
      <span style="font-size: 13px; color: {D_SECOND};">Message the agent…</span>
      <span style="display: flex; align-items: center; gap: 7px;">
        <span style="height: 22px; padding: 0 8px; border-radius: 11px; background: {D_CTRL}; display: flex; align-items: center; font-size: 11px; color: #C9CBD3;">Codex gpt-6.1 · High</span>
        <span style="flex: 1;"></span>
        <span style="width: 26px; height: 26px; border-radius: 13px; background: {D_TITLE}; display: flex; align-items: center; justify-content: center;">
          <span style="width: 9px; height: 9px; border-radius: 2px; background: {D_BG};"></span></span>
      </span>
    </div>
  </div>"""


def board_mac():
    list_view = f"""
{mac_titlebar()}
{mac_hoststrip()}
  <div style="flex: 1; min-height: 0; overflow: auto; display: flex; flex-direction: column; padding-bottom: 12px; border-top: 1px solid {D_SEP}">
    {mac_list(selected='')}
  </div>"""
    chat_view = f"""
  <div style="display: flex; align-items: center; gap: 8px; height: 52px; padding: 0 12px 0 14px; flex: none">
    {traffic()}
    <button aria-label="Back to Spaces" style="flex: none; width: 26px; height: 26px; margin-left: 4px; border: 0; border-radius: 13px; background: {D_CTRL}; display: flex; align-items: center; justify-content: center; color: {D_TITLE}; cursor: pointer;">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['back']}</svg></button>
    <span style="flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center;">
      <span style="font-size: 13px; font-weight: 600;">Inbox triage</span>
      <span style="display: flex; align-items: center; gap: 5px; font-size: 11px; color: {D_META};">
        <span style="width: 6px; height: 6px; border-radius: 3px; background: {D_GREEN};"></span>
        <span style="color: {D_GREENT}; font-weight: 600;">Working · 2m</span><span>· Pro</span></span>
    </span>
    <button aria-label="Space tools" style="flex: none; width: 26px; height: 26px; border: 0; border-radius: 13px; background: {D_CTRL}; display: flex; align-items: center; justify-content: center; color: {D_TITLE}; cursor: pointer;">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" aria-hidden="true">{I['tools']}</svg></button>
  </div>
{mac_chat_column(400)}"""
    body = f'<sc-if value="{{{{isList}}}}" hint-placeholder-val="{{{{true}}}}">{list_view}</sc-if>' \
           f'<sc-if value="{{{{isChat}}}}" hint-placeholder-val="{{{{false}}}}">{chat_view}</sc-if>'
    logic = """
  renderVals() {
    const v = this.props.view || 'list';
    return { isList: v === 'list', isChat: v === 'chat' };
  }"""
    props = {"view": {"editor": "enum", "options": ["list", "chat"], "default": "list"},
             "$preview": {"width": 400, "height": 860}}
    return head("Cua · Mac narrow window") + mac_screen(400, 860, body) + script(props, logic)


# ----------------------------------------------------------- 19. Mac wide --

def desk_pane(x, y, w, h, label_left, controlling=False, radius=14):
    """The desktop pane used on wide Mac and iPad."""
    chip = (f'<span style="height: 26px; padding: 0 10px; border-radius: 13px; background: {CONTROL_RING}; '
            f'display: flex; align-items: center; gap: 5px; font-size: 12px; font-weight: 600; color: #FFFFFF;">'
            f'{svg("hand", 12, "#FFFFFF", 2)}You have control</span>'
            if controlling else
            f'<span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: {D_META};">'
            f'<span style="width: 7px; height: 7px; border-radius: 4px; background: {D_GREEN}; '
            f'box-shadow: 0 0 0 3px rgba(50,215,75,0.22);"></span>'
            f'<span style="color: {D_GREENT}; font-weight: 600;">Working</span> · composing a reply</span>')
    action = ("Release control" if controlling else "Take control")
    ring = (f'<span aria-hidden="true" style="position: absolute; inset: 0; border: 2px solid {CONTROL_RING}; '
            f'border-radius: 8px; pointer-events: none;"></span>' if controlling else '')
    head_h = 38
    dh = h - head_h - 12
    dw = round(dh * 16 / 10)
    if dw > w - 16:
        dw = w - 16
        dh = round(dw * 10 / 16)
    off = (w - dw) // 2
    return f"""
  <div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; height: {h}px; border-radius: {radius}px; background: #121214; border: 1px solid {D_SEP}; overflow: hidden;">
    <div style="height: {head_h}px; display: flex; align-items: center; gap: 8px; padding: 0 8px 0 12px; border-bottom: 1px solid {D_SEP};">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="{D_SECOND}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['desktop']}</svg>
      <span style="font-size: 12px; font-weight: 600; color: {D_TITLE};">Desktop</span>
      <span style="width: 1px; height: 14px; background: {D_SEP};"></span>
      {chip}
      <span style="flex: 1;"></span>
      <button type="button" aria-label="Fit the whole desktop" style="width: 26px; height: 26px; border: 0; border-radius: 13px; background: {D_CTRL}; display: flex; align-items: center; justify-content: center; color: {D_TITLE}; cursor: pointer;">{svg('fit', 14, 'currentColor', 2)}</button>
      <button type="button" style="height: 26px; padding: 0 11px; border: 0; border-radius: 13px; background: {D_FILL}; color: #FFFFFF; font-size: 12px; font-weight: 600; display: flex; align-items: center; gap: 5px; cursor: pointer;">{svg('hand', 12, '#FFFFFF', 2)}{action}</button>
    </div>
    <div style="position: absolute; left: {off}px; top: {head_h + 6}px; width: {dw}px; height: {dh}px; overflow: hidden; border-radius: 6px;">
      {desk(dw, dh, 'compose')}
    </div>
    {ring}
  </div>"""


def board_mac_wide():
    W, H = 1180, 760
    body = f"""
  <div style="position: absolute; inset: 0; background: {D_BG};"></div>
  <div style="position: absolute; left: 0; top: 0; right: 0; height: 52px; display: flex; align-items: center; gap: 8px; padding: 0 12px 0 14px;">
    {traffic()}
    <div style="flex: 1; display: flex; justify-content: center">{mac_tabs()}</div>
    <button aria-label="Search Spaces" style="flex: none; width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 15px; background: {D_CTRL}; color: #D6D7DD">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="7" cy="7" r="4.5"></circle><path d="M10.5 10.5 14 14"></path></svg>
    </button>
  </div>

  <div style="position: absolute; left: 0; top: 52px; width: 300px; bottom: 0; border-right: 1px solid {D_SEP}; overflow: hidden;">
    {mac_hoststrip()}
    <div style="position: absolute; left: 0; right: 0; top: 30px; bottom: 0; overflow: hidden; border-top: 1px solid {D_SEP};">{mac_list()}</div>
  </div>

  <div style="position: absolute; left: 300px; top: 52px; width: 376px; bottom: 0; border-right: 1px solid {D_SEP}; display: flex; flex-direction: column;">
    <div style="height: 44px; display: flex; align-items: center; gap: 8px; padding: 0 14px; border-bottom: 1px solid {D_SEP}; flex: none;">
      <span style="flex: 1; min-width: 0; display: flex; flex-direction: column;">
        <span style="font-size: 14px; font-weight: 600;">Design review replies</span>
        <span style="display: flex; align-items: center; gap: 5px; font-size: 11px; color: {D_META};">
          <span style="width: 6px; height: 6px; border-radius: 3px; background: {D_GREEN};"></span>
          <span style="color: {D_GREENT}; font-weight: 600;">Working · 3m</span><span>· Pro · Ubuntu 24.04</span></span>
      </span>
      <button aria-label="Space tools" style="flex: none; width: 26px; height: 26px; border: 0; border-radius: 13px; background: {D_CTRL}; display: flex; align-items: center; justify-content: center; color: {D_TITLE}; cursor: pointer;">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" aria-hidden="true">{I['tools']}</svg></button>
    </div>
    {mac_chat_column(376, show_stage=False)}
  </div>

{desk_pane(688, 64, W - 688 - 14, H - 64 - 14, 'Desktop')}
"""
    return head("Cua · Mac wide window — chat and desktop together") + \
        f'<div style="width: {W}px; height: {H}px; position: relative; overflow: hidden; background: {D_BG}; ' \
        f'color: {D_TITLE}; font-family: {MAC_FONT}; font-size: 13px; line-height: 1.35;">{body}</div>' + \
        script({"$preview": {"width": W, "height": H}}, "  renderVals() { return {}; }")


# --------------------------------------------------------------- 20. iPad --

def board_ipad():
    W, H = 1210, 834
    rows = [
        (AMBER, "Inbox triage", "Asks: send this reply?", AMBER, "Codex gpt-6.1 · 1m ·", "Pro", True, False, "600", 1),
        (LIVE, "Design review replies", "Working · writing a draft · 3m", LIVE,
         "Codex gpt-6.1 · Ubuntu 24.04 ·", "Pro", False, True, "400", 1),
        (LIVE, "Expense receipts", "Working · downloading PDFs · 12m", LIVE,
         "Codex gpt-6.1 · Ubuntu 24.04 ·", "Pro", False, True, "400", 1),
        (IDLE, "Weekly reading", "Ready · desktop is running", GREY,
         "Codex gpt-6.1 · 2h ·", "Pro", False, False, "400", 1),
        (STOPPED, "Vendor research", "Stopped · send a message to start it", GREY,
         "Codex gpt-6.1 · 1d ·", "Pro", False, False, "400", 1),
    ]
    rh = ""
    for i, (dc, title, line, lc, meta, host, ask, live, w, op) in enumerate(rows):
        sel = i == 1
        selbg = f'background: {IPAD_SEL}; border-radius: 12px; ' if sel else ''
        border = '' if sel else f'border-bottom: 0.5px solid {HAIR};'
        mark = ''
        if ask:
            mark = (f'<svg style="flex: 0 0 14px;" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="{AMBER}" '
                    f'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I["ask"]}'
                    f'<circle cx="12" cy="14.2" r="0.5" fill="{AMBER}"></circle></svg>')
        elif live:
            mark = (f'<span style="width: 7px; height: 7px; flex: 0 0 7px; border-radius: 50%; background: {LIVE}; '
                    f'box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span>')
        rh += (f'<div style="margin: 0 8px; {selbg}display: flex; align-items: flex-start; padding-left: 12px; opacity: {op};">'
               f'<span style="width: 20px; flex: 0 0 20px; padding-top: 18px;">'
               f'<span style="display: block; width: 8px; height: 8px; border-radius: 50%; background: {dc};"></span></span>'
               f'<span style="flex: 1 1 auto; min-width: 0; padding: 11px 8px 12px 0; {border} display: flex; flex-direction: column; gap: 2px;">'
               f'<span style="font-size: 17px; line-height: 22px; font-weight: {w}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{title}</span>'
               f'<span style="display: flex; align-items: center; gap: 5px; font-size: 15px; line-height: 20px; color: {lc}; min-width: 0;">'
               f'{mark}<span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{line}</span></span>'
               f'<span style="display: flex; align-items: center; gap: 5px; font-size: 13px; line-height: 18px; color: {META}; white-space: nowrap; overflow: hidden;">'
               f'<span style="overflow: hidden; text-overflow: ellipsis;">{meta}</span>'
               f'<svg style="flex: 0 0 13px;" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true">{I["host"]}</svg>'
               f'<span>{host}</span></span></span></div>')

    # Chat column, 400pt, between the sidebar and the desktop pane.
    chat_x, chat_w = 348, 400
    desk_x = chat_x + chat_w + 14
    body = f"""
  <aside aria-label="Spaces" style="position: absolute; left: 10px; top: 42px; width: 320px; height: 782px; border-radius: 26px; background: {RAISED}; overflow: hidden;">
    <div style="position: absolute; top: 0; left: 0; right: 0; height: 44px; display: flex; align-items: center; padding: 0 4px 0 16px;">
      <span style="display: flex; align-items: center; gap: 7px; font-size: 16px; font-weight: 600; flex: 1 1 auto;">{dot(LIVE)}2 hosts</span>
      <button aria-label="Search Spaces" style="width: 44px; height: 44px; margin-right: 7px; border: 0; background: transparent; display: flex; align-items: center; justify-content: center; padding: 0;">{svg('search', 21, INK, 2)}</button>
      <button aria-label="New Space" style="width: 44px; height: 44px; border: 0; background: transparent; display: flex; align-items: center; justify-content: center; padding: 0;">{svg('plus', 21, INK, 2.2)}</button>
    </div>
    <div style="position: absolute; top: 56px; left: 0; right: 0; bottom: 0; overflow: hidden;">
      <div style="display: flex; align-items: center; gap: 8px; padding: 14px 16px 6px 20px; font-size: 15px; color: {GREY};">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['chev_d']}</svg>
        <span style="font-weight: 600; color: {AMBER};">Needs input</span><span style="color: {META};">1</span>
      </div>
      {rh}
    </div>
  </aside>

  <div style="position: absolute; left: {chat_x}px; top: 42px; width: {chat_w}px; height: 782px; border-radius: 26px; background: {RAISED}; overflow: hidden; display: flex; flex-direction: column;">
    <div style="height: 58px; display: flex; align-items: center; gap: 10px; padding: 0 14px; border-bottom: 0.5px solid {HAIR}; flex: none;">
      <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
        <span style="font-size: 17px; font-weight: 600;">Design review replies</span>
        <span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: {GREY};">
          {dot(LIVE, halo=True, size=7)}<span style="color: {LIVE}; font-weight: 600;">Working · 3m 02s</span><span>· Pro · Ubuntu 24.04</span></span>
      </span>
      {svg('tools', 20, INK)}
    </div>
    <div style="flex: 1 1 auto; min-height: 0; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; gap: 14px; padding: 14px 16px;">
      <div style="align-self: flex-end; max-width: 300px; background: {BUBBLE}; color: {BUBBLE_INK}; border-radius: 20px; padding: 9px 14px; font-size: 17px; line-height: 22px;">go through this morning’s inbox and draft a reply to the design review thread</div>
      <div style="font-size: 17px; line-height: 24px; color: {SOFT};">I’ll open Gmail in the Space and read what came in this morning.</div>
      <div style="display: flex; align-items: center; gap: 8px; color: {GREY};">
        {svg('mail', 17, 'currentColor')}<span style="flex: 1 1 auto; font-size: 15px;">Opened Gmail, read 12 messages</span>
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="{DIM}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['chev_r']}</svg>
      </div>
      <div style="font-size: 17px; line-height: 24px; color: {SOFT};">Three need an answer. I’ve written one for the design review thread and left it as a draft in Gmail — nothing has been sent.</div>
      <div style="display: flex; align-items: center; gap: 8px; color: {GREY};">
        {svg('edit', 17, 'currentColor')}<span style="flex: 1 1 auto; font-size: 15px;">Saved a draft in Gmail</span>
      </div>
    </div>
    <div style="margin: 0 12px 14px; height: 88px; border-radius: 22px; background: {BLACK}; border: 0.5px solid {EDGE}; padding: 11px 10px 10px 16px; display: flex; flex-direction: column; justify-content: space-between; flex: none;">
      <span style="font-size: 16px; color: {META};">Message the agent…</span>
      <span style="display: flex; align-items: center; gap: 8px;">
        <span style="height: 26px; padding: 0 10px; border-radius: 13px; background: {CARD}; display: flex; align-items: center; font-size: 12px; color: {SECOND};">Codex gpt-6.1 · High</span>
        <span style="flex: 1 1 auto;"></span>
        <span style="width: 32px; height: 32px; border-radius: 16px; background: {SOFT}; display: flex; align-items: center; justify-content: center;">
          <span style="width: 10px; height: 10px; border-radius: 3px; background: {BLACK};"></span></span>
      </span>
    </div>
  </div>

{desk_pane(desk_x, 42, W - desk_x - 10, 782, 'Desktop', radius=26)}
"""
    return head("Cua · iPad landscape — Spaces, chat and desktop") + \
        f'<div style="width: {W}px; height: {H}px; position: relative; overflow: hidden; background: {BLACK}; ' \
        f'color: {INK}; font-family: {FONT}; -webkit-font-smoothing: antialiased;">{body}</div>' + \
        script({"$preview": {"width": W, "height": H}}, "  renderVals() { return {}; }")


BOARDS = {
    "cua-mac.dc.html": (board_mac, 0, 5056, 400, 860, "Mac · narrow 400pt window, list and chat"),
    "cua-mac-wide.dc.html": (board_mac_wide, 480, 5056, 1180, 760, "Mac · wide window, chat and desktop side by side"),
    "cua-ipad.dc.html": (board_ipad, 1740, 5056, 1210, 834, "iPad · landscape, three columns"),
}
