// Board DOM dump at zoom 1. Paste body into javascript_tool with NAME set.
async function __dump(NAME) {
  await document.fonts.ready;
  const root = document.querySelector('#dc-root');
  root.style.zoom = '1';
  document.body.style.marginLeft = '0px'; document.body.style.marginTop = '0px';
  const art = root.firstElementChild.firstElementChild; // 390x844 artboard
  const ab = art.getBoundingClientRect();
  const lines = [];
  lines.push(`# ${NAME} ${location.href} artboard ${ab.x},${ab.y},${ab.width}x${ab.height} fonts=${[...document.fonts].map(f=>f.family+':'+f.status).join(',')} imgs=${[...document.images].map(i=>i.complete+':'+i.naturalWidth).join(',')}`);
  const keep = ['font-family','font-size','font-weight','letter-spacing','line-height','color','background-color','background-image','border-radius','border-top','border-bottom','border-left','opacity','padding','gap','text-transform','white-space','text-overflow','box-shadow','backdrop-filter','font-variant-numeric','text-align'];
  const walk = (el, d) => {
    const b = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    const direct = [...el.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent.trim()).filter(Boolean).join(' ');
    const props = keep.map(k => {
      const v = cs.getPropertyValue(k);
      if (!v || v === 'none' || v === 'normal' || v === '0px' || v === 'rgba(0, 0, 0, 0)' || v === 'auto') return null;
      if (k === 'border-top' || k === 'border-bottom' || k === 'border-left') { if (v.startsWith('0px')) return null; }
      return `${k}:${v}`;
    }).filter(Boolean);
    let extra = '';
    if (el.tagName.toLowerCase() === 'svg') extra = ' svg=' + el.outerHTML.replace(/\s+/g, ' ').slice(0, 400);
    if (b.width > 0 && b.height > 0)
      lines.push(`${' '.repeat(d)}${el.tagName.toLowerCase()} [${(b.x-ab.x).toFixed(2)},${(b.y-ab.y).toFixed(2)},${b.width.toFixed(2)},${b.height.toFixed(2)}]${direct ? ' "' + direct.slice(0, 120) + '"' : ''} {${props.join('; ')}}${extra}`);
    if (el.tagName.toLowerCase() !== 'svg') for (const c of el.children) walk(c, d + 1);
  };
  walk(art, 0);
  // text line boxes for direct text nodes
  const tw = document.createTreeWalker(art, NodeFilter.SHOW_TEXT);
  lines.push('## text line boxes');
  let n;
  while ((n = tw.nextNode())) {
    const t = n.textContent.trim(); if (!t) continue;
    const r = document.createRange(); r.selectNodeContents(n);
    const rects = [...r.getClientRects()].map(q => `[${(q.x-ab.x).toFixed(2)},${(q.y-ab.y).toFixed(2)},${q.width.toFixed(2)},${q.height.toFixed(2)}]`);
    lines.push(`"${t.slice(0, 60)}" ${rects.join(' ')}`);
  }
  const body = lines.join('\n');
  await fetch('http://127.0.0.1:8798/dom-' + NAME + '.txt', { method: 'POST', body });
  // set up 3x tiling
  document.documentElement.style.overflow = 'hidden'; document.body.style.overflow = 'hidden'; document.body.style.margin = '0';
  root.style.zoom = '3';
  window.__tile = (x, y) => { document.body.style.marginLeft = (-x) + 'px'; document.body.style.marginTop = (-y) + 'px'; const q = art.getBoundingClientRect(); return location.href + ' art@' + q.x + ',' + q.y + ',' + q.width + 'x' + q.height; };
  return { href: location.href, lines: lines.length, head: lines[0].slice(0, 300), tile: window.__tile(0, 0) };
}
