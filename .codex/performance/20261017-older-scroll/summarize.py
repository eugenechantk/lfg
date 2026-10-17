"""Attribute sampled main-thread stacks without double-counting ancestors."""
import json
import re
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parent


def summary(path):
    lines = path.read_text().split("Call graph:", 1)[1].splitlines()
    nodes = []
    active = False
    stack = []
    for line in lines:
        m = re.match(r"^([ +!|:]*)(\d+) (.*)", line)
        if not m:
            continue
        indent, count, name = len(m[1]), int(m[2]), m[3]
        if name.startswith("Thread_"):
            if active:
                break
            if "Main Thread" not in name:
                continue
            active = True
        if not active:
            continue
        while stack and nodes[stack[-1]]["indent"] >= indent:
            stack.pop()
        parent = stack[-1] if stack else None
        node = dict(indent=indent, count=count, name=name, children=0, parent=parent)
        if parent is not None:
            nodes[parent]["children"] += count
        nodes.append(node)
        stack.append(len(nodes)-1)
    totals = Counter()
    inclusive = Counter()
    for i, node in enumerate(nodes):
        weight = max(0, node["count"]-node["children"])
        if not weight:
            continue
        ancestors = []
        current = i
        while current is not None:
            ancestors.append(nodes[current]["name"])
            current = nodes[current]["parent"]
        text = "\n".join(ancestors)
        markers = {"task_formatting": "TaskRowModel.make", "text_sizing": "SelectableProseView.sizeThatFits",
                   "session_timeline": "closure #1 in closure #1 in SessionRow.body"}
        for label, marker in markers.items():
            if marker in text:
                inclusive[label] += weight
        if "mshMIGPerform" in text or "_AXXMIG" in text:
            category = "automation_accessibility"
        elif "__CFRunLoopServiceMachPort" in text or "__psynch_cvwait" in text:
            category = "waiting"
        elif "TaskRowModel.make" in text:
            category = "task_formatting"
        elif "SelectableProseView.sizeThatFits" in text:
            category = "text_sizing"
        elif "CA::" in text:
            category = "core_animation"
        elif "sizeThatFits" in text or "Layout" in text or "layoutSubviews" in text:
            category = "layout"
        else:
            category = "other"
        totals[category] += weight
    return dict(main_samples=nodes[0]["count"], categories=dict(totals), inclusive=dict(inclusive))


results = []
valid_before = {"before-iphone-sessions-final", "before-iphone-tasks", "before-iphone-transcript-final",
                "before-ipad-sessions", "before-ipad-tasks-final", "before-ipad-transcript"}
for path in sorted(root.glob("*/metrics.json")):
    if path.parent.name not in valid_before and not path.parent.name.startswith("after-"):
        continue
    row = json.loads(path.read_text())
    row["label"] = path.parent.name
    row["stacks"] = summary(path.parent/"stacks.txt")
    results.append(row)
(root/"summary.json").write_text(json.dumps(results, indent=2))
for row in results:
    print(row["label"], "CPU seconds", round(row["cpu_seconds"], 2), row["stacks"])
