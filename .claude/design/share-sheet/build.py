#!/usr/bin/env python3
"""Build every `sh-*` artboard and the canvas index entries for the page
"Share sheet (Oct 23)" on the LFG UI Map canvas.

Run:  python3 build.py
Out:  project/sh-*.dc.html  and  canvas-entries.json
"""

import json
import pathlib

from sheet_parts import (T, head, script, phone, svg, dot, ring_dot, I, lfg_icon, pin,
                         backdrop, safari_page, sheet, send_btn, circle_btn, eyebrow,
                         to_strip, status_hint, new_session_fields, message_field,
                         card_link, card_quote, card_images, card_file, footnote, keyboard,
                         compose_logic, session_rows, rows_logic, search_field, done_sheet,
                         BLACK, RAISED, CARD, CONTROL, INK, SOFT, SECOND, GREY, META, DIM,
                         ACCENT, ACCENT_INK, LIVE, AMBER, AMBER_INK, RED, IDLE, STOPPED,
                         BUBBLE, BUBBLE_INK, UNREAD)

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "project"
PAGE = {"id": "share-sheet", "name": "Share sheet (Oct 23)"}
PV = {"$preview": {"width": 390, "height": 844}}
NOOP = "  renderVals() { return {}; }"

PAGE_TITLE = "Sheets | Apple Developer Documentation"
PAGE_DOMAIN = "developer.apple.com"
PAGE_URL = "https://developer.apple.com/design/human-interface-guidelines/sheets"
LINK_TAIL = "your message, then the page title and link."


def compose_body(card_html, with_keyboard, banner=""):
    inner = T("""
    <div style="position: absolute; top: 70px; left: 0; right: 0; bottom: 0; display: flex; flex-direction: column;">
      [[BANNER]]
      [[STRIP]]
      [[HINT]]
      [[NEW]]
      [[MSG]]
      [[CARD]]
      [[FOOT]]
    </div>""", BANNER=banner, STRIP=to_strip(), HINT=status_hint(), NEW=new_session_fields(),
              MSG=message_field(), CARD=card_html, FOOT=footnote())
    return inner


def compose_board(title, card_html, logic, bg_title="Sheets", bg_url=PAGE_DOMAIN,
                  with_keyboard=True, banner="", kbd=("the", "fork", "sheet")):
    body = (backdrop(bg_title, bg_url) +
            sheet("Share to LFG", compose_body(card_html, with_keyboard, banner), lead="close",
                  lead_href="sh-system.dc.html", action=send_btn()) +
            (keyboard(kbd) if with_keyboard else ""))
    return head(title) + phone(body) + script(PV, logic)


# ------------------------------------------------------------ row 1 --

def board_system():
    """The iOS share sheet over Safari: LFG in the app row (1) and, as a
    proposal, recent sessions in the suggestions row (2)."""
    def person(avatar, label, href="sh2-selected.dc.html"):
        tag, extra = ("a", f' href="{href}"') if href else ("span", "")
        return (f'<{tag}{extra} style="width: 76px; flex: 0 0 76px; display: flex; flex-direction: column; '
                f'align-items: center; gap: 6px; text-align: center;">{avatar}'
                f'<span style="font-size: 11px; line-height: 13px; color: #F2F2F7; display: -webkit-box; '
                f'-webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;">{label}</span></{tag}>')

    def session_avatar(letter, tint):
        return (f'<span style="position: relative; width: 60px; height: 60px; border-radius: 30px; background: {tint}; '
                f'display: flex; align-items: center; justify-content: center; font-size: 24px; font-weight: 600; '
                f'color: #F2F2F7;">{letter}<span style="position: absolute; right: -3px; bottom: -3px; '
                f'border-radius: 7px; box-shadow: 0 0 0 2px #1C1C1E;">{lfg_icon(22, 6)}</span></span>')

    airdrop = (f'<span style="width: 60px; height: 60px; border-radius: 30px; background: #0A84FF; display: flex; '
               f'align-items: center; justify-content: center; color: #FFFFFF;">{svg("airdrop", 30, "currentColor", 1.8)}</span>')

    def app(tile, label, href=None):
        tag, extra = ("a", f' href="{href}"') if href else ("span", "")
        return (f'<{tag}{extra} style="width: 70px; flex: 0 0 70px; display: flex; flex-direction: column; '
                f'align-items: center; gap: 6px;">{tile}<span style="font-size: 11px; color: #F2F2F7;">{label}</span></{tag}>')

    def tile(bg, icon, ink="#FFFFFF"):
        return (f'<span style="width: 60px; height: 60px; border-radius: 14px; background: {bg}; display: flex; '
                f'align-items: center; justify-content: center; color: {ink};">{icon}</span>')

    def action(label, icon, last=False):
        b = "" if last else " border-bottom: 0.5px solid #38383A;"
        return (f'<div style="height: 48px; padding: 0 16px; display: flex; align-items: center; font-size: 17px;{b}">'
                f'<span style="flex: 1 1 auto;">{label}</span>{svg(icon, 20, "#F2F2F7", 1.8)}</div>')

    more = ('<svg width="26" height="26" viewBox="0 0 24 24" fill="#F2F2F7" aria-hidden="true">'
            '<circle cx="5" cy="12" r="2"></circle><circle cx="12" cy="12" r="2"></circle><circle cx="19" cy="12" r="2"></circle></svg>')

    sheet_html = T("""
  <section role="dialog" aria-label="Share" style="position: absolute; left: 0; right: 0; top: 292px; bottom: 0; background: #1C1C1E; border-radius: 38px 38px 0 0; overflow: hidden;">
    <div aria-hidden="true" style="position: absolute; top: 6px; left: 50%; width: 36px; height: 5px; margin-left: -18px; border-radius: 3px; background: #48484A;"></div>
    <div style="position: absolute; top: 22px; left: 18px; right: 16px; display: flex; align-items: center; gap: 12px;">
      <span style="width: 44px; height: 44px; flex: 0 0 44px; border-radius: 10px; background: #3A3A3C; display: flex; align-items: center; justify-content: center; color: #A1A1A6;">[[GLOBE]]</span>
      <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px;">
        <span style="font-size: 15px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">[[PTITLE]]</span>
        <span style="font-size: 13px; color: #8E8E93;">[[PDOMAIN]] · Options ›</span>
      </span>
      <span style="width: 30px; height: 30px; flex: 0 0 30px; border-radius: 15px; background: #3A3A3C; display: flex; align-items: center; justify-content: center;">[[X]]</span>
    </div>
    <div style="position: absolute; top: 86px; left: 10px; right: 0; display: flex; gap: 4px;">[[PEOPLE]]</div>
    <div style="position: absolute; top: 190px; left: 18px; right: 18px; height: 0.5px; background: #38383A;"></div>
    <div style="position: absolute; top: 206px; left: 8px; right: 0; display: flex; gap: 4px;">[[APPS]]</div>
    <div style="position: absolute; top: 312px; left: 16px; right: 16px; border-radius: 14px; background: #2C2C2E; overflow: hidden;">[[ACTIONS]]</div>
    [[PIN1]][[PIN2]]
  </section>""",
                   GLOBE=svg("globe", 22, "currentColor", 1.6), PTITLE=PAGE_TITLE, PDOMAIN=PAGE_DOMAIN,
                   X=svg("x", 13, SECOND, 2.8),
                   PEOPLE=person(airdrop, "AirDrop", href=None)
                   + person(session_avatar("F", "#3A5A8C"), "Fork session feature")
                   + person(session_avatar("L", "#5E4A7D"), "Liquid Glass tab bar")
                   + person(session_avatar("S", "#3F6B52"), "Ship lfg 1.3.1 to TestFlight")
                   + person(session_avatar("S", "#7A5A38"), "Shinkai room decorator"),
                   APPS=app(tile("#30D158", svg("bubble", 32, "#FFFFFF", 1.6)), "Messages")
                   + app(tile("#0A84FF", svg("mail", 30, "#FFFFFF", 1.6)), "Mail")
                   + app(lfg_icon(60, 14), "LFG", href="sh2-list.dc.html")
                   + app(tile("#FFD60A", svg("notes", 30, "#1C1C1E", 1.7)), "Notes")
                   + app(tile("#3A3A3C", more), "More"),
                   ACTIONS=action("Copy", "copy") + action("Add to Reading List", "book")
                   + action("Add Bookmark", "bookmark", last=True),
                   PIN1=pin(1, 196, 170), PIN2=pin(2, 74, 92))
    body = safari_page() + sheet_html
    return head("Share · iOS share sheet, LFG entry points") + phone(body) + script(PV, NOOP)


def board_compose():
    logic = compose_logic(initial="fork", draft="use this sheet pattern for the fork confirmation",
                          receives_tail=LINK_TAIL)
    return compose_board("Share · compose, a link from Safari", card_link(PAGE_TITLE, PAGE_DOMAIN), logic)


def board_pick():
    inner = T("""
    <div style="position: absolute; top: 70px; left: 0; right: 0; bottom: 0; display: flex; flex-direction: column;">
      [[SEARCH]]
      <div style="flex: 1 1 auto; overflow: hidden; padding-top: 4px;">[[ROWS]]</div>
    </div>""", SEARCH=search_field(), ROWS=session_rows(href="sh-compose.dc.html"))
    body = (backdrop() +
            sheet("All sessions", inner, lead="back", lead_href="sh-compose.dc.html"))
    return head("Share · all sessions") + phone(body) + script(PV, rows_logic(checked="fork"))


def board_new():
    logic = compose_logic(initial="new", draft="read this and plan the LFG share sheet with it",
                          receives_tail=LINK_TAIL)
    return compose_board("Share · start a new session with it", card_link(PAGE_TITLE, PAGE_DOMAIN), logic,
                         with_keyboard=False)


def board_landed():
    """How the share lands: a plain user turn in Fork session feature."""
    msg = ('use this sheet pattern for the fork confirmation<br><br>'
           f'{PAGE_TITLE}<br>'
           f'<span style="text-decoration: underline; word-break: break-all;">{PAGE_URL}</span>')
    tool = (f'<div style="display: flex; align-items: center; gap: 8px; padding: 2px 0; color: {GREY};">'
            f'{svg("globe", 17, "currentColor")}<span style="flex: 1 1 auto; font-size: 15px;">Fetched developer.apple.com</span>'
            f'{svg("chev_r", 12, DIM, 2.8)}</div>')
    body = T("""
  <div style="position: absolute; top: 112px; left: 0; right: 0; bottom: 140px; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; gap: 14px; padding: 0 16px 8px; box-sizing: border-box;">
    <div style="align-self: flex-end; max-width: 290px; background: [[BUB]]; color: [[BUBINK]]; border-radius: 20px; padding: 9px 14px; font-size: 17px; line-height: 22px;">when i tap fork on desktop or phone, it should open the fork right away</div>
    <div style="display: flex; align-items: center; gap: 8px; padding: 2px 0; color: #A1A1A6;">[[EDIT]]<span style="flex: 1 1 auto; font-size: 15px;">Edited 2 files</span>[[CHEV]]</div>
    <div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">The fork now opens as soon as the host returns its id. Next I’ll add the confirmation before it starts.</div>
    <div style="align-self: flex-end; max-width: 300px; background: [[BUB]]; color: [[BUBINK]]; border-radius: 20px; padding: 9px 14px; font-size: 17px; line-height: 22px;">[[MSG]]</div>
    [[TOOL]]
    <div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">I’ll match the fork confirmation to that: one task, a clear Fork button, and Cancel on the left.</div>
  </div>
  <div style="position: absolute; top: 0; left: 0; right: 0; height: 124px; background: linear-gradient(#000000 72%, rgba(0,0,0,0));"></div>
  <div style="position: absolute; top: 54px; left: 16px; right: 16px; height: 56px; display: flex; align-items: center; gap: 10px;">
    <a href="s2-list.dc.html" aria-label="Back to sessions" style="width: 44px; height: 44px; flex: 0 0 44px; border-radius: 22px; background: rgba(44,44,46,0.92); box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center;">[[BACK]]</a>
    <a href="s2-menu.dc.html" style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 3px;">
      <span style="font-size: 17px; font-weight: 600;">Fork session feature</span>
      <span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: #A1A1A6; white-space: nowrap;">
        <span style="width: 7px; height: 7px; border-radius: 50%; background: #30D158; box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span>
        <span style="color: #30D158; font-weight: 600;">Working · 4m 05s</span><span>· Pro · lfg</span>
      </span>
    </a>
    <a href="s2-menu.dc.html" aria-label="Session tools and options" style="width: 44px; height: 44px; flex: 0 0 44px; border-radius: 22px; background: rgba(44,44,46,0.92); box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center;">[[TOOLS]]</a>
  </div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 170px; background: linear-gradient(rgba(0,0,0,0), #000000 22%);"></div>
  <div style="position: absolute; left: 12px; right: 12px; bottom: 28px; height: 96px; border-radius: 24px; background: #1C1C1E; border: 0.5px solid #38383A; box-sizing: border-box; padding: 11px 10px 10px 16px; display: flex; flex-direction: column; justify-content: space-between;">
    <span style="font-size: 17px; line-height: 22px; color: #8E8E93;">Add to this turn…</span>
    <span style="display: flex; align-items: center; gap: 8px;">
      [[CLIP]]
      <span style="height: 28px; padding: 0 10px; border-radius: 14px; background: #2C2C2E; display: flex; align-items: center; font-size: 13px; font-weight: 500; color: #D1D1D6;">Opus 5.5 · High</span>
      <span style="flex: 1 1 auto;"></span>
      <span aria-label="Stop the current turn" role="img" style="width: 34px; height: 34px; border-radius: 17px; background: #F2F2F7; display: flex; align-items: center; justify-content: center;"><span style="width: 11px; height: 11px; border-radius: 3px; background: #000000;"></span></span>
    </span>
  </div>""", BUB=BUBBLE, BUBINK=BUBBLE_INK, MSG=msg, TOOL=tool,
             EDIT=svg("edit", 17, "currentColor"), CHEV=svg("chev_r", 12, DIM, 2.8),
             BACK=svg("back", 20, INK, 2.4), TOOLS=svg("tools", 20, INK),
             CLIP=('<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#A1A1A6" stroke-width="1.7" '
                   'stroke-linecap="round" aria-hidden="true"><path d="M20.5 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1l8.6-8.6a3.4 3.4 0 0 1 '
                   '4.8 4.8l-8.6 8.6a1.7 1.7 0 0 1-2.4-2.4l7.9-7.9"></path></svg>'))
    return head("Share · how it lands in the session") + phone(body) + script(PV, NOOP)


# ------------------------------------------------------------ row 2 --

def board_quote():
    logic = compose_logic(initial="fork", draft="this is the rule to follow for the fork sheet",
                          receives_tail="your message, then the quote, the page title and link.")
    card = card_quote("A sheet should hold one scoped task that stays close to what people were doing.",
                      f"{PAGE_TITLE} · {PAGE_DOMAIN}")
    return compose_board("Share · selected text from a page", card, logic, with_keyboard=False)


def board_images():
    logic = compose_logic(initial="glass", draft="the tab bar overlaps the composer on iPad, see both",
                          receives_tail="your message, then both images. They upload to its host first.")
    return compose_board("Share · screenshots from Photos", card_images("2 screenshots", "3.4 MB"), logic,
                         bg_title="Recents", bg_url="Photos", with_keyboard=False)


def board_file():
    logic = compose_logic(initial="readwise", draft="the export format changed, see page 3",
                          receives_tail="your message, then the PDF. It uploads to its host first.")
    return compose_board("Share · a PDF from Files", card_file("readwise-export-format.pdf", "PDF · 412 KB"),
                         logic, bg_title="Downloads", bg_url="Files", with_keyboard=False)


# ------------------------------------------------------------ row 3 --

CHECK = svg("check", 30, "currentColor", 3)


def done_board(title, icon, icon_bg, icon_ink, heading, dot_html, session, say, top=470):
    body = safari_page() + done_sheet(icon, icon_bg, icon_ink, heading, dot_html, session, say, top=top)
    return head(title) + phone(body) + script(PV, NOOP)


def halo_dot(color):
    return (f'<span style="width: 9px; height: 9px; flex: 0 0 9px; border-radius: 50%; background: {color}; '
            f'box-shadow: 0 0 0 3px {color}40;"></span>')


def board_joined():
    return done_board("Share · sent to a working session", CHECK, LIVE, BLACK, "Sent", halo_dot(LIVE),
                      "Fork session feature", "It’s working, so your message joins the current turn.")


def board_sent():
    return done_board("Share · sent to an idle session", CHECK, LIVE, BLACK, "Sent", dot(IDLE, size=9),
                      "Shinkai room decorator", "It starts its next turn on Pro now.")


def board_waits():
    return done_board("Share · sent to a session that needs input", CHECK, LIVE, BLACK, "Sent", dot(AMBER, size=9),
                      "Ship lfg 1.3.1 to TestFlight",
                      "It’s waiting on your answer to “upload build 205 now?” Your message runs after that.", top=448)


def board_resumed():
    return done_board("Share · sent to a closed session", CHECK, LIVE, BLACK, "Sent", dot(STOPPED, size=9),
                      "Readwise import fix", "It had ended, so this resumes it on Pro.")


def board_started():
    return done_board("Share · started a new session", CHECK, LIVE, BLACK, "Started", dot(LIVE, size=9),
                      "New session in lfg", "Claude starts on Pro with your message and the link.")


def board_queued():
    return done_board("Share · queued for an offline host", svg("clock", 30, "currentColor", 2.4), "#3D2B0E",
                      AMBER_INK, "Queued", ring_dot(AMBER, size=9), "Search Console audit",
                      "Air is offline. LFG sends it when Air is back; until then it waits in the session’s strip.",
                      top=448)


def board_failed():
    banner = T("""
      <div role="alert" style="margin: 0 16px 14px; border-radius: 14px; background: #2C2C2E; padding: 10px 12px; display: flex; align-items: center; gap: 10px;">
        <span style="width: 22px; height: 22px; flex: 0 0 22px; border-radius: 11px; background: [[RED]]; display: flex; align-items: center; justify-content: center; color: #FFFFFF; font-size: 14px; font-weight: 800;">!</span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">
          <span style="font-size: 15px; font-weight: 600; color: [[RED]];">Not sent</span>
          <span style="font-size: 13px; color: #A1A1A6;">Your draft is still here.</span>
        </span>
        <a href="sh-joined.dc.html" style="min-height: 44px; padding: 0 4px; display: flex; align-items: center; font-size: 15px; font-weight: 600; color: [[ACC]];">Try again</a>
      </div>""", RED=RED, ACC=ACCENT_INK)
    logic = compose_logic(initial="fork", draft="use this sheet pattern for the fork confirmation",
                          receives_tail=LINK_TAIL)
    return compose_board("Share · not sent", card_link(PAGE_TITLE, PAGE_DOMAIN), logic,
                         with_keyboard=False, banner=banner)


# ------------------------------------------------------------ row 4 --

def board_b_list():
    inner = T("""
    <div style="position: absolute; top: 70px; left: 0; right: 0; bottom: 0; display: flex; flex-direction: column;">
      [[CARD]]
      <div style="height: 12px;"></div>
      [[SEARCH]]
      <div style="flex: 1 1 auto; overflow: hidden; padding-top: 4px;">[[ROWS]]</div>
    </div>""", CARD=card_link(PAGE_TITLE, PAGE_DOMAIN, compact=True), SEARCH=search_field("Send to…"),
              ROWS=session_rows(href="sh-b-compose.dc.html"))
    body = backdrop() + sheet("Share to LFG", inner, lead="close", lead_href="sh-system.dc.html")
    return head("Share · option B, pick the session first") + phone(body) + script(PV, rows_logic(checked=""))


def board_b_compose():
    to_row = T("""
      <div style="padding: 0 20px 7px;">[[EB]]</div>
      <a href="sh-b-list.dc.html" style="margin: 0 16px; min-height: 52px; border-radius: 14px; background: #2C2C2E; padding: 8px 12px 8px 14px; box-sizing: border-box; display: flex; align-items: center; gap: 10px;">
        <span style="width: 9px; height: 9px; flex: 0 0 9px; border-radius: 50%; background: #30D158; box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span>
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">
          <span style="font-size: 16px; font-weight: 600;">Fork session feature</span>
          <span style="font-size: 13px; color: #8E8E93;">Working · Pro · lfg — joins its current turn</span>
        </span>
        [[CH]]
      </a>""", EB=eyebrow("Send to"), CH=svg("chev_r", 12, DIM, 2.8))
    inner = T("""
    <div style="position: absolute; top: 70px; left: 0; right: 0; bottom: 0; display: flex; flex-direction: column;">
      [[TO]]
      [[MSG]]
      [[CARD]]
    </div>""", TO=to_row, MSG=message_field(), CARD=card_link(PAGE_TITLE, PAGE_DOMAIN))
    body = (backdrop() +
            sheet("Share to LFG", inner, lead="back", lead_href="sh-b-list.dc.html",
                  action=send_btn(href="sh-joined.dc.html", bg=ACCENT, ink="#FFFFFF")) +
            keyboard(("the", "fork", "sheet")))
    logic = """
  constructor(props) { super(props); this.state = { draft: 'use this sheet pattern for the fork confirmation' }; }
  renderVals() { return { draft: this.state.draft, onType: (e) => this.setState({ draft: e.target.value }) }; }"""
    return head("Share · option B, compose after picking") + phone(body) + script(PV, logic)


# ------------------------------------------------------------ layout --

import gen_v2  # noqa: E402

V1, V2, AFTER, A1, A2, B = 0, 1264, 2528, 3792, 5056, 6320
_v1 = {**{"sh-system.dc.html": (board_system, "Share · 1 LFG in the app row, 2 sessions as suggestions (proposal)")},
       **{k: v for k, v in gen_v2.BOARDS2.items() if k in (
           "sh2-list.dc.html", "sh2-search.dc.html", "sh2-selected.dc.html", "sh2-typing.dc.html",
           "sh2-new.dc.html", "sh2-landed-waiting.dc.html", "sh2-landed.dc.html")}}
ROWS = [
    (V1, list(_v1.items())),
    (V2, [(k, gen_v2.BOARDS2[k]) for k in ("sh2-quote.dc.html", "sh2-images.dc.html", "sh2-file.dc.html",
                                           "sh2-failed.dc.html")]),
    (AFTER, [
        ("sh-joined.dc.html", (board_joined, "After Send · working session")),
        ("sh-sent.dc.html", (board_sent, "After Send · idle session")),
        ("sh-waits.dc.html", (board_waits, "After Send · session that needs input")),
        ("sh-resumed.dc.html", (board_resumed, "After Send · closed session")),
        ("sh-started.dc.html", (board_started, "After Send · new session")),
        ("sh-queued.dc.html", (board_queued, "After Send · host offline")),
    ]),
    (A1, [
        ("sh-compose.dc.html", (board_compose, "Draft A · compose: the guess is already in Send to")),
        ("sh-pick.dc.html", (board_pick, "Draft A · All sessions")),
        ("sh-new.dc.html", (board_new, "Draft A · New session")),
        ("sh-landed.dc.html", (board_landed, "Draft A · how it lands")),
        ("sh-failed.dc.html", (board_failed, "Draft A · not sent")),
    ]),
    (A2, [
        ("sh-quote.dc.html", (board_quote, "Draft A · selected text on a page")),
        ("sh-images.dc.html", (board_images, "Draft A · screenshots from Photos")),
        ("sh-file.dc.html", (board_file, "Draft A · a PDF from Files")),
    ]),
    (B, [
        ("sh-b-list.dc.html", (board_b_list, "Draft B · pick first")),
        ("sh-b-compose.dc.html", (board_b_compose, "Draft B · then compose")),
    ]),
]
BOARDS = {}
for y, items in ROWS:
    for i, (name, (fn, title)) in enumerate(items):
        BOARDS[name] = (fn, 470 * i, y, title)
ORDER = list(BOARDS)

SX = 3800  # sticky column, right of the widest row
NOTES = {
    "shTitle": {"x": 0, "y": V1 - 300, "kind": "title1", "maxW": 3680, "page": PAGE["id"],
                "text": "Share sheet (Oct 23): pick the session, then edit what you send"},
    "shTitleKinds": {"x": 0, "y": V2 - 300, "kind": "title1", "maxW": 1800, "page": PAGE["id"],
                     "text": "What you can share"},
    "shTitleAfter": {"x": 0, "y": AFTER - 300, "kind": "title1", "maxW": 2740, "page": PAGE["id"],
                     "text": "After Send: it says what happened, then closes itself"},
    "shTitleOld": {"x": 0, "y": A1 - 300, "kind": "title1", "maxW": 2270, "page": PAGE["id"],
                   "text": "First draft A (superseded): compose first"},
    "shTitleOldKinds": {"x": 0, "y": A2 - 300, "kind": "title1", "maxW": 1330, "page": PAGE["id"],
                        "text": "First draft A: what you can share"},
    "shTitleB": {"x": 0, "y": B - 300, "kind": "title1", "maxW": 1330, "page": PAGE["id"],
                 "text": "First draft B (superseded): pick first"},

    "shFlow": {"x": SX, "y": 0, "w": 460, "fill": "blue", "page": PAGE["id"], "text": (
        "The flow (Eugene's pick, Oct 23)\n\n"
        "Any app → Share → LFG → Send to → tap a session → the panel comes up → edit the text → Send.\n\n"
        "Most of the sheet is search and the list. Nothing is chosen when it opens, so the keyboard stays "
        "down and the list gets the screen.\n\n"
        "Pinned row: New session (your New Session defaults; ••• changes host, folder and agent). Then "
        "Recent (the five sessions you messaged last) and All sessions (the rest by last activity, so closed "
        "ones sink). Search matches title and folder.\n\n"
        "Choosing a session raises the panel: the preview, the text field, who gets it and what Send will "
        "do, then Send.\n\n"
        "The text field is exactly what is sent. It starts with the link; you type around it. Attachments "
        "are the one addition: they upload to the session's host when you send, and their paths go in after "
        "the text, as the paperclip does today.\n\n"
        "In the session (last two boards): a working session holds it in the soft strip until its turn "
        "takes it; then it is a plain blue bubble. An idle session shows the bubble at once."
    )},
    "shDecisions": {"x": SX, "y": 720, "w": 460, "fill": "orange", "page": PAGE["id"], "text": (
        "Decisions worth arguing with\n\n"
        "1. ONE SESSION PER SHARE. The reference app lets you tick several. Sending one link to two agents "
        "is rare, and the panel's “what Send will do” line needs one recipient. Ticking another session "
        "moves the check.\n\n"
        "2. WHAT YOU SEE IS WHAT IS SENT. No hidden title or template is added to the text. The preview is "
        "only a preview.\n\n"
        "3. RECENT = THE SESSIONS YOU MESSAGED LAST (lastUserAt), not the ones that are busy. That is the "
        "reference's “frequently contacted”.\n\n"
        "4. THE CHECK IS BLUE, not the reference's green: blue is the S2 accent for send.\n\n"
        "5. NEW SESSION IS THE PINNED ROW, like the reference's “My status”. Its ••• is the one button in a "
        "row anywhere in LFG; it is there because a new session has settings and a session does not.\n\n"
        "6. AFTER SEND it shows what happened for about 2 seconds, then closes (row 3). The reference app "
        "just closes; ours says when a message will wait or was queued."
    )},
    "shEntry": {"x": SX, "y": 1440, "w": 460, "fill": "pink", "page": PAGE["id"], "text": (
        "Two ways in (first board)\n\n"
        "1. LFG in the app row. Opens Send to with nothing chosen.\n\n"
        "2. PROPOSAL: your recent sessions in the suggestions row, next to AirDrop. Tapping one opens Send "
        "to with that session already chosen and the panel up.\n\n"
        "2 needs LFG to donate an INSendMessageIntent for a session each time you send to it from the app, "
        "and the extension to read the intent's conversation id. None of that exists today, so it can ship "
        "after 1."
    )},
    "shBuild": {"x": SX, "y": 2160, "w": 460, "fill": "green", "page": PAGE["id"], "text": (
        "What it takes to build\n\n"
        "• A new target: a share extension (SwiftUI) for links, text, images, movies and files.\n"
        "• Safari: a JavaScript preprocessing file returns the URL, page title and the current selection, so "
        "a quote arrives with its page.\n"
        "• App Group (none today). Move the hosts (lfg.hosts), recent folders and New Session defaults to a "
        "shared UserDefaults suite, plus a session snapshot so the list shows at once.\n"
        "• Keychain access group (none today) for the Cloudflare Access tokens.\n"
        "• Sending reuses what exists: POST /upload per file (64 MB cap), then POST /send {text, clientId}. "
        "A closed session resumes through the same call. New session: POST /api/sessions/new.\n"
        "• Offline host: the extension writes the message into the shared outbox, so the app's existing "
        "retry sends it. That moves the GRDB store into the App Group.\n"
        "• Server: no change."
    )},
    "shReused": {"x": SX, "y": 2880, "w": 460, "fill": "gray", "page": PAGE["id"], "text": (
        "Reused, not reinvented\n\n"
        "• Layout: the reference share sheet (Send to, search pill, grouped cards, round checks, bottom panel).\n"
        "• Status dots, words and colours, the offline ring: s2-list and dA2-sessions.\n"
        "• Agent marks: the app's own agent-claude / agent-codex images.\n"
        "• Sheet scaffold, grabber, 38pt corners, the close circle: s2-menu.\n"
        "• How it lands (the soft strip while it waits, then a bubble): s2-view, s2-queued.\n"
        "• Not sent = a red mark and “Not sent”, no reason: the S2 rule.\n\n"
        "Rows 4 to 6 are the first draft, kept for reference. Delete them once this is settled."
    )},
    "shLater": {"x": SX, "y": 3600, "w": 460, "fill": "gray", "page": PAGE["id"], "text": (
        "Not in this pass\n\n"
        "• Mac share extension. It could fit the desktop scope later without the New session row.\n"
        "• iPad: the same sheet as a form sheet. Check the panel and the keyboard there before building.\n"
        "• Light mode, with the rest of S2."
    )},
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = {}
    for name in ORDER:
        build, x, y, title = BOARDS[name]
        (OUT / name).write_text(build(), encoding="utf-8")
        entries[name] = {"x": x, "y": y, "w": 390, "h": 844, "title": title,
                         "page": PAGE["id"], "is_interactive": True}
    (HERE / "canvas-entries.json").write_text(json.dumps({
        "canvas": "https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD",
        "page": PAGE, "order": ORDER, "boards": entries, "notes": NOTES,
    }, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(entries)} boards to {OUT}")


if __name__ == "__main__":
    main()
