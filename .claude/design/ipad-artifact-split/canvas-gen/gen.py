#!/usr/bin/env python3
"""Generate the iPad artifact-pane boards for the LFG UI Map canvas.

ia-proto.dc.html is the one interactive board (every state lives in it);
the other ia-*.dc.html boards dc-import it with a starting state.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'canvas', 'project')
os.makedirs(OUT, exist_ok=True)

FONT = "-apple-system, 'SF Pro Text', system-ui, sans-serif"
MONO = "ui-monospace, 'SF Mono', Menlo, monospace"

P = {
    'image': 'M3 4h18v16H3zM8.5 10.5a1.5 1.5 0 1 0 0-.01M21 16l-5-5-9 9',
    'video': 'M3 6h12v12H3zM15 10l6-3v10l-6-3',
    'doc': 'M6 2.5h8l4.5 4.5v14.5H6zM14 2.5V7h4.5M9 12h6M9 16h6',
    'web': 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9M12 3c-2.5 2.6-3.8 5.6-3.8 9s1.3 6.4 3.8 9',
    'close': 'M6 6l12 12M18 6L6 18',
    'back': 'M15 5l-7 7 7 7',
    'expand': 'M14 4h6v6M20 4l-6.5 6.5M10 20H4v-6M4 20l6.5-6.5',
    'collapse': 'M19.5 4.5L14 10M14 5v5h5M4.5 19.5L10 14M5 14h5v5',
    'chev': 'M9 5l7 7-7 7',
    'reload': 'M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4.5v4h-4',
    'link': 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
    'pip': 'M3 5h18v14H3zM12 12h7v5h-7z',
    'transcript': 'M4 5h16v11H9l-5 4z',
    'copy': 'M8 8h11v12H8zM5 16V4h11',
    'share': 'M12 3v12M7.5 7.5L12 3l4.5 4.5M5 12v8h14v-8',
    'safari': 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M15.5 8.5l-2 5-5 2 2-5z',
    'source': 'M8.5 7L3.5 12l5 5M15.5 7l5 5-5 5',
}

def icon(path, size=20, color='currentColor', sw=1.9):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
            f'<path d="{path}"></path></svg>')

DOTS = ('<svg width="20" height="20" viewBox="0 0 24 24" fill="#FFFFFF" aria-hidden="true">'
        '<circle cx="5" cy="12" r="1.9"></circle><circle cx="12" cy="12" r="1.9"></circle>'
        '<circle cx="19" cy="12" r="1.9"></circle></svg>')
LIST_ICON = ('<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.8" '
             'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4.5" width="18" '
             'height="15" rx="3"></rect><path d="M9.5 4.5v15"></path><path d="M5.5 8h1.8M5.5 11h1.8M5.5 14h1.8"></path></svg>')
TUNE_ICON = ('<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.9" '
             'stroke-linecap="round" aria-hidden="true"><path d="M4 7h9M17 7h3M4 17h3M11 17h9"></path>'
             '<circle cx="15" cy="7" r="2.2"></circle><circle cx="9" cy="17" r="2.2"></circle></svg>')
GLASS = ('border-radius: 22px; background: rgba(44,44,46,0.92); box-shadow: 0 2px 12px rgba(0,0,0,0.5); '
         'border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center; '
         'padding: 0; cursor: pointer; color: #FFFFFF;')
CIRCLE = ('width: 44px; height: 44px; flex: 0 0 44px; border: 0; border-radius: 22px; background: #2C2C2E; '
          'display: flex; align-items: center; justify-content: center; padding: 0; cursor: pointer; color: #FFFFFF;')
PLAIN_BTN = 'border: 0; background: transparent; padding: 0; font: inherit; color: inherit; cursor: pointer;'

sidebar = open(os.path.join(HERE, 'sidebar.html')).read()
sidebar = sidebar.replace('border-radius: 26px; background: #1C1C1E; overflow: hidden;',
                          'border-radius: 26px; background: #1C1C1E; overflow: hidden; box-shadow: {{sideShadow}};', 1)
sidebar = sidebar.replace('height: 782px;', 'height: {{sideH}};', 1)
assert '{{sideShadow}}' in sidebar and '{{sideH}}' in sidebar


def tool_row(path, label):
    return (f'<div style="display: flex; align-items: center; gap: 8px; padding: 2px 0; color: #A1A1A6;">'
            f'{icon(path, 17, "currentColor", 1.9)}'
            f'<span style="flex: 1 1 auto; font-size: 15px;">{label}</span>'
            f'{icon(P["chev"], 12, "#636366", 2.8)}</div>')


def card_list(listname):
    # Same anatomy as the shipped MediaAttachmentsView card: icon, filename, chevron,
    # padding 10, radius 10, tertiarySystemBackground. Open = selected fill + blue ring.
    return f'''<div style="display: flex; flex-direction: column; gap: 8px;">
      <sc-for list="{{{{{listname}}}}}" as="c" hint-placeholder-count="2">
        <button onClick="{{{{c.open}}}}" aria-label="{{{{c.label}}}}" style="{PLAIN_BTN} width: 100%; box-sizing: border-box; display: flex; align-items: center; gap: 10px; padding: 10px; border-radius: 10px; background: {{{{c.bg}}}}; box-shadow: {{{{c.ring}}}}; text-align: left;">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#A1A1A6" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{c.icon}}}}"></path></svg>
          <span style="flex: 1 1 auto; min-width: 0; font-size: 15px; line-height: 20px; color: #F2F2F7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{{{c.name}}}}</span>
          <sc-if value="{{{{c.isOpen}}}}" hint-placeholder-val="{{{{false}}}}"><span style="font-size: 13px; font-weight: 600; color: #409CFF;">Open</span></sc-if>
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="{{{{c.chev}}}}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 5l7 7-7 7"></path></svg>
        </button>
      </sc-for>
    </div>'''


TRANSCRIPT = f'''<div style="position: absolute; top: {{{{trTop}}}}; left: {{{{colL}}}}; width: {{{{colW}}}}; bottom: 178px; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; gap: 14px; padding: 0 16px 6px; box-sizing: border-box;">
    <div style="align-self: flex-end; max-width: {{{{bubbleMax}}}}; background: #355C8F; color: #F2F2F7; border-radius: 20px; padding: 9px 14px; font-size: 17px; line-height: 22px;">when i tap fork on desktop or phone, it should open the fork right away. right now it waits for the transcript, and on the ipad that reads like the tap did nothing</div>
    <div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">Small forks wait for a transcript that is only written on the first turn, so the client polls until the file exists. I’ll open the fork as soon as the host returns its id.</div>
    {tool_row('M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4', 'Edited 2 files')}
    {tool_row('M4 5h16v14H4zM8 10l3 2-3 2M13 15h3', 'Ran bun test src/sessions.test.ts')}
    <div style="display: flex; flex-direction: column; gap: 10px;">
      <div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">Both clients now open the fork right away. Here is the simulator before and after, and a recording of the tap:</div>
      {card_list('mediaCards')}
    </div>
    <div style="display: flex; flex-direction: column; gap: 10px;">
      <div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">I wrote up the timing and drew the flow as a page. The PR is up: <button onClick="{{{{openLink}}}}" style="{PLAIN_BTN} color: #409CFF; text-decoration: {{{{linkDeco}}}}; font-size: 17px; line-height: 24px;">PR #412 · Fork opens right away</button></div>
      {card_list('docCards')}
    </div>
    <sc-if value="{{{{fresh}}}}" hint-placeholder-val="{{{{false}}}}">
    <div style="display: flex; flex-direction: column; gap: 10px;">
      <div style="font-size: 17px; line-height: 24px; color: #F2F2F7;">Added a timeline of the tap, frame by frame:</div>
      {card_list('newCards')}
    </div>
    </sc-if>
  </div>'''


def pill(inner, extra_style='', onclick=None, label=None):
    tag_open = f'<button onClick="{{{{{onclick}}}}}"' if onclick else '<a href="s2-subagents.dc.html"'
    tag_close = '</button>' if onclick else '</a>'
    al = f' aria-label="{label}"' if label else ''
    return (f'{tag_open}{al} style="{PLAIN_BTN} flex: 0 0 auto; height: 36px; padding: 0 12px; border-radius: 18px; '
            f'background: #1C1C1E; border: 0.5px solid #38383A; display: flex; align-items: center; gap: 6px; '
            f'font-size: 14px; font-weight: 500; color: #F2F2F7; box-sizing: border-box; {extra_style}">{inner}{tag_close}')


SUBAGENT_RING = ('<svg width="22" height="22" viewBox="0 0 22 22" aria-hidden="true"><circle cx="11" cy="11" r="8" fill="none" stroke="#3A3A3C" stroke-width="3"></circle>'
                 '<circle cx="11" cy="11" r="8" fill="none" stroke="#30D158" stroke-width="3" stroke-linecap="round" stroke-dasharray="25.1 50.3" transform="rotate(-90 11 11)"></circle>'
                 '<circle cx="11" cy="11" r="8" fill="none" stroke="#FF453A" stroke-width="3" stroke-linecap="round" stroke-dasharray="9 50.3" stroke-dashoffset="-28.6" transform="rotate(-90 11 11)"></circle></svg>')

BOTTOM = f'''<div style="position: absolute; left: {{{{regL}}}}; width: {{{{regW}}}}; bottom: 0; height: 182px; background: linear-gradient(rgba(0,0,0,0), #000000 22%);"></div>
  <div style="position: absolute; left: {{{{pillsL}}}}; bottom: 120px; display: flex; gap: 8px; padding: 0 4px;">
    {pill(SUBAGENT_RING + '<span>Subagents</span><span style="color: #30D158;">1 running</span>', 'padding: 0 12px 0 8px; gap: 8px;', None, 'Subagents: 1 running')}
    <button onClick="{{{{openFiles}}}}" style="{PLAIN_BTN} flex: 0 0 auto; height: 36px; padding: 0 12px; border-radius: 18px; background: {{{{filesPillBg}}}}; border: 0.5px solid {{{{filesPillBorder}}}}; display: flex; align-items: center; gap: 6px; font-size: 14px; font-weight: 500; color: #F2F2F7; box-sizing: border-box;">{icon(P['doc'], 15, 'currentColor', 1.9)}Files <span style="color: {{{{filesCountInk}}}};">{{{{filesCount}}}}</span><sc-if value="{{{{freshDot}}}}" hint-placeholder-val="{{{{false}}}}"><span aria-label="1 new file" style="width: 8px; height: 8px; border-radius: 4px; background: #0A84FF;"></span></sc-if></button>
    <a href="s2-terminal.dc.html" style="flex: 0 0 auto; height: 36px; padding: 0 12px; border-radius: 18px; background: #1C1C1E; border: 0.5px solid #38383A; display: flex; align-items: center; gap: 6px; font-size: 14px; font-weight: 500; color: #F2F2F7; box-sizing: border-box;">{icon('M4 5h16v14H4zM8 10l3 2-3 2M13 15h3', 15, 'currentColor', 1.9)}Terminal</a>
  </div>
  <div style="position: absolute; left: {{{{compL}}}}; width: {{{{compW}}}}; bottom: 14px; height: 96px; border-radius: 24px; background: #1C1C1E; border: 0.5px solid #38383A; box-sizing: border-box; padding: 11px 10px 10px 16px; display: flex; flex-direction: column; justify-content: space-between;">
    <textarea aria-label="Message" rows="1" placeholder="Add to this turn…" style="border: 0; outline: none; resize: none; padding: 0; background: transparent; font: inherit; font-size: 17px; line-height: 22px; color: #FFFFFF;"></textarea>
    <span style="display: flex; align-items: center; gap: 8px;">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#A1A1A6" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"><path d="M20.5 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1l8.6-8.6a3.4 3.4 0 0 1 4.8 4.8l-8.6 8.6a1.7 1.7 0 0 1-2.4-2.4l7.9-7.9"></path></svg>
      <span style="height: 28px; padding: 0 10px; border-radius: 14px; background: #2C2C2E; display: flex; align-items: center; gap: 5px; font-size: 13px; font-weight: 500; color: #D1D1D6;">Opus 5.5 · High
        <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"></path></svg></span>
      <span style="flex: 1 1 auto;"></span>
      <button aria-label="Stop the current turn" style="width: 34px; height: 34px; border: 0; border-radius: 17px; background: #F2F2F7; display: flex; align-items: center; justify-content: center; padding: 0;"><span style="width: 11px; height: 11px; border-radius: 3px; background: #000000;"></span></button>
    </span>
  </div>'''

TOPBAR = f'''<div style="position: absolute; top: {{{{gradTop}}}}; left: {{{{regL}}}}; width: {{{{regW}}}}; height: {{{{gradH}}}}; background: linear-gradient(#000000 72%, rgba(0,0,0,0));"></div>
  <button onClick="{{{{toggleList}}}}" aria-label="{{{{listLabel}}}}" style="position: absolute; left: {{{{listL}}}}; top: {{{{barT}}}}; width: 44px; height: 44px; {GLASS}">{LIST_ICON}
    <sc-if value="{{{{showBadge}}}}" hint-placeholder-val="{{{{false}}}}"><span style="position: absolute; top: -4px; right: -4px; min-width: 18px; height: 18px; border-radius: 9px; background: #FF9F0A; color: #1C1C1E; font-size: 11px; font-weight: 700; display: flex; align-items: center; justify-content: center;">2</span></sc-if>
  </button>
  <a href="s2-menu.dc.html" style="position: absolute; left: {{{{titleL}}}}; width: {{{{titleW}}}}; top: {{{{titleT}}}}; height: 40px; display: flex; flex-direction: column; align-items: center; gap: 3px;">
    <span style="font-size: 17px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%;">Fork session feature</span>
    <span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: #A1A1A6; white-space: nowrap;"><span style="width: 7px; height: 7px; flex: 0 0 7px; border-radius: 50%; background: #30D158; box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span><span style="color: #30D158; font-weight: 600;">Working · 3m 12s</span><span>· Pro · lfg</span></span>
  </a>
  <a href="s2-menu.dc.html" aria-label="Session tools and options" style="position: absolute; left: {{{{menuL}}}}; top: {{{{barT}}}}; width: 44px; height: 44px; box-sizing: border-box; {GLASS}">{TUNE_ICON}</a>'''


def phone_shot(kind):
    """A schematic simulator screenshot (portrait), drawn at 0.62 of a 390x844 phone."""
    if kind == 'before':
        body = '''<span style="font-size: 10px; font-weight: 600; color: #F2F2F7; text-align: center;">Fork session feature</span>
          <span style="align-self: center; font-size: 8px; color: #30D158;">Working · 2m</span>
          <span style="height: 34px; border-radius: 10px; background: #355C8F; align-self: flex-end; width: 70%;"></span>
          <span style="height: 7px; border-radius: 3px; background: #3A3A3C; width: 92%;"></span>
          <span style="height: 7px; border-radius: 3px; background: #3A3A3C; width: 80%;"></span>
          <span style="height: 7px; border-radius: 3px; background: #3A3A3C; width: 86%;"></span>
          <span style="margin-top: 10px; align-self: center; width: 76%; border-radius: 10px; background: #2C2C2E; display: flex; flex-direction: column; overflow: hidden;">
            <span style="padding: 7px 10px; font-size: 9px; color: #F2F2F7; border-bottom: 0.5px solid #48484A;">Rename</span>
            <span style="padding: 7px 10px; font-size: 9px; color: #F2F2F7; background: #3A3A3C; border-bottom: 0.5px solid #48484A;">Fork</span>
            <span style="padding: 7px 10px; font-size: 9px; color: #FF453A;">End session</span>
          </span>
          <span style="align-self: center; margin-top: 6px; font-size: 8px; color: #8E8E93;">tapped Fork · nothing for 4.8 s</span>'''
    else:
        body = '''<span style="font-size: 10px; font-weight: 600; color: #F2F2F7; text-align: center;">Fork of Fork session feature</span>
          <span style="align-self: center; font-size: 8px; color: #30D158;">Working · 0s</span>
          <span style="height: 34px; border-radius: 10px; background: #355C8F; align-self: flex-end; width: 70%;"></span>
          <span style="height: 7px; border-radius: 3px; background: #3A3A3C; width: 92%;"></span>
          <span style="height: 7px; border-radius: 3px; background: #3A3A3C; width: 80%;"></span>
          <span style="display: flex; align-items: center; gap: 5px; font-size: 9px; color: #A1A1A6; margin-top: 4px;"><span style="width: 8px; height: 8px; border-radius: 4px; border: 1.5px solid #636366; border-top-color: #D1D1D6;"></span>Starting…</span>'''
    return f'''<div style="width: 100%; height: 100%; box-sizing: border-box; background: #000000; padding: 34px 12px 12px; display: flex; flex-direction: column; gap: 8px; position: relative;">
          {body}
          <span style="position: absolute; left: 10px; right: 10px; bottom: 12px; height: 40px; border-radius: 14px; background: #1C1C1E; border: 0.5px solid #38383A;"></span>
        </div>'''


# ---- pane bodies ----------------------------------------------------------

MEDIA_WELL = f'''<div style="position: absolute; left: 8px; right: 8px; top: 64px; bottom: 8px; border-radius: 18px; background: #000000; overflow: hidden;">
      <div style="position: absolute; left: 0; right: 0; top: 0; bottom: 84px; display: flex; align-items: center; justify-content: center;">
        <div style="width: {{{{shotW}}}}; height: {{{{shotH}}}}; border-radius: 6px; overflow: hidden; position: relative; box-shadow: 0 0 0 0.5px #38383A;">
          <sc-if value="{{{{isBefore}}}}" hint-placeholder-val="{{{{false}}}}">{phone_shot('before')}</sc-if>
          <sc-if value="{{{{isAfter}}}}" hint-placeholder-val="{{{{false}}}}">{phone_shot('after')}</sc-if>
          <sc-if value="{{{{isVideo}}}}" hint-placeholder-val="{{{{false}}}}">
            {phone_shot('after')}
            <div style="position: absolute; inset: 0; background: rgba(0,0,0,0.28);"></div>
            <button aria-label="Picture in picture" style="{PLAIN_BTN} position: absolute; top: 10px; left: 10px; width: 32px; height: 32px; border-radius: 16px; background: rgba(60,60,64,0.8); display: flex; align-items: center; justify-content: center; color: #FFFFFF;">{icon(P['pip'], 16, 'currentColor', 1.8)}</button>
            <button aria-label="Pause" style="{PLAIN_BTN} position: absolute; left: 50%; top: 50%; width: 60px; height: 60px; margin: -30px 0 0 -30px; border-radius: 30px; background: rgba(60,60,64,0.8); display: flex; align-items: center; justify-content: center;"><svg width="22" height="22" viewBox="0 0 24 24" fill="#FFFFFF" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1"></rect><rect x="14" y="5" width="4" height="14" rx="1"></rect></svg></button>
            <div style="position: absolute; left: 10px; right: 10px; bottom: 10px; height: 34px; border-radius: 17px; background: rgba(60,60,64,0.8); display: flex; align-items: center; gap: 8px; padding: 0 12px; font-size: 11px; font-weight: 600; color: #F2F2F7; font-variant-numeric: tabular-nums;">
              <span>0:04</span>
              <span style="flex: 1 1 auto; height: 4px; border-radius: 2px; background: rgba(255,255,255,0.3); position: relative;"><span style="position: absolute; left: 0; top: 0; bottom: 0; width: 33%; border-radius: 2px; background: #FFFFFF;"></span></span>
              <span>0:12</span>
            </div>
          </sc-if>
        </div>
      </div>
      <div style="position: absolute; left: 0; right: 0; bottom: 14px; display: flex; justify-content: center;">
        <div role="group" aria-label="Images and videos in this session" style="height: 60px; border-radius: 16px; background: #1C1C1E; display: flex; align-items: center; gap: 8px; padding: 0 8px;">
          <sc-for list="{{{{strip}}}}" as="t" hint-placeholder-count="3">
            <button onClick="{{{{t.open}}}}" aria-label="{{{{t.label}}}}" style="{PLAIN_BTN} width: 30px; height: 46px; border-radius: 6px; background: #2C2C2E; box-shadow: {{{{t.ring}}}}; display: flex; align-items: center; justify-content: center; color: #A1A1A6;">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{t.icon}}}}"></path></svg>
            </button>
          </sc-for>
        </div>
      </div>
    </div>'''

DOC_WELL = f'''<div style="position: absolute; left: 8px; right: 8px; top: 64px; bottom: 8px; border-radius: 18px; background: #000000; overflow: hidden;">
      <div style="padding: 28px {{{{docPad}}}} 28px; max-width: 680px; box-sizing: border-box; margin: 0 auto; display: flex; flex-direction: column; gap: 14px; color: #F2F2F7;">
        <span style="font-size: 28px; line-height: 34px; font-weight: 700;">Fork latency</span>
        <span style="font-size: 15px; line-height: 22px; color: #A1A1A6;">Pro host, iPhone 17 Pro simulator, 10 forks of each size.</span>
        <span style="font-size: 20px; line-height: 26px; font-weight: 700; margin-top: 6px;">Before</span>
        <span style="font-size: 17px; line-height: 26px;">The client waited for the fork’s transcript file before it opened the fork. Small forks write that file only on their first turn, so the tap looked dead for up to five seconds.</span>
        <span style="font-size: 20px; line-height: 26px; font-weight: 700; margin-top: 6px;">After</span>
        <span style="font-size: 17px; line-height: 26px;">The client opens the fork as soon as the host returns its id, and the transcript fills in behind it. The change is in <span style="font-family: {MONO}; font-size: 15px; background: #1C1C1E; border-radius: 5px; padding: 1px 5px;">SessionStore.swift</span>.</span>
        <div style="margin-top: 6px; border: 0.5px solid #38383A; border-radius: 10px; overflow: hidden; font-size: 15px; line-height: 20px;">
          <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); background: #1C1C1E; font-weight: 600;"><span style="padding: 9px 12px;">Fork</span><span style="padding: 9px 12px;">Before</span><span style="padding: 9px 12px;">After</span></div>
          <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); border-top: 0.5px solid #38383A;"><span style="padding: 9px 12px;">Small</span><span style="padding: 9px 12px;">4.8 s</span><span style="padding: 9px 12px;">0.3 s</span></div>
          <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); border-top: 0.5px solid #38383A;"><span style="padding: 9px 12px;">Large</span><span style="padding: 9px 12px;">0.6 s</span><span style="padding: 9px 12px;">0.3 s</span></div>
        </div>
      </div>
    </div>'''

HTML_WELL = '''<div style="position: absolute; left: 8px; right: 8px; top: 64px; bottom: 8px; border-radius: 18px; background: #0E1014; overflow: hidden;">
      <div style="padding: 36px {{webPad}} 28px; max-width: 760px; box-sizing: border-box; margin: 0 auto; display: flex; flex-direction: column; gap: 18px; color: #E8E6E1; font-family: Georgia, 'Times New Roman', serif;">
        <span style="font-size: 12px; letter-spacing: 1.5px; text-transform: uppercase; color: #8A93A6; font-family: -apple-system, system-ui, sans-serif;">Explainer</span>
        <span style="font-size: 30px; line-height: 36px;">Why some forks felt instant and others did not</span>
        <div style="display: flex; align-items: stretch; gap: 10px; flex-wrap: wrap; font-family: -apple-system, system-ui, sans-serif; font-size: 14px; line-height: 19px;">
          <span style="flex: 1 1 150px; border-radius: 12px; background: #1A1E26; padding: 12px;"><b style="display: block; color: #FFFFFF;">1 · Tap Fork</b><span style="color: #A8B0C0;">The phone asks the host for a fork.</span></span>
          <span style="flex: 1 1 150px; border-radius: 12px; background: #1A1E26; padding: 12px;"><b style="display: block; color: #FFFFFF;">2 · Host returns an id</b><span style="color: #A8B0C0;">In about 0.3 s, for every size.</span></span>
          <span style="flex: 1 1 150px; border-radius: 12px; background: #23324A; padding: 12px;"><b style="display: block; color: #FFFFFF;">3 · Open now</b><span style="color: #C9D6EC;">The transcript fills in behind it.</span></span>
        </div>
        <span style="font-size: 18px; line-height: 28px; color: #C9C6BF;">Before the fix, step 3 waited for a transcript file. A large fork writes that file when it boots. A small one writes it only on its first turn, so the phone sat on the old session.</span>
      </div>
    </div>'''

LINK_WELL = '''<div style="position: absolute; left: 8px; right: 8px; top: 64px; bottom: 8px; border-radius: 18px; background: #111113; overflow: hidden;">
      <div aria-label="Web page placeholder" style="padding: 28px 28px; display: flex; flex-direction: column; gap: 14px;">
        <span style="height: 22px; width: 62%; border-radius: 6px; background: #2C2C2E;"></span>
        <span style="height: 12px; width: 38%; border-radius: 4px; background: #232325;"></span>
        <span style="height: 1px; background: #232325; margin: 6px 0;"></span>
        <span style="height: 12px; width: 92%; border-radius: 4px; background: #232325;"></span>
        <span style="height: 12px; width: 86%; border-radius: 4px; background: #232325;"></span>
        <span style="height: 12px; width: 72%; border-radius: 4px; background: #232325;"></span>
        <span style="height: 140px; border-radius: 10px; background: #1A1A1C; margin-top: 8px;"></span>
        <span style="height: 12px; width: 88%; border-radius: 4px; background: #232325;"></span>
        <span style="height: 12px; width: 64%; border-radius: 4px; background: #232325;"></span>
        <span style="align-self: center; margin-top: 12px; font-size: 13px; color: #8E8E93;">Any web page, drawn as a placeholder</span>
      </div>
    </div>'''

FILES_BODY = f'''<div style="position: absolute; left: 16px; right: 16px; top: 72px; height: 34px; border-radius: 17px; background: #2C2C2E; padding: 2px; box-sizing: border-box; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));">
      <sc-for list="{{{{tabs}}}}" as="t" hint-placeholder-count="2">
        <button onClick="{{{{t.pick}}}}" style="border: 0; border-radius: 15px; background: {{{{t.bg}}}}; font: inherit; font-size: 14px; font-weight: 600; color: #FFFFFF; cursor: pointer;">{{{{t.label}}}}</button>
      </sc-for>
    </div>
    <div style="position: absolute; top: 118px; left: 0; right: 0; bottom: 0; overflow: hidden;">
      <sc-if value="{{{{isFilesTab}}}}" hint-placeholder-val="{{{{true}}}}">
        <sc-for list="{{{{sections}}}}" as="sec" hint-placeholder-count="3">
          <div style="padding: 10px 20px 4px; display: flex; align-items: center; gap: 6px; font-size: 13px; color: #A1A1A6;"><span style="font-weight: 600;">{{{{sec.label}}}}</span><span style="color: #8E8E93;">{{{{sec.count}}}}</span></div>
          <sc-for list="{{{{sec.files}}}}" as="f" hint-placeholder-count="2">
            <button onClick="{{{{f.open}}}}" style="{PLAIN_BTN} width: 100%; display: flex; align-items: center; gap: 12px; padding: 0 0 0 20px; text-align: left;">
              <svg style="flex: 0 0 24px;" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#D1D1D6" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{sec.icon}}}}"></path></svg>
              <span style="flex: 1 1 auto; min-width: 0; padding: 10px 16px 10px 0; border-bottom: 0.5px solid #38383A; display: flex; align-items: center; gap: 10px;">
                <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">
                  <span style="font-size: 17px; line-height: 22px; color: #FFFFFF; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{{{f.name}}}}</span>
                  <span style="font-size: 13px; color: #A1A1A6;">{{{{f.meta}}}}</span>
                </span>
                <sc-if value="{{{{f.isNew}}}}" hint-placeholder-val="{{{{false}}}}"><span style="font-size: 13px; font-weight: 600; color: #409CFF;">New</span></sc-if>
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#636366" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M9 5l7 7-7 7"></path></svg>
              </span>
            </button>
          </sc-for>
        </sc-for>
      </sc-if>
      <sc-if value="{{{{isLinksTab}}}}" hint-placeholder-val="{{{{false}}}}">
        <sc-for list="{{{{links}}}}" as="l" hint-placeholder-count="2">
          <button onClick="{{{{l.open}}}}" style="{PLAIN_BTN} width: 100%; display: flex; align-items: center; gap: 12px; padding: 0 0 0 20px; text-align: left;">
            <span style="width: 30px; height: 30px; flex: 0 0 30px; border-radius: 8px; background: #2C2C2E; font-size: 14px; font-weight: 700; color: #D1D1D6; display: flex; align-items: center; justify-content: center;">{{{{l.mark}}}}</span>
            <span style="flex: 1 1 auto; min-width: 0; padding: 11px 16px 11px 0; border-bottom: 0.5px solid #38383A; display: flex; align-items: center; gap: 10px;">
              <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 1px;">
                <span style="font-size: 17px; line-height: 22px; color: #FFFFFF; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{{{l.title}}}}</span>
                <span style="font-size: 13px; color: #A1A1A6;">{{{{l.domain}}}}</span>
              </span>
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#636366" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M9 5l7 7-7 7"></path></svg>
            </span>
          </button>
        </sc-for>
      </sc-if>
    </div>'''

MENU = f'''<div role="menu" aria-label="File actions" style="position: absolute; right: 62px; top: 58px; width: 250px; border-radius: 14px; background: #2C2C2E; box-shadow: 0 12px 40px rgba(0,0,0,0.6); overflow: hidden; z-index: 5;">
      <sc-for list="{{{{menuItems}}}}" as="m" hint-placeholder-count="4">
        <button role="menuitem" style="{PLAIN_BTN} width: 100%; height: 44px; display: flex; align-items: center; gap: 12px; padding: 0 16px; box-sizing: border-box; border-bottom: 0.5px solid #3A3A3C; font-size: 17px; color: #FFFFFF; text-align: left;">
          <span style="flex: 1 1 auto;">{{{{m.label}}}}</span>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{m.icon}}}}"></path></svg>
        </button>
      </sc-for>
    </div>'''


def src_well(lines, tint):
    rows = []
    for i, ln in enumerate(lines, 1):
        esc = ln.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        if tint == 'html':
            esc = re.sub(r'(&lt;/?[a-z0-9!]+)', r'<span style="color: #FF7AB2;">\1</span>', esc)
            esc = esc.replace('&gt;', '<span style="color: #FF7AB2;">&gt;</span>')
        elif esc.startswith('#'):
            esc = f'<span style="color: #64D2FF; font-weight: 600;">{esc}</span>'
        elif esc.startswith('|'):
            esc = f'<span style="color: #D1D1D6;">{esc}</span>'
        rows.append(f'<span style="color: #636366; text-align: right; user-select: none;">{i}</span><span style="white-space: pre-wrap; overflow-wrap: anywhere;">{esc or " "}</span>')
    return ('<div style="position: absolute; left: 8px; right: 8px; top: 64px; bottom: 8px; border-radius: 18px; background: #000000; overflow: hidden;">'
            f'<div style="padding: 22px 22px 22px 12px; display: grid; grid-template-columns: 34px minmax(0, 1fr); column-gap: 14px; row-gap: 3px; font-family: {MONO}; font-size: 13.5px; line-height: 20px; color: #E5E5EA;">'
            + ''.join(rows) + '</div></div>')

DOC_SRC_WELL = src_well([
    '# Fork latency', '', 'Pro host, iPhone 17 Pro simulator, 10 forks of each size.', '', '## Before', '',
    'The client waited for the fork’s transcript file before it opened the fork. Small forks write that file only on their first turn, so the tap looked dead for up to five seconds.',
    '', '## After', '', 'The client opens the fork as soon as the host returns its id, and the transcript fills in behind it. The change is in `SessionStore.swift`.',
    '', '| Fork | Before | After |', '| --- | --- | --- |', '| Small | 4.8 s | 0.3 s |', '| Large | 0.6 s | 0.3 s |'], 'md')
HTML_SRC_WELL = src_well([
    '<!doctype html>', '<html lang="en">', '<head>', '  <meta charset="utf-8">', '  <title>Why some forks felt instant</title>',
    '  <link rel="stylesheet" href="explainer.css">', '</head>', '<body>', '  <p class="kicker">Explainer</p>',
    '  <h1>Why some forks felt instant and others did not</h1>', '  <ol class="flow">',
    '    <li><b>1 · Tap Fork</b> The phone asks the host for a fork.</li>',
    '    <li><b>2 · Host returns an id</b> In about 0.3 s, for every size.</li>',
    '    <li class="now"><b>3 · Open now</b> The transcript fills in behind it.</li>', '  </ol>',
    '  <p>Before the fix, step 3 waited for a transcript file.</p>', '</body>', '</html>'], 'html')

PANE = f'''<section aria-label="File pane" style="position: absolute; left: {{{{paneL}}}}; top: {{{{paneT}}}}; width: {{{{paneW}}}}; height: {{{{paneH}}}}; border-radius: {{{{paneR}}}}; background: #1C1C1E; overflow: hidden; box-shadow: {{{{paneShadow}}}};">
    <div style="position: absolute; left: 0; right: 0; top: 0; height: 64px; display: flex; align-items: center; gap: 8px; padding: 0 10px; box-sizing: border-box;">
      <sc-if value="{{{{showSessionChip}}}}" hint-placeholder-val="{{{{false}}}}">
        <button onClick="{{{{toggleFocus}}}}" aria-label="Back to the transcript" style="{PLAIN_BTN} height: 44px; flex: 0 0 auto; border-radius: 22px; background: #2C2C2E; display: flex; align-items: center; gap: 8px; padding: 0 14px 0 12px; font-size: 15px; font-weight: 600; color: #FFFFFF;">{icon(P['back'], 16, 'currentColor', 2.4)}<span style="width: 7px; height: 7px; border-radius: 50%; background: #30D158; box-shadow: 0 0 0 3px rgba(48,209,88,0.25);"></span>Fork session feature</button>
      </sc-if>
      <sc-if value="{{{{showBack}}}}" hint-placeholder-val="{{{{true}}}}">
        <button onClick="{{{{backToFiles}}}}" aria-label="All files and links" style="{CIRCLE}">{icon(P['back'], 20, 'currentColor', 2.4)}</button>
      </sc-if>
      <sc-if value="{{{{showTitle}}}}" hint-placeholder-val="{{{{true}}}}">
        <span style="flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 2px; padding-left: {{{{titlePad}}}};">
          <span style="font-size: 17px; line-height: 22px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{{{paneTitle}}}}</span>
          <span style="font-size: 13px; line-height: 18px; color: #A1A1A6; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{{{paneMeta}}}}</span>
        </span>
      </sc-if>
      <sc-if value="{{{{showAddress}}}}" hint-placeholder-val="{{{{false}}}}">
        <span style="flex: 1 1 auto; min-width: 0; height: 40px; border-radius: 20px; background: #2C2C2E; display: flex; align-items: center; gap: 8px; padding: 0 6px 0 14px; box-sizing: border-box;">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#A1A1A6" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{addrIcon}}}}"></path></svg>
          <span style="flex: 1 1 auto; min-width: 0; font-size: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;"><span style="color: #FFFFFF;">{{{{addrMain}}}}</span><span style="color: #8E8E93;">{{{{addrRest}}}}</span></span>
          <button aria-label="Reload" style="{PLAIN_BTN} width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; color: #D1D1D6;">{icon(P['reload'], 17, 'currentColor', 2)}</button>
        </span>
      </sc-if>
      <span style="flex: 0 0 auto; height: 44px; border-radius: 22px; background: #2C2C2E; display: flex; align-items: center;">
        <sc-if value="{{{{showSplitToggle}}}}" hint-placeholder-val="{{{{false}}}}">
          <button onClick="{{{{toggleSplit}}}}" aria-label="{{{{splitLabel}}}}" style="{PLAIN_BTN} width: 38px; height: 38px; margin: 0 2px 0 3px; border-radius: 19px; background: {{{{splitBg}}}}; display: flex; align-items: center; justify-content: center; color: #FFFFFF;"><svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="4" width="16" height="16" rx="3"></rect><path d="M4 12h16"></path></svg></button>
        </sc-if>
        <sc-if value="{{{{showExpand}}}}" hint-placeholder-val="{{{{true}}}}">
          <button onClick="{{{{toggleFocus}}}}" aria-label="{{{{expandLabel}}}}" style="{PLAIN_BTN} width: 44px; height: 44px; display: flex; align-items: center; justify-content: center; color: #FFFFFF;"><svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{expandIcon}}}}"></path></svg></button>
        </sc-if>
        <button onClick="{{{{toggleMenu}}}}" aria-label="More actions" style="{PLAIN_BTN} width: 44px; height: 44px; display: flex; align-items: center; justify-content: center;">{DOTS}</button>
      </span>
      <button onClick="{{{{closePane}}}}" aria-label="Close the file pane" style="{CIRCLE}">{icon(P['close'], 15, '#D1D1D6', 2.8)}</button>
    </div>
    <sc-if value="{{{{isMedia}}}}" hint-placeholder-val="{{{{false}}}}">{MEDIA_WELL}</sc-if>
    <sc-if value="{{{{isDoc}}}}" hint-placeholder-val="{{{{false}}}}">{DOC_WELL}</sc-if>
    <sc-if value="{{{{isHtml}}}}" hint-placeholder-val="{{{{false}}}}">{HTML_WELL}</sc-if>
    <sc-if value="{{{{isLink}}}}" hint-placeholder-val="{{{{false}}}}">{LINK_WELL}</sc-if>
    <sc-if value="{{{{isFiles}}}}" hint-placeholder-val="{{{{false}}}}">{FILES_BODY}</sc-if>
    <sc-if value="{{{{menuOpen}}}}" hint-placeholder-val="{{{{false}}}}">{MENU}</sc-if>
  </section>'''

GRABBER = '''<button onClick="{{toggleWidth}}" aria-label="Resize the file pane" title="Drag to resize. Tap to switch between wide and narrow." style="position: absolute; left: {{grabL}}; top: {{grabT}}; width: 20px; height: 72px; border: 0; background: transparent; padding: 0; cursor: col-resize; display: flex; align-items: center; justify-content: center;"><span style="width: 5px; height: 44px; border-radius: 3px; background: #636366;"></span></button>'''

SCRIPT = r'''
class Component extends DCLogic {
  constructor(props) {
    super(props);
    const st = props.start;
    const start = st && st !== 'none' ? st : null;
    this.state = {
      open: start,
      wide: props.wide ?? Component.defaultWide(start),
      focus: !!props.focus,
      overlay: !!props.overlay,
      menu: !!props.menu,
      tab: props.tab ?? 'files',
      fresh: !!props.fresh,
      seen: false,
      updated: !!props.updated,
      psplit: !!props.split,
      snap: props.snap != null ? Number(props.snap) : 1
    };
  }
  static defaultWide(k) { return !(k === 'before' || k === 'after' || k === 'video' || k === 'timeline'); }
  renderVals() {
    const s = this.state;
    const layout = this.props.layout ?? 'A';
    const portrait = layout === 'portrait', B = layout === 'B', L13 = layout === '13';
    const W = portrait ? 834 : L13 ? 1376 : 1210, H = portrait ? 1210 : L13 ? 1032 : 834;
    const px = (n) => Math.round(n) + 'px';
    const open = s.open, isOpen = open !== null;
    const FILES = {
      before: { name: 'fork-before.png', kind: 'image', meta: '.claude/evidence · 6m ago' },
      after: { name: 'fork-after.png', kind: 'image', meta: '.claude/evidence · 4m ago' },
      video: { name: 'fork-opens-right-away.mp4', kind: 'video', meta: '.claude/evidence · 3m ago' },
      doc: { name: 'fork-latency.md', kind: 'doc', meta: '.claude/evidence · 4m ago' },
      html: { name: 'fork-explainer.html', kind: 'html', meta: '.claude/evidence · 2m ago' },
      notes: { name: 'release-notes.md', kind: 'doc', meta: '.claude · 1h ago' },
      timeline: { name: 'fork-timeline.png', kind: 'image', meta: '.claude/evidence · just now' }
    };
    const ICON = {
      image: 'M3 4h18v16H3zM8.5 10.5a1.5 1.5 0 1 0 0-.01M21 16l-5-5-9 9',
      video: 'M3 6h12v12H3zM15 10l6-3v10l-6-3',
      doc: 'M6 2.5h8l4.5 4.5v14.5H6zM14 2.5V7h4.5M9 12h6M9 16h6',
      html: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9M12 3c-2.5 2.6-3.8 5.6-3.8 9s1.3 6.4 3.8 9',
      link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1'
    };
    const go = (k) => () => this.setState({ open: k, wide: B ? false : Component.defaultWide(k), menu: false, overlay: false, seen: s.seen || k === 'timeline' || k === 'files' });
    const SEL = 'inset 0 0 0 1.5px #0A6EE0';

    // ---- geometry -------------------------------------------------------
    const sideDocked = !portrait && (!isOpen || B || L13) && !s.focus;
    const showSidebar = sideDocked || (s.overlay && isOpen && !s.focus && !B);
    let regL = 330, regR = W, paneL = 0, paneT = 42, paneW = 0, paneH = H - 52, paneR = 26;
    const splitP = portrait && isOpen && s.psplit;
    if (splitP) { regL = 0; regR = W; paneL = 10; paneT = 42; paneW = W - 20; paneH = [440, 560, 760][s.snap]; paneR = 26; }
    else if (portrait) { regL = 0; regR = W; paneL = 40; paneT = 96; paneW = W - 80; paneH = H - 136; paneR = 38; }
    else if (isOpen && s.focus) { paneL = 10; paneW = W - 20; }
    else if (isOpen && B) { paneW = 390; paneL = W - 10 - paneW; regL = 330; regR = paneL - 10; }
    else if (isOpen && L13) { paneW = s.wide ? 600 : 420; paneL = W - 10 - paneW; regL = 330; regR = paneL - 10; }
    else if (isOpen) { paneW = s.wide ? 720 : 420; paneL = W - 10 - paneW; regL = 0; regR = paneL - 10; }
    else if (!sideDocked) { regL = 0; }
    const regW = regR - regL;
    const colW = Math.min(720, regW - 10);
    const colL = regL + (regW - colW) / 2;
    const listL = sideDocked && !portrait ? 350 : 10;
    const menuL = regR - 60;
    const titleL = listL + 54, titleW = menuL - 10 - titleL;

    // pane media frame (portrait phone capture, 1206 x 2622)
    const wellW = paneW - 16, wellH = paneH - 72 - 84 - 24;
    let shotH = wellH, shotW = shotH * 0.46;
    if (shotW > wellW - 32) { shotW = wellW - 32; shotH = shotW / 0.46; }

    const kind = isOpen ? (open === 'files' ? 'files' : open === 'link' ? 'link' : FILES[open].kind) : null;
    const isWeb = kind === 'html' || kind === 'link';
    const narrowPane = paneW < 560;

    const cards = (keys) => keys.map((k) => {
      const f = FILES[k], on = open === k;
      return { name: f.name, label: 'Open ' + f.name, icon: ICON[f.kind], isOpen: on,
        bg: on ? '#182B3E' : '#2C2C2E', ring: on ? SEL : 'none', chev: on ? '#409CFF' : '#636366', open: go(k) };
    });
    const media = s.fresh ? ['before', 'after', 'timeline', 'video'] : ['before', 'after', 'video'];
    const menuFor = {
      image: [['Show in transcript', 'M4 5h16v11H9l-5 4z'], ['Copy path', 'M8 8h11v12H8zM5 16V4h11']],
      doc: [['Show in transcript', 'M4 5h16v11H9l-5 4z'], ['Copy path', 'M8 8h11v12H8zM5 16V4h11']],
      html: [['Show in transcript', 'M4 5h16v11H9l-5 4z'], ['Copy path', 'M8 8h11v12H8zM5 16V4h11']],
      link: [['Show in transcript', 'M4 5h16v11H9l-5 4z'], ['Open in Safari', 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M15.5 8.5l-2 5-5 2 2-5z'], ['Copy link', 'M8 8h11v12H8zM5 16V4h11']],
      files: [['Copy all paths', 'M8 8h11v12H8zM5 16V4h11']]
    };
    const mk = kind === 'video' ? 'image' : kind;

    let paneTitle = '', paneMeta = '';
    if (kind === 'files') { paneTitle = 'Files & links'; paneMeta = 'Shared in this session'; }
    else if (isOpen && FILES[open]) { paneTitle = FILES[open].name; paneMeta = s.updated ? '.claude/evidence · updated just now' : FILES[open].meta; }

    return {
      rootW: px(W), rootH: px(H),
      showTranscript: !(isOpen && s.focus),
      colL: px(colL), colW: px(colW), bubbleMax: colW >= 600 ? '480px' : '290px',
      regL: px(regL), regW: px(regW), pillsL: px(colL + 8), compL: px(colL + 12), compW: px(colW - 24),
      listL: px(listL), barT: px(splitP ? paneT + paneH + 22 : 42), titleL: px(titleL), titleW: px(titleW), titleT: px(splitP ? paneT + paneH + 24 : 44),
      trTop: px(splitP ? paneT + paneH + 88 : 112), gradTop: px(splitP ? paneT + paneH + 12 : 0), gradH: px(splitP ? 100 : 124), menuL: px(menuL),
      listLabel: sideDocked ? 'Hide sessions list' : 'Show sessions list',
      showBadge: !sideDocked && !showSidebar,
      toggleList: () => { if (isOpen && !B && !portrait && !L13) this.setState({ overlay: !s.overlay, menu: false }); },
      showSidebar, sideShadow: sideDocked ? 'none' : '0 12px 48px rgba(0,0,0,0.7)',
      overlayScrim: isOpen && s.overlay && !s.focus && !B && !portrait && !L13,
      sideH: px(H - 52),
      portraitScrim: portrait && isOpen && !s.psplit,
      closeOverlay: () => this.setState({ overlay: false }),
      closeSheet: () => this.setState({ open: null, menu: false }),
      mediaCards: cards(['before', 'after', 'video']), docCards: cards(['doc', 'html']),
      openLink: go('link'), linkDeco: open === 'link' ? 'underline' : 'none',
      openFiles: go('files'),
      fresh: s.fresh, freshDot: s.fresh && !s.seen, newCards: cards(['timeline']), filesCount: s.fresh ? '7' : '6', filesCountInk: s.fresh && !s.seen ? '#409CFF' : '#8E8E93',
      filesPillBg: open === 'files' ? '#182B3E' : '#1C1C1E', filesPillBorder: open === 'files' ? '#0A6EE0' : '#38383A',
      paneOpen: isOpen,
      paneL: px(paneL), paneT: px(paneT), paneW: px(paneW), paneH: px(paneH), paneR: px(paneR),
      paneShadow: portrait && !s.psplit ? '0 20px 60px rgba(0,0,0,0.7)' : 'none',
      showSplitToggle: portrait, splitBg: s.psplit ? '#636366' : 'transparent',
      splitLabel: s.psplit ? 'Show the file as a sheet' : 'Split the screen with the transcript',
      toggleSplit: () => this.setState({ psplit: !s.psplit, menu: false }),
      showHGrab: splitP, hGrabL: px(W / 2 - 40), hGrabT: px(paneT + paneH),
      cycleSnap: () => this.setState({ snap: (s.snap + 1) % 3 }),
      showSessionChip: isOpen && s.focus,
      showBack: isOpen && kind !== 'files' && !s.focus,
      showTitle: !isWeb, showAddress: isWeb, titlePad: kind === 'files' ? '8px' : '2px',
      paneTitle, paneMeta,
      addrIcon: kind === 'link' ? ICON.link : ICON.doc,
      addrMain: kind === 'link' ? 'github.com' : 'fork-explainer.html',
      addrRest: kind === 'link' ? '/eugenechantk/lfg/pull/412' : (narrowPane ? '' : '  ·  .claude/evidence'),
      showExpand: !portrait,
      expandLabel: s.focus ? 'Show the transcript again' : 'Use the full width',
      expandIcon: s.focus ? 'M19.5 4.5L14 10M14 5v5h5M4.5 19.5L10 14M5 14h5v5' : 'M14 4h6v6M20 4l-6.5 6.5M10 20H4v-6M4 20l6.5-6.5',
      toggleFocus: () => this.setState({ focus: !s.focus, menu: false, overlay: false }),
      toggleMenu: () => this.setState({ menu: !s.menu }),
      closePane: () => this.setState({ open: null, focus: false, menu: false, overlay: false }),
      backToFiles: go('files'),
      menuOpen: isOpen && s.menu,
      menuItems: (menuFor[mk] || []).slice(0, 4).map(([label, icon]) => ({ label, icon })),
      isMedia: kind === 'image' || kind === 'video', isBefore: open === 'before', isAfter: open === 'after' || open === 'timeline', isVideo: open === 'video',
      shotW: px(shotW), shotH: px(shotH),
      strip: media.map((k) => ({ label: FILES[k].name, icon: ICON[FILES[k].kind], ring: open === k ? '0 0 0 2px #0A6EE0' : 'none', open: go(k) })),
      isDoc: kind === 'doc', docPad: narrowPane ? '22px' : '40px',
      isHtml: kind === 'html', webPad: narrowPane ? '22px' : '40px',
      isLink: kind === 'link',
      isFiles: kind === 'files',
      tabs: [['files', s.fresh ? 'Files 7' : 'Files 6'], ['links', 'Links 2']].map(([id, label]) => ({ label, bg: s.tab === id ? '#636366' : 'transparent', pick: () => this.setState({ tab: id }) })),
      isFilesTab: s.tab === 'files', isLinksTab: s.tab === 'links',
      sections: [
        { label: 'Images', icon: ICON.image, keys: s.fresh ? ['timeline', 'before', 'after'] : ['before', 'after'] },
        { label: 'Videos', icon: ICON.video, keys: ['video'] },
        { label: 'Documents', icon: ICON.doc, keys: ['doc', 'html', 'notes'] }
      ].map((sec) => ({ label: sec.label, icon: sec.icon, count: String(sec.keys.length),
        files: sec.keys.map((k) => ({ name: FILES[k].name, meta: FILES[k].meta, isNew: k === 'timeline', open: go(k) })) })),
      links: [
        { mark: 'G', title: 'PR #412 · Fork opens right away', domain: 'github.com', open: go('link') },
        { mark: 'A', title: 'TestFlight build 205', domain: 'appstoreconnect.apple.com', open: go('link') }
      ],
      showGrabber: isOpen && !s.focus && !B && !portrait,
      grabL: px(paneL - 15), grabT: px(paneT + paneH / 2 - 36),
      toggleWidth: () => this.setState({ wide: !s.wide })
    };
  }
}
'''

PROPS = {
    'start': {'editor': 'enum', 'options': ['none', 'before', 'after', 'video', 'doc', 'html', 'link', 'files'], 'default': 'none'},
    'layout': {'editor': 'enum', 'options': ['A', 'B', 'portrait', '13'], 'default': 'A'},
    'split': {'editor': 'boolean', 'default': False},
    'fresh': {'editor': 'boolean', 'default': False},
    'updated': {'editor': 'boolean', 'default': False},
    'snap': {'editor': 'enum', 'options': ['0', '1', '2'], 'default': '1'},
    'wide': {'editor': None},
    'focus': {'editor': 'boolean', 'default': False},
    'overlay': {'editor': 'boolean', 'default': False},
    'menu': {'editor': 'boolean', 'default': False},
    'tab': {'editor': 'enum', 'options': ['files', 'links'], 'default': 'files'},
    '$preview': {'width': 1210, 'height': 834},
}

HEAD = '''<!doctype html>
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
textarea::placeholder{{color:#8E8E93}}
</style>
</helmet>
'''

proto = HEAD.format(title='iPad · file pane prototype') + f'''<div style="width: {{{{rootW}}}}; height: {{{{rootH}}}}; position: relative; overflow: hidden; background: #000000; color: #FFFFFF; font-family: {FONT}; -webkit-font-smoothing: antialiased;">
<sc-if value="{{{{showTranscript}}}}" hint-placeholder-val="{{{{true}}}}">
  {TRANSCRIPT}
  {BOTTOM}
  {TOPBAR}
</sc-if>
<sc-if value="{{{{portraitScrim}}}}" hint-placeholder-val="{{{{false}}}}"><button onClick="{{{{closeSheet}}}}" aria-label="Close the file" style="position: absolute; inset: 0; border: 0; padding: 0; background: rgba(0,0,0,0.6); cursor: default;"></button></sc-if>
<sc-if value="{{{{paneOpen}}}}" hint-placeholder-val="{{{{false}}}}">
  {PANE}
</sc-if>
<sc-if value="{{{{showGrabber}}}}" hint-placeholder-val="{{{{false}}}}">{GRABBER}</sc-if>
<sc-if value="{{{{showHGrab}}}}" hint-placeholder-val="{{{{false}}}}"><button onClick="{{{{cycleSnap}}}}" aria-label="Resize the split" title="Drag to resize. Tap to step through the sizes." style="position: absolute; left: {{{{hGrabL}}}}; top: {{{{hGrabT}}}}; width: 80px; height: 22px; border: 0; background: transparent; padding: 0; cursor: row-resize; display: flex; align-items: center; justify-content: center;"><span style="width: 44px; height: 5px; border-radius: 3px; background: #636366;"></span></button></sc-if>
<sc-if value="{{{{overlayScrim}}}}" hint-placeholder-val="{{{{false}}}}"><button onClick="{{{{closeOverlay}}}}" aria-label="Hide the sessions list" style="position: absolute; inset: 0; border: 0; padding: 0; background: rgba(0,0,0,0.4); cursor: default;"></button></sc-if>
<sc-if value="{{{{showSidebar}}}}" hint-placeholder-val="{{{{true}}}}">
  {sidebar}
</sc-if>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{json.dumps(PROPS)}'>{SCRIPT}</script>
</body>
</html>
'''
open(os.path.join(OUT, 'ia-proto.dc.html'), 'w').write(proto)


def importer(stem, title, w, h, **props):
    attrs = ' '.join(f'{k}="{v}"' for k, v in props.items())
    html = HEAD.format(title=title) + f'''<div style="width: {w}px; height: {h}px;"><dc-import name="ia-proto" {attrs} hint-size="{w}px,{h}px"></dc-import></div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{w},"height":{h}}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
'''
    open(os.path.join(OUT, stem + '.dc.html'), 'w').write(html)


BOARDS = [
    # stem, title, w, h, props
    ('ia-a-image', 'A · image beside the transcript (narrow pane)', 1210, 834, dict(start='after')),
    ('ia-a-video', 'A · video (narrow pane)', 1210, 834, dict(start='video')),
    ('ia-a-doc', 'A · Markdown file (wide pane)', 1210, 834, dict(start='doc')),
    ('ia-a-web', 'A · HTML page (wide pane)', 1210, 834, dict(start='html')),
    ('ia-a-files', 'A · Files & links in the pane', 1210, 834, dict(start='files')),
    ('ia-a-link', 'A · a link, opened in the pane', 1210, 834, dict(start='link')),
    ('ia-a-menu', 'A · the ••• menu', 1210, 834, dict(start='doc', menu='{{true}}')),
    ('ia-a-list', 'A · list called back over the pane', 1210, 834, dict(start='doc', overlay='{{true}}')),
    ('ia-a-full', 'A · full width', 1210, 834, dict(start='html', focus='{{true}}')),
    ('ia-a-portrait', 'Portrait · sheet (the default)', 834, 1210, dict(start='after', layout='portrait')),
    ('ia-p-split-image', 'Portrait · split, file 55%', 834, 1210, dict(start='after', layout='portrait', split='{{true}}', snap='1')),
    ('ia-p-split-doc', 'Portrait · split, file 40%', 834, 1210, dict(start='doc', layout='portrait', split='{{true}}', snap='0')),
    ('ia-p-split-web', 'Portrait · split, file 70%', 834, 1210, dict(start='html', layout='portrait', split='{{true}}', snap='2')),
    ('ia-a-newfile', 'A · a new file arrives while you read', 1210, 834, dict(start='doc', fresh='{{true}}')),
    ('ia-a-updated', 'A · the open file was rewritten', 1210, 834, dict(start='doc', updated='{{true}}')),
    ('ia-a-13in', '13-inch · the list stays (width rule)', 1376, 1032, dict(start='doc', layout='13')),
    ('ia-b-image', 'B · list stays, image in a third column', 1210, 834, dict(start='after', layout='B')),
    ('ia-b-doc', 'B · list stays, Markdown file in a third column', 1210, 834, dict(start='doc', layout='B')),
]
for stem, title, w, h, props in BOARDS:
    importer(stem, title, w, h, **props)

json.dump([b[:4] for b in BOARDS], open(os.path.join(HERE, 'boards.json'), 'w'))
print('wrote', len(BOARDS) + 1, 'boards to', OUT)
