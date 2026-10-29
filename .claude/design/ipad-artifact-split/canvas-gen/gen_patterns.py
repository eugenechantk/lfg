#!/usr/bin/env python3
"""ia-patterns.dc.html: the inspiration board (six layout patterns as mini wireframes)."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'canvas', 'project')
PAT = json.load(open(os.path.join(HERE, 'patterns.json')))

FILE = '#23324A'   # the file pane
CHAT = '#2C2C2E'   # the conversation
LIST = '#3A3A3C'   # the session list / sidebar


def col(kind, flex, label, extra=''):
    bg = {'file': FILE, 'chat': CHAT, 'list': LIST, 'ghost': 'transparent', 'dim': '#26262A'}[kind]
    border = 'border: 1.5px dashed #48484A;' if kind == 'ghost' else ''
    color = '#C9D6EC' if kind == 'file' else '#A1A1A6'
    return (f'<span style="flex: {flex}; min-width: 0; border-radius: 8px; background: {bg}; {border} box-sizing: border-box; '
            f'display: flex; align-items: flex-end; padding: 8px; font-size: 12px; font-weight: 600; color: {color}; {extra}">{label}</span>')


def wire(spec):
    cols = ''.join(col(*c) for c in spec['cols'])
    over = ''
    if spec.get('overlay'):
        k, left, width, label = spec['overlay']
        over = (f'<span style="position: absolute; left: {left}; top: 10px; bottom: 10px; width: {width}; border-radius: 8px; '
                f'background: {FILE if k == "file" else LIST}; box-shadow: 0 6px 24px rgba(0,0,0,0.7); display: flex; align-items: flex-end; '
                f'padding: 8px; box-sizing: border-box; font-size: 12px; font-weight: 600; color: #C9D6EC;">{label}</span>')
    strip = ''
    if spec.get('strip'):
        strip = ('<span style="position: absolute; left: 50%; bottom: 18px; width: 96px; margin-left: -48px; height: 22px; border-radius: 7px; '
                 'background: #1C1C1E; display: flex; gap: 4px; align-items: center; justify-content: center;">'
                 + ''.join('<span style="width: 14px; height: 14px; border-radius: 3px; background: #48484A;"></span>' for _ in range(4)) + '</span>')
    extra = ''
    if spec.get('chip'):
        extra += ('<span style="position: absolute; left: 18px; top: 18px; height: 20px; width: 120px; border-radius: 10px; background: #2C2C2E; '
                  'display: flex; align-items: center; gap: 6px; padding: 0 8px; box-sizing: border-box;"><span style="width: 7px; height: 7px; border-radius: 4px; background: #30D158;"></span>'
                  '<span style="height: 5px; flex: 1 1 auto; border-radius: 3px; background: #636366;"></span></span>')
    if spec.get('mark'):
        extra += ('<span style="position: absolute; left: 22px; width: 31%; top: 92px; height: 20px; border-radius: 5px; background: #182B3E; '
                  'box-shadow: inset 0 0 0 1.5px #0A6EE0;"></span>'
                  '<span style="position: absolute; left: 22px; width: 31%; top: 66px; height: 20px; border-radius: 5px; background: #3A3A3C;"></span>'
                  '<span style="position: absolute; left: 22px; width: 31%; top: 118px; height: 20px; border-radius: 5px; background: #3A3A3C;"></span>')
    tabs = ''
    if spec.get('tabs'):
        tabs = ('<span style="position: absolute; right: 10px; top: 10px; display: flex; gap: 3px;">'
                + ''.join(f'<span style="width: 46px; height: 14px; border-radius: 4px 4px 0 0; background: {FILE if i == 0 else "#2F3C52"};"></span>' for i in range(3)) + '</span>')
    return (f'<div aria-hidden="true" style="position: relative; height: 190px; border-radius: 14px; background: #121214; border: 0.5px solid #38383A; '
            f'padding: 10px; box-sizing: border-box; display: flex; gap: 6px;">{cols}{over}{strip}{tabs}{extra}</div>')


TAG = {'Today': ('#D1D1D6', 'rgba(209,209,214,0.14)'), 'Taken': ('#30D158', 'rgba(48,209,88,0.14)'), 'Partly': ('#FF9F0A', 'rgba(255,159,10,0.14)'),
       'Option B': ('#64D2FF', 'rgba(100,210,255,0.14)'), 'Not taken': ('#A1A1A6', 'rgba(142,142,147,0.16)')}

cards = []
for p in PAT['patterns']:
    fg, bg = TAG[p['tag']]
    cards.append(f'''<article style="display: flex; flex-direction: column; gap: 14px; padding: 20px; border-radius: 20px; background: #1C1C1E;">
      {wire(p['wire'])}
      <div style="display: flex; align-items: center; gap: 10px;">
        <span style="flex: 1 1 auto; font-size: 22px; line-height: 28px; font-weight: 700;">{p['name']}</span>
        <span style="flex: 0 0 auto; height: 26px; padding: 0 10px; border-radius: 13px; background: {bg}; color: {fg}; font-size: 13px; font-weight: 700; display: flex; align-items: center;">{p['tag']}</span>
      </div>
      <span style="font-size: 16px; line-height: 23px; color: #D1D1D6;">{p['what']}</span>
      <span style="font-size: 14px; line-height: 20px; color: #A1A1A6;"><b style="color: #D1D1D6; font-weight: 600;">Seen in</b> {p['seen']}</span>
      <span style="font-size: 15px; line-height: 22px; color: #F2F2F7; border-top: 0.5px solid #38383A; padding-top: 12px;"><b style="font-weight: 600;">For lfg:</b> {p['lfg']}</span>
    </article>''')

W, H = PAT['w'], PAT['h']
legend = ''.join(f'<span style="display: flex; align-items: center; gap: 8px;"><span style="width: 16px; height: 16px; border-radius: 4px; background: {c};"></span>{t}</span>'
                 for c, t in [(LIST, 'Session list'), (CHAT, 'Conversation'), (FILE, 'File')])

html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Inspiration · eight layout patterns</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
a{{color:#409CFF;text-decoration:none}}a:hover{{color:#64A8FF}}
</style>
</helmet>
<div style="width: {W}px; height: {H}px; box-sizing: border-box; padding: 64px; background: #000000; color: #FFFFFF; font-family: -apple-system, 'SF Pro Text', system-ui, sans-serif; -webkit-font-smoothing: antialiased; display: flex; flex-direction: column; gap: 28px;">
  <div style="display: flex; align-items: flex-end; gap: 24px;">
    <div style="flex: 1 1 auto; display: flex; flex-direction: column; gap: 8px;">
      <span style="font-size: 40px; line-height: 46px; font-weight: 700;">{PAT['title']}</span>
      <span style="font-size: 18px; line-height: 26px; color: #A1A1A6; max-width: 1100px;">{PAT['sub']}</span>
    </div>
    <div style="flex: 0 0 auto; display: flex; gap: 18px; font-size: 14px; color: #A1A1A6;">{legend}</div>
  </div>
  <div style="display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 28px;">
    {''.join(cards)}
  </div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{W},"height":{H}}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
'''
open(os.path.join(OUT, 'ia-patterns.dc.html'), 'w').write(html)
print('wrote ia-patterns', W, H)
