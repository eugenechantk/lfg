#!/usr/bin/env python3
"""V2, Eugene's pick (Oct 23): the list-first share sheet.

Modelled on the reference screenshot he sent (a messaging app's share
extension): most of the sheet is search + the session list; picking a session
raises a bottom panel with the preview, the editable text and Send. Styling
stays S2 (dark, blue accent, S2 dots and status words).

The text field holds exactly what is sent. It starts with the link (or the
quote and its link); you type around it. Attachments are the one addition:
they upload at send time and their paths go in after the text.
"""

import pathlib
import re

from sheet_parts import (T, js, head, script, phone, svg, I, lfg_icon, backdrop, sheet,
                         keyboard, shot_thumb, ring_dot, dot,
                         BLACK, RAISED, CARD, CONTROL, INK, SOFT, SECOND, GREY, META, DIM,
                         ACCENT, ACCENT_INK, LIVE, AMBER, AMBER_INK, RED, IDLE, STOPPED,
                         BUBBLE, BUBBLE_INK, UNREAD)

PV = {"$preview": {"width": 390, "height": 844}}
ASSETS = pathlib.Path(__file__).resolve().parents[3] / "ios" / "LFG" / "Assets.xcassets"

PAGE_TITLE = "Sheets | Apple Developer Documentation"
PAGE_DOMAIN = "developer.apple.com"
PAGE_URL = "https://developer.apple.com/design/human-interface-guidelines/sheets"
QUOTE = "A sheet should hold one scoped task that stays close to what people were doing."
MESSAGE = "use this sheet pattern for the fork confirmation"
CARD_BG = "#2C2C2E"
DOCK_BG = "#48484A"   # 2026-11-05: three levels like the reference (list, cards, lighter panel)


def agent_svg(name, size):
    """The app's own agent marks (Assets.xcassets/agent-*.imageset), inlined."""
    src = (ASSETS / f"agent-{name}.imageset" / f"agent-{name}.svg").read_text()
    src = re.sub(r"<title>.*?</title>", "", src)
    src = re.sub(r"<(path|stop)([^>]*?)\s*/>", r"<\1\2></\1>", src)
    src = re.sub(r"<svg[^>]*?(viewBox=\"[^\"]+\")[^>]*>",
                 rf'<svg width="{size}" height="{size}" \1 aria-hidden="true">', src, count=1)
    return src


# ------------------------------------------------------------ the data --
# The S2 sample sessions. `recent` = the five you messaged last (lastUserAt);
# the rest follow under All sessions by last activity, so closed ones sink.

ROWS = [
    {"id": "fork", "title": "Fork session feature", "agent": "claude", "kind": "working",
     "line": "Working · 3m", "where": "lfg · Pro", "recent": True},
    {"id": "ship", "title": "Ship lfg 1.3.1 to TestFlight", "agent": "claude", "kind": "needs",
     "line": "Asks: upload build 205 now?", "where": "lfg · Pro", "recent": True},
    {"id": "glass", "title": "Liquid Glass tab bar", "agent": "codex", "kind": "unread",
     "line": "New reply", "where": "lfg · Pro", "recent": True},
    {"id": "audit", "title": "Search Console audit", "agent": "codex", "kind": "offline",
     "line": "Air is offline", "where": "inbox", "recent": True},
    {"id": "shinkai", "title": "Shinkai room decorator", "agent": "claude", "kind": "idle",
     "line": "Idle · 1d", "where": "SleepingBeauty · Pro", "recent": True},
    {"id": "rsync", "title": "Readwise sync check", "agent": "codex", "kind": "working",
     "line": "Working · 12m", "where": "readwise-sync · Pro", "recent": False},
    {"id": "repo", "title": "Daily repo review", "agent": "claude", "kind": "unread",
     "line": "New reply", "where": "lfg · Pro", "recent": False},
    {"id": "iphone", "title": "Enhance iPhone control skill", "agent": "codex", "kind": "unread",
     "line": "New reply", "where": "inbox · Pro", "recent": False},
    {"id": "readwise", "title": "Readwise import fix", "agent": "codex", "kind": "closed",
     "line": "Ended yesterday", "where": "readwise-sync · Pro", "recent": False},
    {"id": "ipadpane", "title": "Made-for-iPad file pane", "agent": "claude", "kind": "idle",
     "line": "Idle · 2d", "where": "lfg · Pro", "recent": False},
    {"id": "madmen", "title": "Mad Men", "agent": "claude", "kind": "idle", "chat": True,
     "line": "Idle", "where": "Chat · Pro", "recent": False},
    {"id": "atlas", "title": "Atlas", "agent": "claude", "kind": "idle", "chat": True,
     "line": "Idle", "where": "Chat · Pro", "recent": False},
]

# Dot, line colour, what Send will do, and the After Send board it leads to.
K2 = {
    "working": {"dot": LIVE, "halo": True, "color": LIVE, "weight": "400",
                "does": "Joins its current turn", "done": "sh-joined.dc.html"},
    "needs": {"dot": AMBER, "halo": False, "color": AMBER, "weight": "600",
              "does": "Runs after you answer its question", "done": "sh-waits.dc.html"},
    "unread": {"dot": UNREAD, "halo": False, "color": "#D1D1D6", "weight": "600",
               "does": "Starts its next turn now", "done": "sh-sent.dc.html"},
    "idle": {"dot": IDLE, "halo": False, "color": GREY, "weight": "400",
             "does": "Starts its next turn now", "done": "sh-sent.dc.html"},
    "closed": {"dot": STOPPED, "halo": False, "color": GREY, "weight": "400",
               "does": "Resumes it", "done": "sh-resumed.dc.html"},
    "offline": {"dot": AMBER, "halo": False, "ring": True, "color": AMBER_INK, "weight": "400",
                "does": "LFG queues it until Air is back", "done": "sh-queued.dc.html"},
}


# ------------------------------------------------------------ pieces --

def avatar_markup(prefix="r"):
    """Agent mark in a circle, with the S2 status dot as a corner badge."""
    return T("""
          <span style="position: relative; width: 44px; height: 44px; flex: 0 0 44px; border-radius: 22px; background: #3A3A3C; display: flex; align-items: center; justify-content: center;">
            <sc-if value="{{[[P]].claude}}" hint-placeholder-val="{{true}}">[[CLAUDE]]</sc-if>
            <sc-if value="{{[[P]].codex}}" hint-placeholder-val="{{false}}">[[CODEX]]</sc-if>
            <span style="position: absolute; right: -2px; bottom: -2px; width: 11px; height: 11px; border-radius: 50%; background: {{[[P]].dotBg}}; border: 2.5px solid #2C2C2E; box-shadow: {{[[P]].dotShadow}}; box-sizing: content-box;"></span>
          </span>""", P=prefix, CLAUDE=agent_svg("claude", 24), CODEX=agent_svg("codex", 26))


def radio(on_key, off_key):
    return T("""
            <sc-if value="{{[[ON]]}}" hint-placeholder-val="{{false}}">
              <span style="width: 26px; height: 26px; flex: 0 0 26px; border-radius: 13px; background: #0A6EE0; display: flex; align-items: center; justify-content: center;">[[CHECK]]</span>
            </sc-if>
            <sc-if value="{{[[OFF]]}}" hint-placeholder-val="{{true}}">
              <span style="width: 26px; height: 26px; flex: 0 0 26px; border-radius: 13px; border: 1.5px solid #636366; box-sizing: border-box;"></span>
            </sc-if>""", ON=on_key, OFF=off_key, CHECK=svg("check", 15, "#FFFFFF", 3.2))


def search_pill():
    return T("""
    <div style="position: absolute; top: 70px; left: 16px; right: 16px; height: 44px; border-radius: 22px; background: #3A3A3C; display: flex; align-items: center; gap: 9px; padding: 0 14px; box-sizing: border-box; color: #8E8E93;">
      [[ICON]]
      <input aria-label="Search sessions and chats" placeholder="Search sessions and chats" value="{{q}}" onInput="{{onSearch}}" style="flex: 1 1 auto; min-width: 0; border: 0; outline: none; background: transparent; padding: 0; font-size: 17px; color: #FFFFFF;">
    </div>""", ICON=svg("search", 19, "currentColor", 2.1))


def new_row():
    """Pinned like the reference's 'My status' row: start a new session with this."""
    menu_item = lambda label, value, last=False: (
        f'<div style="min-height: 44px; padding: 0 14px 0 16px; display: flex; align-items: center; gap: 10px;'
        f'{"" if last else " border-bottom: 0.5px solid #48484A;"}">'
        f'<span style="flex: 1 1 auto; font-size: 16px;">{label}</span>'
        f'<span style="font-size: 16px; color: #A1A1A6;">{value}</span>{svg("chev_r", 11, "#636366", 2.8)}</div>')
    return T("""
    <sc-if value="{{showNew}}" hint-placeholder-val="{{true}}">
      <div style="margin: 12px 16px 0; border-radius: 22px; background: #2C2C2E; display: flex; align-items: center; padding: 0 14px 0 14px; min-height: 66px; position: relative;">
        <button type="button" onClick="{{pickNew}}" style="flex: 1 1 auto; min-width: 0; border: 0; background: transparent; font: inherit; color: inherit; text-align: left; display: flex; align-items: center; gap: 12px; padding: 11px 0; cursor: pointer;">
          <span style="width: 44px; height: 44px; flex: 0 0 44px; border-radius: 22px; background: #3A3A3C; display: flex; align-items: center; justify-content: center; color: #FFFFFF;">[[PLUS]]</span>
          <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
            <span style="font-size: 17px; line-height: 22px;">New session</span>
            <span style="font-size: 14px; color: #8E8E93; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">lfg · Claude · Opus 5.5 · Pro</span>
          </span>
        </button>
        <button type="button" onClick="{{toggleMenu}}" aria-label="New session options" style="width: 44px; height: 44px; flex: 0 0 44px; border: 0; background: transparent; display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer;">[[DOTS]]</button>
        <button type="button" onClick="{{pickNew}}" aria-label="Choose New session" style="width: 34px; height: 44px; flex: 0 0 34px; border: 0; background: transparent; display: flex; align-items: center; justify-content: flex-end; padding: 0; cursor: pointer;">[[RADIO]]</button>
        <sc-if value="{{menuOpen}}" hint-placeholder-val="{{false}}">
          <div role="menu" aria-label="New session options" style="position: absolute; right: 12px; top: 60px; width: 268px; border-radius: 16px; background: rgba(58,58,60,0.98); box-shadow: 0 12px 40px rgba(0,0,0,0.6); overflow: hidden; z-index: 4;">
            [[M1]][[M2]][[M3]]
          </div>
        </sc-if>
      </div>
    </sc-if>""", PLUS=svg("plus", 20, "currentColor", 2.2), RADIO=radio("newOn", "newOff"),
             DOTS=('<svg width="22" height="22" viewBox="0 0 24 24" fill="#F2F2F7" aria-hidden="true">'
                   '<circle cx="5" cy="12" r="1.9"></circle><circle cx="12" cy="12" r="1.9"></circle>'
                   '<circle cx="19" cy="12" r="1.9"></circle></svg>'),
             M1=menu_item("Host", "Pro"), M2=menu_item("Folder", "lfg"),
             M3=menu_item("Agent", "Claude · Opus 5.5", last=True))


def session_list(top=114):
    return T("""
  <div style="position: absolute; top: [[TOP]]px; left: 0; right: 0; bottom: 0; overflow: hidden;">
    [[NEW]]
    <sc-for list="{{sections}}" as="sec" hint-placeholder-count="2">
      <div style="padding: 20px 20px 8px; font-size: 15px; font-weight: 600; color: #8E8E93;">{{sec.label}}</div>
      <div style="margin: 0 16px; border-radius: 22px; background: #2C2C2E; overflow: hidden;">
        <sc-for list="{{sec.rows}}" as="r" hint-placeholder-count="3">
          <button type="button" onClick="{{r.pick}}" aria-pressed="{{r.pressed}}" style="width: 100%; border: 0; background: transparent; font: inherit; color: inherit; text-align: left; display: flex; align-items: center; gap: 12px; padding: 0 0 0 14px; cursor: pointer; opacity: {{r.opacity}};">
            [[AVATAR]]
            <span style="flex: 1 1 auto; min-width: 0; min-height: 66px; padding: 10px 14px 10px 0; box-sizing: border-box; border-bottom: {{r.rule}}; display: flex; align-items: center; gap: 10px;">
              <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
                <span style="font-size: 17px; line-height: 22px; font-weight: {{r.weight}}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{r.title}}</span>
                <span style="font-size: 14px; line-height: 19px; color: #8E8E93; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;"><span style="color: {{r.color}};">{{r.line}}</span> · {{r.where}}</span>
              </span>
              [[RADIO]]
            </span>
          </button>
        </sc-for>
      </div>
    </sc-for>
    <sc-if value="{{noMatch}}" hint-placeholder-val="{{false}}">
      <div style="padding: 40px 32px; text-align: center; font-size: 15px; line-height: 21px; color: #8E8E93;">No session or chat matches “{{q}}”. Start a new one with it instead.</div>
    </sc-if>
    <div style="height: {{listPad}};"></div>
  </div>""", TOP=top, NEW=new_row(), AVATAR=avatar_markup("r"), RADIO=radio("r.on", "r.off"))


# ------------------------------------------------------- dock previews --

def prev_link():
    return T("""
      <div style="height: 64px; display: flex; align-items: center; gap: 12px; padding-right: 16px; border-bottom: 0.5px solid #636366;">
        <span style="width: 64px; height: 64px; flex: 0 0 64px; background: #3A3A3C; display: flex; align-items: center; justify-content: center; color: #A1A1A6;">[[G]]</span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 15px; font-weight: 600; color: #F2F2F7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">[[TITLE]]</span>
          <span style="font-size: 13px; color: #8E8E93;">[[DOMAIN]]</span>
        </span>
      </div>""", G=svg("globe", 26, "currentColor", 1.5), TITLE=PAGE_TITLE, DOMAIN=PAGE_DOMAIN)


def remove_x(label):
    return (f'<button type="button" aria-label="{label}" style="width: 44px; height: 44px; flex: 0 0 44px; border: 0; '
            f'background: transparent; display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer;">'
            f'<span style="width: 26px; height: 26px; border-radius: 13px; border: 1.5px solid #D1D1D6; box-sizing: border-box; '
            f'display: flex; align-items: center; justify-content: center;">{svg("x", 12, "#D1D1D6", 2.8)}</span></button>')


def prev_quote():
    return T("""
      <div style="height: 64px; display: flex; align-items: center; gap: 12px; padding-right: 16px; border-bottom: 0.5px solid #636366;">
        <span style="width: 64px; height: 64px; flex: 0 0 64px; background: #3A3A3C; display: flex; align-items: center; justify-content: center; color: #A1A1A6;">[[Q]]</span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 15px; font-weight: 600; color: #F2F2F7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">Selected text · [[TITLE]]</span>
          <span style="font-size: 13px; color: #8E8E93;">[[DOMAIN]]</span>
        </span>
      </div>""", Q=svg("quote", 24, "currentColor", 1.7), TITLE=PAGE_TITLE, DOMAIN=PAGE_DOMAIN)


def prev_images():
    return T("""
      <div style="height: 76px; display: flex; align-items: center; gap: 8px; padding: 0 4px 0 12px; border-bottom: 0.5px solid #636366;">
        [[A]][[B]]
        <span style="flex: 1 1 auto; min-width: 0; padding-left: 4px; display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 15px; font-weight: 600; color: #F2F2F7;">2 screenshots</span>
          <span style="font-size: 13px; color: #8E8E93;">3.4 MB · upload to Pro when sent</span>
        </span>
        [[X]]
      </div>""", A=shot_thumb(34, 60, 0), B=shot_thumb(34, 60, 1), X=remove_x("Remove the screenshots"))


def prev_file():
    return T("""
      <div style="height: 68px; display: flex; align-items: center; gap: 12px; padding: 0 4px 0 14px; border-bottom: 0.5px solid #636366;">
        <span style="width: 38px; height: 48px; flex: 0 0 38px; border-radius: 5px; background: #F2F2F7; display: flex; align-items: flex-end; justify-content: center; padding-bottom: 6px; box-sizing: border-box;"><span style="font-size: 9px; font-weight: 800; color: #FF453A;">PDF</span></span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 15px; font-weight: 600; color: #F2F2F7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">readwise-export-format.pdf</span>
          <span style="font-size: 13px; color: #8E8E93;">PDF · 412 KB · uploads to Pro when sent</span>
        </span>
        [[X]]
      </div>""", X=remove_x("Remove the PDF"))


def dock(preview_html, banner=""):
    """Appears once a session is chosen: preview, the text that is sent, who gets it, Send."""
    return T("""
  <sc-if value="{{hasSel}}" hint-placeholder-val="{{true}}">
    <div style="position: absolute; left: 0; right: 0; bottom: {{dockBottom}}; background: [[BG]]; border-top: 0.5px solid #636366; box-shadow: 0 -10px 30px rgba(0,0,0,0.45);">
      [[PREVIEW]]
      [[BANNER]]
      <div style="padding: 10px 16px 0;">
        <textarea aria-label="Message to send" rows="{{rows}}" placeholder="Add a message…" value="{{draft}}" onInput="{{onType}}" style="display: block; width: 100%; box-sizing: border-box; border-radius: 22px; background: #1C1C1E; border: 1px solid #636366; padding: 11px 16px; font: inherit; font-size: 17px; line-height: 22px; color: #FFFFFF; resize: none; outline: none;"></textarea>
      </div>
      <div style="min-height: 58px; padding: 4px 6px 4px 20px; box-sizing: border-box; display: flex; align-items: center; gap: 10px;">
        <span style="width: 8px; height: 8px; flex: 0 0 8px; border-radius: 50%; background: {{toDotBg}}; box-shadow: {{toDotShadow}};"></span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">
          <span style="font-size: 15px; font-weight: 600; color: #F2F2F7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{toTitle}}</span>
          <span style="font-size: 13px; color: #8E8E93; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{toDoes}}</span>
        </span>
        <a href="{{sendHref}}" style="min-height: 44px; min-width: 88px; padding: 0 20px; box-sizing: border-box; border-radius: 22px; background: #0A6EE0; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600; color: #FFFFFF;">Send</a>
      </div>
      <div style="height: {{homePad}};"></div>
    </div>
  </sc-if>""", BG=DOCK_BG, PREVIEW=preview_html, BANNER=banner)


def logic(sel=None, q="", kbd=None, draft=None, menu=False):
    """One logic class for every v2 board: search, selection, dock, Send target.

    kbd: None (keyboard down) | 'search' | 'message' — which field the board
    shows focused. The keyboard itself is drawn by the board.
    """
    return T("""
  constructor(props) { super(props); this.state = { sel: [[SEL]], q: [[Q]], draft: [[DRAFT]], menu: [[MENU]] }; }
  renderVals() {
    const ROWS = [[ROWS]], K = [[K]], KBD = [[KBD]];
    const s = this.state, q = s.q.trim().toLowerCase();
    const pick = (id) => () => this.setState({ sel: s.sel === id ? null : id, menu: false });
    const decorate = (list) => list.map((x, i) => {
      const k = K[x.kind], on = s.sel === x.id;
      return {
        title: x.title, line: x.line, where: x.where, color: k.color, weight: k.weight,
        claude: x.agent === 'claude', codex: x.agent === 'codex',
        dotBg: k.ring ? '#2C2C2E' : k.dot,
        dotShadow: k.ring ? 'inset 0 0 0 1.8px ' + k.dot : 'none',
        opacity: x.kind === 'offline' ? '0.55' : '1',
        rule: i === list.length - 1 ? '0' : '0.5px solid #3A3A3C',
        on, off: !on, pressed: on ? 'true' : 'false', pick: pick(x.id)
      };
    });
    let sections;
    if (q) {
      const hits = ROWS.filter((x) => (x.title + ' ' + x.where).toLowerCase().indexOf(q) >= 0);
      // Sessions first; chats keep their own section after them.
      sections = [
        { label: 'Sessions', rows: decorate(hits.filter((x) => !x.chat)) },
        { label: 'Chats', rows: decorate(hits.filter((x) => x.chat)) }
      ].filter((x) => x.rows.length);
    } else {
      sections = [
        { label: 'Recent', rows: decorate(ROWS.filter((x) => x.recent)) },
        { label: 'All sessions', rows: decorate(ROWS.filter((x) => !x.recent && !x.chat)) },
        { label: 'Chats', rows: decorate(ROWS.filter((x) => !x.recent && x.chat)) }
      ].filter((x) => x.rows.length);
    }
    const hasSel = s.sel !== null;
    const cur = hasSel && s.sel !== 'new' ? ROWS.find((x) => x.id === s.sel) : null;
    const k = cur ? K[cur.kind] : null;
    const lines = s.draft.split('\\n').reduce((n, l) => n + Math.max(1, Math.ceil(l.length / 36)), 0);
    return {
      q: s.q, onSearch: (e) => this.setState({ q: e.target.value }),
      showNew: !q, noMatch: !!q && sections.length === 0,
      sections,
      pickNew: () => this.setState({ sel: s.sel === 'new' ? null : 'new', menu: false }),
      newOn: s.sel === 'new', newOff: s.sel !== 'new',
      menuOpen: s.menu, toggleMenu: () => this.setState({ menu: !s.menu }),
      hasSel,
      draft: s.draft, onType: (e) => this.setState({ draft: e.target.value }),
      rows: String(Math.min(6, Math.max(1, lines))),
      toTitle: cur ? cur.title : 'New session in lfg',
      toDoes: cur ? (k.does + ' \\u00b7 ' + cur.where) : 'Claude \\u00b7 Opus 5.5 on Pro \\u00b7 this is its first prompt',
      toDotBg: cur ? (k.ring ? 'transparent' : k.dot) : '#30D158',
      toDotShadow: cur ? (k.ring ? 'inset 0 0 0 1.6px ' + k.dot : k.halo ? '0 0 0 3px rgba(48,209,88,0.25)' : 'none') : 'none',
      sendHref: cur ? k.done : 'sh-started.dc.html',
      dockBottom: KBD === 'message' ? '336px' : '0px',
      homePad: KBD === 'message' ? '0px' : '30px',
      listPad: hasSel ? '260px' : '40px'
    };
  }""", SEL=js(sel), Q=js(q), DRAFT=js(draft if draft is not None else PAGE_URL), MENU=js(menu),
             ROWS=js(ROWS), K=js(K2), KBD=js(kbd))


def v2_board(title, sel=None, q="", kbd=None, draft=None, menu=False, preview=None, banner="",
             bg=("Sheets", PAGE_DOMAIN), kbd_words=("the", "fork", "sheet")):
    body = (backdrop(*bg) +
            sheet("Send to", search_pill() + session_list(), lead="close", lead_href="sh-system.dc.html", bg="#111113") +
            dock(preview if preview is not None else prev_link(), banner) +
            (keyboard(kbd_words) if kbd else ""))
    return head(title) + phone(body) + script(PV, logic(sel, q, kbd, draft, menu))


# ------------------------------------------------------------ boards --

def board_list():
    return v2_board("Share v2 · Send to, nothing chosen yet")


def board_search():
    return v2_board("Share v2 · searching sessions and chats", q="mad", kbd="search", kbd_words=("mad", "made", "Mad"))


def board_selected():
    return v2_board("Share v2 · a session chosen: the panel comes up", sel="fork")


def board_typing():
    return v2_board("Share v2 · editing the text", sel="fork", kbd="message",
                    draft=MESSAGE + "\n" + PAGE_URL)


def board_new():
    return v2_board("Share v2 · New session chosen, options open", sel="new", menu=True,
                    draft="read this and plan the LFG share sheet with it\n" + PAGE_URL)


def board_quote():
    return v2_board("Share v2 · selected text", sel="fork", preview=prev_quote(),
                    draft="this is the rule for the fork sheet:\n“" + QUOTE + "”\n" + PAGE_URL)


def board_images():
    return v2_board("Share v2 · screenshots", sel="glass", preview=prev_images(),
                    draft="the tab bar overlaps the composer on iPad, see both", bg=("Recents", "Photos"))


def board_file():
    return v2_board("Share v2 · a PDF, to a closed session", sel="readwise", preview=prev_file(),
                    draft="the export format changed, see page 3", bg=("Downloads", "Files"))


def board_failed():
    banner = T("""
      <div role="alert" style="margin: 10px 16px 0; display: flex; align-items: center; gap: 8px; font-size: 14px;">
        <span style="width: 18px; height: 18px; flex: 0 0 18px; border-radius: 9px; background: [[RED]]; color: #FFFFFF; font-size: 12px; font-weight: 800; display: flex; align-items: center; justify-content: center;">!</span>
        <span style="flex: 1 1 auto; color: [[RED]]; font-weight: 600;">Not sent</span>
        <span style="color: #8E8E93;">Your text is still here</span>
      </div>""", RED=RED)
    return v2_board("Share v2 · not sent", sel="fork", banner=banner, draft=MESSAGE + "\n" + PAGE_URL)


# ---------------------------------------------- how it looks in the session --

def _session_view(title, transcript_html, status_html, strip_html="", transcript_bottom=140):
    return T("""
  <div style="position: absolute; top: 112px; left: 0; right: 0; bottom: [[TB]]px; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; gap: 14px; padding: 0 16px 8px; box-sizing: border-box;">
    [[TRANSCRIPT]]
  </div>
  <div style="position: absolute; top: 0; left: 0; right: 0; height: 124px; background: linear-gradient(#000000 72%, rgba(0,0,0,0));"></div>
  <div style="position: absolute; top: 54px; left: 16px; right: 16px; height: 56px; display: flex; align-items: center; gap: 10px;">
    <a href="s2-list.dc.html" aria-label="Back to sessions" style="width: 44px; height: 44px; flex: 0 0 44px; border-radius: 22px; background: rgba(44,44,46,0.92); box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center;">[[BACK]]</a>
    <a href="s2-menu.dc.html" style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 3px;">
      <span style="font-size: 17px; font-weight: 600;">[[TITLE]]</span>
      <span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: #A1A1A6; white-space: nowrap;">[[STATUS]]</span>
    </a>
    <a href="s2-menu.dc.html" aria-label="Session tools and options" style="width: 44px; height: 44px; flex: 0 0 44px; border-radius: 22px; background: rgba(44,44,46,0.92); box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center;">[[TOOLS]]</a>
  </div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 196px; background: linear-gradient(rgba(0,0,0,0), #000000 26%);"></div>
  [[STRIP]]
  <div style="position: absolute; left: 12px; right: 12px; bottom: 28px; height: 96px; border-radius: 24px; background: #1C1C1E; border: 0.5px solid #38383A; box-sizing: border-box; padding: 11px 10px 10px 16px; display: flex; flex-direction: column; justify-content: space-between;">
    <span style="font-size: 17px; line-height: 22px; color: #8E8E93;">Add to this turn…</span>
    <span style="display: flex; align-items: center; gap: 8px;">
      [[CLIP]]
      <span style="height: 28px; padding: 0 10px; border-radius: 14px; background: #2C2C2E; display: flex; align-items: center; font-size: 13px; font-weight: 500; color: #D1D1D6;">Opus 5.5 · High</span>
      <span style="flex: 1 1 auto;"></span>
      <span aria-label="Stop the current turn" role="img" style="width: 34px; height: 34px; border-radius: 17px; background: #F2F2F7; display: flex; align-items: center; justify-content: center;"><span style="width: 11px; height: 11px; border-radius: 3px; background: #000000;"></span></span>
    </span>
  </div>""", TB=transcript_bottom, TRANSCRIPT=transcript_html, TITLE=title, STATUS=status_html, STRIP=strip_html,
             BACK=svg("back", 20, INK, 2.4), TOOLS=svg("tools", 20, INK),
             CLIP=('<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#A1A1A6" stroke-width="1.7" '
                   'stroke-linecap="round" aria-hidden="true"><path d="M20.5 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1l8.6-8.6a3.4 3.4 0 0 1 '
                   '4.8 4.8l-8.6 8.6a1.7 1.7 0 0 1-2.4-2.4l7.9-7.9"></path></svg>'))


def _earlier():
    return T("""
    <div style="align-self: flex-end; max-width: 290px; background: [[BUB]]; color: [[INK]]; border-radius: 20px; padding: 9px 14px; font-size: 17px; line-height: 22px;">when i tap fork on desktop or phone, it should open the fork right away</div>
    <div style="display: flex; align-items: center; gap: 8px; padding: 2px 0; color: #A1A1A6;">[[EDIT]]<span style="flex: 1 1 auto; font-size: 15px;">Edited 2 files</span>[[CHEV]]</div>
    <div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">The fork now opens as soon as the host returns its id. Next I’ll add the confirmation before it starts.</div>""",
             BUB=BUBBLE, INK=BUBBLE_INK, EDIT=svg("edit", 17, "currentColor"), CHEV=svg("chev_r", 12, DIM, 2.8))


def _working(t, extra=""):
    return ('<span style="width: 7px; height: 7px; border-radius: 50%; background: #30D158; '
            'box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span>'
            f'<span style="color: #30D158; font-weight: 600;">Working · {t}</span><span>{extra}· Pro · lfg</span>')


def board_landed_waiting():
    """Fork is mid-turn, so the share waits in S2's soft strip until the turn takes it."""
    strip = T("""
  <a href="s2-queued.dc.html" aria-label="Queued message options" style="position: absolute; left: 12px; right: 12px; bottom: 130px; height: 32px; border-radius: 16px; background: rgba(118,118,128,0.22); padding: 0 10px 0 12px; display: flex; align-items: center; gap: 8px;">
    <svg style="flex: 0 0 13px;" width="13" height="13" viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="12" cy="12" r="9" stroke="#48484A" stroke-width="3"></circle><path d="M12 3a9 9 0 0 1 9 9" stroke="#A1A1A6" stroke-width="3" stroke-linecap="round"></path></svg>
    <span style="flex: 1 1 auto; min-width: 0; font-size: 13px; color: #A1A1A6; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">[[TEXT]]</span>
    <svg style="flex: 0 0 16px;" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#8E8E93" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><circle cx="8" cy="12" r="0.9" fill="#8E8E93"></circle><circle cx="12" cy="12" r="0.9" fill="#8E8E93"></circle><circle cx="16" cy="12" r="0.9" fill="#8E8E93"></circle></svg>
  </a>""", TEXT=MESSAGE + " " + PAGE_URL)
    run = (f'<div style="display: flex; align-items: center; gap: 8px; padding: 2px 0; color: {GREY};">'
           f'{svg("search", 17, "currentColor")}<span style="flex: 1 1 auto; font-size: 15px;">Read 3 files</span>'
           f'{svg("chev_r", 12, DIM, 2.8)}</div>')
    body = _session_view("Fork session feature", _earlier() + run, _working("3m 58s", "· 1 queued "), strip,
                         transcript_bottom=176)
    return head("Share v2 · in the session: waiting for the turn") + phone(body) + script(PV, "  renderVals() { return {}; }")


def board_landed():
    """The turn has taken it: a plain user bubble, exactly the text that was in the field."""
    bubble = T("""
    <div style="align-self: flex-end; max-width: 300px; background: [[BUB]]; color: [[INK]]; border-radius: 20px; padding: 9px 14px; font-size: 17px; line-height: 22px;">[[MSG]]<br><span style="text-decoration: underline; word-break: break-all;">[[URL]]</span></div>""",
               BUB=BUBBLE, INK=BUBBLE_INK, MSG=MESSAGE, URL=PAGE_URL)
    fetched = (f'<div style="display: flex; align-items: center; gap: 8px; padding: 2px 0; color: {GREY};">'
               f'{svg("globe", 17, "currentColor")}<span style="flex: 1 1 auto; font-size: 15px;">Fetched developer.apple.com</span>'
               f'{svg("chev_r", 12, DIM, 2.8)}</div>')
    reply = ('<div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">I’ll match the fork confirmation to that '
             'page: one task, a clear Fork button, and Cancel on the left.</div>')
    body = _session_view("Fork session feature", _earlier() + bubble + fetched + reply, _working("4m 20s"))
    return head("Share v2 · in the session: the turn took it") + phone(body) + script(PV, "  renderVals() { return {}; }")


BOARDS2 = {
    "sh2-list.dc.html": (board_list, "Send to · nothing chosen: the list gets the screen"),
    "sh2-search.dc.html": (board_search, "Send to · search finds sessions and chats, in their own sections"),
    "sh2-selected.dc.html": (board_selected, "Send to · a session chosen: the panel comes up"),
    "sh2-typing.dc.html": (board_typing, "Send to · editing the text that is sent"),
    "sh2-new.dc.html": (board_new, "Send to · New session, with its options"),
    "sh2-landed-waiting.dc.html": (board_landed_waiting, "In the session · waits in the strip while it works"),
    "sh2-landed.dc.html": (board_landed, "In the session · the turn took it"),
    "sh2-quote.dc.html": (board_quote, "Send to · selected text"),
    "sh2-images.dc.html": (board_images, "Send to · screenshots"),
    "sh2-file.dc.html": (board_file, "Send to · a PDF, to a closed session"),
    "sh2-failed.dc.html": (board_failed, "Send to · not sent"),
}
