import subprocess, sys, json
import numpy as np

path, keylog = sys.argv[1], sys.argv[2]
p = json.loads(subprocess.check_output(["ffprobe","-v","error","-select_streams","v:0","-show_entries","stream=width,height","-of","json",path]))
W,H = p["streams"][0]["width"], p["streams"][0]["height"]
pts = subprocess.check_output(["ffprobe","-v","error","-select_streams","v:0","-show_entries","frame=pts_time","-of","csv=p=0",path]).decode().split()
pts = [float(x.strip(",")) for x in pts if x.strip(",")]
proc = subprocess.Popen(["ffmpeg","-v","quiet","-i",path,"-vsync","0","-f","rawvideo","-pix_fmt","gray","-"], stdout=subprocess.PIPE)
sy = H/874.0
T0,T1 = int(110*sy), int(800*sy)    # terminal text rows, excludes tmux status line
S0,S1,SX0,SX1 = int(15*sy), int(50*sy), int(20*sy), int(130*sy)  # iOS status-bar clock
prev=None; i=0; term_ev=[]; clock_ev=[]
while True:
    buf = proc.stdout.read(W*H)
    if len(buf) < W*H: break
    f = np.frombuffer(buf, dtype=np.uint8).reshape(H,W)
    if prev is not None:
        dt_ = (np.abs(f[T0:T1].astype(np.int16)-prev[T0:T1].astype(np.int16))>40)
        ds_ = (np.abs(f[S0:S1,SX0:SX1].astype(np.int16)-prev[S0:S1,SX0:SX1].astype(np.int16))>40)
        if dt_.sum()>30:
            rows=np.where(dt_.any(axis=1))[0]; cols=np.where(dt_.any(axis=0))[0]
            term_ev.append((i, pts[i], int(dt_.sum()), int(rows.min()/sy+110), int(cols.min()/sy), int(cols.max()/sy)))
        if ds_.sum()>30: clock_ev.append((i, pts[i], int(ds_.sum())))
    prev=f; i+=1
dts=np.diff(pts)
print(f"frames {i} dur {pts[-1]:.2f}s interval median {np.median(dts)*1000:.1f}ms max {dts.max()*1000:.1f}ms")
print("clock ticks (video t):", clock_ev)
print("terminal change events:", len(term_ev))
for e in term_ev: print("  ", e)
keys=[float(l.split()[0]) for l in open(keylog)]
print("keylog bytes:", len(keys))
# Merge frames that belong to one keystroke (within 150 ms)
glyph=[]
for e in term_ev:
    if glyph and e[1]-glyph[-1][1] < 0.15: glyph[-1][2]+=1; continue
    glyph.append([e[0], e[1], 1])
print("grouped glyph events:", len(glyph), "multi-frame groups:", sum(1 for g in glyph if g[2]>1))
json.dump(dict(pts_interval_ms=float(np.median(dts)*1000), clock=clock_ev, term=term_ev, glyph=glyph, keys=keys), open(sys.argv[3],"w"))
