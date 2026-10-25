#!/usr/bin/env python3
"""Measure per-byte round trip over an ssh command: send one byte, wait for its uppercase echo."""
import os, subprocess, sys, time, statistics, select
cmd = sys.argv[1:]
n = int(os.environ.get("N", "30"))
remote = 'exec python3 -u -c "import os\nwhile True:\n b=os.read(0,1)\n if not b: break\n os.write(1,b.upper())"'
p = subprocess.Popen(cmd + [remote], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
t0 = time.time()
p.stdin.write(b"a"); 
r,_,_ = select.select([p.stdout],[],[],30)
if not r: print("no echo within 30s (connect failed?)"); p.kill(); sys.exit(1)
p.stdout.read(1)
print(f"connect+first echo: {(time.time()-t0)*1000:.0f} ms")
rtts=[]
for i in range(n):
    t=time.time(); p.stdin.write(b"b")
    r,_,_=select.select([p.stdout],[],[],10)
    if not r: print("timeout"); break
    p.stdout.read(1); rtts.append((time.time()-t)*1000)
    time.sleep(0.2)
p.stdin.close(); p.kill()
rtts.sort()
print(f"n={len(rtts)} min={rtts[0]:.0f} p50={statistics.median(rtts):.0f} p90={rtts[int(len(rtts)*.9)-1]:.0f} max={rtts[-1]:.0f} ms")
