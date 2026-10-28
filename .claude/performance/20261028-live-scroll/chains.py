"""Print distinct caller chains (root->target) for main-thread samples that hit a frame."""
import re, sys
from collections import Counter
from pathlib import Path
text = Path(sys.argv[1]).read_text().split("Call graph:", 1)[1].splitlines()
target = sys.argv[2]
keep = re.compile(sys.argv[3]) if len(sys.argv) > 3 else None
nodes, stack, active = [], [], False
for line in text:
    m = re.match(r"^([ +!|:]*)(\d+) (.*)", line)
    if not m: continue
    indent, count, name = len(m[1]), int(m[2]), m[3]
    if name.startswith("Thread_"):
        if active: break
        if "Main Thread" not in name: continue
        active = True
    if not active: continue
    while stack and nodes[stack[-1]]["indent"] >= indent: stack.pop()
    parent = stack[-1] if stack else None
    nodes.append(dict(indent=indent, count=count, name=re.sub(r"\s+\(in [^)]*\).*$", "", name).strip(), parent=parent))
    stack.append(len(nodes)-1)
chains = Counter()
for i, n in enumerate(nodes):
    if target not in n["name"]: continue
    # only the outermost match
    cur = n["parent"]; outer = True
    while cur is not None:
        if target in nodes[cur]["name"]: outer = False; break
        cur = nodes[cur]["parent"]
    if not outer: continue
    chain = []; cur = i
    while cur is not None:
        nm = nodes[cur]["name"]
        if keep is None or keep.search(nm): chain.append(nm[:110])
        cur = nodes[cur]["parent"]
    chains[" <- ".join(chain[:14])] += n["count"]
for c, k in sorted(((v, k) for k, v in chains.items()), reverse=True)[:8]:
    print(c, "::", k, "\n")
