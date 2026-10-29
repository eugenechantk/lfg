#!/usr/bin/env python3
"""Row 1 — Spaces: list, empty, create, host, Space sheet, startup."""

from parts import *  # noqa: F401,F403
from parts import (head, script, phone, svg, dots, dot, ring_dot, glass_btn, top_bar,
                   status_line, composer, bottom_fade, I,
                   BLACK, RAISED, CARD, CONTROL, HAIR, EDGE, GLASS, GLASS_EDGE,
                   INK, SOFT, SECOND, GREY, META, DIM, ACCENT, ACCENT_INK,
                   LIVE, AMBER, AMBER_INK, RED, IDLE, STOPPED, desk)

PV = {"$preview": {"width": 390, "height": 844}}


# ------------------------------------------------------------- list chrome --

def host_header():
    """S2 list header: every host as a dot and its label."""
    return (f'<div style="flex: 1 1 auto; display: flex; align-items: center; gap: 12px; font-size: 16px; font-weight: 600;">'
            f'<span style="display: flex; align-items: center; gap: 6px;">{dot(LIVE)}Pro</span>'
            f'<span style="display: flex; align-items: center; gap: 6px;">{dot(LIVE)}Air</span></div>')


def list_top(plus_href="cua-new.dc.html"):
    return f"""
  <div style="position: absolute; top: 54px; left: 16px; right: 16px; height: 52px; display: flex; align-items: center; gap: 10px;">
    {host_header()}
    <div style="height: 48px; border-radius: 24px; background: {GLASS}; box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid {GLASS_EDGE}; display: flex; align-items: center; padding: 0 4px;">
      <button type="button" aria-label="Search Spaces" style="width: 44px; height: 44px; border: 0; background: transparent; display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer;">{svg('search', 21, INK, 2)}</button>
      <button type="button" aria-label="More options" style="width: 44px; height: 44px; border: 0; background: transparent; display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer;">{dots(20)}</button>
    </div>
  </div>"""


def tab_bar(current="message", plus_href="cua-new.dc.html"):
    """The S2 floating dock, with Message added as a third tab."""
    tabs = [
        ("sessions", "Sessions", "s2-list.dc.html", None),
        ("tasks", "Tasks", "tA2d-list.dc.html", "2"),
        ("message", "Message", "cua-list.dc.html", "1"),
    ]
    glyph = {
        "sessions": '<path d="M3 1h12a2.5 2.5 0 0 1 2.5 2.5v7A2.5 2.5 0 0 1 15 13H8.5L4 16.5V13H3A2.5 2.5 0 0 1 .5 10.5v-7A2.5 2.5 0 0 1 3 1z"></path>',
        "tasks": None,
        "message": None,
    }
    out = []
    for tid, label, href, badge in tabs:
        on = tid == current
        fill = f'background: {CONTROL}; ' if on else ''
        col = ACCENT_INK if on else INK
        cur = ' aria-current="page"' if on else ''
        if tid == "sessions":
            ic = f'<svg width="22" height="18" viewBox="0 0 26 22" fill="currentColor" aria-hidden="true">{glyph["sessions"]}</svg>'
        elif tid == "tasks":
            ic = ('<svg width="20" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
                  'stroke-linecap="round" aria-hidden="true"><rect x="2.5" y="4.5" width="15" height="14" rx="2"></rect>'
                  '<path d="M2.5 9h15M6.5 2.5v4M13.5 2.5v4"></path><circle cx="18" cy="17" r="4.2" fill="#242426"></circle>'
                  '<path d="M18 15.3V17l1.2 1"></path></svg>')
        else:
            ic = ('<svg width="21" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
                  'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
                  '<rect x="2.5" y="3.5" width="19" height="13" rx="2.5"></rect>'
                  '<path d="M7 20.5h10M12 16.5v4"></path><path d="M6.5 8.5h7M6.5 11.5h4"></path></svg>')
        bd = ('' if not badge else
              f'<span style="position: absolute; top: 4px; right: 16px; min-width: 18px; height: 18px; border-radius: 9px; '
              f'background: {AMBER}; color: {RAISED}; font-size: 11px; font-weight: 700; display: flex; align-items: center; '
              f'justify-content: center; padding: 0 4px; box-sizing: border-box;">{badge}</span>')
        out.append(f'<a href="{href}"{cur} style="width: 84px; height: 48px; border-radius: 24px; {fill}'
                   f'display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; '
                   f'color: {col}; position: relative;">{ic}'
                   f'<span style="font-size: 10px; font-weight: 600;">{label}</span>{bd}</a>')
    return f"""
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 150px; background: linear-gradient(rgba(0,0,0,0), rgba(0,0,0,0.96) 55%); pointer-events: none;"></div>
  <nav aria-label="Tabs" style="position: absolute; left: 16px; bottom: 28px; height: 56px; border-radius: 28px; background: rgba(36,36,38,0.94); box-shadow: 0 4px 24px rgba(0,0,0,0.5); border: 0.5px solid {GLASS_EDGE}; display: flex; align-items: center; padding: 4px; box-sizing: border-box;">
    {''.join(out)}
  </nav>
  <a href="{plus_href}" aria-label="New Space" style="position: absolute; right: 16px; bottom: 28px; width: 56px; height: 56px; border-radius: 28px; background: rgba(36,36,38,0.94); box-shadow: 0 4px 24px rgba(0,0,0,0.5); border: 0.5px solid {GLASS_EDGE}; display: flex; align-items: center; justify-content: center; color: {INK};">
    {svg('plus', 22, 'currentColor', 2.2)}
  </a>"""


# ----------------------------------------------------------------- 1. list --

def board_list():
    """Spaces list. Rows carry no buttons — swipe actions only, as S2 decided."""
    body = f"""
  <div style="position: absolute; top: 112px; left: 0; right: 0; bottom: 0; overflow: hidden;">
    <sc-for list="{{{{sections}}}}" as="sec" hint-placeholder-count="4">
      <button onClick="{{{{sec.toggle}}}}" aria-expanded="{{{{sec.expanded}}}}" style="width: 100%; border: 0; background: transparent; font: inherit; display: flex; align-items: center; gap: 8px; padding: 14px 16px 6px 20px; font-size: 15px; color: {GREY}; text-align: left; cursor: pointer;">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{sec.chevron}}}}"></path></svg>
        <span style="font-weight: 600; color: {{{{sec.color}}}};">{{{{sec.label}}}}</span>
        <span style="color: {META};">{{{{sec.count}}}}</span>
        <span style="flex: 1 1 auto;"></span>
      </button>
      <sc-for list="{{{{sec.rows}}}}" as="r" hint-placeholder-count="2">
        <a href="{{{{r.href}}}}" style="display: flex; align-items: flex-start; padding-left: 20px; opacity: {{{{r.opacity}}}};">
          <span style="width: 20px; flex: 0 0 20px; padding-top: 18px;"><span style="display: block; width: 8px; height: 8px; border-radius: 50%; background: {{{{r.dotBg}}}}; border: {{{{r.dotBorder}}}}; box-sizing: border-box;"></span></span>
          <span style="flex: 1 1 auto; min-width: 0; padding: 11px 16px 12px 0; border-bottom: 0.5px solid {HAIR}; display: flex; flex-direction: column; gap: 2px;">
            <span style="font-size: 17px; line-height: 22px; font-weight: {{{{r.weight}}}}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{{{r.title}}}}</span>
            <span style="display: flex; align-items: center; gap: 5px; font-size: 15px; line-height: 20px; color: {{{{r.lineColor}}}}; min-width: 0;">
              <sc-if value="{{{{r.ask}}}}" hint-placeholder-val="{{{{false}}}}">
                <svg style="flex: 0 0 14px;" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="{AMBER}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['ask']}<circle cx="12" cy="14.2" r="0.5" fill="{AMBER}"></circle></svg>
              </sc-if>
              <sc-if value="{{{{r.live}}}}" hint-placeholder-val="{{{{false}}}}">
                <span style="width: 7px; height: 7px; flex: 0 0 7px; border-radius: 50%; background: {LIVE}; box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span>
              </sc-if>
              <span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{{{r.line}}}}</span>
            </span>
            <span style="display: flex; align-items: center; gap: 5px; font-size: 13px; line-height: 18px; color: {META}; white-space: nowrap; overflow: hidden;">
              <span style="overflow: hidden; text-overflow: ellipsis;">{{{{r.meta}}}}</span>
              <svg style="flex: 0 0 13px;" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true">{I['host']}</svg>
              <span>{{{{r.host}}}}</span>
            </span>
          </span>
        </a>
      </sc-for>
    </sc-for>
  </div>
{list_top()}
  <div style="position: absolute; top: 0; left: 0; right: 0; height: 112px; background: {BLACK}; z-index: -1;"></div>
{tab_bar()}"""
    logic = f"""
  constructor(props) {{ super(props); this.state = {{ collapsed: {{ needs: false, working: false, ready: false, stopped: true }} }}; }}
  renderVals() {{
    const c = this.state.collapsed;
    const open = 'M6 9l6 6 6-6', shut = 'M9 6l6 6-6 6';
    const d = (col) => ({{ dotBg: col, dotBorder: '0' }});
    const ring = (col) => ({{ dotBg: 'transparent', dotBorder: '1.5px solid ' + col }});
    const row = (o) => Object.assign({{ href: 'cua-chat.dc.html', weight: '400', lineColor: '{GREY}', ask: false, live: false, opacity: '1' }}, o);
    const defs = [
      {{ id: 'needs', label: 'Needs input', color: '{AMBER}', rows: [
        row({{ href: 'cua-confirm.dc.html', ...d('{AMBER}'), weight: '600', title: 'Inbox triage',
              ask: true, line: 'Asks: send this reply?', lineColor: '{AMBER}',
              meta: 'Codex gpt-6.1 \\u00b7 Ubuntu 24.04 \\u00b7 1m \\u00b7', host: 'Pro' }})
      ]}},
      {{ id: 'working', label: 'Working', color: '{GREY}', rows: [
        row({{ href: 'cua-chat.dc.html', ...d('{LIVE}'), title: 'Design review replies', live: true,
              line: 'Working \\u00b7 writing a draft \\u00b7 3m', lineColor: '{LIVE}',
              meta: 'Codex gpt-6.1 \\u00b7 Ubuntu 24.04 \\u00b7', host: 'Pro' }}),
        row({{ ...d('{LIVE}'), title: 'Expense receipts', live: true,
              line: 'Working \\u00b7 downloading PDFs \\u00b7 12m', lineColor: '{LIVE}',
              meta: 'Codex gpt-6.1 \\u00b7 Ubuntu 24.04 \\u00b7', host: 'Pro' }})
      ]}},
      {{ id: 'ready', label: 'Ready', color: '{GREY}', rows: [
        row({{ ...d('{IDLE}'), title: 'Weekly reading', line: 'Ready \\u00b7 desktop is running',
              meta: 'Codex gpt-6.1 \\u00b7 Ubuntu 24.04 \\u00b7 2h \\u00b7', host: 'Pro' }}),
        row({{ ...ring('{AMBER}'), title: 'Travel bookings', line: 'Air is offline \\u00b7 last seen 14m ago',
              lineColor: '{AMBER_INK}', opacity: '0.5',
              meta: 'Codex gpt-6.1 \\u00b7 Ubuntu 24.04 \\u00b7 4h \\u00b7', host: 'Air' }})
      ]}},
      {{ id: 'stopped', label: 'Stopped', color: '{GREY}', rows: [
        row({{ href: 'cua-stopped.dc.html', ...d('{STOPPED}'), title: 'Vendor research',
              line: 'Stopped \\u00b7 send a message to start it',
              meta: 'Codex gpt-6.1 \\u00b7 1d \\u00b7', host: 'Pro' }})
      ]}}
    ];
    const counts = {{ needs: '1', working: '2', ready: '2', stopped: '6' }};
    return {{ sections: defs.map((x) => ({{
      label: x.label, color: x.color, count: counts[x.id],
      chevron: c[x.id] ? shut : open, expanded: c[x.id] ? 'false' : 'true',
      rows: c[x.id] ? [] : x.rows,
      toggle: () => {{ const n = Object.assign({{}}, c); n[x.id] = !c[x.id]; this.setState({{ collapsed: n }}); }}
    }})) }};
  }}"""
    return head("Cua · Spaces list") + phone(body) + script(PV, logic)


# ---------------------------------------------------------------- 2. empty --

def board_empty():
    body = f"""
  <div style="position: absolute; top: 112px; left: 32px; right: 32px; bottom: 190px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; text-align: center;">
    <span style="width: 84px; height: 84px; border-radius: 42px; background: {RAISED}; border: 0.5px solid {EDGE}; display: flex; align-items: center; justify-content: center; color: {GREY};">
      {svg('desktop', 36, 'currentColor', 1.5)}
    </span>
    <span style="font-size: 22px; line-height: 28px; font-weight: 600;">No Spaces yet</span>
    <span style="font-size: 16px; line-height: 22px; color: {SECOND};">A Space is a Linux desktop that Codex works in. Chat with it here, watch what it does, or take over the screen yourself.</span>
    <a href="cua-new.dc.html" style="margin-top: 6px; height: 50px; padding: 0 22px; border-radius: 25px; background: {ACCENT}; color: {INK}; font-size: 17px; font-weight: 600; display: flex; align-items: center; gap: 8px;">
      {svg('plus', 17, 'currentColor', 2.4)}New Space</a>
    <span style="font-size: 13px; line-height: 18px; color: {META};">Spaces run on Pro or Air, the same hosts your sessions use.</span>
  </div>
{list_top()}
{tab_bar()}"""
    return head("Cua · Spaces, empty") + phone(body) + script(PV, "  renderVals() { return {}; }")


# ----------------------------------------------------------------- 3. new --

def sheet_shell(title, inner, lead="Close", lead_href="cua-list.dc.html", top=96):
    """The NewSession sheet scaffold: drag indicator, 34pt corners, Close leading."""
    return f"""
  <div aria-hidden="true" style="position: absolute; inset: 0; background: rgba(0,0,0,0.5);"></div>
  <section role="dialog" aria-label="{title}" style="position: absolute; left: 0; right: 0; top: {top}px; bottom: 0; border-radius: 34px 34px 0 0; background: {RAISED}; border-top: 0.5px solid {GLASS_EDGE}; display: flex; flex-direction: column;">
    <div aria-hidden="true" style="height: 20px; display: flex; align-items: center; justify-content: center;"><span style="width: 36px; height: 5px; border-radius: 3px; background: {CONTROL};"></span></div>
    <div style="height: 44px; padding: 0 16px; display: flex; align-items: center; gap: 8px;">
      <a href="{lead_href}" style="min-width: 60px; min-height: 44px; display: flex; align-items: center; font-size: 17px; color: {ACCENT_INK};">{lead}</a>
      <h1 style="flex: 1 1 auto; margin: 0; text-align: center; font-size: 17px; font-weight: 600;">{title}</h1>
      <span style="min-width: 60px;"></span>
    </div>
    <div style="flex: 1 1 auto; overflow: hidden; padding: 6px 16px 0;">{inner}</div>
  </section>"""


def field_row(label, value, sub=None, chevron=True, icon=None, href=None, value_color=INK):
    ch = (f'<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="{DIM}" stroke-width="2.6" '
          f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I["chev_r"]}</svg>') if chevron else ''
    ic = f'{svg(icon, 17, GREY)}' if icon else ''
    s = (f'<span style="font-size: 13px; color: {META};">{sub}</span>') if sub else ''
    tag, extra = ("a", f' href="{href}"') if href else ("div", "")
    return (f'<{tag}{extra} style="min-height: 52px; padding: 10px 14px; border-bottom: 0.5px solid {HAIR}; '
            f'display: flex; align-items: center; gap: 10px;">{ic}'
            f'<span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">'
            f'<span style="font-size: 16px;">{label}</span>{s}</span>'
            f'<span style="font-size: 16px; color: {value_color}; white-space: nowrap;">{value}</span>{ch}</{tag}>')


def board_new():
    seg = f"""
      <div role="tablist" aria-label="Agent" style="height: 34px; border-radius: 9px; background: rgba(118,118,128,0.24); padding: 2px; box-sizing: border-box; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); margin: 10px 0 2px;">
        <button role="tab" aria-selected="{{{{codexOn}}}}" onClick="{{{{pickCodex}}}}" type="button" style="border: 0; border-radius: 7px; background: {{{{codexBg}}}}; color: {{{{codexFg}}}}; font-size: 14px; font-weight: {{{{codexW}}}}; cursor: pointer;">Codex</button>
        <button role="tab" aria-selected="{{{{claudeOn}}}}" onClick="{{{{pickClaude}}}}" type="button" style="border: 0; border-radius: 7px; background: {{{{claudeBg}}}}; color: {{{{claudeFg}}}}; font-size: 14px; font-weight: {{{{claudeW}}}}; cursor: pointer;">Claude Code</button>
      </div>"""
    inner = f"""
    <label for="cua-name" style="display: block; font-size: 12px; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; color: {META}; margin: 4px 0 7px 2px;">Name</label>
    <input id="cua-name" value="Inbox triage" style="width: 100%; height: 48px; box-sizing: border-box; border: 0; border-radius: 14px; background: {CARD}; padding: 0 14px; font-size: 17px; color: {INK}; outline: none;">
    <div style="font-size: 12px; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; color: {META}; margin: 18px 0 0 2px;">Agent</div>
    {seg}
    <div style="font-size: 13px; line-height: 18px; color: {META}; margin: 2px 2px 0;">{{{{agentNote}}}}</div>
    <div style="font-size: 12px; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; color: {META}; margin: 18px 0 7px 2px;">Space</div>
    <div style="border-radius: 14px; background: {CARD}; overflow: hidden;">
      {field_row('Host', 'Pro', icon='host', href='cua-host.dc.html')}
      {field_row('Desktop', 'Ubuntu 24.04', sub='1280 × 800', icon='desktop')}
      {field_row('Folders it can read', 'None', sub='Share a folder from Pro', icon='folder')}
    </div>
    <div style="font-size: 13px; line-height: 18px; color: {META}; margin: 10px 2px 0;">The Space starts when you create it and keeps running until you stop it.</div>
    <button type="button" style="position: absolute; left: 16px; right: 16px; bottom: 34px; height: 50px; border: 0; border-radius: 25px; background: {ACCENT}; color: {INK}; font-size: 17px; font-weight: 600; cursor: pointer;">Create Space</button>"""
    body = f"""
{list_top()}
  <div style="position: absolute; top: 112px; left: 20px; right: 20px; display: flex; flex-direction: column; gap: 18px; opacity: 0.4;">
    <span style="width: 62%; height: 13px; border-radius: 6px; background: rgba(255,255,255,0.08);"></span>
    <span style="width: 48%; height: 13px; border-radius: 6px; background: rgba(255,255,255,0.08);"></span>
  </div>
{sheet_shell('New Space', inner)}"""
    logic = f"""
  renderVals() {{
    const a = (this.state && this.state.agent) || 'codex';
    const on = {{ bg: 'rgba(255,255,255,0.18)', fg: '{INK}', w: '600' }};
    const off = {{ bg: 'transparent', fg: '{SECOND}', w: '500' }};
    const c = a === 'codex' ? on : off, l = a === 'claude' ? on : off;
    return {{
      codexOn: a === 'codex' ? 'true' : 'false', claudeOn: a === 'claude' ? 'true' : 'false',
      codexBg: c.bg, codexFg: c.fg, codexW: c.w, claudeBg: l.bg, claudeFg: l.fg, claudeW: l.w,
      agentNote: a === 'codex'
        ? 'Codex drives the desktop \\u2014 it can open apps, click and type.'
        : 'Claude Code works in the Space over the terminal. It does not drive the desktop.',
      pickCodex: () => this.setState({{ agent: 'codex' }}),
      pickClaude: () => this.setState({{ agent: 'claude' }})
    }};
  }}"""
    return head("Cua · New Space") + phone(body) + script(PV, logic)


# ---------------------------------------------------------------- 4. host --

def board_host():
    rows = []
    for name, machine, online, sel in [("Pro", "Eugenes-MacBook-Pro", True, True),
                                       ("Air", "Eugenes-MacBook-Air", True, False)]:
        mark = (f'<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="{ACCENT_INK}" stroke-width="2.6" '
                f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I["check"]}</svg>') if sel else ''
        rows.append(
            f'<button type="button" aria-pressed="{str(sel).lower()}" style="width: 100%; min-height: 60px; padding: 11px 14px; '
            f'border: 0; border-bottom: 0.5px solid {HAIR}; background: transparent; display: flex; align-items: center; gap: 11px; '
            f'text-align: left; cursor: pointer;">{dot(LIVE)}'
            f'<span style="flex: 1 1 auto; display: flex; flex-direction: column; gap: 1px;">'
            f'<span style="font-size: 17px; font-weight: 500;">{name}</span>'
            f'<span style="font-size: 13px; color: {META};">{machine} · 2 Spaces running</span></span>{mark}</button>')
    rows.append(
        f'<div style="min-height: 60px; padding: 11px 14px; display: flex; align-items: center; gap: 11px; opacity: 0.5;">'
        f'{ring_dot(AMBER)}'
        f'<span style="flex: 1 1 auto; display: flex; flex-direction: column; gap: 1px;">'
        f'<span style="font-size: 17px; font-weight: 500;">Mini</span>'
        f'<span style="font-size: 13px; color: {AMBER_INK};">Offline · you can’t start a Space here yet</span></span></div>')
    inner = f"""
    <div style="border-radius: 14px; background: {CARD}; overflow: hidden;">{''.join(rows)}</div>
    <div style="font-size: 13px; line-height: 18px; color: {META}; margin: 12px 2px 0;">The Space lives on this Mac. Folders you share must be on the same Mac, and the desktop stops being reachable while that Mac is offline.</div>"""
    body = f"""
{list_top()}
  <div style="position: absolute; top: 112px; left: 20px; right: 20px; display: flex; flex-direction: column; gap: 18px; opacity: 0.4;">
    <span style="width: 62%; height: 13px; border-radius: 6px; background: rgba(255,255,255,0.08);"></span>
  </div>
{sheet_shell('Host', inner, lead='Back', lead_href='cua-new.dc.html', top=300)}"""
    return head("Cua · Host picker") + phone(body) + script(PV, "  renderVals() { return {}; }")


# --------------------------------------------------------------- 5. sheet --

def board_sheet():
    """Space sheet. Space POWER lives here and nowhere near the composer."""
    tiles = [
        ("desktop", "Watch desktop", "cua-watch.dc.html"),
        ("hand", "Take control", "cua-handoff.dc.html"),
        ("folder", "Shared folders", None),
        ("file", "Files & links", None),
        ("key", "Accounts", None),
        ("browser", "Open apps", None),
    ]
    tg = []
    for icon, label, href in tiles:
        tag, extra = ("a", f' href="{href}"') if href else ("div", "")
        tg.append(f'<{tag}{extra} style="height: 74px; border-radius: 16px; background: {CARD}; display: flex; '
                  f'flex-direction: column; align-items: center; justify-content: center; gap: 6px; '
                  f'font-size: 13px; color: {SOFT};">{svg(icon, 21, SECOND)}{label}</{tag}>')
    inner = f"""
    <div style="display: flex; flex-direction: column; gap: 2px; padding: 0 2px 12px;">
      <span style="font-size: 20px; font-weight: 600;">Inbox triage</span>
      <span style="font-size: 13px; color: {META};">Pro · Ubuntu 24.04 · started 42m ago</span>
    </div>
    <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px;">{''.join(tg)}</div>

    <div style="font-size: 12px; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; color: {META}; margin: 20px 0 7px 2px;">Agent</div>
    <div style="border-radius: 14px; background: {CARD}; overflow: hidden;">
      {field_row('Model', 'Codex gpt-6.1')}
      {field_row('Effort', 'High')}
      {field_row('Stop the current turn', '', chevron=False, value_color=ACCENT_INK)}
    </div>

    <div style="font-size: 12px; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; color: {META}; margin: 20px 0 7px 2px;">Space</div>
    <div style="border-radius: 14px; background: {CARD}; overflow: hidden;">
      <div style="min-height: 52px; padding: 10px 14px; border-bottom: 0.5px solid {HAIR}; display: flex; align-items: center; gap: 10px;">
        {dot(LIVE)}<span style="flex: 1 1 auto; font-size: 16px;">Running</span>
        <span style="font-size: 13px; color: {META};">42m · 1.2 GB</span>
      </div>
      <button type="button" style="width: 100%; min-height: 52px; padding: 10px 14px; border: 0; background: transparent; display: flex; align-items: center; gap: 10px; text-align: left; cursor: pointer;">
        {svg('power', 17, AMBER_INK)}<span style="flex: 1 1 auto; font-size: 16px; color: {AMBER_INK};">Stop this Space</span>
      </button>
    </div>
    <div style="font-size: 13px; line-height: 18px; color: {META}; margin: 9px 2px 0;">Stopping the Space closes the desktop and its open apps. The chat is kept, and sending a message starts it again.</div>"""
    body = f"""
{top_bar('Inbox triage', status_line(LIVE, 'Working · 2m', ' · Pro'))}
{sheet_shell('Space', inner, top=132)}"""
    return head("Cua · Space sheet") + phone(body) + script(PV, "  renderVals() { return {}; }")


# ------------------------------------------------------------ 6. starting --

def board_starting():
    steps = [
        ("done", "Space created"),
        ("done", "Desktop image ready"),
        ("now", "Starting the desktop"),
        ("todo", "Connecting Codex"),
    ]
    sh = []
    for kind, label in steps:
        if kind == "done":
            mark = (f'<span style="width: 20px; height: 20px; flex: 0 0 20px; border-radius: 10px; background: {LIVE}; '
                    f'display: flex; align-items: center; justify-content: center;">'
                    f'<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="{BLACK}" stroke-width="3.4" '
                    f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I["check"]}</svg></span>')
            col, w = SOFT, "400"
        elif kind == "now":
            mark = ('<svg style="flex: 0 0 20px;" width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">'
                    f'<circle cx="12" cy="12" r="9" stroke="{CONTROL}" stroke-width="3"></circle>'
                    f'<path d="M12 3a9 9 0 0 1 9 9" stroke="{ACCENT_INK}" stroke-width="3" stroke-linecap="round"></path></svg>')
            col, w = INK, "600"
        else:
            mark = (f'<span style="width: 20px; height: 20px; flex: 0 0 20px; border-radius: 10px; '
                    f'border: 2px solid {CONTROL}; box-sizing: border-box;"></span>')
            col, w = META, "400"
        sh.append(f'<div style="display: flex; align-items: center; gap: 11px; min-height: 34px;">{mark}'
                  f'<span style="font-size: 16px; font-weight: {w}; color: {col};">{label}</span></div>')
    body = f"""
{top_bar('Inbox triage', status_line(IDLE, 'Starting · 12s', ' · Pro'))}
  <div style="position: absolute; top: 150px; left: 16px; right: 16px; border-radius: 20px; background: {RAISED}; border: 0.5px solid {EDGE}; padding: 18px; display: flex; flex-direction: column; gap: 4px;">
    <span style="font-size: 18px; font-weight: 600; margin-bottom: 8px;">Starting this Space</span>
    {''.join(sh)}
    <span style="font-size: 13px; line-height: 18px; color: {META}; margin-top: 10px;">About 20 seconds. You can type now — your message is sent as soon as Codex connects.</span>
  </div>
  <div style="position: absolute; top: 420px; left: 16px; right: 16px; height: 229px; border-radius: 20px; background: {RAISED}; border: 0.5px solid {EDGE}; overflow: hidden; display: flex; align-items: center; justify-content: center;">
    <span style="display: flex; flex-direction: column; align-items: center; gap: 10px; color: {DIM};">
      {svg('desktop', 30, 'currentColor', 1.5)}
      <span style="font-size: 14px;">The desktop appears here</span>
    </span>
  </div>
{bottom_fade()}
{composer(placeholder='Tell Codex what to do…', stop_default=False)}"""
    logic = """
  renderVals() {
    const d = (this.state && this.state.draft) || '';
    return { draft: d, onType: (e) => this.setState({ draft: e.target.value }),
      showStop: false, showSend: true, send: () => this.setState({ draft: '' }) };
  }"""
    return head("Cua · Space starting") + phone(body) + script(PV, logic)


BOARDS = {
    "cua-list.dc.html": (board_list, 0, 0, 390, 844, "Phone · Spaces list, every status"),
    "cua-empty.dc.html": (board_empty, 470, 0, 390, 844, "Phone · no Spaces yet"),
    "cua-new.dc.html": (board_new, 940, 0, 390, 844, "Phone · create a Space (Codex is primary)"),
    "cua-host.dc.html": (board_host, 1410, 0, 390, 844, "Phone · host picker, existing Pro/Air pattern"),
    "cua-sheet.dc.html": (board_sheet, 1880, 0, 390, 844, "Phone · Space sheet — power lives here, not by the composer"),
    "cua-starting.dc.html": (board_starting, 2350, 0, 390, 844, "Phone · startup progress"),
}
