"""Inclusive sample counts per frame name on the main thread (each sample counted once per name)."""
import re, sys
from collections import Counter
from pathlib import Path
text = Path(sys.argv[1]).read_text().split("Call graph:", 1)[1].splitlines()
nodes, stack, active = [], [], False
for line in text:
    m = re.match(r"^([ +!|:]*)(\d+) (.*)", line)
    if not m: continue
    indent, count, name = len(m[1]), int(m[2]), m[3]
    if name.startswith("Thread_"):
        if active: break
        if "Main Thread" not in name and "main-thread" not in name: continue
        active = True
    if not active: continue
    while stack and nodes[stack[-1]]["indent"] >= indent: stack.pop()
    parent = stack[-1] if stack else None
    nodes.append(dict(indent=indent, count=count, name=name, children=0, parent=parent))
    if parent is not None: nodes[parent]["children"] += count
    stack.append(len(nodes)-1)
inc = Counter(); selfc = Counter()
for i, n in enumerate(nodes):
    w = max(0, n["count"] - n["children"])
    if not w: continue
    names = set(); cur = i
    short = lambda s: re.sub(r"\s+\(in [^)]*\).*$", "", s).strip()[:150]
    selfc[short(n["name"])] += w
    while cur is not None:
        names.add(short(nodes[cur]["name"])); cur = nodes[cur]["parent"]
    for nm in names: inc[nm] += w
flt = sys.argv[2] if len(sys.argv) > 2 else ""
print("== inclusive (filtered: %r)" % flt)
for nm, c in inc.most_common(400):
    if flt and not re.search(flt, nm): continue
    print(c, nm)
print("== self top 25")
for nm, c in selfc.most_common(25): print(c, nm)
