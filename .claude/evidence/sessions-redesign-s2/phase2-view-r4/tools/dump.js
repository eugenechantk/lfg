// DOM dump of everything visible inside the 390x844 artboard at the top-left. Paste into the page with NAME set.
(async (NAME) => {
  await document.fonts.ready;
  const out = [];
  const r1 = (v) => Math.round(v * 10) / 10;
  const vis = (r) => r.width > 0 && r.height > 0 && r.right > 0 && r.left < 390 && r.bottom > 0 && r.top < 844;
  const all = document.querySelectorAll('body *');
  for (const el of all) {
    const r = el.getBoundingClientRect();
    if (!vis(r)) continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    const tag = el.tagName.toLowerCase();
    if (tag === 'script' || tag === 'style') continue;
    let own = '';
    for (const n of el.childNodes) if (n.nodeType === 3) own += n.textContent;
    own = own.replace(/\s+/g, ' ').trim();
    const bits = [`${tag} [${r1(r.left)},${r1(r.top)},${r1(r.width)},${r1(r.height)}]`];
    const bg = cs.backgroundColor;
    if (bg && bg !== 'rgba(0, 0, 0, 0)') bits.push('bg=' + bg);
    if (cs.backgroundImage !== 'none') bits.push('bgi=' + cs.backgroundImage.slice(0, 160));
    if (cs.borderTopWidth !== '0px' || cs.borderBottomWidth !== '0px' || cs.borderLeftWidth !== '0px') bits.push(`bd=${cs.borderTopWidth}/${cs.borderRightWidth}/${cs.borderBottomWidth}/${cs.borderLeftWidth} ${cs.borderTopColor}|${cs.borderBottomColor}`);
    if (cs.borderTopLeftRadius !== '0px') bits.push('rad=' + cs.borderTopLeftRadius);
    const pad = `${cs.paddingTop} ${cs.paddingRight} ${cs.paddingBottom} ${cs.paddingLeft}`;
    if (pad !== '0px 0px 0px 0px') bits.push('pad=' + pad);
    if (cs.gap && cs.gap !== 'normal') bits.push('gap=' + cs.gap);
    if (cs.opacity !== '1') bits.push('op=' + cs.opacity);
    if (cs.boxShadow !== 'none') bits.push('sh=' + cs.boxShadow.slice(0, 80));
    if (cs.backdropFilter && cs.backdropFilter !== 'none') bits.push('bf=' + cs.backdropFilter);
    if (cs.maskImage && cs.maskImage !== 'none') bits.push('mask=' + cs.maskImage.slice(0, 160));
    if (cs.overflow !== 'visible') bits.push('ov=' + cs.overflow);
    if (tag === 'svg') bits.push(`svg stroke=${cs.stroke} sw=${el.getAttribute('stroke-width') || cs.strokeWidth} fill=${cs.fill} vb=${el.getAttribute('viewBox')}`);
    if (['path', 'circle', 'rect', 'line', 'polyline'].includes(tag)) {
      const a = {};
      for (const at of el.attributes) a[at.name] = at.value.slice(0, 120);
      bits.push(tag + ' ' + JSON.stringify(a) + ` stroke=${cs.stroke} fill=${cs.fill}`);
    }
    if (own) {
      bits.push(`T="${own.slice(0, 80)}" f=${cs.fontSize}/${cs.lineHeight} w=${cs.fontWeight} ls=${cs.letterSpacing} c=${cs.color} ff=${cs.fontFamily.slice(0, 40)} tt=${cs.textTransform} ws=${cs.whiteSpace}`);
      const rng = document.createRange();
      const rects = [];
      for (const n of el.childNodes) if (n.nodeType === 3 && n.textContent.trim()) { rng.selectNodeContents(n); for (const q of rng.getClientRects()) rects.push(`${r1(q.left)},${r1(q.top)},${r1(q.width)},${r1(q.height)}`); }
      bits.push('lines=' + rects.join(' '));
    }
    out.push(bits.join(' | '));
  }
  await fetch('http://127.0.0.1:8798/' + NAME, { method: 'POST', body: out.join('\n'), headers: { 'Content-Type': 'text/plain' } });
  return NAME + ' ' + out.length;
})
