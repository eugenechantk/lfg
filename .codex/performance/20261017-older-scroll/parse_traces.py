"""Summarize exported Time Profiler data without counting stack ancestors twice."""
from collections import Counter
import json
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent / "traces"
results = []
for path in sorted(root.glob("*/time-profile.xml")):
    tree = ET.parse(path).getroot()
    ids = {e.attrib["id"]: e for e in tree.iter() if "id" in e.attrib}

    def resolve(e):
        return ids[e.attrib["ref"]] if e is not None and "ref" in e.attrib else e

    main = 0
    total = 0
    categories = Counter()
    inclusive = Counter()
    functions = Counter()
    self_functions = Counter()
    rows = tree.findall(".//row")
    for row in rows:
        weight = int(resolve(row.find("weight")).text)
        total += weight
        thread = resolve(row.find("thread"))
        if "Main Thread" not in thread.attrib.get("fmt", ""):
            continue
        main += weight
        frames = [resolve(frame) for frame in resolve(row.find("backtrace"))]
        names = [frame.attrib.get("name", "") for frame in frames]
        text = "\n".join(names)
        for name, marker in [("task_formatting", "TaskRowModel.make"),
                             ("text_sizing", "SelectableProseView.sizeThatFits"),
                             ("session_timeline", "closure #1 in closure #1 in SessionRow.body")]:
            if marker in text:
                inclusive[name] += weight
        if "mshMIGPerform" in text or "_AXXMIG" in text:
            category = "automation_accessibility"
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
        categories[category] += weight
        if category != "automation_accessibility" and frames:
            binary = resolve(frames[0].find("binary"))
            binary_name = binary.attrib.get("name", "unknown") if binary is not None else "unknown"
            self_functions[f"{names[0]} [{binary_name}]"] += weight
        app_names = set()
        for frame in frames:
            binary = resolve(frame.find("binary"))
            if binary is not None and binary.attrib.get("name") == "LFG":
                app_names.add(frame.attrib.get("name", ""))
        for name in app_names:
            if "LFGApp.$main()" not in name:
                functions[name] += weight
    to_ms = lambda c: {k: round(v/1e6, 3) for k, v in c.items()}
    toc = ET.parse(path.parent / "toc.xml").getroot()
    hangs_path = path.parent / "hangs.xml"
    hangs = ET.parse(hangs_path).getroot().findall(".//row") if hangs_path.exists() else None
    result = dict(label=path.parent.name, rows=len(rows),
                  duration_seconds=float(toc.findtext(".//summary/duration")),
                  sampled_all_threads_ms=round(total/1e6, 3), sampled_main_thread_ms=round(main/1e6, 3),
                  sampled_non_automation_main_ms=round((main-categories["automation_accessibility"])/1e6, 3),
                  main_categories_ms=to_ms(categories), inclusive_main_ms=to_ms(inclusive),
                  top_app_functions_main_ms=to_ms(Counter(dict(functions.most_common(20)))),
                  top_non_automation_main_self_functions_ms=to_ms(Counter(dict(self_functions.most_common(25)))),
                  potential_hangs_count=None if hangs is None else len(hangs))
    (path.parent / "summary.json").write_text(json.dumps(result, indent=2))
    results.append(result)
    print(json.dumps(result))
(root / "summary.json").write_text(json.dumps(results, indent=2))
