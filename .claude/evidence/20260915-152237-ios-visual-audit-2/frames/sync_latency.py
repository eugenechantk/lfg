"""Same method as audit 1: glyph frame (terminal-area diff) minus pty receive time,
video<->host synced on the status-bar minute tick. Usage: an.json keylog.txt"""
import json, sys, statistics as st, datetime
d = json.load(open(sys.argv[1]))
keys = [float(l.split()[0]) for l in open(sys.argv[2])]
tick_video = d["clock"][0][1]
# host minute boundary nearest the keystrokes that the tick corresponds to
glyph = [g[1] for g in d["glyph"]]
assert len(glyph) == len(keys), (len(glyph), len(keys))
# approximate offset using first key vs first glyph, then snap to the minute boundary
approx = keys[0] - glyph[0]
host_tick = round((tick_video + approx) / 60.0) * 60.0
off = host_tick - tick_video
lat = [(g + off - k) * 1000 for g, k in zip(glyph, keys)]
s = sorted(lat); n = len(s)
print("minute tick host", datetime.datetime.fromtimestamp(host_tick))
print("samples ms:", [round(x) for x in lat])
print("n %d median %.0f p90 %.0f min %.0f max %.0f sd %.1f" % (n, st.median(s), s[int(.9 * n) - 1], s[0], s[-1], st.pstdev(s)))
