#!/usr/bin/env python3
"""Rows 2 and 3 — the chat, the stage, the handoff."""

from parts import (head, script, phone, svg, dot, glass_btn, top_bar, status_line, status_dyn,
                   composer, bottom_fade, transcript, bubble, prose, tool_row,
                   tool_group, fact_row, desk, I,
                   BLACK, RAISED, CARD, CONTROL, HAIR, EDGE, GLASS, GLASS_EDGE,
                   INK, SOFT, SECOND, GREY, META, DIM, ACCENT, ACCENT_INK,
                   LIVE, AMBER, AMBER_INK, RED, IDLE, STOPPED, BUBBLE, CONTROL_RING)

PV = {"$preview": {"width": 390, "height": 844}}

# ---------------------------------------------------------------- the stage --
# New component. The phone cannot hold a transcript and a live desktop at full
# size at once, so the stage has two states and the chat never leaves the screen.


def desk_thumb(w, h):
    """An abstract desktop, for sizes too small to render the real thing."""
    return (f'<span style="display: block; width: {w}px; height: {h}px; border-radius: 7px; overflow: hidden; '
            f'position: relative; background: linear-gradient(150deg, #332A4A, #1A172B);">'
            f'<span style="position: absolute; left: 14%; top: 22%; right: 12%; bottom: 14%; border-radius: 3px; '
            f'background: #202124; border: 0.5px solid rgba(255,255,255,0.12);"></span>'
            f'<span style="position: absolute; left: 14%; top: 22%; right: 12%; height: 5px; '
            f'background: #35363A; border-radius: 3px 3px 0 0;"></span>'
            f'<span style="position: absolute; left: 18%; top: 44%; width: 22%; height: 3px; border-radius: 2px; '
            f'background: #8AB4F8;"></span>'
            f'<span style="position: absolute; left: 18%; top: 56%; width: 46%; height: 3px; border-radius: 2px; '
            f'background: rgba(255,255,255,0.22);"></span>'
            f'<span style="position: absolute; left: 18%; top: 68%; width: 34%; height: 3px; border-radius: 2px; '
            f'background: rgba(255,255,255,0.14);"></span></span>')


def stage_collapsed(bottom=134, line="Working · composing a reply", color=LIVE,
                    href="cua-watch.dc.html"):
    """The resting state: a 44pt live strip in the slot S2 gives its pill row."""
    return f"""
  <a href="{href}" aria-label="Watch the desktop" style="position: absolute; left: 12px; right: 12px; bottom: {bottom}px; height: 44px; border-radius: 22px; background: {RAISED}; border: 0.5px solid {EDGE}; display: flex; align-items: center; gap: 10px; padding: 0 12px 0 5px; box-sizing: border-box;">
    {desk_thumb(56, 34)}
    <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">
      <span style="font-size: 14px; font-weight: 500; color: {SOFT};">Desktop</span>
      <span style="display: flex; align-items: center; gap: 5px; font-size: 12px; color: {color}; white-space: nowrap; overflow: hidden;">
        {dot(color, halo=(color == LIVE), size=6)}<span style="overflow: hidden; text-overflow: ellipsis;">{line}</span>
      </span>
    </span>
    <span style="font-size: 14px; font-weight: 600; color: {ACCENT_INK};">Watch</span>
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="{DIM}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['chev_u']}</svg>
  </a>"""


def stage_expanded(bottom=134, variant="compose", status=LIVE,
                   status_text="Working · composing a reply",
                   action="Take control", action_href="cua-handoff.dc.html", overlay=""):
    return f"""
  <div style="position: absolute; left: 12px; right: 12px; bottom: {bottom}px; height: 229px; border-radius: 20px; overflow: hidden; border: 0.5px solid {EDGE}; background: {RAISED};">
    {desk(366, 229, variant)}
    <a href="cua-chat.dc.html" aria-label="Collapse the desktop" style="position: absolute; top: 8px; right: 8px; width: 30px; height: 30px; border-radius: 15px; background: rgba(0,0,0,0.5); backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); display: flex; align-items: center; justify-content: center;">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="{INK}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{I['chev_d']}</svg>
    </a>
    <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 46px; background: rgba(0,0,0,0.58); backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px); display: flex; align-items: center; gap: 8px; padding: 0 8px 0 12px;">
      {dot(status, halo=(status == LIVE), size=7)}
      <span style="flex: 1 1 auto; min-width: 0; font-size: 13px; color: {SOFT}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{status_text}</span>
      <a href="{action_href}" style="height: 32px; padding: 0 13px; border-radius: 16px; background: {ACCENT}; color: {INK}; font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 6px;">
        {svg('hand', 14, 'currentColor', 1.9)}{action}</a>
    </div>
    {overlay}
  </div>"""


# ------------------------------------------------------- 6/7. chat + tools --

CHAT_ITEMS = [
    bubble("go through this morning’s inbox and draft a reply to the design review thread"),
    prose("I’ll open Gmail in the Space and read what came in this morning."),
]


def board_chat():
    items = CHAT_ITEMS + [
        tool_group("mail", "Opened Gmail, read 12 messages", [
            "Opened Chrome", "Signed in to Google", "Read 12 messages in Inbox",
            "Opened “Design review — round 3”",
        ]),
        prose("Three need an answer. I’ve written one for the design review thread and left it as a "
              "draft in Gmail — nothing has been sent."),
        tool_row("edit", "Saved a draft in Gmail"),
    ]
    body = f"""
{transcript(items, bottom=186)}
{top_bar('Inbox triage', status_line(LIVE, 'Working · 2m 14s', ' · Pro'))}
{bottom_fade()}
{stage_collapsed()}
{composer()}"""
    logic = f"""
  constructor(props) {{ super(props); this.state = {{ tool: false, draft: '' }}; }}
  renderVals() {{
    const s = this.state, open = 'M6 9l6 6 6-6', shut = 'M9 6l6 6-6 6';
    const hasText = s.draft.trim().length > 0;
    return {{
      toolOpen: s.tool, toolChevron: s.tool ? open : shut,
      toggleTool: () => this.setState({{ tool: !s.tool }}),
      draft: s.draft, onType: (e) => this.setState({{ draft: e.target.value }}),
      showStop: !hasText, showSend: hasText, send: () => this.setState({{ draft: '' }})
    }};
  }}"""
    return head("Cua · Chat, agent working") + phone(body) + script(PV, logic)


def board_tools():
    items = [
        tool_group("mail", "Opened Gmail, read 12 messages", [
            "Opened Chrome", "Signed in to Google", "Read 12 messages in Inbox",
            "Opened “Design review — round 3”",
        ]),
        fact_row("check", "Google · connected", "Signed in inside this Space", icon_color=LIVE),
        fact_row("folder", "lfg on Pro · shared", "The Space can read this folder while the task runs",
                 icon_color=GREY),
        prose("I pulled the spacing numbers from the shared folder so the reply quotes the real values."),
        tool_group("file", "Read 2 files", [
            "Read lfg/.claude/feature/sessions-redesign-s2.md",
            "Read lfg/ios/LFG/SessionListView.swift",
        ], open_key="tool2Open", chev_key="tool2Chevron", toggle="toggleTool2"),
    ]
    body = f"""
{transcript(items, bottom=186)}
{top_bar('Inbox triage', status_line(LIVE, 'Working · 2m 40s', ' · Pro'))}
{bottom_fade()}
{stage_collapsed(line='Working · reading shared files')}
{composer()}"""
    logic = f"""
  constructor(props) {{ super(props); this.state = {{ tool: true, tool2: false, draft: '' }}; }}
  renderVals() {{
    const s = this.state, open = 'M6 9l6 6 6-6', shut = 'M9 6l6 6-6 6';
    const hasText = s.draft.trim().length > 0;
    return {{
      toolOpen: s.tool, toolChevron: s.tool ? open : shut, toggleTool: () => this.setState({{ tool: !s.tool }}),
      tool2Open: s.tool2, tool2Chevron: s.tool2 ? open : shut, toggleTool2: () => this.setState({{ tool2: !s.tool2 }}),
      draft: s.draft, onType: (e) => this.setState({{ draft: e.target.value }}),
      showStop: !hasText, showSend: hasText, send: () => this.setState({{ draft: '' }})
    }};
  }}"""
    return head("Cua · Tool step expanded, accounts and folders") + phone(body) + script(PV, logic)


# ------------------------------------------------------------- 8. queued --

def board_queued():
    """The soft strip above the composer — s2-queued, unchanged behaviour."""
    items = [
        prose("Three need an answer. I’ve written one for the design review thread and left it as a "
              "draft in Gmail — nothing has been sent."),
        tool_row("edit", "Saved a draft in Gmail"),
    ]
    strip = f"""
  <sc-if value="{{{{isQueued}}}}" hint-placeholder-val="{{{{true}}}}">
    <button onClick="{{{{toggleMenu}}}}" aria-haspopup="menu" aria-expanded="{{{{menuAttr}}}}" aria-label="Queued message options" style="position: absolute; left: 12px; right: 12px; bottom: 186px; height: 32px; border: 0; border-radius: 16px; background: {{{{rowBg}}}}; backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); padding: 0 10px 0 12px; font: inherit; display: flex; align-items: center; gap: 8px; text-align: left; cursor: pointer;">
      <svg style="flex: 0 0 13px;" width="13" height="13" viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="12" cy="12" r="9" stroke="{CONTROL}" stroke-width="3"></circle><path d="M12 3a9 9 0 0 1 9 9" stroke="{GREY}" stroke-width="3" stroke-linecap="round"></path></svg>
      <span style="flex: 1 1 auto; min-width: 0; font-size: 13px; color: {GREY}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">also check the calendar thread before you reply</span>
      <svg style="flex: 0 0 16px;" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{META}" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><circle cx="8" cy="12" r="0.9" fill="{META}"></circle><circle cx="12" cy="12" r="0.9" fill="{META}"></circle><circle cx="16" cy="12" r="0.9" fill="{META}"></circle></svg>
    </button>
  </sc-if>
  <sc-if value="{{{{isFailed}}}}" hint-placeholder-val="{{{{false}}}}">
    <button onClick="{{{{toggleMenu}}}}" aria-haspopup="menu" aria-expanded="{{{{menuAttr}}}}" aria-label="Message not sent, options" style="position: absolute; left: 12px; right: 12px; bottom: 186px; height: 32px; border: 0; border-radius: 16px; background: {{{{rowBg}}}}; backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); padding: 0 10px 0 12px; font: inherit; display: flex; align-items: center; gap: 8px; text-align: left; cursor: pointer;">
      <svg style="flex: 0 0 13px;" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="{RED}" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 7.5v5"></path><path d="M12 16h.01"></path></svg>
      <span style="flex: 1 1 auto; min-width: 0; font-size: 13px; color: {RED}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">Not sent · also check the calendar thread before you reply</span>
      <svg style="flex: 0 0 16px;" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{META}" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><circle cx="8" cy="12" r="0.9" fill="{META}"></circle><circle cx="12" cy="12" r="0.9" fill="{META}"></circle><circle cx="16" cy="12" r="0.9" fill="{META}"></circle></svg>
    </button>
  </sc-if>"""
    menu = f"""
  <sc-if value="{{{{menuOpen}}}}" hint-placeholder-val="{{{{true}}}}">
    <button aria-label="Close menu" onClick="{{{{toggleMenu}}}}" style="position: absolute; left: 0; right: 0; top: 0; bottom: 228px; border: 0; padding: 0; background: transparent; cursor: default;"></button>
    <div role="menu" style="position: absolute; right: 12px; bottom: 226px; width: 256px; border-radius: 16px; background: rgba(44,44,46,0.97); box-shadow: 0 12px 40px rgba(0,0,0,0.6); overflow: hidden;">
      <button role="menuitem" type="button" style="width: 100%; border: 0; border-bottom: 0.5px solid #48484A; background: transparent; font: inherit; color: {INK}; display: flex; align-items: center; gap: 10px; padding: 10px 16px; text-align: left; cursor: pointer;">
        <span style="flex: 1 1 auto; display: flex; flex-direction: column;"><span style="font-size: 17px;">{{{{firstLabel}}}}</span><span style="font-size: 13px; color: {GREY};">{{{{firstSub}}}}</span></span>
        {svg('send', 18, 'currentColor', 2)}
      </button>
      <button role="menuitem" type="button" style="width: 100%; border: 0; border-bottom: 0.5px solid #48484A; background: transparent; font: inherit; font-size: 17px; color: {INK}; display: flex; align-items: center; gap: 10px; padding: 11px 16px; text-align: left; cursor: pointer;">
        <span style="flex: 1 1 auto;">Edit</span>{svg('edit', 17, 'currentColor', 2)}
      </button>
      <button role="menuitem" type="button" style="width: 100%; border: 0; background: transparent; font: inherit; font-size: 17px; color: {RED}; display: flex; align-items: center; gap: 10px; padding: 11px 16px; text-align: left; cursor: pointer;">
        <span style="flex: 1 1 auto;">Remove</span>
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13"></path></svg>
      </button>
    </div>
  </sc-if>"""
    body = f"""
{transcript(items, bottom=228)}
{top_bar('Inbox triage', status_dyn())}
{bottom_fade()}
{strip}
{stage_collapsed()}
{composer()}
{menu}"""
    logic = f"""
  constructor(props) {{ super(props); this.state = {{ menu: true, draft: '' }}; }}
  renderVals() {{
    const kind = this.props.state || 'queued';
    const s = this.state, hasText = s.draft.trim().length > 0;
    const live = {{ dotColor: '{LIVE}', dotHalo: '0 0 0 3px rgba(48,209,88,0.25)', statusColor: '{LIVE}',
      statusLabel: 'Working \\u00b7 3m 40s', statusTail: ' \\u00b7 1 queued \\u00b7 Pro' }};
    const dead = {{ dotColor: '{RED}', dotHalo: 'none', statusColor: '{RED}',
      statusLabel: 'Pro offline \\u00b7 2m', statusTail: ' \\u00b7 1 not sent' }};
    return Object.assign({{}}, kind === 'queued' ? live : dead, {{
      isQueued: kind === 'queued', isFailed: kind === 'failed',
      rowBg: s.menu ? 'rgba(118,118,128,0.40)' : 'rgba(118,118,128,0.22)',
      menuOpen: s.menu, menuAttr: s.menu ? 'true' : 'false',
      toggleMenu: () => this.setState({{ menu: !s.menu }}),
      firstLabel: kind === 'queued' ? 'Send now' : 'Try again',
      firstSub: kind === 'queued' ? 'Stops the current step first' : 'Pro has to be reachable',
      draft: s.draft, onType: (e) => this.setState({{ draft: e.target.value }}),
      showStop: !hasText, showSend: hasText, send: () => this.setState({{ draft: '' }})
    }});
  }}"""
    props = dict(PV, state={"editor": "enum", "options": ["queued", "failed"], "default": "queued"})
    return head("Cua · Queued and not-sent") + phone(body) + script(props, logic)


# ------------------------------------------------------- 9/10. ask panels --

def panel(eyebrow_color, eyebrow, title, body_text, card_html, buttons_html, footnote):
    return f"""
  <div style="position: absolute; left: 8px; right: 8px; bottom: 8px; border-radius: 32px; background: {RAISED}; border: 0.5px solid {EDGE}; box-shadow: 0 -2px 30px rgba(0,0,0,0.6); padding: 16px 16px 26px; display: flex; flex-direction: column; gap: 14px;">
    <div style="display: flex; align-items: center; gap: 8px;">
      {dot(eyebrow_color, halo=True)}
      <span style="flex: 1 1 auto; font-size: 12px; font-weight: 700; letter-spacing: 0.4px; text-transform: uppercase; color: {AMBER_INK};">{eyebrow}</span>
    </div>
    <div style="display: flex; flex-direction: column; gap: 4px;">
      <span style="font-size: 20px; line-height: 25px; font-weight: 600;">{title}</span>
      <span style="font-size: 15px; line-height: 20px; color: {SECOND};">{body_text}</span>
    </div>
    {card_html}
    {buttons_html}
    <span style="font-size: 13px; line-height: 18px; color: {META}; text-align: center;">{footnote}</span>
  </div>"""


def board_confirm():
    send_card = f"""
    <div style="border-radius: 14px; background: {CARD}; padding: 13px 14px; display: flex; flex-direction: column; gap: 7px;">
      <span style="display: flex; gap: 8px; font-size: 14px;"><span style="color: {META}; flex: 0 0 52px;">To</span><span style="color: {SOFT};">design review thread · 3 people</span></span>
      <span style="display: flex; gap: 8px; font-size: 14px;"><span style="color: {META}; flex: 0 0 52px;">Subject</span><span style="color: {SOFT};">Re: Design review — round 3</span></span>
      <span style="height: 0.5px; background: {EDGE};"></span>
      <span style="font-size: 14px; line-height: 20px; color: {SECOND};">Thanks both — I’ll tighten the row spacing to 8pt and re-post the board tonight. The header stays as it is for now.</span>
    </div>"""
    send_btns = f"""
    <div style="display: flex; flex-direction: column; gap: 8px;">
      <button type="button" style="height: 50px; border: 0; border-radius: 25px; background: {ACCENT}; color: {INK}; font-size: 17px; font-weight: 600; cursor: pointer;">Send it</button>
      <button type="button" style="height: 48px; border: 0; border-radius: 24px; background: {CARD}; color: {SOFT}; font-size: 17px; font-weight: 500; cursor: pointer;">Keep it as a draft</button>
    </div>"""
    folder_card = f"""
    <div style="border-radius: 14px; background: {CARD}; padding: 12px 14px; display: flex; align-items: center; gap: 12px;">
      <span style="width: 32px; height: 32px; flex: 0 0 32px; border-radius: 8px; background: {CONTROL}; display: flex; align-items: center; justify-content: center;">{svg('folder', 17, SOFT)}</span>
      <span style="flex: 1 1 auto; display: flex; flex-direction: column; gap: 1px;">
        <span style="font-size: 16px; font-weight: 500;">lfg</span>
        <span style="font-size: 13px; color: {GREY};">On Pro · read-only · just this Space</span>
      </span>
    </div>"""
    folder_btns = f"""
    <div style="display: flex; flex-direction: column; gap: 8px;">
      <button type="button" style="height: 50px; border: 0; border-radius: 25px; background: {ACCENT}; color: {INK}; font-size: 17px; font-weight: 600; cursor: pointer;">Share this folder</button>
      <button type="button" style="height: 48px; border: 0; border-radius: 24px; background: {CARD}; color: {SOFT}; font-size: 17px; font-weight: 500; cursor: pointer;">Not now</button>
    </div>"""
    send_panel = panel(AMBER, "Needs your OK", "Send this reply?",
                       "The draft is written and saved in Gmail. It goes out only when you say so.",
                       send_card, send_btns,
                       "Nothing has been sent. Tap Send it and the agent sends this message.")
    folder_panel = panel(AMBER, "Needs your OK", "Let this Space read a folder?",
                         "Codex wants the spacing numbers from your own files to quote them in the reply.",
                         folder_card, folder_btns,
                         "You can take this back any time in the Space sheet.")
    items_send = [
        bubble("go through this morning’s inbox and draft a reply to the design review thread"),
        tool_row("mail", "Opened Gmail, read 12 messages"),
        prose("The draft is ready. It is saved in Gmail and has not been sent."),
    ]
    body = f"""
  <sc-if value="{{{{isSend}}}}" hint-placeholder-val="{{{{true}}}}">
    {transcript(items_send, bottom=460, pad='0 16px 12px')}
  </sc-if>
  <sc-if value="{{{{isFolder}}}}" hint-placeholder-val="{{{{false}}}}">
    {transcript([bubble('use the real spacing values from the lfg repo'), prose('I need to read that folder from Pro first.')], bottom=416, pad='0 16px 12px')}
  </sc-if>
{top_bar('Inbox triage', status_line(AMBER, 'Needs your OK · 40s', ' · Pro'))}
  <sc-if value="{{{{isSend}}}}" hint-placeholder-val="{{{{true}}}}">{send_panel}</sc-if>
  <sc-if value="{{{{isFolder}}}}" hint-placeholder-val="{{{{false}}}}">{folder_panel}</sc-if>"""
    logic = """
  renderVals() {
    const k = this.props.kind || 'send';
    return { isSend: k === 'send', isFolder: k === 'folder' };
  }"""
    props = dict(PV, kind={"editor": "enum", "options": ["send", "folder"], "default": "send"})
    return head("Cua · Asks before sending / before reading a folder") + phone(body) + script(props, logic)


def board_signin():
    card = f"""
    <div style="border-radius: 14px; background: {CARD}; padding: 12px 14px; display: flex; align-items: center; gap: 12px;">
      <span style="width: 32px; height: 32px; flex: 0 0 32px; border-radius: 8px; background: {CONTROL}; font-size: 15px; font-weight: 700; color: {SOFT}; display: flex; align-items: center; justify-content: center;">G</span>
      <span style="flex: 1 1 auto; display: flex; flex-direction: column; gap: 1px;">
        <span style="font-size: 16px; font-weight: 500;">accounts.google.com</span>
        <span style="font-size: 13px; color: {GREY};">To Chrome in the Inbox triage Space</span>
      </span>
    </div>"""
    btns = f"""
    <a href="s2-signin.dc.html" style="height: 50px; border-radius: 25px; background: {ACCENT}; color: {INK}; font-size: 17px; font-weight: 600; display: flex; align-items: center; justify-content: center; gap: 8px;">
      {svg('key', 17, 'currentColor', 2.2)}Sign in on iPhone</a>"""
    items = [
        bubble("go through this morning’s inbox and draft a reply to the design review thread"),
        tool_row("browser", "Opened Gmail in Chrome"),
        prose("Google wants a login before it shows the inbox. I’ll wait here until you sign in."),
    ]
    body = f"""
{transcript(items, bottom=394, pad='0 16px 12px')}
{top_bar('Inbox triage', status_line(AMBER, 'Needs sign-in · 1m', ' · Pro'))}
{panel(AMBER, 'Sign-in needed', 'Sign in to Google',
       'You log in on this iPhone. The sign-in then goes to Chrome inside this Space, where the agent is waiting.',
       card, btns,
       'There is no Dismiss here. The agent stays paused on this step until the sign-in arrives.')}"""
    return head("Cua · Sign-in needed") + phone(body) + script(PV, "  renderVals() { return {}; }")


# --------------------------------------------------------------- 11. watch --

def board_watch():
    items = [
        prose("Three need an answer. I’ve written one for the design review thread and left it as a "
              "draft in Gmail — nothing has been sent."),
        tool_row("edit", "Saved a draft in Gmail"),
    ]
    body = f"""
{transcript(items, bottom=379)}
{top_bar('Inbox triage', status_line(LIVE, 'Working · 3m 02s', ' · Pro'))}
{bottom_fade(h=250, start=16)}
{stage_expanded()}
{composer()}"""
    logic = """
  renderVals() {
    const d = (this.state && this.state.draft) || '';
    const has = d.trim().length > 0;
    return { draft: d, onType: (e) => this.setState({ draft: e.target.value }),
      showStop: !has, showSend: has, send: () => this.setState({ draft: '' }) };
  }"""
    return head("Cua · Watching the desktop") + phone(body) + script(PV, logic)


# ------------------------------------------------------------- 12. handoff --

def board_handoff():
    overlay = f"""
    <div style="position: absolute; inset: 0; background: {{{{scrim}}}}; display: flex; align-items: center; justify-content: center; padding: 0 20px;">
      <div style="display: flex; flex-direction: column; align-items: center; gap: 9px; text-align: center;">
        <sc-if value="{{{{isSpin}}}}" hint-placeholder-val="{{{{true}}}}">
          <svg width="34" height="34" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <circle cx="12" cy="12" r="9" stroke="rgba(255,255,255,0.22)" stroke-width="2.6"></circle>
            <path d="M12 3a9 9 0 0 1 9 9" stroke="{ACCENT_INK}" stroke-width="2.6" stroke-linecap="round"></path></svg>
        </sc-if>
        <sc-if value="{{{{isHand}}}}" hint-placeholder-val="{{{{false}}}}">
          <span style="width: 38px; height: 38px; border-radius: 19px; background: {CONTROL_RING}; display: flex; align-items: center; justify-content: center;">
            {svg('hand', 20, '#FFFFFF', 2.2)}</span>
        </sc-if>
        <sc-if value="{{{{isWarn}}}}" hint-placeholder-val="{{{{false}}}}">
          {svg('warn', 34, RED, 2)}
        </sc-if>
        <span style="font-size: 17px; font-weight: 600; color: {INK};">{{{{title}}}}</span>
        <span style="font-size: 13px; line-height: 18px; color: {SECOND};">{{{{body}}}}</span>
        <span style="display: flex; gap: 8px; margin-top: 4px;">
          <sc-if value="{{{{hasPrimary}}}}" hint-placeholder-val="{{{{false}}}}">
            <a href="{{{{primaryHref}}}}" style="height: 34px; padding: 0 15px; border-radius: 17px; background: {ACCENT}; color: {INK}; font-size: 14px; font-weight: 600; display: flex; align-items: center;">{{{{primary}}}}</a>
          </sc-if>
          <sc-if value="{{{{hasSecondary}}}}" hint-placeholder-val="{{{{true}}}}">
            <a href="cua-watch.dc.html" style="height: 34px; padding: 0 15px; border-radius: 17px; background: rgba(255,255,255,0.14); color: {SOFT}; font-size: 14px; font-weight: 600; display: flex; align-items: center;">{{{{secondary}}}}</a>
          </sc-if>
        </span>
      </div>
    </div>"""
    stage = f"""
  <div style="position: absolute; left: 12px; right: 12px; bottom: 134px; height: 229px; border-radius: 20px; overflow: hidden; border: 0.5px solid {EDGE}; background: {RAISED};">
    {desk(366, 229, 'compose')}
    <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 46px; background: rgba(0,0,0,0.58); backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px); display: flex; align-items: center; gap: 8px; padding: 0 12px;">
      <span style="width: 7px; height: 7px; flex: 0 0 7px; border-radius: 50%; background: {{{{footDotColor}}}};"></span>
      <span style="flex: 1 1 auto; min-width: 0; font-size: 13px; color: {SOFT};">{{{{footText}}}}</span>
    </div>
    {overlay}
  </div>"""
    items = [prose("I’ve written one for the design review thread and left it as a draft in Gmail.")]
    body = f"""
{transcript(items, bottom=379)}
{top_bar('Inbox triage', status_dyn())}
{bottom_fade(h=250, start=16)}
{stage}
{composer()}"""
    logic = f"""
  renderVals() {{
    const st = this.props.state || 'pausing';
    const d = (this.state && this.state.draft) || '', has = d.trim().length > 0;
    const spinner = 'spin', ok = 'hand', warn = 'warn';
    const line = (c, label, tail) => ({{ dotColor: c, dotHalo: 'none', statusColor: c, statusLabel: label, statusTail: tail }});
    const M = {{
      pausing: {{
        mark: spinner, title: 'Pausing the agent',
        body: 'Finishing the step it is on, so it does not fight you for the mouse.',
        primary: '', primaryHref: '#', secondary: 'Cancel', scrim: 'rgba(0,0,0,0.62)',
        footDotColor: '{AMBER}', footText: 'Agent pausing \\u00b7 the Space keeps running',
        status: line('{AMBER}', 'Pausing \\u00b7 2s', ' \\u00b7 Pro')
      }},
      ready: {{
        mark: ok, title: 'You have control',
        body: 'The agent is paused. The Space and its apps keep running.',
        primary: 'Open full screen', primaryHref: 'cua-control.dc.html', secondary: 'Not now',
        scrim: 'rgba(0,0,0,0.55)',
        footDotColor: '{AMBER}', footText: 'Agent paused \\u00b7 you have control',
        status: line('{CONTROL_RING}', 'You have control', ' \\u00b7 agent paused \\u00b7 Pro')
      }},
      disconnected: {{
        mark: warn, title: 'Lost the desktop picture',
        body: 'The Space is still running on Pro and the agent is still paused. Only the live view dropped.',
        primary: 'Try again', primaryHref: 'cua-handoff.dc.html', secondary: 'Back to chat',
        scrim: 'rgba(0,0,0,0.74)',
        footDotColor: '{RED}', footText: 'No picture \\u00b7 last frame 8s ago',
        status: line('{RED}', 'Desktop unreachable \\u00b7 8s', ' \\u00b7 Pro')
      }},
      reconnecting: {{
        mark: spinner, title: 'Reconnecting\\u2026',
        body: 'Attempt 2 of 5. Nothing you did was lost.',
        primary: '', primaryHref: '#', secondary: 'Back to chat', scrim: 'rgba(0,0,0,0.70)',
        footDotColor: '{AMBER}', footText: 'Reconnecting \\u00b7 agent still paused',
        status: line('{AMBER}', 'Reconnecting \\u00b7 11s', ' \\u00b7 Pro')
      }},
      resumed: {{
        mark: ok, title: 'The agent took over again',
        body: 'Your message went through, so control went back to Codex. Take control again any time.',
        primary: 'Take control', primaryHref: 'cua-handoff.dc.html', secondary: 'Watch',
        scrim: 'rgba(0,0,0,0.55)',
        footDotColor: '{LIVE}', footText: 'Working \\u00b7 reading your message',
        status: line('{LIVE}', 'Working \\u00b7 1s', ' \\u00b7 Pro')
      }}
    }};
    const m = M[st];
    return Object.assign({{}}, m, m.status, {{
      isSpin: m.mark === 'spin', isHand: m.mark === 'hand', isWarn: m.mark === 'warn',
      hasPrimary: !!m.primary, hasSecondary: !!m.secondary,
      draft: d, onType: (e) => this.setState({{ draft: e.target.value }}),
      showStop: !has, showSend: has, send: () => this.setState({{ draft: '' }})
    }});
  }}"""
    props = dict(PV, state={"editor": "enum",
                            "options": ["pausing", "ready", "disconnected", "reconnecting", "resumed"],
                            "default": "pausing"})
    return head("Cua · Handing control over") + phone(body) + script(props, logic)


# ------------------------------------------------------------- 13. stopped --

def board_stopped():
    card = f"""
  <div style="position: absolute; left: 12px; right: 12px; bottom: 134px; height: 229px; border-radius: 20px; background: {{{{cardBg}}}}; border: 0.5px solid {{{{cardEdge}}}}; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; padding: 0 26px; text-align: center;">
    <sc-if value="{{{{isPower}}}}" hint-placeholder-val="{{{{true}}}}">
      <span style="width: 40px; height: 40px; border-radius: 20px; background: rgba(255,255,255,0.08); display: flex; align-items: center; justify-content: center;">{svg('power', 20, GREY, 2)}</span>
    </sc-if>
    <sc-if value="{{{{isWarn}}}}" hint-placeholder-val="{{{{false}}}}">
      <span style="width: 40px; height: 40px; border-radius: 20px; background: rgba(255,69,58,0.16); display: flex; align-items: center; justify-content: center;">{svg('warn', 20, RED, 2)}</span>
    </sc-if>
    <span style="font-size: 17px; font-weight: 600;">{{{{title}}}}</span>
    <span style="font-size: 13px; line-height: 18px; color: {SECOND};">{{{{body}}}}</span>
    <span style="display: flex; gap: 8px; margin-top: 4px;">
      <button type="button" style="height: 34px; padding: 0 15px; border: 0; border-radius: 17px; background: {ACCENT}; color: {INK}; font-size: 14px; font-weight: 600; cursor: pointer;">{{{{primary}}}}</button>
      <button type="button" style="height: 34px; padding: 0 15px; border: 0; border-radius: 17px; background: rgba(255,255,255,0.12); color: {SOFT}; font-size: 14px; font-weight: 600; cursor: pointer;">{{{{secondary}}}}</button>
    </span>
  </div>"""
    items = [
        bubble("find the three cheapest vendors for the booth panels"),
        prose("I compared six suppliers and put the shortlist in the shared folder."),
    ]
    body = f"""
{transcript(items, bottom=379)}
{top_bar('Vendor research', status_dyn())}
{bottom_fade(h=250, start=16)}
{card}
{composer(placeholder='{{placeholder}}', stop_default=False)}"""
    logic = f"""
  renderVals() {{
    const st = this.props.state || 'stopped';
    const d = (this.state && this.state.draft) || '', has = d.trim().length > 0;
    const line = (c, label, tail) => ({{ dotColor: c, dotHalo: 'none', statusColor: c, statusLabel: label, statusTail: tail }});
    const M = {{
      stopped: {{
        mark: 'power', title: 'This Space is stopped',
        body: 'The desktop and its open apps are closed. Your chat and shared folders are kept.',
        primary: 'Start the Space', secondary: 'Delete',
        cardBg: '{RAISED}', cardEdge: '{EDGE}',
        placeholder: 'Send a message to start it again\\u2026',
        status: line('{STOPPED}', 'Stopped \\u00b7 1d', ' \\u00b7 Pro')
      }},
      failed: {{
        mark: 'warn', title: 'The desktop stopped on its own',
        body: 'Pro ran out of memory and closed the Space. The chat, the drafts in Gmail and your shared folders are all still there.',
        primary: 'Start it again', secondary: 'What happened',
        cardBg: 'rgba(255,69,58,0.08)', cardEdge: 'rgba(255,69,58,0.28)',
        placeholder: 'Send a message to start it again\\u2026',
        status: line('{RED}', 'Stopped unexpectedly \\u00b7 6m', ' \\u00b7 Pro')
      }}
    }};
    const m = M[st];
    return Object.assign({{}}, m, m.status, {{
      isPower: m.mark === 'power', isWarn: m.mark === 'warn',
      draft: d, onType: (e) => this.setState({{ draft: e.target.value }}),
      showStop: false, showSend: true, send: () => this.setState({{ draft: '' }})
    }});
  }}"""
    props = dict(PV, state={"editor": "enum", "options": ["stopped", "failed"], "default": "stopped"})
    return head("Cua · Stopped Space and recovery") + phone(body) + script(props, logic)


BOARDS = {
    "cua-chat.dc.html": (board_chat, 0, 1264, 390, 844, "Phone · chat with the agent, desktop resting"),
    "cua-tools.dc.html": (board_tools, 470, 1264, 390, 844, "Phone · tool step expanded, account and folder rows"),
    "cua-queued.dc.html": (board_queued, 940, 1264, 390, 844, "Phone · queued and not-sent, soft strip"),
    "cua-confirm.dc.html": (board_confirm, 1410, 1264, 390, 844, "Phone · asks before sending, asks before reading a folder"),
    "cua-signin.dc.html": (board_signin, 1880, 1264, 390, 844, "Phone · sign-in needed inside the Space"),
    "cua-watch.dc.html": (board_watch, 0, 2528, 390, 844, "Phone · watching, with Take control"),
    "cua-handoff.dc.html": (board_handoff, 470, 2528, 390, 844, "Phone · handoff: pausing, ready, lost, reconnecting, resumed"),
    "cua-stopped.dc.html": (board_stopped, 940, 2528, 390, 844, "Phone · stopped Space and recovery from failure"),
}
