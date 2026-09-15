"""Per-frame ink profile of the terminal area. Flags frames where visible text drops
sharply and recovers within <=3 frames (flicker/blank), and prints change timeline + clock ticks."""
import subprocess, json, sys
import numpy as np
path=sys.argv[1]
p=json.loads(subprocess.check_output(["ffprobe","-v","error","-select_streams","v:0","-show_entries","stream=width,height","-of","json",path]))
W,H=p["streams"][0]["width"],p["streams"][0]["height"]
pts=[float(x.strip(",")) for x in subprocess.check_output(["ffprobe","-v","error","-select_streams","v:0","-show_entries","frame=pts_time","-of","csv=p=0",path]).decode().split() if x.strip(",")]
pr=subprocess.Popen(["ffmpeg","-v","quiet","-i",path,"-vsync","0","-f","rawvideo","-pix_fmt","gray","-"],stdout=subprocess.PIPE)
sy=H/874; T0,T1=int(110*sy),int(808*sy)
ink=[]; rows_ink=[]; chg=[]; clock=[]; prevc=None; prev=None; i=0
while True:
    b=pr.stdout.read(W*H)
    if len(b)<W*H: break
    f=np.frombuffer(b,dtype=np.uint8).reshape(H,W)
    t=f[T0:T1:2, ::2]
    lit=(t>90)
    ink.append(float(lit.mean()))
    # per text row (16pt lines): count rows with any ink
    rows=lit.reshape(-1, lit.shape[1]).any(axis=1)
    rows_ink.append(int(rows.sum()))
    if prev is not None: chg.append(int((np.abs(t.astype(np.int16)-prev.astype(np.int16))>40).sum()))
    else: chg.append(0)
    c=f[int(15*sy):int(50*sy),int(20*sy):int(130*sy)].astype(np.int16)
    if prevc is not None and (np.abs(c-prevc)>40).sum()>30: clock.append((i,pts[i]))
    prev=t; prevc=c; i+=1
ink=np.array(ink); rows_ink=np.array(rows_ink)
print("frames",i,"clock ticks",clock)
flags=[]
for k in range(1,i-4):
    base=ink[k-1]
    for L in (1,2,3):
        after=ink[k+L]
        dip=ink[k:k+L].max()
        if base>0.01 and after>0.01 and dip<0.5*min(base,after):
            flags.append((k,round(pts[k],3),L,round(base,4),round(dip,4),round(after,4))); break
print("flicker/blank dips (frame, t, len, ink_before, ink_dip, ink_after):", flags)
json.dump(dict(pts=pts,ink=ink.tolist(),rows=rows_ink.tolist(),chg=chg,clock=clock,flags=flags),open(sys.argv[2],"w"))
# timeline summary: bursts of change
active=[k for k in range(i) if chg[k]>200]
bursts=[]
for k in active:
    if bursts and k-bursts[-1][1]<=6: bursts[-1][1]=k
    else: bursts.append([k,k])
for a,b in bursts: print("burst frames %d-%d t=%.2f-%.2f (%d frames, %d changed) ink %.3f->%.3f"%(a,b,pts[a],pts[b],b-a+1,sum(1 for k in range(a,b+1) if chg[k]>200),ink[a-1],ink[b]))
