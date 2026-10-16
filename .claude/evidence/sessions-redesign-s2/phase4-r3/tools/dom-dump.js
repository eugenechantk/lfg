// Verifier's own DOM dump for dA2-sessions, exactly as run in the board tab (Chrome 154, DPR 1).
// Usage in the tab: paste, then `await window.__post('board-dom-<state>.tsv')` (POSTs to tools/receiver.py on 127.0.0.1:8797).
// TSV: kind, label, x, y, w, h, font-size, weight, line-height, color, bg, border, radius, extra
window.__dumpFn = () => {
  const root = document.querySelector('div[style*="width: 400px"]');
  const out = [];
  const cs = (el) => getComputedStyle(el);
  const r1 = (v) => Math.round(v * 100) / 100;
  const tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let n;
  while ((n = tw.nextNode())) {
    const t = n.textContent.trim();
    if (!t) continue;
    const range = document.createRange();
    range.selectNodeContents(n);
    const rects = [...range.getClientRects()].filter((r) => r.width > 0);
    if (!rects.length) continue;
    const r = range.getBoundingClientRect();
    const el = n.parentElement;
    const s = cs(el);
    let op = 1, e = el;
    while (e && e !== document.body) { op *= parseFloat(cs(e).opacity); e = e.parentElement; }
    out.push(['text', t.slice(0, 48), r1(r.x), r1(r.y), r1(r.width), r1(r.height), s.fontSize, s.fontWeight, s.lineHeight, s.color, '', '', '', 'op=' + op].join('\t'));
  }
  for (const el of root.querySelectorAll('*')) {
    const s = cs(el);
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const hasBg = s.backgroundColor !== 'rgba(0, 0, 0, 0)';
    const hasBorder = parseFloat(s.borderTopWidth) > 0 || parseFloat(s.borderBottomWidth) > 0;
    const isSvg = el.tagName.toLowerCase() === 'svg';
    const isRow = el.tagName === 'A' || (el.tagName === 'BUTTON');
    if (!(hasBg || hasBorder || isSvg || isRow)) continue;
    const path = isSvg ? [...el.querySelectorAll('path,circle')].map(p => p.getAttribute('d') || ('circle r=' + p.getAttribute('r'))).join('|') : '';
    const label = el.tagName.toLowerCase() + (el.getAttribute('aria-label') ? '[' + el.getAttribute('aria-label') + ']' : '') + (el.getAttribute('aria-expanded') ? '[expanded=' + el.getAttribute('aria-expanded') + ']' : '') + (isSvg ? '[' + (el.getAttribute('stroke') || s.color) + ' sw=' + el.getAttribute('stroke-width') + ' ' + path + ']' : '') + ' ' + (el.textContent || '').trim().slice(0, 24);
    const border = hasBorder ? `T${s.borderTopWidth} ${s.borderTopColor} B${s.borderBottomWidth} ${s.borderBottomColor}` : '';
    out.push(['box', label, r1(r.x), r1(r.y), r1(r.width), r1(r.height), '', '', '', s.color, hasBg ? s.backgroundColor : '', border, s.borderRadius, s.boxShadow !== 'none' ? 'shadow=' + s.boxShadow : ''].join('\t'));
  }
  return out.join('\n');
};
window.__post = async (name) => {
  const b = window.__dumpFn();
  await fetch('http://127.0.0.1:8797/' + name, { method: 'POST', body: b, mode: 'no-cors' });
  return [name, b.length, [...document.querySelectorAll('button[aria-expanded]')].map((x) => x.getAttribute('aria-expanded'))];
};
