"""Build a local review page containing only selected evidence and media."""
import html
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "review"
OUT.mkdir(exist_ok=True)
(OUT / "media").mkdir(exist_ok=True)
rows = json.loads((ROOT / "summary.json").read_text())
by_label = {row["label"]: row for row in rows}
before = {
    ("iphone", "sessions"): "before-iphone-sessions-final",
    ("iphone", "tasks"): "before-iphone-tasks",
    ("iphone", "transcript"): "before-iphone-transcript-final",
    ("ipad", "sessions"): "before-ipad-sessions",
    ("ipad", "tasks"): "before-ipad-tasks-final",
    ("ipad", "transcript"): "before-ipad-transcript",
}
names = {"iphone": "iPhone SE 2", "ipad": "iPad mini 5"}
for device, surface in before:
    label = f"after-{device}-{surface}"
    if label not in by_label or not (ROOT / label / "scroll.mov").exists():
        raise SystemExit("All six final after captures are required before building the review page.")
table = []
cards = []
for (device, surface), label in before.items():
    a = by_label.get(label)
    b = by_label.get(f"after-{device}-{surface}")
    if not a or not b:
        continue
    change = (b["cpu_seconds"] / a["cpu_seconds"] - 1) * 100
    if surface == "sessions":
        table.append(f'<tr><th colspan="4">{names[device]}</th></tr>')
    table.append(f'<tr><td>{surface.title()}</td>'
                 f'<td>{a["cpu_seconds"]:.2f} s</td><td>{b["cpu_seconds"]:.2f} s</td>'
                 f'<td class="{"good" if change < 0 else "neutral"}">{change:+.0f}%</td></tr>')
    videos = []
    for title, row in [("Before", a), ("After", b)]:
        folder = ROOT / row["label"]
        target = OUT / "media" / f'{row["label"]}.mp4'
        if not target.exists():
            # FlowDeck captures HEVC. H.264 also plays in Chromium and on
            # devices without an HEVC decoder; retain untouched raw captures.
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                            "-i", str(folder / "scroll.mov"), "-vf", "scale=min(960\\,iw):-2",
                            "-c:v", "libx264", "-preset", "veryfast", "-crf", "21", "-threads", "2",
                            "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", str(target)], check=True)
            print(f"Prepared {target.name}", flush=True)
        previous_copy = OUT / "media" / f'{row["label"]}.mov'
        if previous_copy.exists():
            previous_copy.unlink()
        poster = OUT / "media" / f'{row["label"]}.jpg'
        if not poster.exists():
            shutil.copy2(folder / "gesture-00.jpg", poster)
        videos.append(f'<figure><figcaption>{title}</figcaption><video controls playsinline preload="none" '
                      f'poster="media/{poster.name}" src="media/{target.name}"></video></figure>')
    cards.append(f'<details><summary>{names[device]} · {surface.title()}</summary>'
                 f'<button class="play" type="button">Play both from the start</button>'
                 f'<div class="videos {device}">{"".join(videos)}</div></details>')

def active_main_share(row):
    stacks = row["stacks"]
    categories = stacks["categories"]
    return (stacks["main_samples"] - categories.get("waiting", 0)
            - categories.get("automation_accessibility", 0)) / stacks["main_samples"]

transcript_before = by_label["before-ipad-transcript"]
transcript_after = by_label["after-ipad-transcript"]
before_share, after_share = map(active_main_share, (transcript_before, transcript_after))
transcript_note = (
    f'The iPad transcript total changed by only 2%, which is effectively unchanged in this single comparison. '
    f'Main-thread samples outside waiting and accessibility automation fell from {before_share:.1%} to {after_share:.1%} '
    f'of the window ({(1-after_share/before_share):.1%} less). Hidden task formatting fell from '
    f'{transcript_before["stacks"]["inclusive"].get("task_formatting", 0)} samples to '
    f'{transcript_after["stacks"]["inclusive"].get("task_formatting", 0)}. '
    f'Text sizing fell from {transcript_before["stacks"]["inclusive"].get("text_sizing", 0)} to '
    f'{transcript_after["stacks"]["inclusive"].get("text_sizing", 0)} samples. '
    'Accessibility automation took more work in the after window. The total therefore understates the targeted savings.'
)

profiler = []
for surface in ("tasks", "transcript"):
    paths = [ROOT / "traces" / f"{phase}-ipad-{surface}" / "summary.json" for phase in ("before", "after")]
    if not all(path.exists() for path in paths):
        continue
    a, b = [json.loads(path.read_text()) for path in paths]
    af = a.get("inclusive_main_ms", {}).get("task_formatting", 0)
    bf = b.get("inclusive_main_ms", {}).get("task_formatting", 0)
    am = a["sampled_main_thread_ms"]
    bm = b["sampled_main_thread_ms"]
    text = f'{surface.title()}: sampled main-thread CPU fell from {am:,.0f} to {bm:,.0f} milliseconds ({(1-bm/am):.0%} less). Task formatting fell from {af:.0f} to {bf:.0f} milliseconds.'
    if surface == "transcript":
        at = a.get("inclusive_main_ms", {}).get("text_sizing", 0)
        bt = b.get("inclusive_main_ms", {}).get("text_sizing", 0)
        text += f' Text sizing changed from {at:.0f} to {bt:.0f} milliseconds.'
    text += f' Both windows contain eight gestures in about 22 seconds. Hangs above 250 ms: {a.get("potential_hangs_count", "unknown")} before, {b.get("potential_hangs_count", "unknown")} after.'
    profiler.append(f"<p>{html.escape(text)}</p>")
profiler_html = ('<h2>Independent profiler check</h2><div class="panel">' + "".join(profiler)
                 + '<p>Animation Hitches returned “Hitches is not supported on this platform.” Zero long hangs does not prove smooth frame pacing.</p></div>') if profiler else ""

page = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>LFG scroll performance</title>
<style>
:root{font-family:system-ui,-apple-system,sans-serif;color:#1b2430;background:#f5f6f8;line-height:1.55}
*{box-sizing:border-box}body{margin:0}main{max-width:1080px;margin:auto;padding:36px 20px 72px}
h1{font-size:clamp(28px,5vw,44px);line-height:1.15;letter-spacing:-.03em;margin:8px 0 20px}h2{font-size:23px;margin:32px 0 12px}
p{max-width:76ch}small,.quiet{color:#5d6876}.eyebrow{font-size:13px;text-transform:uppercase;letter-spacing:.1em;color:#45647d}
.panel,details{background:white;border:1px solid #dce1e7;border-radius:16px;padding:20px;margin:16px 0}
.grid{display:grid;grid-template-columns:repeat(2,1fr);gap:16px}.grid p{margin:6px 0}.grid strong{font-size:17px}
.table{overflow:auto}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums;font-size:15px}th,td{text-align:left;padding:12px;border-bottom:1px solid #e2e7ec;white-space:nowrap}th{font-weight:600;color:#506174}.good{color:#08724c;font-weight:650}.neutral{color:#735618}
summary{cursor:pointer;font-size:18px;font-weight:650;min-height:32px}button{font:inherit;background:#155aa8;color:white;border:0;border-radius:8px;padding:10px 14px;margin:16px 0;cursor:pointer}button:focus-visible,summary:focus-visible{outline:3px solid #4282dc;outline-offset:4px}
.videos{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px;align-items:start}figure{margin:0;text-align:center}figcaption{font-weight:600;margin-bottom:10px}video{width:100%;max-height:680px;background:#111;border-radius:10px}.iphone video{max-width:340px}.ipad video{max-width:470px}
a{color:#155aa8}.note{border-left:4px solid #7d9fbc;padding:4px 16px}.status{font-size:14px;border-radius:8px;background:#edf3f8;padding:12px 16px}
@media(max-width:620px){main{padding:24px 14px 48px}.grid{grid-template-columns:1fr}.videos{grid-template-columns:1fr}.panel,details{padding:16px}th,td{padding:10px}video{max-height:600px}}
@media(prefers-color-scheme:dark){:root{color:#e7edf5;background:#10151c}.panel,details{background:#19212c;border-color:#344050}.quiet,small,th{color:#acb9c8}td,th{border-color:#344050}a,.eyebrow{color:#9dcbff}.status{background:#223245}.good{color:#6fe3af}}
</style></head><body><main>
<div class="eyebrow">LFG · October 17, 2026</div><h1>Scroll performance</h1>
<p>Repeated task formatting and text measurement wasted main-thread time. The fixes reduced that work on both older simulator sizes.</p>
<p><strong>Independent iPad mini profiler captures show 22% less main-thread CPU in Tasks and 21% less in transcripts.</strong></p>
<p class="quiet">Each run uses the same optimized build settings, local data, eight gestures, and a 20-second CPU measurement window.</p>
<h2>20-second process CPU windows</h2><div class="panel table"><table><thead><tr><th>Screen</th><th>Before</th><th>After</th><th>Change</th></tr></thead><tbody>TABLE</tbody></table></div>
<p class="note">CPU time measures app work across threads. It includes automation overhead. These numbers do not measure physical-device frame pacing.</p>
<p>TRANSCRIPT_NOTE</p>
PROFILER
<h2>What changed</h2><div class="grid">
<div class="panel"><strong>Prepare visible task rows</strong><p>A concrete row view stops List from formatting offscreen tasks while counting rows.</p></div>
<div class="panel"><strong>Keep task updates local</strong><p>Equal snapshots and stable label inputs skip repeated formatting. Parent updates and navigation actions remain independent.</p></div>
<div class="panel"><strong>Wake clocks when text changes</strong><p>Session ages update at their next second, minute, hour, day, or week boundary.</p></div>
<div class="panel"><strong>Reuse text measurements</strong><p>Each text view remembers recent width measurements. Content and font changes clear them. An unused sizing call is removed.</p></div></div>
<h2>Scroll recordings</h2><p>Open a comparison, then play both recordings. The data includes 320 sessions, 200 tasks, and a rich transcript.</p>
<p class="quiet">Capture timing varies between videos. Use them to inspect content and gestures; playback does not measure frame rate or hitch rate.</p>CARDS
<h2>Verification</h2><div class="status">Core tests: 646 XCTest cases, with one skipped; 457 Swift Testing cases. Desktop: 204 checks passed. AUDIT</div>
<p class="quiet">Both simulators report iOS 26.3.1. A simulator uses the Mac's CPU and graphics. Verification on the physical iPad mini remains separate.</p>
<p class="quiet">No commit, push, TestFlight upload, or physical app replacement was made.</p>
<h2>References</h2><p><a href="https://developer.apple.com/videos/play/wwdc2025/306/">Apple: Optimize SwiftUI performance</a> · <a href="https://developer.apple.com/videos/play/wwdc2019/418/">Apple: Simulator limits</a></p>
<p><small>The recordings stay on the Mac. This share has no login and stops at reboot until it is restarted.</small></p>
</main><script>
document.querySelectorAll('.play').forEach(button=>button.addEventListener('click',()=>{
  const videos=button.parentElement.querySelectorAll('video');
  videos.forEach(v=>{v.currentTime=0;v.play().catch(()=>{});});
}));
document.querySelectorAll('details').forEach(details=>details.addEventListener('toggle',()=>{
  if(!details.open)details.querySelectorAll('video').forEach(v=>v.pause());
}));
</script></body></html>'''
audit_file = ROOT / "audit-status.txt"
audit = audit_file.read_text().strip() if audit_file.exists() else "Independent audits are pending."
page = page.replace("TABLE", "".join(table)).replace("CARDS", "".join(cards)).replace("AUDIT", html.escape(audit)).replace("PROFILER", profiler_html).replace("TRANSCRIPT_NOTE", html.escape(transcript_note))
(OUT / "index.html").write_text(page)
print(OUT / "index.html")
